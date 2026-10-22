// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// Incremental text search. PDFKit searches on its own background thread and reports matches as it goes,
/// so the first hit is shown long before a large document has been fully searched.
final class FindController: NSObject, NSSearchFieldDelegate, PDFDocumentDelegate {
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

    var hasMatches: Bool { !matches.isEmpty }
    /// "3 of 57", "No matches", … (shown by the window in the bar or the toolbar subtitle).
    private(set) var statusText = ""

    /// Search as you type, once typing pauses briefly.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
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
        statusText = status
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
