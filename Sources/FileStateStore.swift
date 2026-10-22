// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import PDFKit

/// What we remember about a file between opens.
struct FileState: Codable {
    var page = 0
    /// Top-left point of the view on `page`, in page space.
    var point: [Double]?
    var bookmarks: [Int] = []
    var displayMode: Int?
    /// Two Pages with the first page shown on its own.
    var coverPage: Bool?
    var fit: String?
    var scale: Double?
    var lastOpened = Date()
}

/// Per-file reading state in one small JSON file. Thread-safe; documents read it on a background thread.
final class FileStateStore: @unchecked Sendable {
    static let shared = FileStateStore()
    private static let maxEntries = 2000

    private let lock = NSLock()
    private var states: [String: FileState]?
    private var saveScheduled = false
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FastPDF/state.json")

    func state(for key: String) -> FileState? {
        lock.withLock { loadIfNeeded(); return states?[key] }
    }

    func update(_ key: String, _ change: (inout FileState) -> Void) {
        lock.withLock {
            loadIfNeeded()
            var state = states?[key] ?? FileState()
            change(&state)
            state.lastOpened = Date()
            states?[key] = state
            scheduleSave()
        }
    }

    /// Moves a file's state to a new key (its /ID changes whenever the file is re-saved).
    func rename(_ old: String, to new: String) {
        lock.withLock {
            loadIfNeeded()
            guard let state = states?.removeValue(forKey: old) else { return }
            states?[new] = state
            scheduleSave()
        }
    }

    /// Writes pending changes now (used at quit).
    func flush() {
        let pending = lock.withLock { saveScheduled }
        if pending { save() }
    }

    /// Bookmarks follow the file, not its path: use the PDF's permanent /ID when it has one.
    static func key(for pdf: PDFDocument, url: URL) -> String {
        if let ids = pdf.documentRef?.fileIdentifier {
            var string: CGPDFStringRef?
            if CGPDFArrayGetString(ids, 0, &string), let string, let bytes = CGPDFStringGetBytePtr(string) {
                let length = CGPDFStringGetLength(string)
                if length > 0 {
                    let hex = UnsafeBufferPointer(start: bytes, count: length).map { String(format: "%02x", $0) }.joined()
                    return "id:\(hex):\(pdf.pageCount)"
                }
            }
        }
        return "path:" + url.standardizedFileURL.path
    }

    private func loadIfNeeded() {
        guard states == nil else { return }
        states = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: FileState].self, from: $0) } ?? [:]
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        ProcessInfo.processInfo.disableSuddenTermination()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { self.save() }
    }

    private func save() {
        let data: Data? = lock.withLock {
            guard saveScheduled, var states else { return nil }
            saveScheduled = false
            if states.count > Self.maxEntries {
                let keep = states.sorted { $0.value.lastOpened > $1.value.lastOpened }.prefix(Self.maxEntries)
                states = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
                self.states = states
            }
            return try? JSONEncoder().encode(states)
        }
        guard let data else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        ProcessInfo.processInfo.enableSuddenTermination()
    }
}
