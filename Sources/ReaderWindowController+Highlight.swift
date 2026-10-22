// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// A highlight and the page it sits on, for menus that act on one highlight.
final class HighlightRef: NSObject {
    let annotation: PDFAnnotation
    let page: PDFPage
    let color: HighlightColor?

    init(_ annotation: PDFAnnotation, on page: PDFPage, color: HighlightColor? = nil) {
        self.annotation = annotation
        self.page = page
        self.color = color
    }
}

extension ReaderWindowController {
    // H / K: highlight the selection, or with nothing selected, toggle highlight mode in that color.
    @objc func highlightPrimary(_ sender: Any?) { highlightOrToggleMode(.primary) }
    @objc func highlightSecondary(_ sender: Any?) { highlightOrToggleMode(.secondary) }

    private func highlightOrToggleMode(_ color: HighlightColor) {
        if let selection = pdfView.currentSelection, selection.hasText {
            highlight(selection, color: color)
            pdfView.clearSelection()
        } else {
            highlightMode = highlightMode == color ? nil : color
        }
    }

    /// In highlight mode every finished text selection becomes a highlight.
    func selectionFinished() {
        guard let color = highlightMode, let selection = pdfView.currentSelection, selection.hasText else { return }
        highlight(selection, color: color)
        pdfView.clearSelection()
    }

    func highlight(_ selection: PDFSelection, color: HighlightColor) {
        guard let reader else { return }
        guard reader.canAnnotate else { return showCannotAnnotate() }
        let lines = selection.selectionsByLine()
        var added: [(PDFAnnotation, PDFPage)] = []
        // One annotation per page, with one quad per line, so other apps treat it as a single highlight.
        for page in selection.pages {
            let rects = lines.map { $0.bounds(for: page) }.filter { $0.width > 0.5 && $0.height > 0.5 }
            guard let first = rects.first else { continue }
            let union = rects.dropFirst().reduce(first) { $0.union($1) }
            let quads = rects.flatMap { rect -> [CGPoint] in
                let r = rect.offsetBy(dx: -union.minX, dy: -union.minY)
                return [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
                        CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)]
            }
            added.append((AnnotationChange.makeHighlight(bounds: union, quadPoints: quads, color: color.color), page))
        }
        changeAnnotations(adding: added, removing: [], actionName: "Highlight")
    }

    /// Removes highlights touching the current selection.
    @objc func removeSelectedHighlights(_ sender: Any?) {
        changeAnnotations(adding: [], removing: highlightsUnderSelection(), actionName: "Remove Highlight")
    }

    @objc func removeHighlight(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? HighlightRef else { return }
        changeAnnotations(adding: [], removing: [(ref.annotation, ref.page)], actionName: "Remove Highlight")
    }

    @objc func recolorHighlight(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? HighlightRef, let color = ref.color else { return }
        let old = ref.annotation
        let new = AnnotationChange.makeMarkup(type: old.type ?? "Highlight", bounds: old.bounds,
                                              quadPoints: old.quadrilateralPoints?.map(\.pointValue) ?? [],
                                              color: color.color, text: old.contents)
        changeAnnotations(adding: [(new, ref.page)], removing: [(old, ref.page)], actionName: "Change Highlight Color")
    }

    private func highlightsUnderSelection() -> [(PDFAnnotation, PDFPage)] {
        guard let selection = pdfView.currentSelection else { return [] }
        return selection.pages.flatMap { page in
            let area = selection.bounds(for: page)
            return page.annotations.filter { $0.isTextMarkup && $0.bounds.intersects(area) }.map { ($0, page) }
        }
    }

    /// Every highlight edit goes through here: it updates the page, queues the change for saving, keeps the
    /// sidebar list in sync and registers the inverse with Undo.
    func changeAnnotations(adding added: [(PDFAnnotation, PDFPage)], removing removed: [(PDFAnnotation, PDFPage)],
                           actionName: String) {
        guard let pdf, let reader, !(added.isEmpty && removed.isEmpty) else { return }
        for (annotation, page) in removed {
            page.removeAnnotation(annotation)
            reader.record(AnnotationChange(.remove, annotation, pageIndex: pdf.index(for: page)))
        }
        for (annotation, page) in added {
            page.addAnnotation(annotation)
            reader.record(AnnotationChange(.add, annotation, pageIndex: pdf.index(for: page)))
        }
        sidebar.annotationsChanged(added: added.map { ($0.0, $0.1, pdf.index(for: $0.1)) },
                                   removed: removed.map { ($0.0, $0.1, pdf.index(for: $0.1)) })
        let undo = reader.undoManager
        undo?.registerUndo(withTarget: self) { target in
            target.changeAnnotations(adding: removed, removing: added, actionName: actionName)
        }
        undo?.setActionName(actionName)
    }

    private func showCannotAnnotate() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "This PDF can’t be highlighted"
        alert.informativeText = pdf?.isEncrypted == true
            ? "FastPDF for Mac doesn’t save highlights into password-protected PDFs."
            : "The PDF’s permissions don’t allow comments or highlights."
        alert.beginSheetModal(for: window)
    }

    /// Items for the right-click menu when the click lands on a highlight.
    func contextMenuItems(for annotation: PDFAnnotation, on page: PDFPage) -> [NSMenuItem] {
        let remove = NSMenuItem(title: "Remove Highlight", action: #selector(removeHighlight(_:)), keyEquivalent: "")
        remove.target = self
        remove.representedObject = HighlightRef(annotation, on: page)
        let colors = NSMenu()
        for color in HighlightColor.allCases {
            let item = NSMenuItem(title: color.name, action: #selector(recolorHighlight(_:)), keyEquivalent: "")
            item.target = self
            item.image = color.swatch
            item.representedObject = HighlightRef(annotation, on: page, color: color)
            colors.addItem(item)
        }
        let recolor = NSMenuItem(title: "Change Color", action: nil, keyEquivalent: "")
        recolor.submenu = colors
        return [remove, recolor, .separator()]
    }

    func updateHighlightControls() {
        bar.highlightButton.tint = HighlightColor.primary.color.blended(withFraction: 0.25, of: .black) ?? .secondaryLabelColor
        bar.highlightButton.activeColor = highlightMode?.color
        toolbarControls.highlightItem?.image = Self.highlighterImage(color: highlightMode?.color)
        bar.noteButton.activeColor = placingNote ? Self.noteColor : nil
        let noteImage = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Add Note")
        toolbarControls.noteItem?.image = placingNote
            ? noteImage?.withSymbolConfiguration(.init(paletteColors: [Self.noteColor])) : noteImage
        refreshStatus()
    }

    static func highlighterImage(color: NSColor?) -> NSImage? {
        let base = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Highlight")
        guard let color else { return base }
        return base?.withSymbolConfiguration(.init(paletteColors: [color]))
    }
}

extension PDFSelection {
    var hasText: Bool { !(string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
