// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit
import UniformTypeIdentifiers

extension ReaderWindowController {
    @objc func copyWithSource(_ sender: Any?) {
        guard let pdf, pdf.allowsCopying, let selection = pdfView.currentSelection,
              let text = selection.string, let first = selection.pages.first,
              let last = selection.pages.last, let name = reader?.fileURL?.lastPathComponent else { return }
        let start = pdf.index(for: first) + 1, end = pdf.index(for: last) + 1
        let pages = start == end ? "p. \(start)" : "pp. \(start)–\(end)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(text)\n\n— \(name), \(pages)", forType: .string)
    }

    @objc func printPages(_ sender: Any?) {
        guard let window, let pdf, pdf.allowsPrinting,
              let operation = pdf.printOperation(for: .shared, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        operation.printPanel.options.insert(.showsPageRange)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func exportAnnotations(_ sender: Any?) {
        guard let window, let pdf, pdf.allowsCopying, let url = reader?.fileURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + " - Notes.md"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                let markdown = await Self.annotationMarkdown(for: pdf, filename: url.lastPathComponent)
                do { try markdown.write(to: destination, atomically: true, encoding: .utf8) }
                catch { NSApp.presentError(error) }
            }
        }
    }

    @MainActor static func annotationMarkdown(for pdf: PDFDocument, filename: String) async -> String {
        var lines = ["# " + filename]
        for index in 0..<pdf.pageCount {
            if let page = pdf.page(at: index) {
                let entries = page.annotations.compactMap { HighlightsPane.entry(for: $0, on: page, index: index) }
                if !entries.isEmpty { lines += ["", "## Page \(index + 1)", ""] }
                for entry in entries {
                    lines.append("- **\(entry.kind)** \(entry.text)")
                    if let note = entry.note { lines.append("  - \(note)") }
                }
            }
            if index % 8 == 0 { await Task.yield() }
        }
        if lines.count == 1 { lines += ["", "No highlights or notes."] }
        return lines.joined(separator: "\n") + "\n"
    }
}
