// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The controls row, drawn in the title bar next to the traffic lights.
///
/// Built from hand-drawn views rather than NSToolbar / NSButton / NSSearchField: on macOS 26 those standard controls
/// size and render through SwiftUI, which cost ~85 ms per window for a toolbar and ~30 ms for a bar of stock
/// controls. These draw an SF Symbol or a string themselves and cost next to nothing.
final class ReaderBar: NSView {
    typealias R = ReaderWindowController
    let sidebarButton = BarButton(symbol: "sidebar.left", label: "Show/Hide Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)))
    let titleLabel = NSTextField(labelWithString: "")
    let previousButton = BarButton(symbol: "chevron.left", label: "Previous Page", action: #selector(R.previousPage(_:)))
    let pageField = NSTextField()
    let pageCountLabel = NSTextField(labelWithString: "")
    let nextButton = BarButton(symbol: "chevron.right", label: "Next Page", action: #selector(R.nextPage(_:)))
    let highlightButton = BarButton(symbol: "highlighter", label: "Highlight (H / K)", action: #selector(R.highlightPrimary(_:)))
    let noteButton = BarButton(symbol: "note.text", label: "Add Note (N)", action: #selector(R.startPlacingNote(_:)))
    let zoomOutButton = BarButton(symbol: "minus.magnifyingglass", label: "Zoom Out", action: #selector(R.zoomOutAction(_:)))
    let viewMenuButton = BarButton(title: "Fit Width", label: "Page layout and zoom", action: #selector(R.showViewMenu(_:)))
    let zoomInButton = BarButton(symbol: "plus.magnifyingglass", label: "Zoom In", action: #selector(R.zoomInAction(_:)))
    let rotateButton = BarButton(symbol: "rotate.right", label: "Rotate Page (⌘R)", action: #selector(R.rotateRight(_:)))
    let bookmarkButton = BarButton(symbol: "bookmark", label: "Bookmarks", action: #selector(R.showBookmarks(_:)))
    let findStatus = NSTextField(labelWithString: "")
    let searchButton = BarButton(symbol: "magnifyingglass", label: "Find", action: #selector(R.startFind(_:)))
    /// Created on first use (⌘F or the magnifier), so opening a document never pays for it.
    private(set) var searchField: NSTextField?
    private let stack = NSStackView()
    private var leading: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        titleLabel.setContentHuggingPriority(.init(100), for: .horizontal)

        let digits = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        styleInlineField(pageField, font: digits)
        pageField.alignment = .right
        pageField.toolTip = "Current page (type a number and press Return)"
        pageCountLabel.font = digits
        pageCountLabel.textColor = .secondaryLabelColor
        findStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        findStatus.textColor = .secondaryLabelColor

        stack.setViews([
            sidebarButton, titleLabel, previousButton, FieldBackground(pageField, width: 40), pageCountLabel, nextButton,
            highlightButton, noteButton, zoomOutButton, viewMenuButton, zoomInButton, rotateButton, bookmarkButton, findStatus, searchButton,
        ], in: .leading)
        stack.spacing = 2
        stack.setCustomSpacing(8, after: sidebarButton)
        stack.setCustomSpacing(16, after: titleLabel)
        stack.setCustomSpacing(12, after: nextButton)
        stack.setCustomSpacing(10, after: noteButton)
        stack.setCustomSpacing(6, after: findStatus)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        NSLayoutConstraint.activate([
            leading,
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Leaves room for the traffic lights when the bar starts at the window's left edge.
    func setClearsWindowButtons(_ clears: Bool) {
        let buttons = window?.standardWindowButton(.zoomButton)?.frame.maxX ?? 70
        // The traffic lights aren't in the content area in full screen.
        let fullScreen = window?.styleMask.contains(.fullScreen) == true
        leading.constant = clears && !fullScreen ? buttons + 10 : 8
    }

    func showSearchField() -> NSTextField {
        if let searchField { return searchField }
        let field = NSTextField()
        styleInlineField(field, font: .systemFont(ofSize: NSFont.smallSystemFontSize))
        field.placeholderString = "Find"
        let background = FieldBackground(field, width: 150)
        stack.insertView(background, at: stack.views.firstIndex(of: searchButton) ?? stack.views.count, in: .leading)
        stack.setCustomSpacing(6, after: findStatus)
        searchButton.isHidden = true
        searchField = field
        return field
    }

    func hideSearchField() {
        guard let field = searchField else { return }
        field.superview?.removeFromSuperview()
        searchField = nil
        findStatus.stringValue = ""
        searchButton.isHidden = false
    }

    private func styleInlineField(_ field: NSTextField, font: NSFont) {
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
    }

    // Empty parts of the bar behave like a title bar: drag to move, double-click to zoom.
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    /// Layout + zoom options; items target the first responder so the menu validates against this window.
    static func viewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Single Page", action: #selector(R.singlePage(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Continuous", action: #selector(R.continuousScroll(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Two Pages", action: #selector(R.twoPages(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Two Pages with Cover", action: #selector(R.twoPagesWithCover(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Fit Width", action: #selector(R.fitWidth(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Fit Page", action: #selector(R.fitPage(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Actual Size", action: #selector(R.actualSize(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Zoom In", action: #selector(R.zoomInAction(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Zoom Out", action: #selector(R.zoomOutAction(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rotate Left", action: #selector(R.rotateLeft(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Rotate Right", action: #selector(R.rotateRight(_:)), keyEquivalent: "")
        return menu
    }
}

/// A flat icon (or short text) button that draws itself. Sends its action through the responder chain.
final class BarButton: NSView {
    var symbol: String? { didSet { image = symbol.flatMap(BarButton.image(for:)); needsDisplay = true } }
    var title: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var tint: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    /// Shown as a filled background, e.g. while highlight mode is on.
    var activeColor: NSColor? { didSet { needsDisplay = true } }
    var action: Selector?
    weak var target: AnyObject?
    private var image: NSImage?
    private var pressed = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private static let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)

    init(symbol: String? = nil, title: String? = nil, label: String, action: Selector) {
        self.symbol = symbol
        self.title = title
        self.action = action
        image = symbol.flatMap(BarButton.image(for:))
        super.init(frame: .zero)
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func image(for symbol: String) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        if let title {
            let width = (title as NSString).size(withAttributes: [.font: Self.titleFont]).width
            return NSSize(width: ceil(width) + 26, height: 22)
        }
        return NSSize(width: 26, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let activeColor {
            activeColor.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        } else if pressed || hovering || title != nil {
            let fill: NSColor = pressed ? .tertiaryLabelColor : (hovering ? .quaternaryLabelColor : .quaternarySystemFill)
            fill.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        if let title {
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.titleFont, .foregroundColor: NSColor.labelColor]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: NSPoint(x: 9, y: (bounds.height - size.height) / 2), withAttributes: attributes)
            let chevron = NSBezierPath()
            let x = bounds.maxX - 12, y = bounds.midY - 1
            chevron.move(to: NSPoint(x: x - 3, y: y - 1.5))
            chevron.line(to: NSPoint(x: x, y: y + 1.5))
            chevron.line(to: NSPoint(x: x + 3, y: y - 1.5))
            chevron.lineWidth = 1.4
            chevron.lineCapStyle = .round
            NSColor.secondaryLabelColor.setStroke()
            chevron.stroke()
        } else if let image {
            let size = image.size
            let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                              width: size.width, height: size.height)
            // Template symbol tinted by filling through its alpha.
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        var inside = true
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = bounds.contains(convert(next.locationInWindow, from: nil))
            pressed = inside
            if next.type == .leftMouseUp { break }
        }
        pressed = false
        if inside { performClick() }
    }

    func performClick() {
        guard let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func accessibilityPerformPress() -> Bool {
        performClick()
        return true
    }
}

/// Rounded fill behind a borderless text field (stock bezeled fields are among the costly controls).
final class FieldBackground: NSView {
    init(_ field: NSTextField, width: CGFloat) {
        super.init(frame: .zero)
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 22),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternarySystemFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    // Clicking the padding focuses the field too.
    override func mouseDown(with event: NSEvent) {
        if let field = subviews.first { window?.makeFirstResponder(field) }
    }
}

/// Window content. Compact mode: the bar in the title-bar strip, the PDF below it. Glass mode: the PDF runs
/// up under the translucent toolbar (its scroll view is inset so the first page still starts below it).
final class ReaderContentView: NSView {
    let bar = ReaderBar()
    private let separator = NSBox()
    let sidebarHandle = SidebarResizeHandle()
    private var pdfBelowBar: NSLayoutConstraint!
    private var pdfUnderToolbar: NSLayoutConstraint!

    func setBarHidden(_ hidden: Bool) {
        bar.isHidden = hidden
        separator.isHidden = hidden
        pdfBelowBar.isActive = !hidden
        pdfUnderToolbar.isActive = hidden
    }

    init(pdfView: NSView, frame: NSRect) {
        super.init(frame: frame)
        separator.boxType = .separator
        for subview in [bar, separator, pdfView, sidebarHandle] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Fill the title-bar strip; in full screen (no title bar) the minimum height wins and the bar
            // becomes its own row instead of being squeezed out of sight.
            { let c = bar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor); c.priority = .init(999); return c }(),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            separator.topAnchor.constraint(equalTo: bar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebarHandle.widthAnchor.constraint(equalToConstant: 12),
            sidebarHandle.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            sidebarHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        pdfBelowBar = pdfView.topAnchor.constraint(equalTo: separator.bottomAnchor)
        pdfUnderToolbar = pdfView.topAnchor.constraint(equalTo: topAnchor)
        pdfBelowBar.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A visible grip at the sidebar's edge: drag to resize the sidebar, double-click to reset its width.
/// (On macOS 26 the sidebar divider is an invisible hairline, and NSSplitView's divider drawing isn't used.)
final class SidebarResizeHandle: NSView {
    private var hovering = false { didSet { needsDisplay = true } }
    private var dragging = false { didSet { needsDisplay = true } }
    static let defaultSidebarWidth: CGFloat = 240

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Drag to resize the sidebar"
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Sidebar width")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    private var splitView: NSSplitView? {
        var view = superview
        while let current = view, !(current is NSSplitView) { view = current.superview }
        return view as? NSSplitView
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = hovering || dragging
        let grip = NSRect(x: bounds.midX - (active ? 2.5 : 2), y: bounds.midY - 24, width: active ? 5 : 4, height: 48)
        (active ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setFill()
        NSBezierPath(roundedRect: grip, xRadius: grip.width / 2, yRadius: grip.width / 2).fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard let splitView else { return }
        if event.clickCount == 2 {
            splitView.setPosition(Self.defaultSidebarWidth, ofDividerAt: 0)
            return
        }
        dragging = true
        let grabOffset = convert(event.locationInWindow, from: nil).x
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let x = splitView.convert(next.locationInWindow, from: nil).x - grabOffset
            splitView.setPosition(x, ofDividerAt: 0)
            if next.type == .leftMouseUp { break }
        }
        dragging = false
    }
}
