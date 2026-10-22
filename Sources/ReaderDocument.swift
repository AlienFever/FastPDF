// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

/// A PDF document. Reading is lazy; edits (annotations and form entries) are written
/// back into the file (in the background) on ⌘S, or automatically when File ▸ Autosave Changes is on.
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
    /// Form field values to write with the next save (snapshotted on the main thread when the save starts).
    private var pendingForms: [FormValue] = []
    private var autosaveWork: DispatchWorkItem?

    /// Form fields were changed since the last save. The window provides the values and is told when they're saved.
    private(set) var formsEdited = false
    var formValuesProvider: (() -> [FormValue])?
    var formsSaved: (([FormValue]) -> Void)?
    var checkForms: ((_ endEditing: Bool) -> Void)?

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

    func formsDidChange() {
        guard !formsEdited else { return }
        formsEdited = true
        updateChangeCount(.changeDone)
        if Self.autosaveEnabled { scheduleSave() }
    }

    private var hasPendingChanges: Bool { formsEdited || changesLock.withLock { !pendingChanges.isEmpty } }

    func saveChanges(completion: ((Error?) -> Void)? = nil) {
        autosaveWork?.cancel()
        guard hasPendingChanges, isDocumentEdited, let url = fileURL else { completion?(nil); return }
        save(to: url, ofType: fileType ?? "com.adobe.pdf", for: .saveOperation) { error in completion?(error) }
    }

    /// ⌘S: nothing to do unless there are edits (saving otherwise would only rewrite the file).
    override func save(_ sender: Any?) {
        checkForms?(true)
        guard hasPendingChanges, isDocumentEdited else { return }
        super.save(sender)
    }

    /// Every save path (⌘S, the close prompt, autosave) comes through here on the main thread: snapshot the
    /// form values now, while it's safe to read the document on screen.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        let forms = formsEdited ? (formValuesProvider?() ?? []) : []
        changesLock.withLock { pendingForms = forms }
        super.save(to: url, ofType: typeName, for: saveOperation) { [self] error in
            if error == nil, !forms.isEmpty {
                formsEdited = false
                formsSaved?(forms)
            }
            completionHandler(error)
        }
    }

    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String,
                                         for saveOperation: NSDocument.SaveOperationType) -> Bool { true }

    /// Runs on a background thread. PDFKit rewrites the whole file (seconds for big PDFs), so instead of touching
    /// the document on screen, this opens its own copy of the current file and replays the pending edits onto it.
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL: URL?) throws {
        let (changes, forms) = changesLock.withLock { (pendingChanges, pendingForms) }
        let source = originalContentsURL ?? fileURL
        let identityURL = fileURL ?? url
        unblockUserInteraction()
        guard let source, let copy = PDFDocument(url: source) else { throw CocoaError(.fileReadNoSuchFile) }
        changes.forEach { $0.apply(to: copy) }
        forms.forEach { $0.apply(to: copy) }
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
        checkForms?(true)
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
