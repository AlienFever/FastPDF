// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// Form filling. PDFKit already lets you type into fields, tick boxes and pick choices; this notices when a field
/// changes, so the document counts as edited, and hands the values to the save.
extension ReaderWindowController {
    func connectForms() {
        guard let reader else { return }
        reader.formValuesProvider = { [weak self] in self?.currentFormValues() ?? [] }
        reader.formsSaved = { [weak self] saved in self?.formsSaved(saved) }
        reader.checkForms = { [weak self] endEditing in self?.checkFormChanges(endEditing: endEditing) }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(formTextChanged(_:)), name: NSText.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(formTextChanged(_:)), name: NSText.didEndEditingNotification, object: nil)
    }

    /// Called on every click in the page, before PDFKit handles it: the first time a page with form fields is
    /// clicked, remember its field values as they were, so later changes can be detected.
    func willClickPage(_ page: PDFPage) {
        guard let pdf else { return }
        let index = pdf.index(for: page)
        guard formBaseline[index] == nil else { return }
        let values = FormValue.values(on: page, index: index)
        if !values.isEmpty { formBaseline[index] = values }
    }

    @objc private func formTextChanged(_ notification: Notification) {
        guard let view = notification.object as? NSView, view.isDescendant(of: pdfView) else { return }
        checkFormChanges()
    }

    /// Marks the document edited if any touched field differs from its last saved value.
    func checkFormChanges(endEditing: Bool = false) {
        guard let reader, reader.canAnnotate, !formBaseline.isEmpty else { return }
        // A field still being typed in commits its value when editing ends (needed before saving or closing).
        if endEditing, let editor = window?.firstResponder as? NSView, editor !== pdfView, editor.isDescendant(of: pdfView) {
            window?.makeFirstResponder(pdfView)
        }
        guard !reader.formsEdited else { return }
        if currentFormValues() != formBaseline.keys.sorted().flatMap({ formBaseline[$0]! }) {
            reader.formsDidChange()
        }
    }

    func currentFormValues() -> [FormValue] {
        guard let pdf else { return [] }
        return formBaseline.keys.sorted().flatMap { index in
            pdf.page(at: index).map { FormValue.values(on: $0, index: index) } ?? []
        }
    }

    /// After a save the saved values become the new baseline; anything typed while saving still counts as a change.
    private func formsSaved(_ saved: [FormValue]) {
        for index in Set(saved.map(\.pageIndex)) {
            formBaseline[index] = saved.filter { $0.pageIndex == index }
        }
        checkFormChanges()
    }
}
