// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// A PDF document. Reading is lazy and read-only; the only edits are highlight annotations, which are written
/// back into the file (in the background) on ⌘S, or automatically when File ▸ Autosave Highlights is on.
@objc(ReaderDocument)
final class ReaderDocument: NSDocument {
    private(set) var pdf: PDFDocument?
    private(set) var stateKey = ""
    private(set) var savedState: FileState?
    /// Kept in memory only, so the highlights scanner can open its own copy of an encrypted file.
    var password: String?

    /// Annotation edits not yet written to disk, in order.
    private let changesLock = NSLock()
    private var pendingChanges: [AnnotationChange] = []
    private var autosaveWork: DispatchWorkItem?

    static var autosaveEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "AutosaveHighlights") }
        set { UserDefaults.standard.set(newValue, forKey: "AutosaveHighlights") }
    }

    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override class var preservesVersions: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    override func read(from url: URL, ofType typeName: String) throws {
        // PDFDocument parses lazily (xref + trailer); pages are decoded only when drawn.
        guard let pdf = PDFDocument(url: url) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }
        stateKey = FileStateStore.key(for: pdf, url: url)
        savedState = FileStateStore.shared.state(for: stateKey)
        self.pdf = pdf
    }

    override func makeWindowControllers() {
        addWindowController(ReaderWindowController())
    }

    // MARK: Annotation edits

    /// Encrypted files would need their passwords re-applied on save, and some PDFs forbid comments.
    var canAnnotate: Bool { pdf.map { !$0.isEncrypted && $0.allowsCommenting } ?? false }

    func record(_ change: AnnotationChange) {
        changesLock.withLock { pendingChanges.append(change) }
        if Self.autosaveEnabled { scheduleSave() }
    }

    private func scheduleSave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveChanges() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private var hasPendingChanges: Bool { changesLock.withLock { !pendingChanges.isEmpty } }

    func saveChanges(completion: ((Error?) -> Void)? = nil) {
        autosaveWork?.cancel()
        guard hasPendingChanges, isDocumentEdited, let url = fileURL else { completion?(nil); return }
        save(to: url, ofType: fileType ?? "com.adobe.pdf", for: .saveOperation) { error in completion?(error) }
    }

    /// ⌘S: nothing to do unless there are highlight edits (saving otherwise would only rewrite the file).
    override func save(_ sender: Any?) {
        guard hasPendingChanges, isDocumentEdited else { return }
        super.save(sender)
    }

    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                         for saveOperation: NSDocument.SaveOperationType) -> Bool { true }

    /// Runs on a background thread. PDFKit rewrites the whole file (seconds for big PDFs), so instead of touching
    /// the document on screen, this opens its own copy of the current file and replays the pending edits onto it.
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL: URL?) throws {
        let changes = changesLock.withLock { pendingChanges }
        let source = originalContentsURL ?? fileURL
        let identityURL = fileURL ?? url
        unblockUserInteraction()
        guard let source, let copy = PDFDocument(url: source) else { throw CocoaError(.fileReadNoSuchFile) }
        changes.forEach { $0.apply(to: copy) }
        guard copy.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        changesLock.withLock { pendingChanges.removeFirst(min(changes.count, pendingChanges.count)) }
        // PDFKit gives every saved file a new /ID; move bookmarks and position to the new identity.
        let newKey = PDFDocument(url: url).map { FileStateStore.key(for: $0, url: identityURL) }
        DispatchQueue.main.async { [self] in
            if let newKey, newKey != stateKey {
                FileStateStore.shared.rename(stateKey, to: newKey)
                stateKey = newKey
            }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        typealias ShouldClose = @convention(c) (AnyObject, Selector, NSDocument, Bool, UnsafeMutableRawPointer?) -> Void
        let reply: (Bool) -> Void = { [self] close in
            guard let selector = shouldCloseSelector, let target = delegate as AnyObject?,
                  let method = target.method(for: selector) else { return }
            unsafeBitCast(method, to: ShouldClose.self)(target, selector, self, close, contextInfo)
        }
        // Edits undone back to the saved state need no save.
        guard isDocumentEdited else { return reply(true) }
        // Without autosave: the standard "Do you want to save the changes…?" sheet (Save / Don't Save / Cancel).
        guard Self.autosaveEnabled else {
            return super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
        saveChanges { [self] error in
            guard let error else { return reply(true) }
            let alert = NSAlert(error: error)
            alert.messageText = "Your highlights in “\(displayName ?? "this PDF")” couldn’t be saved."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Close Without Saving")
            reply(alert.runModal() == .alertSecondButtonReturn)
        }
    }
}
