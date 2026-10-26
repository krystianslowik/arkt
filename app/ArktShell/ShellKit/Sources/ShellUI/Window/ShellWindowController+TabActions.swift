import AppKit

/// The window side of the sidebar tab actions (#105, design/tab-context-menus): the context menus' actions, bulk
/// archive of a multi-selection (BH-072), duplicate with history (BH-027), the empty-area double-click (BH-021) and
/// the non-key dimming (BH-025).
///
/// Bulk actions never tear a Split View apart: a multi-selection reaches them as tabs and whole splits only
/// (`SidebarSelection.bulkTargets`), and each node then takes the same single-node path its own menu item takes
/// (`close(node:)`, `move`, `duplicate(split:)`). No action here runs on its own: every one starts from a user's
/// menu choice or key press, so nothing archives the current or a visible tab behind the user's back.
extension ShellWindowController {
  func wireTabActions() {
    sidebarController.onMenuAction = { [weak self] action in self?.perform(action) }
    sidebarController.onEmptyAreaDoubleClick = { [weak self] in self?.newTab(nil) }
  }

  /// Runs a context menu action of any Space page.
  func perform(_ action: SidebarMenuAction) {
    switch action {
    case .rename(let id): sidebarController.beginRename(node: id)
    case .duplicate(let ids): duplicate(ids)
    case .pinToggle(let ids): pinToggle(ids)
    case .moveToFavorites(let ids):
      for id in Self.moveTargets(ids, in: sidebar) { move(id, to: .favorites(profile: sidebarController.profile)) }
    case .moveToSpace(let ids, let space): move(ids, toSpace: space)
    case .copyLinks(let ids, let markdown): copyLinks(ids, markdown: markdown)
    case .archiveBelow(let id): archiveBelow(id)
    case .archive(let ids): closeAll(ids)
    case .resetPinned(let id): resetPinned(node: id)
    case .replacePin(let id): replacePin(node: id)
    case .separateFromPinned(let id): separateFromPinned(node: id)
    case .removeFromFavorites(let id): removeFromFavorites(id)
    case .openInSplitView(let ids): openInSplitView(ids)
    case .newFolder(let ids): newFolder(holding: ids)
    case .newEmptyFolder(let space): newFolder(in: space)
    case .separateSplit(let id): separateAllTabs(of: id)
    case .convertSplit(let id): flipOrientation(of: id)
    case .duplicateSplit(let id): duplicate(split: id)
    case .removePane(let id): removeFromSplit(id)
    case .deleteFolder(let id): deleteFolder(id)
    case .pasteURLAsNewTab(let location): pasteURLAsNewTab(in: location)
    case .newTab: newTab(nil)
    case .clearToday(let space): clearToday(space)
    }
  }

  // MARK: Archive (BH-072, BH-075, BH-077)

  /// Closes `ids` the way Cmd-W closes one node. One node: exactly `close(node:)` (a pane archives alone, BH-123).
  /// Two or more: whole tabs and splits only, the node holding the current tab last, so the tab that becomes current
  /// afterwards is one that stays; then "Archived N tabs" when two or more Today tabs went (alerts design, decision 3).
  func closeAll(_ ids: [NodeID]) {
    guard ids.count > 1 else {
      if let id = ids.first { close(node: id) }
      return
    }
    let targets = SidebarSelection.bulkTargets(ids, in: sidebar)
    let holdsCurrent = { (node: NodeID) in self.currentNode.map(self.tabs(in: node).contains) ?? false }
    let ordered = targets.filter { !holdsCurrent($0) } + targets.filter(holdsCurrent)
    let archivedTabs = ordered.reduce(0) { count, node in
      if case .today? = sidebar.section(containing: node) { count + tabs(in: node).count } else { count }
    }
    for node in ordered { close(node: node) }
    if archivedTabs >= 2 { toasts.show(Toast(text: Self.archivedToastText(count: archivedTabs))) }
  }

  /// The several-tabs archive toast (alerts design 4.3).
  nonisolated static func archivedToastText(count: Int) -> String { "Archived \(count) tabs" }

  /// Archive Below (BH-077): the Today rows below `id` (a pane: the panes below it in its split, each archived
  /// alone, BH-126).
  func archiveBelow(_ id: NodeID) {
    if case .split(let split)? = sidebar.parent(of: id) {
      let panes = sidebar.children(of: .split(split))
      guard let index = panes.firstIndex(of: id) else { return }
      for pane in panes[(index + 1)...].reversed() { close(node: pane) }
      return
    }
    closeAll(SidebarContextMenu.todayNodesBelow(id, sidebar))
  }

  /// Clear Today Tabs (BH-075): every Today row of the Space; a Today folder goes to the Archive whole.
  func clearToday(_ space: SpaceID) {
    let rows = sidebar.children(of: .today(space))
    let folders = rows.filter { if case .folder? = sidebar.node($0) { true } else { false } }
    if !folders.isEmpty { onArchive?(folders) }
    closeAll(rows.filter { !folders.contains($0) })
  }

  /// Cmd-W with two or more selected rows (BH-072); nil otherwise, so Cmd-W closes the current tab as before.
  func closeSelection() -> Bool {
    let selected = sidebarController.selectedNodes
    guard selected.count >= 2 else { return false }
    closeAll(selected)
    return true
  }

  // MARK: Delete folder (BH-095)

  /// The folder and every tab in it go to the Archive (restorable from there); their pages close with the rows. When
  /// it held the current tab, the next tab becomes current, as Close Tab does.
  func deleteFolder(_ id: NodeID) {
    guard case .folder? = sidebar.node(id) else { return }
    archive(id, heldCurrent: currentNode.map(tabs(in: id).contains) ?? false)
  }

  // MARK: Duplicate (BH-027, BH-095)

  /// Each node gets a copy right after it. A loaded tab's copy gets the engine's duplicate, history included; a
  /// split goes through Duplicate Split View; a folder copies its rows. A single duplicated tab becomes current [I].
  func duplicate(_ ids: [NodeID]) {
    for id in ids {
      switch sidebar.node(id) {
      case .split?:
        duplicate(split: id)
      case .tab?:
        if let copy = duplicateTab(id), ids.count == 1 { activate(node: copy) }
      case .folder?:
        do { try sidebar.duplicateNode(id) } catch { onError?(.addTab, error) }
      case nil:
        break
      }
    }
  }

  /// The copy's node, with the engine's duplicate of the live tab mapped to it (history and all).
  private func duplicateTab(_ id: NodeID) -> NodeID? {
    let copy: NodeID
    do { copy = try sidebar.duplicateNode(id) } catch {
      onError?(.addTab, error)
      return nil
    }
    if let tab = tabsByNode[id], let copyTab = engine.duplicateTab(tab) {
      tabsByNode[copy] = copyTab
      nodeByTab[copyTab] = copy
      sidebarController.markLoaded(node: copy)
      if let snapshot = engine.snapshot(of: copyTab) { replay(snapshot, into: copy) }
    }
    return copy
  }

  // MARK: Pin, move

  /// Pin Tabs / Unpin Tabs (KB-012) on a selection: when every pinnable node is pinned they all unpin, otherwise the
  /// Today ones pin. Panes act through their split (`pinnableNode`). One toast-less move per node.
  func pinToggle(_ ids: [NodeID]) {
    var seen: Set<NodeID> = []
    let nodes = ids.compactMap { Self.pinnableNode($0, in: sidebar) }.filter { seen.insert($0).inserted }
    guard nodes.count > 1 else {
      if let node = nodes.first { togglePin(of: node) }
      return
    }
    let isPinned = { (node: NodeID) in if case .pinned? = self.sidebar.parent(of: node) { true } else { false } }
    if nodes.allSatisfy(isPinned) {
      for node in nodes.reversed() {
        guard case .pinned(let space)? = sidebar.parent(of: node) else { continue }
        move(node, to: .today(space), at: 0)
      }
    } else {
      for node in nodes where !isPinned(node) {
        guard case .today(let space)? = sidebar.parent(of: node) else { continue }
        move(node, to: .pinned(space))
      }
    }
  }

  /// Cmd-D with a multi-selection pins or unpins it; false when there is none.
  func pinSelection() -> Bool {
    let selected = sidebarController.selectedNodes
    guard selected.count >= 2 else { return false }
    pinToggle(selected)
    return true
  }

  /// The nodes a move acts on: one node as chosen (a folder too), a selection as whole tabs and splits.
  static func moveTargets(_ ids: [NodeID], in sidebar: any SidebarSource) -> [NodeID] {
    ids.count == 1 ? ids : SidebarSelection.bulkTargets(ids, in: sidebar)
  }

  /// Move To > a Space (BH-042): pinned rows (foldered ones too) land at the end of that Space's Pinned, Today rows
  /// on top of its Today, in their order. The current tab moving away takes the window with it [I].
  func move(_ ids: [NodeID], toSpace space: SpaceID) {
    let current = currentNode
    var movedCurrent = false
    var todayIndex = 0
    for node in Self.moveTargets(ids, in: sidebar) {
      let destination: SidebarLocation
      switch sidebar.section(containing: node) {
      case .pinned?: destination = .pinned(space)
      case .today?: destination = .today(space)
      default: continue
      }
      let index: Int? = if case .today = destination { todayIndex } else { nil }
      guard move(node, to: destination, at: index) else { continue }
      if case .today = destination { todayIndex += 1 }
      if let current, tabs(in: node).contains(current) { movedCurrent = true }
    }
    if movedCurrent, let current { activate(node: current) }
  }

  /// Remove from Favorites: the Favorite goes on top of the current Space's Today, as an ordinary tab.
  func removeFromFavorites(_ id: NodeID) {
    guard let space = sidebarController.currentSpace ?? createSpace() else { return }
    move(id, to: .today(space), at: 0)
  }

  // MARK: Split View (BH-117)

  /// Open in Split View: the selected tabs (2 to 4) become one split at the first tab's place, side by side.
  func openInSplitView(_ ids: [NodeID]) {
    guard (2...SplitLayoutInfo.maximumPanes).contains(ids.count), let first = ids.first else { return }
    do {
      var target = first
      for (offset, tab) in ids.dropFirst().enumerated() {
        target = try sidebar.addToSplit(.existing(tab), target: target, at: offset + 1, orientation: .horizontal).split
      }
      activate(node: first)
    } catch {
      onError?(.addPane, error)
    }
  }

  // MARK: Folders (BH-094, KB-040)

  /// The title a new folder gets before the user names it [I].
  static let newFolderTitle = "New Folder"

  /// New Folder on a selection: a new folder takes the selected rows in order, then opens for naming [I]. Rows that
  /// all sit in one folder form a folder nested there, at the first one's place (BH-094); any other selection gets a
  /// new folder in Pinned (at the first selected pinned row's place, else at the end).
  func newFolder(holding ids: [NodeID]) {
    let nodes = Self.moveTargets(ids, in: sidebar)
    guard let space = nodes.lazy.compactMap({ self.sidebar.spaceID(containing: $0) }).first else { return }
    let location = Self.newFolderLocation(for: nodes, in: sidebar) ?? .pinned(space)
    let siblings = sidebar.children(of: location)
    let index = nodes.lazy.compactMap { siblings.firstIndex(of: $0) }.min()
    let folder: NodeID
    do { folder = try sidebar.addFolder(title: Self.newFolderTitle, in: location, at: index) } catch {
      onError?(.moveNode, error)
      return
    }
    for node in nodes { move(node, to: .folder(folder)) }
    sidebarController.beginRename(node: folder)
  }

  /// The folder holding every node, when they share one (BH-094's nested folder); nil otherwise.
  static func newFolderLocation(for nodes: [NodeID], in sidebar: any SidebarSource) -> SidebarLocation? {
    let parents = Set(nodes.compactMap { sidebar.parent(of: $0) })
    guard parents.count == 1, let parent = parents.first, case .folder = parent else { return nil }
    return parent
  }

  /// New Folder on the empty area: an empty folder at the end of the Space's Pinned, open for naming [I].
  func newFolder(in space: SpaceID) {
    do {
      let folder = try sidebar.addFolder(title: Self.newFolderTitle, in: .pinned(space), at: nil)
      sidebarController.beginRename(node: folder)
    } catch {
      onError?(.moveNode, error)
    }
  }

  // MARK: Links (KB-013, KB-014, KB-016, BH-095)

  /// Copy Link, Copy Links, Copy All Links: the URLs of every tab in `ids` (a folder's nested tabs and a split's
  /// panes included), one per line; Markdown links with the Option alternates.
  func copyLinks(_ ids: [NodeID], markdown: Bool) {
    let links = ids.flatMap { tabs(in: $0) }.compactMap { node -> SidebarLink? in
      guard case .tab(_, let stored, let title)? = sidebar.node(node) else { return nil }
      let live = tabsByNode[node].flatMap { engine.snapshot(of: $0)?.url }
      return SidebarLink(title: title, url: live ?? stored)
    }
    guard !links.isEmpty else { return }
    linkPasteboard.clearContents()
    linkPasteboard.setString(SidebarLink.text(for: links, markdown: markdown), forType: .string)
  }

  /// Paste URL as New Tab: the clipboard's URL as a new tab in `location` (a folder: at its end; Today: on top).
  func pasteURLAsNewTab(in location: SidebarLocation) {
    guard let raw = linkPasteboard.string(forType: .string),
          let url = URLInputParser.url(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
    let index: Int? = if case .today = location { 0 } else { nil }
    do {
      try sidebar.addTab(url: url, title: url.host() ?? url.absoluteString, in: location, at: index)
      announceCreation(.tab)                                        // BH-006
    } catch {
      onError?(.addTab, error)
    }
  }

  // MARK: Non-key dimming (BH-025)

  /// Only the sidebar dims while another window is key; the content card is untouched (design 5). This window's
  /// own panels taking key (the command bar, a sheet such as Delete Space, a child window) do not count, or every
  /// Cmd-T would dim the sidebar.
  func windowKeyStateChanged(isKey: Bool) {
    guard !isKey else {
      sidebarController.view.isDimmed = false
      return
    }
    // The next key window is known only after this resign is delivered.
    Task { @MainActor [weak self] in
      guard let self, let window = self.window else { return }
      self.sidebarController.view.isDimmed = Self.dimsSidebar(
        window: window, keyWindow: NSApp.keyWindow, isKey: window.isKeyWindow, ownPanels: self.ownKeyableWindows)
    }
  }

  /// The windows that may take key without dimming this window's sidebar: the command bar panel, attached sheets and
  /// child windows.
  var ownKeyableWindows: [NSWindow] {
    guard let window else { return [commandBar.panel] }
    return [commandBar.panel] + window.sheets + (window.childWindows ?? [])
  }

  /// The sidebar dims unless this window or one of its own panels is key; with no key window (the app is in the
  /// background) it dims too.
  nonisolated static func dimsSidebar(window: AnyObject, keyWindow: AnyObject?, isKey: Bool,
                                      ownPanels: [AnyObject]) -> Bool {
    if isKey { return false }
    guard let keyWindow else { return true }
    return keyWindow !== window && !ownPanels.contains { $0 === keyWindow }
  }
}

/// A tab's title and URL as Copy Link writes them.
struct SidebarLink: Equatable, Sendable {
  var title: String
  var url: URL

  /// Plain: one URL per line. Markdown: one `[title](url)` per line, with brackets in the title escaped.
  static func text(for links: [SidebarLink], markdown: Bool) -> String {
    links.map { link in
      guard markdown else { return link.url.absoluteString }
      let title = link.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
      return "[\(title.isEmpty ? link.url.absoluteString : title)](\(link.url.absoluteString))"
    }.joined(separator: "\n")
  }
}
