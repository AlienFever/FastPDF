// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// Popover listing the user's own page bookmarks for this file (stored by FastPDF; the PDF is never modified).
final class BookmarksViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let owner: ReaderWindowController
    private let toggle = NSButton()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(wrappingLabelWithString: "No bookmarks yet.\nPress ⌘D to bookmark the current page.")
    private var pages: [Int] = []
    private var snippets: [Int: String] = [:]
    private static let rowHeight: CGFloat = 40

    init(owner: ReaderWindowController) {
        self.owner = owner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        toggle.bezelStyle = .push
        toggle.controlSize = .large
        toggle.target = self
        toggle.action = #selector(toggleCurrent)
        let column = NSTableColumn(identifier: .init("bookmark"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = Self.rowHeight
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        for subview in [toggle, scroll, empty] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            toggle.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            toggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            toggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: toggle.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    func reload() {
        _ = view
        pages = owner.bookmarks
        let current = owner.currentPageIndex
        toggle.title = pages.contains(current) ? "Remove Bookmark for Page \(current + 1)" : "Bookmark Page \(current + 1)"
        empty.isHidden = !pages.isEmpty
        table.reloadData()
        let listHeight = pages.isEmpty ? 70 : min(CGFloat(pages.count) * (Self.rowHeight + 4) + 12, 360)
        preferredContentSize = NSSize(width: 300, height: 12 + 32 + 8 + listHeight + 6)
    }

    @objc private func toggleCurrent() { owner.toggleBookmark(nil) }

    @objc private func clicked() {
        guard pages.indices.contains(table.clickedRow) else { return }
        owner.go(toPage: pages[table.clickedRow])
        owner.bookmarksPopover.close()
    }

    @objc private func remove(_ sender: NSButton) {
        guard pages.indices.contains(sender.tag) else { return }
        owner.removeBookmark(pages[sender.tag])
    }

    /// First line of the page's text, so bookmarks are recognizable without opening them.
    private func snippet(for index: Int) -> String {
        if let cached = snippets[index] { return cached }
        let text = owner.pdf?.page(at: index)?.string ?? ""
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let result = String(line.prefix(80))
        snippets[index] = result
        return result
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("bookmark")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? BookmarkCell ?? BookmarkCell(id: id)
        cell.title.stringValue = "Page \(pages[row] + 1)"
        cell.subtitle.stringValue = snippet(for: pages[row])
        cell.removeButton.tag = row
        cell.removeButton.target = self
        cell.removeButton.action = #selector(remove(_:))
        return cell
    }
}

private final class BookmarkCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let removeButton = NSButton()

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove Bookmark")
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.toolTip = "Remove Bookmark"
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for subview in [text, removeButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -6),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
