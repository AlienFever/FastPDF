// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The standard macOS (Liquid Glass) toolbar, offered as an alternative to the compact ReaderBar.
/// It costs ~60–80 ms per window opened on macOS 26 (each item renders through SwiftUI), so it's a choice:
/// View ▸ Glass Toolbar.

extension NSToolbarItem.Identifier {
    static let previousPage = Self("previousPage")
    static let page = Self("page")
    static let nextPage = Self("nextPage")
    static let highlight = Self("highlight")
    static let note = Self("note")
    static let zoomOut = Self("zoomOut")
    static let zoom = Self("zoom")
    static let zoomIn = Self("zoomIn")
    static let bookmarks = Self("bookmarks")
    static let search = Self("search")
}

/// The glass toolbar's live controls (nil until the toolbar is first shown).
final class ToolbarControls {
    let pageField = NSTextField()
    let pageCountLabel = NSTextField(labelWithString: "")
    var zoomItem: NSMenuToolbarItem?
    var bookmarkItem: NSToolbarItem?
    var highlightItem: NSToolbarItem?
    var noteItem: NSToolbarItem?
    var searchItem: NSSearchToolbarItem?
}

extension ReaderWindowController: NSToolbarDelegate {
    static var prefersGlassToolbar: Bool {
        get { UserDefaults.standard.object(forKey: "GlassToolbar") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "GlassToolbar") }
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "Reader")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .previousPage, .page, .nextPage, .flexibleSpace,
         .highlight, .note, .zoomOut, .zoom, .zoomIn, .bookmarks, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let controls = toolbarControls
        switch id {
        case .previousPage:
            return button(id, "chevron.left", "Previous Page", #selector(previousPage(_:)))
        case .nextPage:
            return button(id, "chevron.right", "Next Page", #selector(nextPage(_:)))
        case .page:
            let field = controls.pageField
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            field.target = self
            field.action = #selector(pageFieldEntered(_:))
            field.toolTip = "Current page (type a number and press Return)"
            field.widthAnchor.constraint(equalToConstant: 48).isActive = true
            controls.pageCountLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            controls.pageCountLabel.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [field, controls.pageCountLabel])
            stack.spacing = 4
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = stack
            item.label = "Page"
            return item
        case .highlight:
            let item = button(id, "highlighter", "Highlight (H / K)", #selector(highlightPrimary(_:)))
            controls.highlightItem = item
            return item
        case .note:
            let item = button(id, "note.text", "Add Note (N)", #selector(startPlacingNote(_:)))
            controls.noteItem = item
            return item
        case .zoomOut:
            return button(id, "minus.magnifyingglass", "Zoom Out", #selector(zoomOutAction(_:)))
        case .zoomIn:
            return button(id, "plus.magnifyingglass", "Zoom In", #selector(zoomInAction(_:)))
        case .zoom:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "View"
            item.toolTip = "Page layout and zoom"
            item.showsIndicator = true
            item.menu = ReaderBar.viewMenu()
            controls.zoomItem = item
            return item
        case .bookmarks:
            let item = button(id, "bookmark", "Bookmarks", #selector(showBookmarks(_:)))
            controls.bookmarkItem = item
            return item
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.label = "Find"
            item.preferredWidthForSearchField = 180
            item.searchField.placeholderString = "Find"
            item.searchField.delegate = find
            item.searchField.target = find
            item.searchField.action = #selector(FindController.searchFieldAction(_:))
            controls.searchItem = item
            return item
        default:
            return nil
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }
}
