import AppKit

/// What a sidebar context menu item does. The outline runs the split and pin items through its existing callbacks
/// and hands every other action to the window (`SidebarOutlineController.onMenuAction`).
public enum SidebarMenuAction: Hashable, Sendable {
  /// Opens the inline rename field (BH-026).
  case rename(NodeID)
  /// Duplicates every node, each copy right after its original (BH-027, BH-095).
  case duplicate([NodeID])
  /// Pin Tab / Unpin Tab / Pin Tabs (BH-055, KB-012).
  case pinToggle([NodeID])
  case moveToFavorites([NodeID])
  /// Move To > a Space (BH-042): each node goes to the same section of that Space.
  case moveToSpace([NodeID], SpaceID)
  /// Copy Link, Copy Links, Copy All Links (KB-013, BH-095); `markdown` for the Option alternates (KB-014, GS-034).
  case copyLinks([NodeID], markdown: Bool)
  /// Archive Below (BH-077, BH-126).
  case archiveBelow(NodeID)
  /// Archive, Close and Keep Pinned, Close and Keep Favorite: the close that Cmd-W runs on each node (BH-072).
  case archive([NodeID])
  case resetPinned(NodeID)
  case replacePin(NodeID)
  case separateFromPinned(NodeID)
  /// Remove from Favorites (BH-047's inverse).
  case removeFromFavorites(NodeID)
  /// Open in Split View (BH-117).
  case openInSplitView([NodeID])
  /// New Folder from a multi-selection (BH-094): the selection moves into a new pinned folder.
  case newFolder([NodeID])
  /// New Folder on the empty sidebar area (KB-040).
  case newEmptyFolder(SpaceID)
  case separateSplit(NodeID)
  case convertSplit(NodeID)
  case duplicateSplit(NodeID)
  case removePane(NodeID)
  /// Delete on a folder (BH-095): the folder and its tabs go to the Archive.
  case deleteFolder(NodeID)
  /// Paste URL as New Tab (KB-016, BH-095), into `location`.
  case pasteURLAsNewTab(SidebarLocation)
  /// New Tab (KB-001): the command bar, as Cmd-T and the BH-021 double-click.
  case newTab
  /// Clear Today Tabs (BH-075): every Today tab of the Space is archived.
  case clearToday(SpaceID)
  /// Mute / Unmute (BH-126, #364): the tab's page is muted or unmuted.
  case toggleMute(NodeID)
}

/// One context menu item, separator or submenu, as a value. `title` is "" for a separator.
public struct SidebarMenuEntry: Equatable, Sendable {
  public var title: String
  public var action: SidebarMenuAction?
  public var keyEquivalent: String
  public var modifiers: NSEvent.ModifierFlags
  public var isEnabled: Bool
  /// An Option-held alternate of the item before it (`NSMenuItem.isAlternate`).
  public var isAlternate: Bool
  public var submenu: [SidebarMenuEntry]?

  public var isSeparator: Bool { title.isEmpty && action == nil && submenu == nil }

  public static let separator = SidebarMenuEntry(title: "", action: nil, isEnabled: false)

  public init(title: String, action: SidebarMenuAction?, key: String = "",
              modifiers: NSEvent.ModifierFlags = .command, isEnabled: Bool = true, isAlternate: Bool = false,
              submenu: [SidebarMenuEntry]? = nil) {
    self.title = title
    self.action = action
    self.keyEquivalent = key
    self.modifiers = key.isEmpty && !isAlternate ? [] : modifiers
    self.isEnabled = isEnabled && (action != nil || submenu != nil)
    self.isAlternate = isAlternate
    self.submenu = submenu
  }

  /// An item that is shown but not built yet (Share, Change Icon, Edit Pinned URL): disabled, as the settings
  /// precedent shows unbuilt rows (design OQ6).
  static func unavailable(_ title: String) -> SidebarMenuEntry {
    SidebarMenuEntry(title: title, action: nil, isEnabled: false)
  }
}

/// What the menu needs besides the source: the Spaces for Move To, which pinned tabs left their pinned URL, whether
/// the clipboard holds a URL, which tabs have a page open, and their sound (#364).
public struct SidebarMenuContext: Sendable {
  public var spaces: [(id: SpaceID, title: String)]
  public var navigatedPins: Set<NodeID>
  public var clipboardHasURL: Bool
  /// Tabs whose page is open in the engine: only those can be muted.
  public var loadedTabs: Set<NodeID>
  /// Sound of the tabs that play or are muted; a missing tab is silent.
  public var audio: [NodeID: TabAudio]

  public init(spaces: [(id: SpaceID, title: String)] = [], navigatedPins: Set<NodeID> = [],
              clipboardHasURL: Bool = false, loadedTabs: Set<NodeID> = [], audio: [NodeID: TabAudio] = [:]) {
    self.spaces = spaces
    self.navigatedPins = navigatedPins
    self.clipboardHasURL = clipboardHasURL
    self.loadedTabs = loadedTabs
    self.audio = audio
  }
}

/// What a right-click (or Ctrl-click) lands on.
public enum SidebarMenuTarget: Equatable, Sendable {
  /// One row, or a multi-selection of two or more.
  case rows([NodeID])
  case favorite(NodeID)
  /// The sidebar below and between rows, in this Space.
  case empty(SpaceID)
}

/// The sidebar context menus of design/tab-context-menus (#105), section 3: one builder per row kind, plain native
/// items only. Separator placement follows the prototype. Key equivalents are shown only where the menu bar owns
/// the same key (Cmd-D, Cmd-W, Cmd-T), because a context menu's key fires only while that menu is open; Copy Link
/// (Shift-Cmd-C), Paste URL as New Tab (Opt-Cmd-V) and Clear Today Tabs (Shift-Cmd-K) get theirs with their menu bar
/// items.
public enum SidebarContextMenu {
  @MainActor
  public static func entries(for target: SidebarMenuTarget, in source: any SidebarSource,
                             context: SidebarMenuContext) -> [SidebarMenuEntry] {
    switch target {
    case .rows(let ids) where ids.count >= 2:
      return multiSelection(ids, source, context)
    case .rows(let ids):
      guard let id = ids.first else { return [] }
      return row(id, source, context)
    case .favorite(let id):
      return favorite(id, context)
    case .empty(let space):
      return emptyArea(space, source, context)
    }
  }

  /// The native menu for `entries` (design 7): plain `NSMenuItem`s, no custom views and no attributed titles,
  /// `autoenablesItems` off with the entries' enabled rules. Each item carries its `SidebarMenuAction` as its
  /// `representedObject` and sends `action` to `target`.
  @MainActor
  public static func menu(_ entries: [SidebarMenuEntry], target: AnyObject, action: Selector) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for entry in entries {
      if entry.isSeparator {
        menu.addItem(.separator())
        continue
      }
      let item = NSMenuItem(title: entry.title, action: entry.action == nil ? nil : action,
                            keyEquivalent: entry.keyEquivalent)
      item.keyEquivalentModifierMask = entry.modifiers
      item.isAlternate = entry.isAlternate
      item.isEnabled = entry.isEnabled
      item.target = target
      item.representedObject = entry.action
      if let submenu = entry.submenu { item.submenu = self.menu(submenu, target: target, action: action) }
      menu.addItem(item)
    }
    return menu
  }

  @MainActor
  private static func row(_ id: NodeID, _ source: any SidebarSource,
                          _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    switch (source.node(id), source.parent(of: id)) {
    case (.tab?, .split(let split)?):
      return pane(id, split: split, source, context)
    case (.tab?, _):
      if case .favorites? = source.section(containing: id) { return favorite(id, context) }
      if case .pinned? = source.section(containing: id) { return pinnedTab(id, source, context) }
      return todayTab(id, source, context)
    case (.folder?, _):
      return folder(id, source, context)
    case (.split(_, let layout)?, _):
      return splitRow(id, layout: layout, source, context)
    case (nil, _):
      return []
    }
  }

  // MARK: 3.1 Today tab

  @MainActor
  private static func todayTab(_ id: NodeID, _ source: any SidebarSource,
                               _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    var items = [SidebarMenuEntry(title: "Rename", action: .rename(id)),
                 SidebarMenuEntry(title: "Duplicate", action: .duplicate([id]))]
    if pinnable(id, source) { items.append(pinItem(pinned: false, [id])) }
    items.append(moveTo([id], source, context))
    items += [.separator] + soundGroup(id, context) + copyLink([id], plural: false) + [.separator]
    items.append(SidebarMenuEntry(title: "Archive Below", action: .archiveBelow(id),
                                  isEnabled: !todayNodesBelow(id, source).isEmpty))
    items.append(SidebarMenuEntry(title: "Archive", action: .archive([id]), key: "w"))
    return items
  }

  // MARK: 3.2 Pinned tab

  /// Separate From Pinned Tab (BH-061) is not in the design's table; it shipped with #108 and this menu is its only
  /// entry point, so it stays in the reset group.
  @MainActor
  private static func pinnedTab(_ id: NodeID, _ source: any SidebarSource,
                                _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    let navigated = context.navigatedPins.contains(id)
    var items = [SidebarMenuEntry(title: "Rename", action: .rename(id)),
                 SidebarMenuEntry(title: "Duplicate", action: .duplicate([id]))]
    if pinnable(id, source) { items.append(pinItem(pinned: true, [id])) }
    items += [.separator,
              SidebarMenuEntry(title: "Back to Pinned URL", action: .resetPinned(id), isEnabled: navigated),
              SidebarMenuEntry(title: "Replace Pin with Current Page", action: .replacePin(id), isEnabled: navigated),
              SidebarMenuEntry(title: "Separate From Pinned Tab", action: .separateFromPinned(id),
                               isEnabled: navigated),
              .unavailable("Edit Pinned URL"),
              .separator,
              moveTo([id], source, context),
              .separator]
    items += soundGroup(id, context) + copyLink([id], plural: false)
    items += [.separator, SidebarMenuEntry(title: "Close and Keep Pinned", action: .archive([id]), key: "w")]
    return items
  }

  // MARK: 3.3 Favorite

  /// Rename has no in-place field on a tile (no title is drawn), so it waits with Change Icon and Edit Pinned URL.
  /// Back to Pinned URL for Favorites is PARITY and disabled, as the design's screenshot shows it.
  private static func favorite(_ id: NodeID, _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    [.unavailable("Rename"), .unavailable("Change Icon"), .separator,
     .unavailable("Back to Pinned URL"), .unavailable("Edit Pinned URL"), .separator]
      + copyLink([id], plural: false)
      + [.separator,
         SidebarMenuEntry(title: "Remove from Favorites", action: .removeFromFavorites(id)),
         SidebarMenuEntry(title: "Close and Keep Favorite", action: .archive([id]), key: "w")]
  }

  // MARK: 3.4 Folder

  @MainActor
  private static func folder(_ id: NodeID, _ source: any SidebarSource,
                             _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    [SidebarMenuEntry(title: "Rename", action: .rename(id)), .unavailable("Change Icon"), .separator,
     SidebarMenuEntry(title: "Duplicate", action: .duplicate([id])), .unavailable("Share"), .separator,
     SidebarMenuEntry(title: "Copy All Links", action: .copyLinks([id], markdown: false)),
     SidebarMenuEntry(title: "Copy All as Markdown Links", action: .copyLinks([id], markdown: true),
                      modifiers: .option, isAlternate: true),
     SidebarMenuEntry(title: "Paste URL as New Tab", action: .pasteURLAsNewTab(.folder(id)),
                      isEnabled: context.clipboardHasURL),
     .separator,
     moveTo([id], source, context, offersFavorites: false),
     SidebarMenuEntry(title: "Delete", action: .deleteFolder(id))]
  }

  // MARK: 3.5 Split row, 3.6 pane row

  @MainActor
  private static func splitRow(_ id: NodeID, layout: SplitLayoutInfo, _ source: any SidebarSource,
                               _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    var items: [SidebarMenuEntry] = [
      .unavailable("Rename"),                  // a split has no stored title yet
      SidebarMenuEntry(title: "Duplicate Split View", action: .duplicateSplit(id)), .separator,
      SidebarMenuEntry(title: "Separate All Tabs", action: .separateSplit(id)),
      SidebarMenuEntry(title: SplitMenu.convertTitle(for: layout.orientation), action: .convertSplit(id)),
      .separator,
    ]
    if pinnable(id, source) {
      let isPinned = if case .pinned? = source.parent(of: id) { true } else { false }
      items.append(pinItem(pinned: isPinned, [id]))
    }
    items += [moveTo([id], source, context), .unavailable("Share Split View")]
    return items
  }

  @MainActor
  private static func pane(_ id: NodeID, split: NodeID, _ source: any SidebarSource,
                           _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    let panes = source.children(of: .split(split))
    let below = panes.firstIndex(of: id).map { panes.count - $0 - 1 } ?? 0
    return [muteItem(id, context),
            SidebarMenuEntry(title: "Duplicate Split View", action: .duplicateSplit(split)),
            SidebarMenuEntry(title: "Archive Below", action: .archiveBelow(id), isEnabled: below > 0),
            .unavailable("Share"),
            .separator,
            SidebarMenuEntry(title: "Remove Tab from Split View", action: .removePane(id)),
            SidebarMenuEntry(title: "Archive", action: .archive([id]), key: "w")]
  }

  // MARK: 3.7 Multi-selection

  @MainActor
  private static func multiSelection(_ ids: [NodeID], _ source: any SidebarSource,
                                     _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    let plainTabs = ids.allSatisfy {
      if case .tab? = source.node($0), !isPane($0, source) { true } else { false }
    }
    let splittable = plainTabs && (2...SplitLayoutInfo.maximumPanes).contains(ids.count)
    let allPinned = ids.allSatisfy { if case .pinned? = source.parent(of: $0) { true } else { false } }
    var items = [SidebarMenuEntry(title: "Open in Split View", action: .openInSplitView(ids), isEnabled: splittable),
                 SidebarMenuEntry(title: "New Folder", action: .newFolder(ids)),
                 .separator,
                 SidebarMenuEntry(title: "Duplicate", action: .duplicate(ids))]
    let anyPinnable = ids.contains { pinnable($0, source) }
    items.append(SidebarMenuEntry(title: allPinned ? "Unpin Tabs" : "Pin Tabs", action: .pinToggle(ids), key: "d",
                                  isEnabled: anyPinnable))
    items += [moveTo(ids, source, context), .separator]
    items += copyLink(ids, plural: true)
    items += [.separator, SidebarMenuEntry(title: "Archive", action: .archive(ids), key: "w")]
    return items
  }

  // MARK: 3.8 Empty area

  @MainActor
  private static func emptyArea(_ space: SpaceID, _ source: any SidebarSource,
                                _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    [SidebarMenuEntry(title: "New Tab", action: .newTab, key: "t"),
     SidebarMenuEntry(title: "New Folder", action: .newEmptyFolder(space)),
     SidebarMenuEntry(title: "Paste URL as New Tab", action: .pasteURLAsNewTab(.today(space)),
                      isEnabled: context.clipboardHasURL),
     .separator,
     SidebarMenuEntry(title: "Clear Today Tabs", action: .clearToday(space),
                      isEnabled: !source.children(of: .today(space)).isEmpty)]
  }

  // MARK: Shared items

  /// Mute / Unmute (BH-126): enabled while the tab's page is open, "Unmute" while it is muted. A row that shows
  /// sound has a page whatever the loaded set says, so its item is never disabled: a disabled item takes the click
  /// and sends nothing.
  private static func muteItem(_ id: NodeID, _ context: SidebarMenuContext) -> SidebarMenuEntry {
    let audio = context.audio[id] ?? .silent
    return SidebarMenuEntry(title: audio.toggleTitle, action: .toggleMute(id),
                            isEnabled: audio != .silent || context.loadedTabs.contains(id))
  }

  /// A tab row's Mute group, only while its page plays or is muted: the design's tab menus have no Mute item
  /// (BH-126 confirms it for panes only), so a silent tab keeps the designed menu (#364).
  private static func soundGroup(_ id: NodeID, _ context: SidebarMenuContext) -> [SidebarMenuEntry] {
    guard let audio = context.audio[id], audio != .silent else { return [] }
    return [muteItem(id, context), .separator]
  }

  private static func pinItem(pinned: Bool, _ ids: [NodeID]) -> SidebarMenuEntry {
    SidebarMenuEntry(title: pinned ? "Unpin Tab" : "Pin Tab", action: .pinToggle(ids), key: "d")
  }

  /// Copy Link with its Option alternate (KB-013, KB-014); "Copy Links" for a multi-selection.
  private static func copyLink(_ ids: [NodeID], plural: Bool) -> [SidebarMenuEntry] {
    let title = plural ? "Copy Links" : "Copy Link"
    return [SidebarMenuEntry(title: title, action: .copyLinks(ids, markdown: false)),
            SidebarMenuEntry(title: "\(title) as Markdown", action: .copyLinks(ids, markdown: true),
                             modifiers: .option, isAlternate: true)]
  }

  /// Move To: Favorites (tabs and splits only, BH-047, BH-115), a separator, then every Space in order; the Space the
  /// nodes are in is disabled when they all share it.
  @MainActor
  private static func moveTo(_ ids: [NodeID], _ source: any SidebarSource, _ context: SidebarMenuContext,
                             offersFavorites: Bool = true) -> SidebarMenuEntry {
    let homes = Set(ids.map { source.spaceID(containing: $0) })
    let home = homes.count == 1 ? homes.first ?? nil : nil
    var submenu: [SidebarMenuEntry] = []
    if offersFavorites {
      submenu += [SidebarMenuEntry(title: "Favorites", action: .moveToFavorites(ids)), .separator]
    }
    submenu += context.spaces.map {
      SidebarMenuEntry(title: $0.title, action: .moveToSpace(ids, $0.id), isEnabled: $0.id != home)
    }
    return SidebarMenuEntry(title: "Move To", action: nil, submenu: submenu)
  }

  /// A node directly in Pinned or Today (a split included) pins and unpins itself; a foldered tab is pinned through
  /// its folder.
  @MainActor
  private static func pinnable(_ id: NodeID, _ source: any SidebarSource) -> Bool {
    switch source.parent(of: id) {
    case .pinned?, .today?: true
    default: false
    }
  }

  @MainActor
  private static func isPane(_ id: NodeID, _ source: any SidebarSource) -> Bool {
    if case .split? = source.parent(of: id) { true } else { false }
  }

  /// The tabs and splits after `id`'s top-level row in its Space's Today list (BH-077). Empty outside Today.
  @MainActor
  public static func todayNodesBelow(_ id: NodeID, _ source: any SidebarSource) -> [NodeID] {
    var top = id
    for _ in 0..<64 {                       // depth guard against a malformed source
      guard let container = source.parent(of: top)?.containerNode else { break }
      top = container
    }
    guard case .today(let space)? = source.parent(of: top) else { return [] }
    let siblings = source.children(of: .today(space))
    guard let index = siblings.firstIndex(of: top) else { return [] }
    return siblings[(index + 1)...].filter {
      if case .folder? = source.node($0) { false } else { true }
    }
  }
}
