// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let chromeStyleChanged = Notification.Name("FastPDFChromeStyleChanged")
    static let highlightColorsChanged = Notification.Name("FastPDFHighlightColorsChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stay resident so the next double-click doesn't pay launch cost again.
        ProcessInfo.processInfo.disableAutomaticTermination("Stay resident for instant opens")
        DispatchQueue.main.async {
            if let menu = NSApp.mainMenu { MainMenu.addEditMenu(to: menu) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        for window in NSApp.windows {
            (window.windowController as? ReaderWindowController)?.saveState()
        }
        FileStateStore.shared.flush()
    }

    @objc func toggleGlassToolbar(_ sender: Any?) {
        ReaderWindowController.prefersGlassToolbar.toggle()
        NotificationCenter.default.post(name: .chromeStyleChanged, object: nil)
    }

    @objc func toggleAutosave(_ sender: Any?) {
        ReaderDocument.autosaveEnabled.toggle()
        if ReaderDocument.autosaveEnabled {
            for case let document as ReaderDocument in NSDocumentController.shared.documents { document.saveChanges() }
        }
    }

    @objc func setPrimaryHighlightColor(_ sender: NSMenuItem) {
        HighlightColor.primary = HighlightColor.allCases[sender.tag]
        NotificationCenter.default.post(name: .highlightColorsChanged, object: nil)
    }

    @objc func setSecondaryHighlightColor(_ sender: NSMenuItem) {
        HighlightColor.secondary = HighlightColor.allCases[sender.tag]
        NotificationCenter.default.post(name: .highlightColorsChanged, object: nil)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleAutosave(_:)):
            item.state = ReaderDocument.autosaveEnabled ? .on : .off
        case #selector(toggleGlassToolbar(_:)):
            item.state = ReaderWindowController.prefersGlassToolbar ? .on : .off
        case #selector(setPrimaryHighlightColor(_:)):
            item.state = HighlightColor.allCases[item.tag] == .primary ? .on : .off
        case #selector(setSecondaryHighlightColor(_:)):
            item.state = HighlightColor.allCases[item.tag] == .secondary ? .on : .off
        default: break
        }
        return true
    }

    @objc func makeDefaultViewer(_ sender: Any?) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .pdf) { error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if let error {
                    alert.messageText = "Couldn’t make FastPDF the default PDF viewer"
                    alert.informativeText = error.localizedDescription
                } else {
                    alert.messageText = "FastPDF is now your default PDF viewer"
                    alert.informativeText = "Double-clicking a PDF in Finder will open it here."
                }
                alert.runModal()
            }
        }
    }
}
