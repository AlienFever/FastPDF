// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = submenu(in: main, title: "FastPDF")
        appMenu.addItem(withTitle: "About FastPDF", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Make FastPDF the Default PDF Viewer", action: #selector(AppDelegate.makeDefaultViewer(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide FastPDF", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit FastPDF", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(in: main, title: "File")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenu(title: "Open Recent")
        // NSDocumentController finds and manages this menu through its Clear Menu item.
        recent.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recent
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "Autosave Highlights", action: #selector(AppDelegate.toggleAutosave(_:)), keyEquivalent: "")

        // Edit is inserted after launch; see addEditMenu.

        typealias R = ReaderWindowController
        let view = submenu(in: main, title: "View")
        view.addItem(item("Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .option]))
        view.addItem(item("Contents", #selector(R.showContents(_:)), "1", [.command, .option]))
        view.addItem(item("Thumbnails", #selector(R.showThumbnails(_:)), "2", [.command, .option]))
        view.addItem(item("Highlights & Notes", #selector(R.showHighlights(_:)), "3", [.command, .option]))
        view.addItem(.separator())
        // Plain-letter shortcuts are only enabled while the page (not a text field) has focus.
        view.addItem(item("Switch Fit Width / Fit Page", #selector(R.cycleFit(_:)), "v", []))
        view.addItem(item("Next Page Layout", #selector(R.cycleLayout(_:)), "d", []))
        view.addItem(.separator())
        view.addItem(item("Single Page", #selector(R.singlePage(_:)), "1"))
        view.addItem(item("Continuous", #selector(R.continuousScroll(_:)), "2"))
        view.addItem(item("Two Pages", #selector(R.twoPages(_:)), "3"))
        view.addItem(.separator())
        view.addItem(item("Actual Size", #selector(R.actualSize(_:)), "0"))
        view.addItem(item("Fit Page", #selector(R.fitPage(_:)), "9"))
        view.addItem(item("Fit Width", #selector(R.fitWidth(_:)), "8"))
        view.addItem(item("Zoom In", #selector(R.zoomInAction(_:)), "+"))
        let zoomInAlias = item("Zoom In", #selector(R.zoomInAction(_:)), "=")
        zoomInAlias.isHidden = true
        zoomInAlias.allowsKeyEquivalentWhenHidden = true
        view.addItem(zoomInAlias)
        view.addItem(item("Zoom Out", #selector(R.zoomOutAction(_:)), "-"))
        view.addItem(.separator())
        view.addItem(item("Glass Toolbar", #selector(AppDelegate.toggleGlassToolbar(_:)), "t", [.command, .option]))
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let go = submenu(in: main, title: "Go")
        go.addItem(item("Previous Page", #selector(R.previousPage(_:)), key(NSUpArrowFunctionKey), [.command, .option]))
        go.addItem(item("Next Page", #selector(R.nextPage(_:)), key(NSDownArrowFunctionKey), [.command, .option]))
        go.addItem(item("First Page", #selector(R.firstPage(_:)), key(NSHomeFunctionKey), []))
        go.addItem(item("Last Page", #selector(R.lastPage(_:)), key(NSEndFunctionKey), []))
        go.addItem(.separator())
        go.addItem(item("Back", #selector(R.historyBack(_:)), "["))
        go.addItem(item("Forward", #selector(R.historyForward(_:)), "]"))
        go.addItem(.separator())
        go.addItem(item("Go to Page…", #selector(R.goToPage(_:)), "g", [.command, .option]))

        let highlight = submenu(in: main, title: "Annotate")
        highlight.delegate = HighlightMenu.shared
        HighlightMenu.populate(highlight)

        let marks = submenu(in: main, title: "Bookmarks")
        marks.addItem(item("Add Bookmark", #selector(R.toggleBookmark(_:)), "d"))
        marks.addItem(item("Show Bookmarks", #selector(R.showBookmarks(_:)), "b", [.command, .option]))
        marks.addItem(.separator())
        marks.delegate = BookmarksMenu.shared

        let window = submenu(in: main, title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        return main
    }

    /// Added after launch: if an Edit menu exists during finishLaunching, AppKit loads the Writing Tools
    /// framework (~25 ms) to decorate it with Dictation/Emoji/Writing Tools items a viewer doesn't need.
    static func addEditMenu(to main: NSMenu) {
        typealias R = ReaderWindowController
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(item("Find…", #selector(R.startFind(_:)), "f"))
        edit.addItem(item("Find Next", #selector(R.findNext(_:)), "g"))
        edit.addItem(item("Find Previous", #selector(R.findPrevious(_:)), "g", [.command, .shift]))
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        main.insertItem(item, at: 2)
    }

    static func submenu(in parent: NSMenu, title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        parent.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        return menu
    }

    static func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        return item
    }

    static func key(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(UInt16(functionKey))!))
    }
}

/// Lists the front document's bookmarks at the bottom of the Bookmarks menu.
final class BookmarksMenu: NSObject, NSMenuDelegate {
    static let shared = BookmarksMenu()
    private static let fixedItems = 3

    func menuNeedsUpdate(_ menu: NSMenu) {
        while menu.items.count > Self.fixedItems { menu.removeItem(at: Self.fixedItems) }
        guard let reader = NSApp.mainWindow?.windowController as? ReaderWindowController else { return }
        let pages = reader.bookmarks
        if pages.isEmpty {
            menu.addItem(withTitle: "No Bookmarks", action: nil, keyEquivalent: "").isEnabled = false
        }
        for page in pages.prefix(100) {
            let item = NSMenuItem(title: "Page \(page + 1)", action: #selector(ReaderWindowController.goToBookmark(_:)), keyEquivalent: "")
            item.tag = page
            menu.addItem(item)
        }
    }
}

/// The Highlight menu: shortcuts show the current primary/secondary colors, and both colors can be chosen here.
final class HighlightMenu: NSObject, NSMenuDelegate {
    static let shared = HighlightMenu()
    typealias R = ReaderWindowController

    static func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let primary = HighlightColor.primary, secondary = HighlightColor.secondary
        // H and K have no modifier; they're only enabled while the page (not a text field) has focus.
        let first = MainMenu.item("Highlight \(primary.name)", #selector(R.highlightPrimary(_:)), "h", [])
        first.image = primary.swatch
        first.toolTip = "Highlights the selection, or with nothing selected, turns highlight mode on or off."
        menu.addItem(first)
        let second = MainMenu.item("Highlight \(secondary.name)", #selector(R.highlightSecondary(_:)), "k", [])
        second.image = secondary.swatch
        second.toolTip = first.toolTip
        menu.addItem(second)
        let note = MainMenu.item("Add Note", #selector(R.startPlacingNote(_:)), "n", [])
        note.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
        note.toolTip = "Then click where the note should go."
        menu.addItem(note)
        menu.addItem(.separator())
        for (title, action) in [("Primary Color (H)", #selector(AppDelegate.setPrimaryHighlightColor(_:))),
                                ("Secondary Color (K)", #selector(AppDelegate.setSecondaryHighlightColor(_:)))] {
            let colors = NSMenu()
            for (i, color) in HighlightColor.allCases.enumerated() {
                let item = NSMenuItem(title: color.name, action: action, keyEquivalent: "")
                item.tag = i
                item.image = color.swatch
                colors.addItem(item)
            }
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = colors
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove Highlight", action: #selector(R.removeSelectedHighlights(_:)), keyEquivalent: "")
    }

    func menuNeedsUpdate(_ menu: NSMenu) { Self.populate(menu) }
}
