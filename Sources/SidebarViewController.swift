// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// The "menu" sidebar: Contents | Thumbnails | Highlights. Nothing here is built until the sidebar is first shown,
/// and each pane is built only when its tab is first selected.
final class SidebarViewController: NSViewController {
    enum Tab: Int { case contents, thumbnails, highlights }

    private unowned let owner: ReaderWindowController
    private let tabs = NSSegmentedControl()
    private let container = NSView()
    private var panes: [Tab: NSView] = [:]
    private var built = false
    private var selected: Tab?
    private var outlinePane: OutlinePane? { panes[.contents] as? OutlinePane }
    private var highlightsPane: HighlightsPane? { panes[.highlights] as? HighlightsPane }

    init(owner: ReaderWindowController) {
        self.owner = owner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
    }

    func activate() {
        guard !built, owner.pdf != nil else { return }
        built = true
        tabs.segmentCount = 3
        tabs.trackingMode = .selectOne
        for (i, (symbol, tip)) in [("list.bullet.indent", "Contents"), ("square.grid.2x2", "Thumbnails"),
                                   ("highlighter", "Highlights & Notes")].enumerated() {
            tabs.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: tip), forSegment: i)
            tabs.setToolTip(tip, forSegment: i)
            tabs.setWidth(52, forSegment: i)
        }
        tabs.target = self
        tabs.action = #selector(tabClicked)
        for subview in [tabs, container] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tabs.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let saved = Tab(rawValue: UserDefaults.standard.integer(forKey: "SidebarTab")) ?? .contents
        let hasOutline = (owner.pdf?.outlineRoot?.numberOfChildren ?? 0) > 0
        select(saved == .contents && !hasOutline ? .thumbnails : saved, remember: false)
    }

    @objc private func tabClicked() {
        if let tab = Tab(rawValue: tabs.selectedSegment) { select(tab) }
    }

    func select(_ tab: Tab, remember: Bool = true) {
        guard built else { return }
        tabs.selectedSegment = tab.rawValue
        if remember { UserDefaults.standard.set(tab.rawValue, forKey: "SidebarTab") }
        guard tab != selected else { return }
        selected = tab
        container.subviews.forEach { $0.removeFromSuperview() }
        let pane = panes[tab] ?? makePane(tab)
        panes[tab] = pane
        pane.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: container.topAnchor),
            pane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        pageChanged(to: owner.currentPageIndex)
    }

    private func makePane(_ tab: Tab) -> NSView {
        switch tab {
        case .contents: return OutlinePane(pdfView: owner.pdfView)
        case .thumbnails: return ThumbnailsPane(pdfView: owner.pdfView)
        case .highlights:
            let pane = HighlightsPane(pdfView: owner.pdfView, url: owner.reader?.fileURL, password: owner.reader?.password)
            pane.openNote = { [unowned owner] index, bounds in owner.editNote(onPage: index, bounds: bounds) }
            return pane
        }
    }

    func pageChanged(to index: Int) {
        switch selected {
        case .contents: outlinePane?.reveal(page: index)
        case .thumbnails: (panes[.thumbnails] as? ThumbnailsPane)?.reveal(page: index)
        default: break
        }
    }

    func annotationsChanged(added: [(PDFAnnotation, PDFPage, Int)], removed: [(PDFAnnotation, PDFPage, Int)]) {
        highlightsPane?.annotationsChanged(added: added, removed: removed)
    }

    func cancelWork() {
        highlightsPane?.cancel()
    }
}

/// Placeholder text for empty panes.
func emptyStateLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.alignment = .center
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

func pin(_ view: NSView, in parent: NSView, inset: CGFloat = 0) {
    view.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(view)
    NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
        view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
        view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
        view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
    ])
}

// MARK: - Thumbnails

final class ThumbnailsPane: NSView {
    private let thumbnails = PDFThumbnailView()

    init(pdfView: PDFView) {
        super.init(frame: .zero)
        thumbnails.pdfView = pdfView
        thumbnails.maximumNumberOfColumns = 1
        thumbnails.allowsDragging = false
        thumbnails.allowsMultipleSelection = false
        thumbnails.backgroundColor = .clear
        thumbnails.thumbnailSize = NSSize(width: 150, height: 200)
        pin(thumbnails, in: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// PDFThumbnailView marks the current page but never scrolls to it; its grid is an NSCollectionView inside.
    func reveal(page: Int) {
        guard let grid = Self.collectionView(in: thumbnails), grid.numberOfSections == 1,
              page < grid.numberOfItems(inSection: 0) else { return }
        let path = IndexPath(item: page, section: 0)
        if !grid.indexPathsForVisibleItems().contains(path) {
            grid.scrollToItems(at: [path], scrollPosition: .centeredVertically)
        }
    }

    private static func collectionView(in view: NSView) -> NSCollectionView? {
        for subview in view.subviews {
            if let grid = subview as? NSCollectionView { return grid }
            if let grid = collectionView(in: subview) { return grid }
        }
        return nil
    }

    override func layout() {
        super.layout()
        // Thumbnails fill the sidebar width; only re-render when the width changes meaningfully.
        let width = max(80, bounds.width - 48)
        if abs(thumbnails.thumbnailSize.width - width) > 12 {
            thumbnails.thumbnailSize = NSSize(width: width, height: width * 1.35)
        }
    }
}
