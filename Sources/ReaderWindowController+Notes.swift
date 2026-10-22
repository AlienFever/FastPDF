// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// Sticky notes: standard PDF "Text" annotations, shown as note icons on the page.
extension ReaderWindowController {
    static let noteColor = NSColor(srgbRed: 1.0, green: 0.84, blue: 0.25, alpha: 1)

    /// N: with text selected, puts a note beside the selection; otherwise the next click on a page places one.
    @objc func startPlacingNote(_ sender: Any?) {
        guard let reader, reader.canAnnotate else { return showCannotAnnotateNotes() }
        if let selection = pdfView.currentSelection, selection.hasText, let page = selection.pages.first {
            let line = selection.selectionsByLine().first?.bounds(for: page) ?? selection.bounds(for: page)
            pdfView.clearSelection()
            placeNote(at: CGPoint(x: line.maxX + 14, y: line.maxY), on: page)
        } else {
            placingNote.toggle()
        }
    }

    @objc func addNoteHere(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? NoteTarget else { return }
        guard reader?.canAnnotate == true else { return showCannotAnnotateNotes() }
        placeNote(at: target.point, on: target.page)
    }

    /// Shows a note icon at once and opens the editor; the note is only kept (and undoable) once it has text.
    func placeNote(at point: CGPoint, on page: PDFPage) {
        placingNote = false
        let size: CGFloat = 22
        let box = page.bounds(for: pdfView.displayBox)
        let origin = CGPoint(x: min(max(point.x - size / 2, box.minX), box.maxX - size),
                             y: min(max(point.y - size / 2, box.minY), box.maxY - size))
        let draft = AnnotationChange.makeNote(bounds: CGRect(origin: origin, size: CGSize(width: size, height: size)),
                                              text: "", color: Self.noteColor)
        page.addAnnotation(draft)
        showNoteEditor(for: draft, on: page, isNew: true)
    }

    func editNote(_ note: PDFAnnotation, on page: PDFPage) {
        showNoteEditor(for: note, on: page, isNew: false)
    }

    /// From the sidebar list: find the note on the page shown here and open it.
    func editNote(onPage index: Int, bounds: CGRect) {
        guard let page = pdf?.page(at: index),
              let note = page.annotations.first(where: { $0.isNote && $0.bounds.isClose(to: bounds) }) else { return }
        editNote(note, on: page)
    }

    @objc func editNoteFromMenu(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? HighlightRef else { return }
        editNote(ref.annotation, on: ref.page)
    }

    @objc func deleteNoteFromMenu(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? HighlightRef else { return }
        changeAnnotations(adding: [], removing: [(ref.annotation, ref.page)], actionName: "Delete Note")
    }

    private func showNoteEditor(for note: PDFAnnotation, on page: PDFPage, isNew: Bool) {
        let pageNumber = (pdf.map { $0.index(for: page) } ?? 0) + 1
        let editor = NoteEditorViewController(text: note.contents ?? "", title: "Note · Page \(pageNumber)")
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = editor
        popover.delegate = editor
        editor.popover = popover
        editor.onDelete = { [weak self, weak popover] in
            editor.deleted = true
            popover?.close()
            if !isNew { self?.changeAnnotations(adding: [], removing: [(note, page)], actionName: "Delete Note") }
        }
        editor.onClose = { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if isNew {
                page.removeAnnotation(note)   // the draft; replaced by a recorded note below
                guard !editor.deleted, !trimmed.isEmpty else { return }
                let final = AnnotationChange.makeNote(bounds: note.bounds, text: text, color: note.color)
                self.changeAnnotations(adding: [(final, page)], removing: [], actionName: "Add Note")
            } else if !editor.deleted, text != (note.contents ?? "") {
                if trimmed.isEmpty {
                    self.changeAnnotations(adding: [], removing: [(note, page)], actionName: "Delete Note")
                } else {
                    let edited = AnnotationChange.makeNote(bounds: note.bounds, text: text, color: note.color)
                    self.changeAnnotations(adding: [(edited, page)], removing: [(note, page)], actionName: "Edit Note")
                }
            }
            self.window?.makeFirstResponder(self.pdfView)
        }
        let anchor = pdfView.convert(note.bounds, from: page)
        popover.show(relativeTo: anchor, of: pdfView, preferredEdge: .maxX)
    }

    func noteContextMenuItems(for note: PDFAnnotation, on page: PDFPage) -> [NSMenuItem] {
        let edit = NSMenuItem(title: "Edit Note", action: #selector(editNoteFromMenu(_:)), keyEquivalent: "")
        let delete = NSMenuItem(title: "Delete Note", action: #selector(deleteNoteFromMenu(_:)), keyEquivalent: "")
        for item in [edit, delete] {
            item.target = self
            item.representedObject = HighlightRef(note, on: page)
        }
        return [edit, delete, .separator()]
    }

    func addNoteMenuItem(at point: CGPoint, on page: PDFPage) -> NSMenuItem {
        let item = NSMenuItem(title: "Add Note Here", action: #selector(addNoteHere(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
        item.representedObject = NoteTarget(page: page, point: point)
        return item
    }

    private func showCannotAnnotateNotes() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Notes can’t be added to this PDF"
        alert.informativeText = pdf?.isEncrypted == true
            ? "FastPDF doesn’t save annotations into password-protected PDFs."
            : "The PDF’s permissions don’t allow comments."
        alert.beginSheetModal(for: window)
    }
}

final class NoteTarget: NSObject {
    let page: PDFPage
    let point: CGPoint

    init(page: PDFPage, point: CGPoint) {
        self.page = page
        self.point = point
    }
}

/// The popover for reading and writing a note. Closing it (click outside, Esc, Done) keeps the text.
final class NoteEditorViewController: NSViewController, NSPopoverDelegate {
    var onClose: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var deleted = false
    weak var popover: NSPopover?
    private let initialText: String
    private let titleText: String
    private let textView = NSTextView()

    init(text: String, title: String) {
        initialText = text
        titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 190))
        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor

        textView.string = initialText
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let delete = NSButton(title: "Delete", target: self, action: #selector(deleteNote))
        delete.bezelStyle = .push
        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.bezelStyle = .push
        done.keyEquivalent = "\r"
        done.keyEquivalentModifierMask = [.command]
        done.toolTip = "⌘Return"

        for subview in [title, scroll, delete, done] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -8),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            done.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            delete.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            delete.centerYAnchor.constraint(equalTo: done.centerYAnchor),
        ])
        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    @objc private func done() { popover?.close() }

    @objc private func deleteNote() { onDelete?() }

    func popoverDidClose(_ notification: Notification) {
        onClose?(textView.string)
        onClose = nil
    }
}
