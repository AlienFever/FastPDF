// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

final class ReaderWindowController: NSWindowController, NSWindowDelegate {
    enum Fit: String { case width, page, custom }

    let pdfView = ReaderPDFView()
    private(set) lazy var sidebar = SidebarViewController(owner: self)
    private(set) lazy var find = FindController(owner: self)
    private var sidebarItem: NSSplitViewItem!
    private var sidebarObservation: NSKeyValueObservation?

    private(set) var fit: Fit = .width
    private var applyingZoom = false
    private var didPrepare = false
    private var saveWork: DispatchWorkItem?

    private var content: ReaderContentView!
    var bar: ReaderBar { content.bar }
    let toolbarControls = ToolbarControls()
    private lazy var glassToolbar = makeToolbar()
    private(set) var usesGlassToolbar = false

    /// When set, every text selection is highlighted in this color as soon as the mouse is released.
    /// When set, every text selection is marked up (highlight / underline / strike) as soon as the mouse is released.
    var markupMode: MarkupStyle? {
        didSet {
            if markupMode != nil { placingNote = false }
            updateHighlightControls()
        }
    }

    /// Form field values per page as last saved (only pages whose fields have been touched).
    var formBaseline: [Int: [FormValue]] = [:]

    /// N with nothing selected: the next click on a page places a sticky note there.
    var placingNote = false {
        didSet {
            if placingNote { markupMode = nil }
            updateHighlightControls()
        }
    }
    private(set) lazy var bookmarksPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = BookmarksViewController(owner: self)
        return popover
    }()

    var reader: ReaderDocument? { document as? ReaderDocument }
    var pdf: PDFDocument? { pdfView.document }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        // Last page per file is remembered separately; restoring old windows would only delay the file just opened.
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true

        configurePDFView()
        let content = NSViewController()
        self.content = ReaderContentView(pdfView: pdfView, frame: NSRect(x: 0, y: 0, width: 900, height: 1000))
        content.view = self.content
        configureBar()
        let split = NSSplitViewController()
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 420
        sidebarItem.isCollapsed = !UserDefaults.standard.bool(forKey: "SidebarVisible")
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: content))
        window.contentViewController = split
        window.setContentSize(NSSize(width: 900, height: 1000))
        window.setFrameAutosaveName("ReaderWindow")
        window.initialFirstResponder = pdfView
        self.content.sidebarHandle.isHidden = sidebarItem.isCollapsed
        applyChromeStyle()

        sidebarObservation = sidebarItem.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            UserDefaults.standard.set(!item.isCollapsed, forKey: "SidebarVisible")
            self?.bar.setClearsWindowButtons(item.isCollapsed)
            self?.content.sidebarHandle.isHidden = item.isCollapsed
            if !item.isCollapsed { self?.sidebar.activate() }
            // Collapsing the sidebar can hand focus to the page field; keep arrow keys turning pages.
            DispatchQueue.main.async { self?.focusPDFIfNeeded() }
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        center.addObserver(self, selector: #selector(scaleChanged), name: .PDFViewScaleChanged, object: pdfView)
        center.addObserver(self, selector: #selector(applyChromeStyle), name: .chromeStyleChanged, object: nil)
        center.addObserver(self, selector: #selector(highlightColorsChanged), name: .highlightColorsChanged, object: nil)
        pdfView.controller = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Glass toolbar (standard macOS look) or the compact hand-drawn bar (fastest).
    @objc func applyChromeStyle() {
        guard let window else { return }
        let glass = Self.prefersGlassToolbar
        usesGlassToolbar = glass
        if glass {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.toolbarStyle = .unified
            if window.toolbar == nil { window.toolbar = glassToolbar }
            window.standardWindowButton(.documentIconButton)?.isHidden = false
        } else {
            window.toolbar = nil
            window.toolbarStyle = .automatic
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            bar.setClearsWindowButtons(sidebarItem.isCollapsed)
            // The title's document icon stays visible after switching from the toolbar and would cover the bar.
            window.standardWindowButton(.documentIconButton)?.isHidden = true
        }
        content.setBarHidden(glass)
        pdfView.removeTopInset()
        updatePageControls()
        updateZoomTitle()
        updateHighlightControls()
    }

    @objc private func highlightColorsChanged() { updateHighlightControls() }

    /// Find results take precedence; otherwise say when highlight mode is on.
    func refreshStatus() {
        var text = find.statusText
        if text.isEmpty, let mode = markupMode { text = "\(mode.kind.activeVerb) in \(mode.color.name) · Esc to stop" }
        if text.isEmpty, placingNote { text = "Click where the note should go · Esc to cancel" }
        if usesGlassToolbar {
            window?.subtitle = text
        } else {
            bar.findStatus.stringValue = text
        }
    }

    private func configureBar() {
        for button in [bar.previousButton, bar.nextButton, bar.highlightButton, bar.noteButton, bar.zoomOutButton, bar.viewMenuButton,
                       bar.zoomInButton, bar.rotateButton, bar.bookmarkButton, bar.searchButton] {
            button.target = self
        }
        bar.pageField.target = self
        bar.pageField.action = #selector(pageFieldEntered(_:))
    }

    private func configurePDFView() {
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = .underPageBackgroundColor
        pdfView.autoScales = false
        pdfView.minScaleFactor = 0.1
        pdfView.maxScaleFactor = 10
    }

    private func focusPDFIfNeeded() {
        guard let window else { return }
        let responder = window.firstResponder
        let delegate = (responder as? NSTextView)?.delegate
        let inPageField = delegate === bar.pageField || delegate === toolbarControls.pageField
        if responder == nil || responder === window || inPageField { window.makeFirstResponder(pdfView) }
    }

    override var document: AnyObject? {
        didSet {
            guard let pdf = reader?.pdf, pdfView.document !== pdf else { return }
            pdfView.document = pdf
            pdfView.removeTopInset()
            connectForms()
        }
    }

    // MARK: Showing

    override func showWindow(_ sender: Any?) {
        guard let window else { return }
        if !didPrepare {
            didPrepare = true
            cascadeFromFrontWindow()
            restoreState()
        }
        // Skip super: NSWindowController routes Finder opens through the "seamless open" zoom-from-icon animation.
        window.makeKeyAndOrderFront(sender)
        window.displayIfNeeded()
        Perf.windowShown(reader?.displayName ?? "?")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // The title-bar proxy icon costs ~15 ms on first use; set it once the page is already on screen.
            window.representedURL = self.reader?.fileURL
            if self.pdf?.isLocked == true { self.askForPassword(); return }
            // Sidebar content (thumbnails especially) is filled in right after the page is on screen.
            if !self.sidebarItem.isCollapsed { self.sidebar.activate() }
        }
    }

    /// Only one window can own the saved frame; later ones open offset from the front reader window.
    private func cascadeFromFrontWindow() {
        guard let window, let front = NSApp.orderedWindows.first(where: {
            $0 !== window && $0.isVisible && $0.windowController is ReaderWindowController
        }) else { return }
        window.setFrame(front.frame, display: false)
        window.setFrameTopLeftPoint(NSPoint(x: front.frame.minX + 24, y: front.frame.maxY - 24))
    }

    override func synchronizeWindowTitleWithDocumentName() {
        // Title only; representedURL is set lazily in showWindow.
        window?.title = reader?.displayName ?? ""
        bar.titleLabel.stringValue = reader?.displayName ?? ""
    }

    /// Applies the remembered view mode, zoom and position before the window is first drawn, so nothing jumps.
    private func restoreState() {
        guard let pdf, pdf.pageCount > 0 else { updatePageControls(); return }
        window?.layoutIfNeeded()
        let saved = reader?.savedState
        if let raw = saved?.displayMode, let mode = PDFDisplayMode(rawValue: raw) { pdfView.displayMode = mode }
        pdfView.displaysAsBook = saved?.coverPage ?? false
        fit = saved?.fit.flatMap(Fit.init(rawValue:)) ?? .width
        if fit == .custom, let scale = saved?.scale {
            setScale(CGFloat(scale))
        } else {
            applyFit(keepPosition: false)
        }
        pdfView.layoutDocumentView()
        pdfView.removeTopInset()
        if let saved, let page = pdf.page(at: min(max(saved.page, 0), pdf.pageCount - 1)) {
            if let p = saved.point, p.count == 2 {
                scroll(to: (page, CGPoint(x: p[0], y: p[1])))
            } else {
                pdfView.go(to: page)
            }
        } else if let first = pdf.page(at: 0) {
            // New file: page 1 starts at the very top of the window, with the glass toolbar overlapping it.
            let box = first.bounds(for: pdfView.displayBox)
            scroll(to: (first, CGPoint(x: box.minX, y: box.maxY)))
        }
        updatePageControls()
        updateZoomTitle()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { reader?.undoManager }

    func windowDidEnterFullScreen(_ notification: Notification) { bar.setClearsWindowButtons(sidebarItem.isCollapsed) }
    func windowDidExitFullScreen(_ notification: Notification) { bar.setClearsWindowButtons(sidebarItem.isCollapsed) }

    func windowWillClose(_ notification: Notification) {
        saveWork?.cancel()
        saveState()
        find.cancel()
        sidebar.cancelWork()
    }

    // MARK: Page tracking and persistence

    var currentPageIndex: Int {
        guard let pdf, let page = pdfView.currentPage else { return 0 }
        return pdf.index(for: page)
    }

    var bookmarks: [Int] {
        guard let key = reader?.stateKey else { return [] }
        return FileStateStore.shared.state(for: key)?.bookmarks ?? []
    }

    @objc private func pageChanged() {
        updatePageControls()
        sidebar.pageChanged(to: currentPageIndex)
        scheduleSave()
    }

    func updatePageControls() {
        let count = pdf?.pageCount ?? 0
        let index = currentPageIndex
        let pageText = count > 0 ? "\(index + 1)" : ""
        for field in [bar.pageField, toolbarControls.pageField] where field.currentEditor() == nil {
            if field.stringValue != pageText { field.stringValue = pageText }
        }
        bar.pageCountLabel.stringValue = "/ \(count)"
        toolbarControls.pageCountLabel.stringValue = "/ \(count)"
        let marked = bookmarks.contains(index)
        let symbol = marked ? "bookmark.fill" : "bookmark"
        toolbarControls.bookmarkItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Bookmarks")
        if bar.bookmarkButton.symbol != symbol {
            bar.bookmarkButton.symbol = symbol
            bar.bookmarkButton.tint = marked ? .controlAccentColor : .secondaryLabelColor
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveState() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveState() {
        guard let key = reader?.stateKey, let pdf, pdf.pageCount > 0, !pdf.isLocked else { return }
        let anchor = topAnchor()
        let index = anchor.map { pdf.index(for: $0.page) } ?? currentPageIndex
        let point = anchor.map { [Double($0.point.x), Double($0.point.y)] }
        let mode = pdfView.displayMode.rawValue, fit = fit.rawValue, scale = Double(pdfView.scaleFactor)
        let cover = pdfView.displaysAsBook
        FileStateStore.shared.update(key) { state in
            state.page = index
            state.point = point
            state.displayMode = mode
            state.coverPage = cover
            state.fit = fit
            state.scale = scale
        }
    }

    // MARK: Zoom and fit

    private func setScale(_ scale: CGFloat) {
        applyingZoom = true
        pdfView.scaleFactor = scale
        applyingZoom = false
    }

    /// Fit Width / Fit Page are modes, not one-off zooms: they are re-applied whenever the view changes size.
    private func applyFit(keepPosition: Bool = true) {
        guard fit != .custom, let pdf, let page = pdfView.currentPage ?? pdf.page(at: 0) else { return }
        var size = page.bounds(for: pdfView.displayBox).size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let across: CGFloat = (pdfView.displayMode == .twoUp || pdfView.displayMode == .twoUpContinuous) ? 2 : 1
        let margins = pdfView.pageBreakMargins
        let scroller = NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        let available = readingArea.size
        let widthScale = (available.width - scroller) / ((size.width + margins.left + margins.right) * across)
        let heightScale = available.height / (size.height + margins.top + margins.bottom)
        let scale = fit == .width ? widthScale : min(widthScale, heightScale)
        guard scale.isFinite, scale > 0, abs(scale - pdfView.scaleFactor) > 0.0005 else { return }
        let anchor = keepPosition ? topAnchor() : nil
        setScale(scale)
        // PDFKit adds spacing (e.g. between side-by-side pages) that the estimate above doesn't know about;
        // if the pages still overflow the view, shrink just enough to remove the horizontal scroller.
        pdfView.layoutDocumentView()
        if let scrollView = pdfView.documentView?.enclosingScrollView, let content = scrollView.documentView {
            let visible = scrollView.contentView.bounds.width
            if content.frame.width > visible + 0.5 {
                setScale(pdfView.scaleFactor * visible / content.frame.width)
            }
        }
        if let anchor { scroll(to: anchor) }
    }

    // MARK: Exact position

    /// The page point currently at the top edge of the view. (PDFView.currentDestination doesn't round-trip
    /// exactly through go(to:), so using it drifts the page a little on every resize.)
    /// The part of the PDF view not covered by the glass toolbar (the view itself runs up underneath it).
    private var readingArea: NSRect {
        let inset = pdfView.documentView?.enclosingScrollView?.contentInsets.top ?? 0
        var area = pdfView.bounds
        area.size.height = max(0, area.height - inset)
        if pdfView.isFlipped { area.origin.y += inset }
        return area
    }

    private var readingTop: NSPoint {
        let area = readingArea
        return NSPoint(x: area.midX, y: pdfView.isFlipped ? area.minY : area.maxY)
    }

    fileprivate func topAnchor() -> (page: PDFPage, point: CGPoint)? {
        let top = readingTop
        guard let page = pdfView.page(for: top, nearest: true) else { return nil }
        return (page, pdfView.convert(top, to: page))
    }

    /// Scrolls so that `anchor.point` on `anchor.page` sits exactly at the top edge of the view.
    private func scroll(to anchor: (page: PDFPage, point: CGPoint)) {
        pdfView.layoutDocumentView()
        guard let scrollView = pdfView.documentView?.enclosingScrollView else { return }
        let clip = scrollView.contentView
        let top = readingTop
        let target = clip.convert(pdfView.convert(anchor.point, from: anchor.page), from: pdfView)
        let edge = clip.convert(top, from: pdfView)
        var bounds = clip.bounds
        bounds.origin.y += target.y - edge.y
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    @objc private func scaleChanged() {
        if !applyingZoom { fit = .custom }
        updateZoomTitle()
        scheduleSave()
    }

    /// Called by the PDF view around every size change, with the position captured before the change.
    fileprivate func pdfViewDidResize(keeping anchor: (page: PDFPage, point: CGPoint)?) {
        guard fit != .custom, didPrepare else { return }
        applyFit(keepPosition: false)
        if let anchor { scroll(to: anchor) }
    }

    func updateZoomTitle() {
        let title: String
        switch fit {
        case .width: title = "Fit Width"
        case .page: title = "Fit Page"
        case .custom: title = "\(Int((pdfView.scaleFactor * 100).rounded()))%"
        }
        if bar.viewMenuButton.title != title { bar.viewMenuButton.title = title }
        if let control = toolbarControls.zoomControl, control.label(forSegment: 1) != title {
            control.setLabel(title, forSegment: 1)
        }
    }

    @objc func showViewMenu(_ sender: Any?) {
        let button = bar.viewMenuButton
        ReaderBar.viewMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    private func setFit(_ newFit: Fit) {
        fit = newFit
        applyFit()
        updateZoomTitle()
        scheduleSave()
    }

    @objc func fitWidth(_ sender: Any?) { setFit(.width) }
    @objc func fitPage(_ sender: Any?) { setFit(.page) }
    @objc func actualSize(_ sender: Any?) { fit = .custom; pdfView.scaleFactor = 1 }
    @objc func zoomInAction(_ sender: Any?) { fit = .custom; pdfView.zoomIn(sender) }
    @objc func zoomOutAction(_ sender: Any?) { fit = .custom; pdfView.zoomOut(sender) }

    // MARK: Display modes

    /// `cover`: in Two Pages, page 1 stands alone and the rest pair up like an open book (2–3, 4–5, …).
    private func setDisplayMode(_ mode: PDFDisplayMode, cover: Bool = false) {
        guard pdfView.displayMode != mode || pdfView.displaysAsBook != cover else { return }
        let page = pdfView.currentPage
        pdfView.displayMode = mode
        pdfView.displaysAsBook = cover
        applyFit(keepPosition: false)
        if let page { pdfView.go(to: page) }
        scheduleSave()
    }

    private var isTwoPages: Bool { pdfView.displayMode == .twoUp || pdfView.displayMode == .twoUpContinuous }

    /// V: Fit Width ⇄ Fit Page.
    @objc func cycleFit(_ sender: Any?) { setFit(fit == .width ? .page : .width) }

    /// D: Single Page → Continuous → Two Pages → Two Pages with Cover.
    @objc func cycleLayout(_ sender: Any?) {
        let order: [(PDFDisplayMode, Bool)] = [(.singlePage, false), (.singlePageContinuous, false),
                                               (.twoUpContinuous, false), (.twoUpContinuous, true)]
        let current = order.firstIndex { $0.0 == pdfView.displayMode && $0.1 == (isTwoPages && pdfView.displaysAsBook) } ?? 0
        let next = order[(current + 1) % order.count]
        setDisplayMode(next.0, cover: next.1)
    }

    // MARK: Rotation

    @objc func rotateRight(_ sender: Any?) { rotateCurrentPage(by: 90) }
    @objc func rotateLeft(_ sender: Any?) { rotateCurrentPage(by: -90) }

    /// Rotates the page being read (the left page of a two-page spread). Saved into the PDF like other edits.
    private func rotateCurrentPage(by degrees: Int) {
        guard let page = pdfView.currentPage else { return }
        setRotation(of: page, to: ((page.rotation + degrees) % 360 + 360) % 360)
    }

    private func setRotation(of page: PDFPage, to rotation: Int) {
        guard let pdf, let reader else { return }
        let previous = page.rotation
        page.rotation = rotation
        reader.recordRotation(pageIndex: pdf.index(for: page), rotation: rotation)
        pdfView.layoutDocumentView()
        applyFit(keepPosition: false)
        let box = page.bounds(for: pdfView.displayBox)
        pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: box.minX, y: box.maxY)))
        reader.undoManager?.registerUndo(withTarget: self) { $0.setRotation(of: page, to: previous) }
        reader.undoManager?.setActionName("Rotate Page")
    }

    @objc func singlePage(_ sender: Any?) { setDisplayMode(.singlePage) }
    @objc func continuousScroll(_ sender: Any?) { setDisplayMode(.singlePageContinuous) }
    @objc func twoPages(_ sender: Any?) { setDisplayMode(.twoUpContinuous) }
    @objc func twoPagesWithCover(_ sender: Any?) { setDisplayMode(.twoUpContinuous, cover: true) }

    // MARK: Navigation

    func go(toPage index: Int) {
        guard let pdf, pdf.pageCount > 0, let page = pdf.page(at: min(max(index, 0), pdf.pageCount - 1)) else { return }
        let box = page.bounds(for: pdfView.displayBox)
        pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: box.minX, y: box.maxY)))
    }

    @objc func previousPage(_ sender: Any?) { pdfView.goToPreviousPage(sender) }
    @objc func nextPage(_ sender: Any?) { pdfView.goToNextPage(sender) }
    // PDFView's goToFirstPage is a no-op while page 1 is "current" even if you're halfway down it.
    @objc func firstPage(_ sender: Any?) { go(toPage: 0) }
    @objc func lastPage(_ sender: Any?) { go(toPage: (pdf?.pageCount ?? 1) - 1) }
    @objc func historyBack(_ sender: Any?) { pdfView.goBack(sender) }
    @objc func historyForward(_ sender: Any?) { pdfView.goForward(sender) }

    @objc func goToPage(_ sender: Any?) {
        let field = usesGlassToolbar ? toolbarControls.pageField : bar.pageField
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    @objc func pageFieldEntered(_ sender: NSTextField) {
        if let number = Int(sender.stringValue.trimmingCharacters(in: .whitespaces)) {
            go(toPage: number - 1)
        }
        window?.makeFirstResponder(pdfView)
        updatePageControls()
    }

    // MARK: Bookmarks

    @objc func toggleBookmark(_ sender: Any?) {
        guard let key = reader?.stateKey, pdf?.pageCount ?? 0 > 0 else { return }
        let index = currentPageIndex
        FileStateStore.shared.update(key) { state in
            if let at = state.bookmarks.firstIndex(of: index) {
                state.bookmarks.remove(at: at)
            } else {
                state.bookmarks.append(index)
                state.bookmarks.sort()
            }
        }
        bookmarksChanged()
    }

    func removeBookmark(_ index: Int) {
        guard let key = reader?.stateKey else { return }
        FileStateStore.shared.update(key) { $0.bookmarks.removeAll { $0 == index } }
        bookmarksChanged()
    }

    private func bookmarksChanged() {
        updatePageControls()
        (bookmarksPopover.contentViewController as? BookmarksViewController)?.reload()
    }

    @objc func showBookmarks(_ sender: Any?) {
        if bookmarksPopover.isShown { bookmarksPopover.close(); return }
        (bookmarksPopover.contentViewController as? BookmarksViewController)?.reload()
        if usesGlassToolbar, let item = toolbarControls.bookmarkItem {
            bookmarksPopover.show(relativeTo: item)
        } else {
            bookmarksPopover.show(relativeTo: bar.bookmarkButton.bounds, of: bar.bookmarkButton, preferredEdge: .minY)
        }
    }

    @objc func goToBookmark(_ sender: NSMenuItem) { go(toPage: sender.tag) }

    // MARK: Sidebar

    @objc func showContents(_ sender: Any?) { showSidebar(.contents) }
    @objc func showThumbnails(_ sender: Any?) { showSidebar(.thumbnails) }
    @objc func showHighlights(_ sender: Any?) { showSidebar(.highlights) }

    private func showSidebar(_ tab: SidebarViewController.Tab) {
        if sidebarItem.isCollapsed { sidebarItem.isCollapsed = false }
        sidebar.activate()
        sidebar.select(tab)
    }

    // MARK: Find

    @objc func startFind(_ sender: Any?) {
        if usesGlassToolbar, let item = toolbarControls.searchItem {
            item.beginSearchInteraction()
            // Focus now, not when the expand animation ends, so typing right after ⌘F lands in the field.
            window?.makeFirstResponder(item.searchField)
            return
        }
        let field = bar.showSearchField()
        field.delegate = find
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }
    /// Called when Esc leaves the find field.
    func endFind() {
        if usesGlassToolbar {
            toolbarControls.searchItem?.endSearchInteraction()
        } else {
            bar.hideSearchField()
        }
        window?.makeFirstResponder(pdfView)
    }

    @objc func findNext(_ sender: Any?) { find.step(1) }
    @objc func findPrevious(_ sender: Any?) { find.step(-1) }

    // MARK: Password

    private func askForPassword(retry: Bool = false) {
        guard let window, let pdf else { return }
        let alert = NSAlert()
        alert.messageText = retry ? "Incorrect password" : "“\(reader?.displayName ?? "This PDF")” is password protected"
        alert.informativeText = "Enter the password to open this document."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else { self.close(); return }
            if pdf.unlock(withPassword: field.stringValue) {
                self.reader?.password = field.stringValue
                self.pdfView.document = nil
                self.pdfView.document = pdf
                self.restoreState()
                if !self.sidebarItem.isCollapsed { self.sidebar.activate() }
            } else {
                self.askForPassword(retry: true)
            }
        }
    }
}

extension ReaderWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasPages = (pdf?.pageCount ?? 0) > 0 && pdf?.isLocked == false
        switch item.action {
        case #selector(fitWidth(_:)): item.state = fit == .width ? .on : .off
        case #selector(fitPage(_:)): item.state = fit == .page ? .on : .off
        case #selector(singlePage(_:)): item.state = pdfView.displayMode == .singlePage ? .on : .off
        case #selector(continuousScroll(_:)): item.state = pdfView.displayMode == .singlePageContinuous ? .on : .off
        case #selector(twoPages(_:)): item.state = isTwoPages && !pdfView.displaysAsBook ? .on : .off
        case #selector(twoPagesWithCover(_:)): item.state = isTwoPages && pdfView.displaysAsBook ? .on : .off
        case #selector(previousPage(_:)): return hasPages && pdfView.canGoToPreviousPage
        case #selector(nextPage(_:)): return hasPages && pdfView.canGoToNextPage
        case #selector(historyBack(_:)): return pdfView.canGoBack
        case #selector(historyForward(_:)): return pdfView.canGoForward
        case #selector(zoomInAction(_:)): return pdfView.canZoomIn
        case #selector(zoomOutAction(_:)): return pdfView.canZoomOut
        case #selector(toggleBookmark(_:)):
            item.title = bookmarks.contains(currentPageIndex) ? "Remove Bookmark" : "Add Bookmark"
        case #selector(findNext(_:)), #selector(findPrevious(_:)): return find.hasMatches
        case #selector(highlightPrimary(_:)), #selector(highlightSecondary(_:)), #selector(underlineSelection(_:)),
             #selector(strikeSelection(_:)), #selector(cycleFit(_:)),
             #selector(cycleLayout(_:)), #selector(startPlacingNote(_:)):
            // Plain-letter shortcuts: only while reading, never while typing in a field.
            return hasPages && window?.firstResponder === pdfView
        case #selector(removeSelectedHighlights(_:)):
            return pdfView.currentSelection?.pages.contains { page in
                page.annotations.contains { $0.isTextMarkup && $0.bounds.intersects(pdfView.currentSelection!.bounds(for: page)) }
            } ?? false
        default: break
        }
        return hasPages
    }
}

final class ReaderPDFView: PDFView {
    fileprivate weak var controller: ReaderWindowController?

    /// The glass toolbar overlaps the document: no automatic top inset. PDFKit creates its scroll view lazily and
    /// turns automatic insets back on when it (re)builds it, so this is re-applied on every layout pass. The
    /// automatic inset both left a gap above page 1 and was re-applied after scrolling, nudging the page down.
    func removeTopInset() {
        guard let scrollView = documentView?.enclosingScrollView else { return }
        if scrollView.automaticallyAdjustsContentInsets { scrollView.automaticallyAdjustsContentInsets = false }
        if scrollView.contentInsets.top != 0 { scrollView.contentInsets = NSEdgeInsetsZero }
        // PDFKit turns auto-hiding off, so with "Always show scroll bars" an empty horizontal scroller sat
        // under every page even when nothing could scroll sideways.
        if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
    }

    override func layout() {
        super.layout()
        removeTopInset()
    }

    override func setFrameSize(_ newSize: NSSize) {
        // Capture the reading position while the old layout is still intact, so fit modes can restore it exactly.
        guard newSize != frame.size, let controller, document != nil else { return super.setFrameSize(newSize) }
        let anchor = controller.topAnchor()
        super.setFrameSize(newSize)
        controller.pdfViewDidResize(keeping: anchor)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        if event.keyCode == 53, let controller, controller.markupMode != nil || controller.placingNote {
            controller.markupMode = nil   // Esc leaves markup / note-placing mode
            controller.placingNote = false
            return
        }
        if modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.unicodeScalars.first.map({ Int($0.value) }) {
            // Left/right arrows flip pages when there is nothing to scroll horizontally.
            if !canScrollHorizontally {
                if key == NSLeftArrowFunctionKey { goToPreviousPage(nil); return }
                if key == NSRightArrowFunctionKey { goToNextPage(nil); return }
            }
            if key == Int(("h" as Unicode.Scalar).value) { controller?.highlightPrimary(nil); return }
            if key == Int(("k" as Unicode.Scalar).value) { controller?.highlightSecondary(nil); return }
            if key == Int(("u" as Unicode.Scalar).value) { controller?.underlineSelection(nil); return }
            if key == Int(("s" as Unicode.Scalar).value) { controller?.strikeSelection(nil); return }
            if key == Int(("v" as Unicode.Scalar).value) { controller?.cycleFit(nil); return }
            if key == Int(("d" as Unicode.Scalar).value) { controller?.cycleLayout(nil); return }
            if key == Int(("n" as Unicode.Scalar).value) { controller?.startPlacingNote(nil); return }
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let controller, let page = page(for: point, nearest: false) {
            let pagePoint = convert(point, to: page)
            if controller.placingNote {
                controller.placeNote(at: pagePoint, on: page)
                return
            }
            // Clicking a sticky note opens it (instead of PDFKit's own popup handling).
            if let note = page.annotations.last(where: { $0.isNote && $0.bounds.insetBy(dx: -3, dy: -3).contains(pagePoint) }) {
                controller.editNote(note, on: page)
                return
            }
            controller.willClickPage(page)
        }
        super.mouseDown(with: event)
        // Checkboxes and radio buttons change during the click itself.
        controller?.checkFormChanges()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        controller?.selectionFinished()
    }

    /// PDFKit's own annotation items would edit highlights behind FastPDF's back (unsaved), and its zoom/layout
    /// items bypass the Fit Width / Fit Page modes, so they're replaced with FastPDF's equivalents.
    private static let replacedActions: Set<String> = [
        "_removeMarkup:", "_addNote:", "_setAutoSize:", "zoomIn:", "zoomOut:", "_setActualSize:",
        "_setSinglePage:", "_setSinglePageScrolling:", "_setDoublePage:", "_setDoublePageScrolling:",
    ]

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        for item in menu.items where item.view != nil
            || item.action.map({ Self.replacedActions.contains(NSStringFromSelector($0)) }) == true {
            menu.removeItem(item)
        }
        let view = ReaderBar.viewMenu()
        menu.addItem(.separator())
        for item in view.items { view.removeItem(item); menu.addItem(item) }

        let point = convert(event.locationInWindow, from: nil)
        if let controller, let page = page(for: point, nearest: false) {
            let pagePoint = convert(point, to: page)
            let items: [NSMenuItem]
            if let note = page.annotations.last(where: { $0.isNote && $0.bounds.insetBy(dx: -3, dy: -3).contains(pagePoint) }) {
                items = controller.noteContextMenuItems(for: note, on: page)
            } else if let annotation = page.annotations.last(where: { $0.isTextMarkup && $0.markedAreaContains(pagePoint) }) {
                items = controller.contextMenuItems(for: annotation, on: page)
            } else {
                items = controller.selectionMenuItems() + [controller.addNoteMenuItem(at: pagePoint, on: page), .separator()]
            }
            for (i, item) in items.enumerated() { menu.insertItem(item, at: i) }
        }
        // Tidy separators left behind by the removals.
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) } else { previousWasSeparator = item.isSeparatorItem }
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(menu.items.last!) }
        return menu
    }

    private var canScrollHorizontally: Bool {
        guard let scrollView = documentView?.enclosingScrollView, let content = scrollView.documentView else { return false }
        return content.frame.width > scrollView.contentView.bounds.width + 1
    }
}
