// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// The PDF's table of contents. Children are read from PDFOutline only as rows are expanded.
final class OutlinePane: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private weak var pdfView: PDFView?
    private let root: PDFOutline?
    private let outlineView = NSOutlineView()
    /// Outline entries in reading order with their page index, built on first use for "you are here".
    private lazy var flattened: [(item: PDFOutline, page: Int)] = {
        guard let root, let pdf = pdfView?.document else { return [] }
        var result: [(PDFOutline, Int)] = []
        func walk(_ node: PDFOutline) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                if let page = Self.destination(of: child)?.page { result.append((child, pdf.index(for: page))) }
                if result.count < 5000 { walk(child) }
            }
        }
        walk(root)
        return result
    }()
    private var revealing = false

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        root = pdfView.document?.outlineRoot
        super.init(frame: .zero)
        guard let root, root.numberOfChildren > 0 else {
            let label = emptyStateLabel("This PDF has no table of contents.")
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            ])
            return
        }
        let column = NSTableColumn(identifier: .init("label"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(clicked)
        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        pin(scroll, in: self)
        // A single top-level entry is usually the book title; open it so the chapters are visible.
        if root.numberOfChildren == 1, let only = root.child(at: 0) { outlineView.expandItem(only) }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func destination(of item: PDFOutline) -> PDFDestination? {
        item.destination ?? (item.action as? PDFActionGoTo)?.destination
    }

    @objc private func clicked() {
        guard !revealing, let item = outlineView.item(atRow: outlineView.clickedRow) as? PDFOutline else { return }
        if let destination = Self.destination(of: item) {
            pdfView?.go(to: destination)
        } else if let action = item.action {
            pdfView?.perform(action)
        }
    }

    /// Selects the section containing `page` if its row is visible in the tree (never expands on its own).
    func reveal(page: Int) {
        guard root != nil, !flattened.isEmpty else { return }
        // Latest-starting section at or before this page; on ties the later (deeper) entry wins.
        var match: PDFOutline?, matchPage = -1
        for entry in flattened where entry.page <= page && entry.page >= matchPage {
            match = entry.item
            matchPage = entry.page
        }
        guard let match else { outlineView.deselectAll(nil); return }
        let row = outlineView.row(forItem: match)
        guard row >= 0 else { return }
        revealing = true
        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        revealing = false
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? PDFOutline ?? root)?.numberOfChildren ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? PDFOutline ?? root)!.child(at: index)!
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        ((item as? PDFOutline)?.numberOfChildren ?? 0) > 0
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let text = (item as? PDFOutline)?.label ?? ""
        cell.textField?.stringValue = text
        cell.toolTip = text
        return cell
    }
}
