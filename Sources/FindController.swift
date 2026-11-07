// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// Incremental text search. PDFKit searches on its own background thread and reports matches as it goes,
/// so the first hit is shown long before a large document has been fully searched.
final class FindController: NSObject, NSSearchFieldDelegate, PDFDocumentDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private weak var owner: ReaderWindowController?
    private var query = ""
    private var matches: [PDFSelection] = []
    private var current = -1
    private var searching = false
    private var refreshScheduled = false
    private var typingWork: DispatchWorkItem?
    /// Highlighting every match on a huge result set gets expensive; this many is plenty to see where they are.
    private static let maxHighlighted = 1000

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    private weak var previewField: NSTextField?
    private var preview: NSPopover?
    private var previewRows = -1
    private var previewStatus = ""

    private weak var resultsTable: NSTableView?

    func makeResultsPane() -> NSView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: .init("match"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 58
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.backgroundColor = .clear
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(resultClicked(_:))
        table.setAccessibilityLabel("Find results")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = table
        resultsTable = table
        return scroll
    }

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("searchResult")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? NSTableCellView()
        if cell.textField == nil {
            cell.identifier = id
            let label = NSTextField(wrappingLabelWithString: "")
            label.maximumNumberOfLines = 3
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.heightAnchor.constraint(lessThanOrEqualToConstant: 54),
            ])
        }
        cell.textField?.stringValue = excerpt(at: row) ?? ""
        cell.toolTip = excerpt(at: row)
        return cell
    }

    private func excerpt(at row: Int) -> String? {
        guard matches.indices.contains(row), let page = matches[row].pages.first,
              let pdf = owner?.pdf, let context = matches[row].copy() as? PDFSelection else { return nil }
        context.extend(atStart: 22)
        context.extend(atEnd: 45)
        let excerpt = context.string?.components(separatedBy: .newlines).joined(separator: " ") ?? ""
        return "p. \(pdf.index(for: page) + 1)   \(excerpt)"
    }

    private func updatePreview() {
        guard let field = previewField, let window = field.window, field.stringValue == query,
              !query.isEmpty else { return }
        let count = min(4, matches.count)
        let message = count == 0 ? statusText : ""
        guard count != previewRows || message != previewStatus else { return }
        if let preview, !preview.isShown { return } // Dismissal lasts until the next query.
        let panel = preview ?? NSPopover()
        panel.animates = false
        panel.behavior = .transient
        let width = min(330, window.frame.width - 32)
        let height = CGFloat(max(1, count) + 1) * 28 + 12
        let controller = NSViewController()
        let list = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        func add(_ view: NSView, row: Int) {
            view.frame = NSRect(x: 8, y: height - 33 - CGFloat(row) * 28, width: width - 16, height: 26)
            list.addSubview(view)
        }
        if count == 0 { add(NSTextField(labelWithString: message), row: 0) }
        for index in 0..<count {
            let button = NSButton(title: excerpt(at: index) ?? "", target: self, action: #selector(pickPreview(_:)))
            button.tag = index
            button.isBordered = false
            button.alignment = .left
            button.cell?.lineBreakMode = .byTruncatingTail
            add(button, row: index)
        }
        add(NSButton(title: "Open Results in Sidebar", target: self, action: #selector(openResults(_:))), row: max(1, count))
        controller.view = list
        let editor = field.currentEditor()
        panel.contentViewController = controller
        panel.contentSize = list.frame.size
        previewRows = count
        previewStatus = message
        preview = panel
        if !panel.isShown {
            panel.show(relativeTo: field.bounds, of: field, preferredEdge: field.isFlipped ? .maxY : .minY)
            if let editor { window.makeFirstResponder(editor) }
        }
    }

    private func dismissPreview() {
        preview?.close()
        preview = nil
        previewRows = -1
    }

    @objc private func pickPreview(_ sender: NSButton) {
        guard matches.indices.contains(sender.tag) else { return }
        previewField = nil
        dismissPreview()
        current = sender.tag
        show(current)
        refresh()
    }

    @objc private func openResults(_ sender: Any?) {
        previewField = nil
        dismissPreview()
        owner?.showResults(sender)
    }

    @objc private func resultClicked(_ sender: NSTableView) {
        guard matches.indices.contains(sender.selectedRow) else { return }
        current = sender.selectedRow
        show(current)
        refresh()
    }

    var hasMatches: Bool { !matches.isEmpty }
    /// "3 of 57", "No matches", … (shown by the window in the bar or the toolbar subtitle).
    private(set) var statusText = ""

    /// Search as you type, once typing pauses briefly.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        previewField = field
        dismissPreview()
        typingWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak field] in
            guard let self, let text = field?.stringValue, text != self.query else { return }
            self.search(text)
        }
        typingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            typingWork?.cancel()
            let text = (control as? NSTextField)?.stringValue ?? ""
            if text != query {
                search(text)
            } else {
                let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                step(backwards ? -1 : 1)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            typingWork?.cancel()
            (control as? NSTextField)?.stringValue = ""
            search("")
            owner?.endFind()
            return true
        default:
            return false
        }
    }

    func search(_ text: String) {
        guard let owner, let pdf = owner.pdf else { return }
        cancel()
        matches = []
        resultsTable?.reloadData()
        current = -1
        owner.pdfView.highlightedSelections = nil
        if !query.isEmpty { owner.pdfView.clearSelection() }
        query = text
        guard text.count >= 1 else { statusText = ""; owner.refreshStatus(); return }
        searching = true
        pdf.delegate = self
        pdf.beginFindString(text, withOptions: [.caseInsensitive, .diacriticInsensitive])
        refresh()
    }

    func cancel() {
        dismissPreview()
        if searching { owner?.pdf?.cancelFindString() }
        searching = false
    }

    func step(_ delta: Int) {
        guard !matches.isEmpty else {
            if query.isEmpty { owner?.startFind(nil) }
            return
        }
        current = (current + delta + matches.count) % matches.count
        show(current)
        refresh()
    }

    private func show(_ index: Int) {
        guard let pdfView = owner?.pdfView, matches.indices.contains(index) else { return }
        let selection = matches[index]
        pdfView.go(to: selection)
        pdfView.setCurrentSelection(selection, animate: true)
    }

    // MARK: PDFDocumentDelegate

    func didMatchString(_ instance: PDFSelection) {
        onMain { [self] in
            guard searching else { return }
            instance.color = .findHighlightColor
            matches.append(instance)
            if matches.count == 1 {
                current = 0
                show(0)
            }
            scheduleRefresh()
        }
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        onMain { [self] in
            searching = false
            refresh()
        }
    }

    // MARK: Status

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    private func refresh() {
        guard let owner else { return }
        owner.pdfView.highlightedSelections = matches.isEmpty ? nil : Array(matches.prefix(Self.maxHighlighted))
        let status: String
        if query.isEmpty {
            status = ""
        } else if matches.isEmpty {
            status = searching ? "Searching…" : "No matches"
        } else {
            let total = "\(matches.count)\(searching ? "+" : "")"
            status = "\(current + 1) of \(total)"
        }
        resultsTable?.noteNumberOfRowsChanged()
        statusText = status
        updatePreview()
        owner.refreshStatus()
    }

    /// The glass toolbar's search field: Return or its clear button.
    @objc func searchFieldAction(_ sender: NSSearchField) {
        typingWork?.cancel()
        if sender.stringValue != query { search(sender.stringValue) }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
