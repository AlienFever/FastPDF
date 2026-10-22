// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit
import os

struct AnnotationEntry {
    let pageIndex: Int
    let bounds: CGRect
    let kind: String
    let text: String
    let note: String?
    let color: NSColor
}

/// Lists highlights, underlines, strike-throughs and notes. The scan runs on a background thread against its own
/// PDFDocument instance (PDFKit objects aren't safe to share with the view that's drawing), and rows appear as found.
final class HighlightsPane: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private weak var pdfView: PDFView?
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private var entries: [AnnotationEntry] = []
    private let cancelled = OSAllocatedUnfairLock(initialState: false)
    private var empty: NSTextField?
    /// Opens a sticky note's editor (set by the sidebar).
    var openNote: ((Int, CGRect) -> Void)?

    init(pdfView: PDFView, url: URL?, password: String?) {
        self.pdfView = pdfView
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: .init("entry"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        addSubview(status)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            status.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        if let url { scan(url: url, password: password) } else { finish() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func cancel() { cancelled.withLock { $0 = true } }

    private func scan(url: URL, password: String?) {
        status.stringValue = "Scanning…"
        let cancelled = self.cancelled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let doc = PDFDocument(url: url) else {
                DispatchQueue.main.async { self?.finish() }
                return
            }
            if doc.isLocked, let password { doc.unlock(withPassword: password) }
            let count = doc.pageCount
            var pending: [AnnotationEntry] = []
            var lastFlush = Date()
            for i in 0..<count {
                if cancelled.withLock({ $0 }) { return }
                autoreleasepool {
                    guard let page = doc.page(at: i) else { return }
                    for annotation in page.annotations {
                        if let entry = Self.entry(for: annotation, on: page, index: i) { pending.append(entry) }
                    }
                }
                if Date().timeIntervalSince(lastFlush) > 0.15 || i == count - 1 {
                    let batch = pending, scanned = i + 1
                    pending = []
                    lastFlush = Date()
                    DispatchQueue.main.async { self?.append(batch, scanned: scanned, of: count) }
                }
            }
            DispatchQueue.main.async { self?.finish() }
        }
    }

    private func append(_ batch: [AnnotationEntry], scanned: Int, of total: Int) {
        if !batch.isEmpty {
            let start = entries.count
            entries += batch
            table.insertRows(at: IndexSet(start..<entries.count), withAnimation: [])
        }
        status.stringValue = "Scanning… page \(scanned) of \(total)"
    }

    private func finish() {
        let count = entries.count
        status.stringValue = count == 0 ? "" : "\(count) item\(count == 1 ? "" : "s")"
        if count == 0, empty == nil {
            let label = emptyStateLabel("No highlights or notes in this document.")
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            ])
            empty = label
        }
    }

    /// Keeps the list in step with highlights made or removed in this window (the scan reads the file on disk,
    /// which doesn't have them until the next save).
    func annotationsChanged(added: [(PDFAnnotation, PDFPage, Int)], removed: [(PDFAnnotation, PDFPage, Int)]) {
        for (annotation, _, index) in removed {
            guard let row = entries.firstIndex(where: { $0.pageIndex == index && $0.bounds.isClose(to: annotation.bounds) })
            else { continue }
            entries.remove(at: row)
            table.removeRows(at: [row], withAnimation: [])
        }
        for (annotation, page, index) in added {
            guard let entry = Self.entry(for: annotation, on: page, index: index) else { continue }
            let row = entries.firstIndex { $0.pageIndex > index } ?? entries.count
            entries.insert(entry, at: row)
            table.insertRows(at: [row], withAnimation: [])
        }
        empty?.isHidden = !entries.isEmpty
        if !status.stringValue.hasPrefix("Scanning") {
            status.stringValue = entries.isEmpty ? "" : "\(entries.count) item\(entries.count == 1 ? "" : "s")"
        }
    }

    @objc private func clicked() {
        let row = table.clickedRow
        guard entries.indices.contains(row), let pdfView, let page = pdfView.document?.page(at: entries[row].pageIndex) else { return }
        let bounds = entries[row].bounds
        pdfView.go(to: bounds.insetBy(dx: 0, dy: -60), on: page)
        if entries[row].kind == "Note" {
            // Let the page scroll into place, then open the note beside its icon.
            let index = entries[row].pageIndex
            DispatchQueue.main.async { [weak self] in self?.openNote?(index, bounds) }
            return
        }
        if let selection = page.selection(for: bounds), !(selection.string ?? "").isEmpty {
            pdfView.setCurrentSelection(selection, animate: true)
        }
    }

    // MARK: Annotation parsing (background thread)

    private static let markupKinds = ["Highlight": "Highlight", "Underline": "Underline",
                                      "StrikeOut": "Strikethrough", "Squiggly": "Squiggly"]
    private static let noteKinds = ["Text": "Note", "FreeText": "Text Box"]

    static func entry(for annotation: PDFAnnotation, on page: PDFPage, index: Int) -> AnnotationEntry? {
        let type = annotation.type ?? ""
        let contents = clean(annotation.contents ?? "")
        if let kind = markupKinds[type] {
            var text = markedText(annotation, on: page)
            if text.isEmpty { text = clean(page.selection(for: annotation.bounds)?.string ?? "") }
            return AnnotationEntry(pageIndex: index, bounds: annotation.bounds, kind: kind, text: text,
                                   note: contents.isEmpty ? nil : contents, color: annotation.color)
        }
        if let kind = noteKinds[type] {
            return AnnotationEntry(pageIndex: index, bounds: annotation.bounds, kind: kind, text: contents,
                                   note: nil, color: annotation.color)
        }
        return nil
    }

    /// Text under each quadrilateral (one per marked line), so multi-line highlights read correctly.
    private static func markedText(_ annotation: PDFAnnotation, on page: PDFPage) -> String {
        let points = annotation.quadrilateralPoints?.map(\.pointValue) ?? []
        guard points.count >= 4 else { return "" }
        let bounds = annotation.bounds
        var parts: [String] = []
        for start in stride(from: 0, through: points.count - 4, by: 4) {
            let quad = points[start..<start + 4]
            let xs = quad.map(\.x), ys = quad.map(\.y)
            var rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            // PDFKit reports quad points relative to the annotation's origin; some files come through in page space.
            let relative = rect.offsetBy(dx: bounds.minX, dy: bounds.minY)
            if bounds.insetBy(dx: -2, dy: -2).intersects(relative) || !bounds.intersects(rect) { rect = relative }
            if let text = page.selection(for: rect.insetBy(dx: 0, dy: rect.height * 0.25))?.string {
                parts.append(text)
            }
        }
        return clean(parts.joined(separator: " "))
    }

    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    private func attributedText(for entry: AnnotationEntry) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        result.append(NSAttributedString(string: "● ", attributes: [.font: small, .foregroundColor: entry.color.withAlphaComponent(1)]))
        result.append(NSAttributedString(string: "Page \(entry.pageIndex + 1) · \(entry.kind)\n",
                                         attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor]))
        let body = entry.text.isEmpty ? "(no text)" : String(entry.text.prefix(220)) + (entry.text.count > 220 ? "…" : "")
        result.append(NSAttributedString(string: body, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                                                    .foregroundColor: NSColor.labelColor]))
        if let note = entry.note {
            let italic = NSFontManager.shared.convert(small, toHaveTrait: .italicFontMask)
            result.append(NSAttributedString(string: "\n" + String(note.prefix(160)),
                                             attributes: [.font: italic, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return result
    }

    private var textWidth: CGFloat { max(60, table.bounds.width - 28) }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let rect = attributedText(for: entries[row]).boundingRect(with: NSSize(width: textWidth, height: 10_000),
                                                                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height) + 12
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("entry")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(wrappingLabelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
            ])
            return cell
        }()
        cell.textField?.preferredMaxLayoutWidth = textWidth
        cell.textField?.attributedStringValue = attributedText(for: entries[row])
        return cell
    }

    override func layout() {
        let oldWidth = table.bounds.width
        super.layout()
        if abs(table.bounds.width - oldWidth) > 1, !entries.isEmpty {
            table.noteHeightOfRows(withIndexesChanged: IndexSet(0..<entries.count))
        }
    }
}
