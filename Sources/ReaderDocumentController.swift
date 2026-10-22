// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

final class ReaderDocumentController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        Perf.openRequestedAt = Date()
        super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
    }

    // We only ever open PDFs; skip the Launch Services / UTType lookup.
    override func typeForContents(of url: URL) throws -> String { "com.adobe.pdf" }
}
