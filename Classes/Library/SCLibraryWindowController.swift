//
//  SCLibraryWindowController.swift
//  Simple Comic
//
//  The library window: a real NSWindow with a real NSToolbar over an NSSplitViewController.
//
//  The chrome is AppKit on purpose. A search field, a couple of pull-down menus and a
//  collapsible inspector are things the system already does properly — with the right
//  metrics, the unified title bar, overflow handling, user customisation and a divider the
//  user can drag and that remembers its width. Rebuilding that inside SwiftUI produced a row
//  of controls that only looked like a toolbar.
//
//  SwiftUI keeps the two panes, where it earns its place: a lazy cover grid and a detail
//  list. They talk to the chrome through SCLibraryUIState and, for the settings that
//  persist, through the same UserDefaults keys their @AppStorage properties read.
//

import AppKit
import SwiftUI

@objc(SCLibraryWindowController)
final class SCLibraryWindowController: NSWindowController, NSWindowDelegate,
									   NSToolbarDelegate, NSMenuDelegate, NSSearchFieldDelegate {

	private static let frameAutosaveName = NSWindow.FrameAutosaveName("SCLibraryWindow")

	private let splitController = SCLibrarySplitViewController()
	private let foldersMenu = NSMenu(title: "")
	private let sortMenu = NSMenu(title: "")
	private var inspectorItem: NSToolbarItem?

	@objc convenience init() {
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
							  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
							  backing: .buffered,
							  defer: false)
		window.title = NSLocalizedString("Library", comment: "library window title")
		window.isReleasedWhenClosed = false
		self.init(window: window)

		// `setFrameAutosaveName` only ever *saves*; restoring is `setFrameUsingName`. The old
		// code centred the window first and never read anything back, so every launch stored a
		// freshly centred frame and the remembered size was lost. Restore first, centre only
		// when there is nothing to restore, and let the controller keep it current after that.
		shouldCascadeWindows = false
		if !window.setFrameUsingName(Self.frameAutosaveName) {
			window.center()
		}
		windowFrameAutosaveName = Self.frameAutosaveName

		window.delegate = self
		window.contentViewController = splitController
		window.toolbarStyle = .unified

		let toolbar = NSToolbar(identifier: "SCLibraryToolbar")
		toolbar.delegate = self
		toolbar.displayMode = .iconOnly
		toolbar.allowsUserCustomization = true
		toolbar.autosavesConfiguration = true
		window.toolbar = toolbar

		foldersMenu.delegate = self
		sortMenu.delegate = self
	}

	override func showWindow(_ sender: Any?) {
		super.showWindow(sender)
		installKeyMonitor()
	}

	func windowWillClose(_ notification: Notification) {
		// A scan that outlives its window would keep writing to a store nobody is watching.
		SCLibraryController.shared.cancelRunningScan()
		SCLibraryStore.shared.flush()
		removeKeyMonitor()
	}

	// MARK: Toolbar

	private enum ItemID {
		static let folders = NSToolbarItem.Identifier("SCLibraryFolders")
		static let sort = NSToolbarItem.Identifier("SCLibrarySort")
		static let coverSize = NSToolbarItem.Identifier("SCLibraryCoverSize")
		static let inspector = NSToolbarItem.Identifier("SCLibraryInspector")
		static let search = NSToolbarItem.Identifier("SCLibrarySearch")
	}

	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[ItemID.folders, ItemID.sort, ItemID.coverSize,
		 .flexibleSpace, ItemID.search, ItemID.inspector]
	}

	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
	}

	func toolbar(_ toolbar: NSToolbar,
				 itemForItemIdentifier identifier: NSToolbarItem.Identifier,
				 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		switch identifier {
		case ItemID.folders:
			let item = NSMenuToolbarItem(itemIdentifier: identifier)
			item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
			item.label = NSLocalizedString("Folders", comment: "library toolbar item")
			item.toolTip = NSLocalizedString("Add, rescan or remove library folders",
											 comment: "library toolbar item tooltip")
			item.menu = foldersMenu
			return item

		case ItemID.sort:
			let item = NSMenuToolbarItem(itemIdentifier: identifier)
			item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
			item.label = NSLocalizedString("Sort", comment: "library toolbar item")
			item.toolTip = NSLocalizedString("Sort and filter the library",
											 comment: "library toolbar item tooltip")
			item.menu = sortMenu
			return item

		case ItemID.coverSize:
			let item = NSToolbarItem(itemIdentifier: identifier)
			let slider = NSSlider(value: SCLibraryDefaults.columnWidth,
								  minValue: Double(SCLibraryMetrics.minimumColumnWidth),
								  maxValue: Double(SCLibraryMetrics.maximumColumnWidth),
								  target: self,
								  action: #selector(changeCoverSize(_:)))
			slider.isContinuous = true
			slider.frame.size.width = 90
			item.view = slider
			item.label = NSLocalizedString("Cover Size", comment: "library toolbar item")
			item.toolTip = item.label
			item.visibilityPriority = .low
			return item

		case ItemID.inspector:
			let item = NSToolbarItem(itemIdentifier: identifier)
			item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
			item.label = NSLocalizedString("Details", comment: "library toolbar item")
			item.toolTip = NSLocalizedString("Show or hide the details", comment: "library toolbar item tooltip")
			item.target = self
			item.action = #selector(toggleInspector(_:))
			item.isBordered = true
			inspectorItem = item
			return item

		case ItemID.search:
			let item = NSSearchToolbarItem(itemIdentifier: identifier)
			item.searchField.delegate = self
			item.searchField.placeholderString = NSLocalizedString("Search", comment: "library search field")
			item.searchField.sendsWholeSearchString = false
			item.searchField.target = self
			item.searchField.action = #selector(search(_:))
			item.resignsFirstResponderWithCancel = true
			return item

		default:
			return nil
		}
	}

	// MARK: Toolbar actions

	@objc private func changeCoverSize(_ sender: NSSlider) {
		SCLibraryDefaults.columnWidth = sender.doubleValue
	}

	@objc private func toggleInspector(_ sender: Any?) {
		splitController.toggleDetails()
	}

	@objc private func search(_ sender: NSSearchField) {
		SCLibraryUIState.shared.searchText = sender.stringValue
	}

	func controlTextDidChange(_ notification: Notification) {
		guard let field = notification.object as? NSSearchField else { return }
		SCLibraryUIState.shared.searchText = field.stringValue
	}

	// MARK: Menus

	/// Both pull-downs are rebuilt as they open, so folders that were added or removed since
	/// the last time show up without any bookkeeping.
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		switch menu {
		case foldersMenu: buildFoldersMenu(menu)
		case sortMenu: buildSortMenu(menu)
		default: break
		}
	}

	private func buildFoldersMenu(_ menu: NSMenu) {
		let store = SCLibraryStore.shared
		let scanning = SCLibraryController.shared.scan != nil

		let add = menu.addItem(withTitle: NSLocalizedString("Add Folder…", comment: "library menu item"),
							   action: #selector(addFolder(_:)), keyEquivalent: "")
		add.target = self
		add.isEnabled = !scanning

		guard !store.folders.isEmpty else { return }
		menu.addItem(.separator())

		for folder in store.folders {
			let item = menu.addItem(withTitle: folder.name, action: nil, keyEquivalent: "")
			let submenu = NSMenu(title: folder.name)
			let rescan = submenu.addItem(withTitle: NSLocalizedString("Rescan", comment: "library menu item"),
										 action: #selector(rescanFolder(_:)), keyEquivalent: "")
			rescan.target = self
			rescan.representedObject = folder.id
			rescan.isEnabled = !scanning

			let reveal = submenu.addItem(withTitle: NSLocalizedString("Remove Folder", comment: "library menu item"),
										 action: #selector(removeFolder(_:)), keyEquivalent: "")
			reveal.target = self
			reveal.representedObject = folder.id
			item.submenu = submenu
		}

		menu.addItem(.separator())
		let rescanAll = menu.addItem(withTitle: NSLocalizedString("Rescan All", comment: "library menu item"),
									 action: #selector(rescanAll(_:)), keyEquivalent: "")
		rescanAll.target = self
		rescanAll.isEnabled = !scanning

		let evict = menu.addItem(withTitle: NSLocalizedString("Remove All Downloads", comment: "library menu item"),
								 action: #selector(removeAllDownloads(_:)), keyEquivalent: "")
		evict.target = self
		evict.isEnabled = store.entries.contains { $0.isFolderBacked && $0.hasLocalArchive }
	}

	private func buildSortMenu(_ menu: NSMenu) {
		for option in SCLibrarySort.allCases {
			let item = menu.addItem(withTitle: option.label,
									action: #selector(changeSort(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = option.rawValue
			item.state = SCLibraryDefaults.sortField == option.rawValue ? .on : .off
		}
		menu.addItem(.separator())
		let ascending = menu.addItem(withTitle: NSLocalizedString("Ascending", comment: "library sort direction"),
									 action: #selector(toggleAscending(_:)), keyEquivalent: "")
		ascending.target = self
		ascending.state = SCLibraryDefaults.sortAscending ? .on : .off

		menu.addItem(.separator())
		let downloaded = menu.addItem(withTitle: NSLocalizedString("Only Downloaded", comment: "library filter"),
									  action: #selector(toggleOnlyDownloaded(_:)), keyEquivalent: "")
		downloaded.target = self
		downloaded.state = SCLibraryDefaults.onlyDownloaded ? .on : .off

		let favorites = menu.addItem(withTitle: NSLocalizedString("Only Favorites", comment: "library filter"),
									 action: #selector(toggleOnlyFavorites(_:)), keyEquivalent: "")
		favorites.target = self
		favorites.state = SCLibraryDefaults.onlyFavorites ? .on : .off
	}

	@objc private func addFolder(_ sender: Any?) {
		SCLibraryController.shared.addFolder(relativeTo: window)
	}

	@objc private func rescanFolder(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID else { return }
		SCLibraryController.shared.rescan(folderID: id)
	}

	@objc private func removeFolder(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? UUID,
			  let folder = SCLibraryStore.shared.folder(id: id) else { return }
		let alert = NSAlert()
		alert.messageText = String(format: NSLocalizedString("Remove “%@” from the library?",
															 comment: "removing a library folder"), folder.name)
		alert.informativeText = NSLocalizedString("The comics scanned from it are removed from the library. The files themselves are not deleted.",
												  comment: "removing a library folder")
		alert.addButton(withTitle: NSLocalizedString("Remove", comment: "destructive button"))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "cancel button"))
		guard let window = window else { return }
		alert.beginSheetModal(for: window) { response in
			if response == .alertFirstButtonReturn {
				SCLibraryController.shared.removeFolder(id: id)
			}
		}
	}

	@objc private func rescanAll(_ sender: Any?) {
		SCLibraryController.shared.rescanAll()
	}

	@objc private func removeAllDownloads(_ sender: Any?) {
		SCLibraryController.shared.evictAll()
	}

	@objc private func changeSort(_ sender: NSMenuItem) {
		guard let raw = sender.representedObject as? String else { return }
		SCLibraryDefaults.sortField = raw
	}

	@objc private func toggleAscending(_ sender: Any?) {
		SCLibraryDefaults.sortAscending.toggle()
	}

	@objc private func toggleOnlyDownloaded(_ sender: Any?) {
		SCLibraryDefaults.onlyDownloaded.toggle()
	}

	@objc private func toggleOnlyFavorites(_ sender: Any?) {
		SCLibraryDefaults.onlyFavorites.toggle()
	}

	// MARK: Keyboard navigation

	private var keyMonitor: Any?

	/// Arrow keys move the selection, Return opens it.
	///
	/// A local key monitor rather than SwiftUI focus: macOS 11 has no @FocusState, and
	/// `.focusable()` on a grid of cells fights the window's own responder chain. This stays
	/// in one place and only ever acts while the library window is key and nothing is being
	/// typed into.
	private func installKeyMonitor() {
		guard keyMonitor == nil else { return }
		keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self = self, let window = self.window, event.window === window else { return event }
			// The field editor is up: the search field owns every key.
			if window.firstResponder is NSTextView { return event }
			// Leave shortcuts to the menus.
			if event.modifierFlags.contains(.command) { return event }

			let state = SCLibraryUIState.shared
			switch event.keyCode {
			case 123: state.move(dx: -1, dy: 0)
			case 124: state.move(dx: 1, dy: 0)
			case 125: state.move(dx: 0, dy: 1)
			case 126: state.move(dx: 0, dy: -1)
			case 36, 76: state.openSelection()
			default: return event
			}
			return nil
		}
	}

	private func removeKeyMonitor() {
		if let keyMonitor = keyMonitor {
			NSEvent.removeMonitor(keyMonitor)
		}
		keyMonitor = nil
	}

	deinit {
		removeKeyMonitor()
	}
}

// MARK: - Split view

/// Grid on the left, details on the right. An ordinary split view item rather than anything
/// hand-drawn, so the divider drags, the width is remembered and the collapse animates the
/// way it does everywhere else.
final class SCLibrarySplitViewController: NSSplitViewController {

	private var detailsItem: NSSplitViewItem?

	override func viewDidLoad() {
		super.viewDidLoad()

		let grid = NSHostingController(rootView: SCLibraryGridView(store: .shared,
																   controller: .shared,
																   state: .shared))
		let gridItem = NSSplitViewItem(viewController: grid)
		gridItem.minimumThickness = 420
		gridItem.canCollapse = false
		addSplitViewItem(gridItem)

		let details = NSHostingController(rootView: SCLibraryDetailPane(store: .shared,
																		controller: .shared,
																		state: .shared))
		let item = NSSplitViewItem(viewController: details)
		item.minimumThickness = 260
		item.maximumThickness = 420
		item.canCollapse = true
		item.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
		item.isCollapsed = !SCLibraryDefaults.showsDetails
		addSplitViewItem(item)
		detailsItem = item

		splitView.autosaveName = "SCLibrarySplit"
	}

	func toggleDetails() {
		guard let detailsItem = detailsItem else { return }
		let collapsed = !detailsItem.isCollapsed
		detailsItem.animator().isCollapsed = collapsed
		SCLibraryDefaults.showsDetails = !collapsed
	}
}
