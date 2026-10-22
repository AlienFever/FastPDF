// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import PDFKit

/// The value of one form field widget, captured on the main thread so the background save can copy it onto its
/// own copy of the document (PDFKit fills in forms in the window; FastPDF only has to notice and save them).
struct FormValue: Equatable {
    let pageIndex: Int
    let fieldName: String?
    let bounds: CGRect
    let text: String?
    let state: Int

    init(_ widget: PDFAnnotation, pageIndex: Int) {
        self.pageIndex = pageIndex
        fieldName = widget.fieldName
        bounds = widget.bounds
        text = widget.widgetFieldType == .button ? nil : widget.widgetStringValue
        state = widget.widgetFieldType == .button ? widget.buttonWidgetState.rawValue : 0
    }

    /// Fillable widgets on a page (signature fields aren't filled in here).
    static func widgets(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { $0.type == "Widget" && $0.widgetFieldType != .signature }
    }

    static func values(on page: PDFPage, index: Int) -> [FormValue] {
        widgets(on: page).map { FormValue($0, pageIndex: index) }
    }

    func apply(to document: PDFDocument) {
        guard let page = document.page(at: pageIndex),
              let widget = Self.widgets(on: page).first(where: { $0.fieldName == fieldName && $0.bounds.isClose(to: bounds) })
        else { return }
        if widget.widgetFieldType == .button {
            widget.buttonWidgetState = PDFWidgetCellState(rawValue: state) ?? .offState
        } else {
            widget.widgetStringValue = text
        }
    }
}
