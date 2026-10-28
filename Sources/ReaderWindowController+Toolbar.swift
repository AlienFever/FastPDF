// FastPDF for Mac — Copyright (C) 2026 Alienfever
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
    static let zoomGroup = Self("zoomGroup")
    static let annotateGroup = Self("annotateGroup")
    static let rotate = Self("rotate")
    static let bookmarks = Self("bookmarks")
    static let search = Self("search")
}

/// The glass toolbar's live controls (nil until the toolbar is first shown).
final class ToolbarControls {
    let pageField = NSTextField()
    let pageCountLabel = NSTextField(labelWithString: "")
    var zoomControl: NSSegmentedControl?
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
         .annotateGroup, .zoomGroup, .rotate, .bookmarks, .search]
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
        case .annotateGroup:
            let highlight = button(.highlight, "highlighter", "Highlight (H / K)", #selector(highlightPrimary(_:)))
            let note = button(.note, "note.text", "Add Note (N)", #selector(startPlacingNote(_:)))
            controls.highlightItem = highlight
            controls.noteItem = note
            let group = NSToolbarItemGroup(itemIdentifier: id)
            group.subitems = [highlight, note]
            group.label = "Annotate"
            group.controlRepresentation = .expanded
            return group
        case .zoomGroup:
            // One segmented control, so zoom out, the zoom level / layout menu and zoom in share one glass
            // capsule (separate items, or an item group containing a menu item, split into three islands).
            let control = NSSegmentedControl(labels: ["", "Fit Width", ""], trackingMode: .momentary,
                                             target: self, action: #selector(zoomSegmentClicked(_:)))
            control.setImage(NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom Out"), forSegment: 0)
            control.setImage(NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom In"), forSegment: 2)
            control.setWidth(Self.zoomButtonWidth, forSegment: 0)
            control.setWidth(Self.zoomButtonWidth, forSegment: 2)
            control.setShowsMenuIndicator(true, forSegment: 1)
            control.setToolTip("Zoom Out", forSegment: 0)
            control.setToolTip("Page layout and zoom", forSegment: 1)
            control.setToolTip("Zoom In", forSegment: 2)
            controls.zoomControl = control
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = control
            item.label = "Zoom"
            return item
        case .rotate:
            return button(id, "rotate.right", "Rotate Page (⌘R)", #selector(rotateRight(_:)))
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

    static let zoomButtonWidth: CGFloat = 34

    @objc func zoomSegmentClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: zoomOutAction(sender)
        case 2: zoomInAction(sender)
        default:
            let x = Self.zoomButtonWidth + 2
            let y = sender.isFlipped ? sender.bounds.maxY + 4 : -4
            ReaderBar.viewMenu().popUp(positioning: nil, at: NSPoint(x: x, y: y), in: sender)
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
