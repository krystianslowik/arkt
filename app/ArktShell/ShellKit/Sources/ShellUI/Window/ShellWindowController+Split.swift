import AppKit
import EngineAPI

/// Split View state of one window (S4). Window lifetime only: the storage format stays at version 1, so nothing here
/// is persisted.
struct SplitWindowState {
  /// The split the content area shows, nil while it shows a plain tab or nothing.
  var split: NodeID?
  /// The panes of `split` as last shown, in order.
  var panes: [NodeID] = []
  /// The pane `split` last showed focused; its successor takes over when it leaves the split.
  var focus: NodeID?
  /// Last focused pane per split (decision 7) [I]. Activating a split row focuses it.
  var activePane: [NodeID: NodeID] = [:]
  /// Panes whose page was closed while their node stayed (Cmd-W on a Pinned or Favorite pane, the X on a Pinned split
  /// row, or the page closing itself): they show a placeholder until clicked or activated, and showing the split
  /// again does not reopen them (decision 6) [I] PARITY(NEEDS-RUNTIME-CHECK RT-36). Forgotten when every pane of the
  /// split is closed.
  var closedPanes: Set<NodeID> = []
  /// A re-show after a source change is queued.
  var resyncPending = false
  /// The local mouse-down monitor that focuses the clicked pane.
  var mouseMonitor: Any?
  /// Where the pane the split pane command bar is open for goes; read when its Enter commits.
  var pendingSide: SplitPaneSide = .afterFocus
  /// The drop target above the page, made on the first sidebar drag and in the view tree only while one runs (S7).
  var dropOverlay: SplitDropOverlayView?
}

/// Where a new pane goes relative to the focused tab, and the orientation of a split made from a plain tab (BH-117).
/// In an existing split the orientation stays as it is [I].
enum SplitPaneSide {
  /// Ctrl-Shift-= (KB-070): right after the focused pane, side by side for a new split.
  case afterFocus
  case right, left, top, bottom

  var isBeforeFocus: Bool { self == .left || self == .top }
  var orientation: SplitOrientation { self == .top || self == .bottom ? .vertical : .horizontal }
}

/// The window side of Split View: one engine tab per pane, the focused pane as `currentTab`, the pane cards' Toolbars,
/// focus by click, divider commits and keeping the shown split in sync with the source (decisions 5, 6, 7, 10).
/// Engine-agnostic: panes are reached only through `EngineClient`, and focus is decided here, not by the engine.
extension ShellWindowController {
  func wireSplit() {
    let container = rootView.split
    container.onCommitFactors = { [weak self] factors in self?.commitSplitFactors(factors) }
    container.onFocusRequest = { [weak self] index in self?.focusPane(at: index) }
    sidebarController.preferredPane = { [weak self] split in self?.preferredPane(of: split) }
    wireSplitRows()
    wireSplitDrag()
    splitState.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      MainActor.assumeIsolated { self?.paneMouseDown(event) }
      return event                                              // the page still gets the click
    }
  }

  func removePaneMouseMonitor() {
    if let monitor = splitState.mouseMonitor { NSEvent.removeMonitor(monitor) }
    splitState.mouseMonitor = nil
  }

  // MARK: Showing

  /// Shows every pane of `split` with `focus` focused. Panes without a page get one (decision 6), except panes in
  /// `closedPanes`, which show a placeholder; the focused pane always opens. The focused pane's tab becomes
  /// `currentTab`, and the panes that left the content area are reported hidden (decision 10).
  func showSplit(_ split: NodeID, focus: NodeID) {
    guard case .split(_, let layout)? = sidebar.node(split) else { return }
    let panes = sidebar.children(of: .split(split))
    guard let focusIndex = panes.firstIndex(of: focus) else { return }
    splitState.closedPanes.remove(focus)
    guard let focusTab = openEngineTab(for: focus) else { return }
    let pages: [NSView?] = panes.map { pane in
      if splitState.closedPanes.contains(pane) { return nil }
      return openEngineTab(for: pane).flatMap { engine.contentView(for: $0) }
    }
    let focusMoved = currentTab != focusTab || splitState.split != split
    rootView.card.setContent(nil)                               // a page shown alone may move into a pane card
    splitState.split = split
    splitState.panes = panes
    splitState.focus = focus
    splitState.activePane[split] = focus
    rootView.showsSplit = true
    rootView.split.show(panes: pages, axis: SplitLayout.axis(for: layout.orientation), factors: layout.widthFactors)
    rootView.split.focusedIndex = focusIndex
    currentTab = focusTab
    setShown(panes.filter { engineTab(of: $0) != nil })
    configurePaneToolbars()
    refreshAddress()
    if focusMoved, let page = engine.contentView(for: focusTab) { window?.makeFirstResponder(page) }
  }

  /// Gives the content area back to the single card; the split container lets go of its pages first.
  func hideSplit() {
    guard splitState.split != nil else { return }
    splitState.split = nil
    splitState.panes = []
    splitState.focus = nil
    rootView.split.show(panes: [], axis: .sideBySide, factors: [])
    rootView.showsSplit = false
  }

  /// The split row's pane to focus: the last focused one unless its page was closed, else the first open pane.
  /// Nil (every pane closed) lets the sidebar pick the first pane, which reopens it.
  private func preferredPane(of split: NodeID) -> NodeID? {
    let open = sidebar.children(of: .split(split)).filter { !splitState.closedPanes.contains($0) }
    if let last = splitState.activePane[split], open.contains(last) { return last }
    return open.first
  }

  // MARK: Focus

  /// Pane N asked for focus: a click on its placeholder, or a pane shortcut. Activation reopens a closed pane.
  func focusPane(at index: Int) {
    guard splitState.split != nil, splitState.panes.indices.contains(index) else { return }
    sidebarController.activate(node: splitState.panes[index])
  }

  /// A mouse-down in another pane's card focuses that pane before the event reaches the page. No engine view
  /// subclassing and no `hitTest` override, so it works for any engine's views.
  private func paneMouseDown(_ event: NSEvent) {
    guard event.window === window, splitState.split != nil else { return }
    let container = rootView.split
    let point = container.convert(event.locationInWindow, from: nil)
    guard let index = container.paneCards.firstIndex(where: { !$0.isHidden && $0.frame.contains(point) }),
          index != container.focusedIndex || currentTab == nil else { return }
    focusPane(at: index)
  }

  // MARK: Pane Toolbars (BH-125, KB-074)

  /// Each pane card shows the Toolbar while it is on, with its own pane's URL and history; its buttons act on that
  /// pane and focus it. Rewired on every show, because a card's pane changes between shows.
  func configurePaneToolbars() {
    let visible = toolbarSetting.isVisible
    for (index, card) in rootView.split.paneCards.enumerated() {
      card.showsToolbar = visible
      let toolbar = card.toolbar
      toolbar.urlBar.isToolbarVisible = visible
      toolbar.urlBar.onPress = { [weak self] in
        guard let self, self.focusPaneForToolbar(index) != nil else { return }
        self.openLocation(nil)
      }
      toolbar.urlBar.onToggleToolbar = { [weak self] in self?.toggleToolbar(nil) }
      toolbar.onBack = { [weak self] in
        guard let self, let tab = self.focusPaneForToolbar(index) else { return }
        self.engine.goBack(tab)
      }
      toolbar.onForward = { [weak self] in
        guard let self, let tab = self.focusPaneForToolbar(index) else { return }
        self.engine.goForward(tab)
      }
      toolbar.onReload = { [weak self] in
        guard let self, let tab = self.focusPaneForToolbar(index) else { return }
        self.engine.reload(tab)
      }
      let pane = splitState.panes.indices.contains(index) ? splitState.panes[index] : nil
      refreshToolbar(toolbar, tab: pane.flatMap { engineTab(of: $0) })
    }
  }

  /// A pane's page changed its URL or history: its own card's Toolbar follows, focused or not.
  func refreshPaneToolbar(of node: NodeID) {
    guard splitState.split != nil, let index = splitState.panes.firstIndex(of: node) else { return }
    let cards = rootView.split.paneCards
    guard cards.indices.contains(index) else { return }
    refreshToolbar(cards[index].toolbar, tab: engineTab(of: node))
  }

  private func refreshToolbar(_ toolbar: ContentToolbarView, tab: TabID?) {
    let snapshot = tab.flatMap { engine.snapshot(of: $0) }
    toolbar.urlBar.url = snapshot?.url
    toolbar.setHistory(canGoBack: snapshot?.canGoBack ?? false, canGoForward: snapshot?.canGoForward ?? false)
  }

  /// Focuses pane `index` when it is not focused yet and returns its tab (nil: no page).
  private func focusPaneForToolbar(_ index: Int) -> TabID? {
    guard splitState.panes.indices.contains(index) else { return nil }
    let pane = splitState.panes[index]
    guard let tab = engineTab(of: pane) else { return nil }
    if tab != currentTab { sidebarController.activate(node: pane) }
    return tab
  }

  // MARK: Source writes and changes

  /// Decision 5: the divider's one commit per drag becomes one source write (and one autosave).
  private func commitSplitFactors(_ factors: [Double]) {
    guard let split = splitState.split else { return }
    do { try sidebar.setSplitWidthFactors(split, factors) } catch { onError?(.editSplit, error) }
  }

  /// Source changes that can change what the shown split looks like (its layout, its panes, the split itself) or
  /// put the current tab into a split queue one re-show.
  func splitSourceDidChange(_ change: SidebarChange) {
    switch change {
    case .node(let id):
      if id == splitState.split { scheduleSplitResync() }
    case .structure, .spaceAdded, .spaceRemoved, .spaceMoved, .spaceChanged:
      if splitState.split != nil || currentNode.map(isPane) == true { scheduleSplitResync() }
    }
  }

  /// Deferred one main-queue turn, like `activateRestoredTabLater`: showing may create engine tabs, whose replay
  /// writes titles to the source, and a source must not be mutated while it delivers a change.
  private func scheduleSplitResync() {
    guard !splitState.resyncPending else { return }
    splitState.resyncPending = true
    DispatchQueue.main.async { [weak self] in self?.resyncSplit() }
  }

  /// Shows the current focus again as the source now has it: the same split re-laid out, a shrunk split, a pane that
  /// became a plain tab, or a tab that became a pane. A focused pane that left the source hands focus to the nearest
  /// pane after it, else before it; with none left the content area empties. Idempotent.
  private func resyncSplit() {
    splitState.resyncPending = false
    splitState.closedPanes = splitState.closedPanes.filter(isPane)            // gone, or no longer a pane
    splitState.activePane = splitState.activePane.filter { sidebar.node($0.key) != nil }
    if let focus = currentNode {
      if splitState.split != nil || isPane(focus) { show(node: focus) }
      return
    }
    guard splitState.split != nil else { return }
    let survivors = splitState.panes.filter { sidebar.node($0) != nil }
    if let next = nearest(to: splitState.focus, in: splitState.panes, where: survivors.contains) {
      sidebarController.activate(node: next)
    } else {
      clearSplit()
    }
  }

  /// A pane's page closed. A pane removed from the source is handled by the re-show its removal queued. A pane that
  /// stays (Pinned, Favorites) shows a placeholder; focus moves to the nearest open pane when it was focused; with no
  /// open pane left the content area empties and the split opens afresh next time (decision 6).
  func paneDidClose(_ node: NodeID, wasFocused: Bool) {
    guard let split = splitState.split else { return }
    guard sidebar.node(node) != nil else {
      scheduleSplitResync()
      return
    }
    splitState.closedPanes.insert(node)
    let panes = splitState.panes
    guard let open = nearest(to: node, in: panes, where: { self.engineTab(of: $0) != nil }) else {
      splitState.closedPanes.subtract(panes)
      clearSplit()
      return
    }
    if wasFocused {
      sidebarController.activate(node: open)
    } else if let focus = currentNode {
      showSplit(split, focus: focus)
    }
  }

  /// A page closed in a split that is not on screen (the X on a Pinned split row, or the page closing itself).
  /// A pane that stays in the source is remembered as closed, so showing its split later does not reopen it
  /// (decision 6); when no pane of that split has a page any more, the split forgets its closed panes and opens
  /// afresh, as for the shown split.
  func hiddenPaneDidClose(_ node: NodeID) {
    guard sidebar.node(node) != nil, let split = split(holding: node) else { return }
    splitState.closedPanes.insert(node)
    let panes = sidebar.children(of: .split(split))
    if !panes.contains(where: { engineTab(of: $0) != nil }) { splitState.closedPanes.subtract(panes) }
  }

  private func isPane(_ node: NodeID) -> Bool {
    if case .split? = sidebar.parent(of: node) { true } else { false }
  }

  /// Hides the split and leaves the content area empty (no current tab).
  private func clearSplit() {
    hideSplit()
    currentTab = nil
    rootView.card.setContent(nil)
    setShown([])
    refreshAddress()
  }

  /// The first pane after `node` in `panes`, else the nearest before it, that satisfies `isCandidate`. With `node`
  /// nil or not in `panes`, the first candidate.
  private func nearest(to node: NodeID?, in panes: [NodeID], where isCandidate: (NodeID) -> Bool) -> NodeID? {
    guard let node, let index = panes.firstIndex(of: node) else { return panes.first(where: isCandidate) }
    let order = panes[(index + 1)...] + panes[..<index].reversed()
    return order.first(where: isCandidate)
  }
}

// MARK: - Shortcuts and menu items (S5)

/// The View menu's Split View actions (`SplitMenu`). Each acts on the current tab as the source has it now, so a
/// shortcut pressed right after a source change still finds the right split.
extension ShellWindowController {
  /// Ctrl-Shift-= (KB-070): the command bar opens for the new pane; Enter adds it right after the focused pane.
  /// A full split shows "Cannot Add New Pane" instead and the bar stays closed (BH-116).
  /// PARITY(NEEDS-RUNTIME-CHECK RT-34): what Arc's new pane shows.
  @objc public func addSplitPane(_ sender: Any?) { beginNewSplitPane(.afterFocus) }
  /// Add Right Split (BH-117), unbound.
  @objc public func addSplitRight(_ sender: Any?) { beginNewSplitPane(.right) }
  /// Add Left Split (BH-117), unbound.
  @objc public func addSplitLeft(_ sender: Any?) { beginNewSplitPane(.left) }
  /// Add Top Split (BH-117), unbound.
  @objc public func addSplitTop(_ sender: Any?) { beginNewSplitPane(.top) }
  /// Add Bottom Split (BH-117), unbound.
  @objc public func addSplitBottom(_ sender: Any?) { beginNewSplitPane(.bottom) }

  /// Ctrl-Shift-- (KB-071, BH-122): the focused pane leaves the split with its page and lands right after it; it is
  /// never archived (CF-18). Focus goes to the pane next to it in the split, after it, else before it (decision 9).
  @objc public func closeSplitPane(_ sender: Any?) {
    guard let pane = currentNode else { return }
    removeFromSplit(pane)
  }

  /// Separate Page from Split View (KB-075), unbound: like Ctrl-Shift--, but the separated page keeps focus and shows
  /// alone [I].
  @objc public func separatePageFromSplit(_ sender: Any?) {
    guard let pane = currentNode, split(holding: pane) != nil else { return }
    do { try sidebar.separatePane(pane) } catch { onError?(.editSplit, error) }
  }

  /// Expand Current Split (KB-075, BH-124), unbound: the focused pane takes the split's place and stays shown; the
  /// other panes follow it as plain tabs.
  @objc public func expandCurrentSplit(_ sender: Any?) {
    guard let pane = currentNode, split(holding: pane) != nil else { return }
    do { try sidebar.expandPane(pane) } catch { onError?(.editSplit, error) }
  }

  /// Convert to Horizontal / Vertical Split View (BH-120): flips the shown split's orientation.
  @objc public func convertSplitOrientation(_ sender: Any?) {
    guard let pane = currentNode, let split = split(holding: pane) else { return }
    flipOrientation(of: split)
  }

  /// Ctrl-Shift-1 ... Ctrl-Shift-4 (KB-072, BH-128): the menu item's tag is the zero-based pane index. A number past
  /// the pane count does nothing.
  @objc public func focusSplitPane(_ sender: Any?) {
    guard let tag = (sender as? NSMenuItem)?.tag, let panes = currentSplitPanes,
          let index = SplitFocus.pane(number: tag + 1, count: panes.count) else { return }
    activate(node: panes[index])
  }

  /// Ctrl-Shift-] (KB-073, BH-128): the next pane, wrapping around. PARITY(NEEDS-RUNTIME-CHECK RT-06)
  @objc public func nextSplitPane(_ sender: Any?) { stepSplitFocus(SplitFocus.next(from:count:)) }

  /// Ctrl-Shift-[ (KB-073, BH-128): the previous pane, wrapping around. PARITY(NEEDS-RUNTIME-CHECK RT-06)
  @objc public func previousSplitPane(_ sender: Any?) { stepSplitFocus(SplitFocus.previous(from:count:)) }

  /// Enables (and titles) the Split View items; nil for any other item. Adding a pane needs a current tab; every other
  /// item needs the current tab to be a split pane, and a focus item a pane with its number.
  func validateSplitMenuItem(_ item: NSMenuItem) -> Bool? {
    switch item.action {
    case #selector(addSplitPane(_:)), #selector(addSplitRight(_:)), #selector(addSplitLeft(_:)),
         #selector(addSplitTop(_:)), #selector(addSplitBottom(_:)):
      return currentNode != nil
    case #selector(convertSplitOrientation(_:)):
      let orientation = currentNode.flatMap(split(holding:)).flatMap { split -> SplitOrientation? in
        if case .split(_, let layout)? = sidebar.node(split) { layout.orientation } else { nil }
      }
      item.title = SplitMenu.convertTitle(for: orientation ?? .horizontal)
      return orientation != nil
    case #selector(focusSplitPane(_:)):
      guard let panes = currentSplitPanes else { return false }
      return SplitFocus.pane(number: item.tag + 1, count: panes.count) != nil
    case #selector(closeSplitPane(_:)), #selector(separatePageFromSplit(_:)), #selector(expandCurrentSplit(_:)),
         #selector(nextSplitPane(_:)), #selector(previousSplitPane(_:)):
      return currentSplitPanes != nil
    default:
      return nil
    }
  }

  /// Commits the split pane command bar (`.newSplitPane`): a new tab for `url` becomes a pane next to the focused tab
  /// on the side the bar was opened for, and gets focus. With no current tab left it opens as a plain new tab [I].
  func openInNewSplitPane(_ url: URL) {
    let side = splitState.pendingSide
    splitState.pendingSide = .afterFocus
    guard let target = currentNode else {
      open(url, inNewTab: true)
      return
    }
    let focusIndex = split(holding: target).flatMap { sidebar.children(of: .split($0)).firstIndex(of: target) } ?? 0
    let index = side.isBeforeFocus ? focusIndex : focusIndex + 1
    do {
      let added = try sidebar.addToSplit(.new(url: url, title: url.host() ?? url.absoluteString), target: target,
                                         at: index, orientation: side.orientation)
      activate(node: added.pane)
    } catch {
      onError?(.addPane, error)
    }
  }

  private func beginNewSplitPane(_ side: SplitPaneSide) {
    if commandBar.isVisible {                       // like Cmd-T and Cmd-L, the shortcut closes an open bar
      commandBar.hide()
      return
    }
    guard currentNode != nil else { return }
    if let panes = currentSplitPanes, panes.count >= SplitLayoutInfo.maximumPanes {
      onError?(.addPane, SplitEditError.splitFull)  // "Cannot Add New Pane", BH-116
      return
    }
    splitState.pendingSide = side
    commandBar.show(.newSplitPane)
  }

  private func stepSplitFocus(_ step: (Int, Int) -> Int) {
    guard let pane = currentNode, let panes = currentSplitPanes, let index = panes.firstIndex(of: pane) else { return }
    activate(node: panes[step(index, panes.count)])
  }

  /// The panes of the split holding the current tab, as the source has them; nil when it is not a split pane.
  private var currentSplitPanes: [NodeID]? {
    currentNode.flatMap(split(holding:)).map { sidebar.children(of: .split($0)) }
  }

  /// The split `node` is a pane of, if any.
  private func split(holding node: NodeID) -> NodeID? {
    if case .split(let split)? = sidebar.parent(of: node) { split } else { nil }
  }
}

// MARK: - Sidebar split rows (S6)

/// The sidebar's split row and pane row interactions: context menus, Opt-clicks and VoiceOver actions (BH-120,
/// BH-121, BH-126, GS-032, GS-033). Like the menu actions above, each reads the split from the source.
extension ShellWindowController {
  func wireSplitRows() {
    sidebarController.onSeparateSplit = { [weak self] split in self?.separateAllTabs(of: split) }
    sidebarController.onRemovePane = { [weak self] pane in self?.removeFromSplit(pane) }
    sidebarController.onConvertSplit = { [weak self] split in self?.flipOrientation(of: split) }
    sidebarController.onDuplicateSplit = { [weak self] split in self?.duplicate(split: split) }
    sidebarController.onDuplicateIntoSplit = { [weak self] tab in self?.duplicateIntoSplit(tab) }
  }

  /// Ctrl-Shift-- and Remove Tab from Split View (BH-121, BH-122): `pane` leaves its split with its page and lands
  /// right after it, never archived (CF-18). When it was focused, focus goes to the pane next to it in the split,
  /// after it, else before it (decision 9); otherwise focus stays where it is.
  func removeFromSplit(_ pane: NodeID) {
    guard let split = split(holding: pane) else { return }
    let survivor = pane == currentNode ? nearest(to: pane, in: sidebar.children(of: .split(split))) { $0 != pane } : nil
    do { try sidebar.separatePane(pane) } catch { onError?(.editSplit, error); return }
    if let survivor { activate(node: survivor) }
  }

  /// Separate All Tabs (BH-121, GS-033): the panes take the split's place as plain tabs. A focused pane stays
  /// focused, now shown alone (the re-show after the source change keeps the focused node).
  func separateAllTabs(of split: NodeID) {
    do { try sidebar.separateSplit(split) } catch { onError?(.editSplit, error) }
  }

  /// Convert to Vertical / Horizontal Split View (BH-120).
  func flipOrientation(of split: NodeID) {
    guard case .split(_, let layout)? = sidebar.node(split) else { return }
    let flipped: SplitOrientation = layout.orientation == .horizontal ? .vertical : .horizontal
    do { try sidebar.setSplitOrientation(split, flipped) } catch { onError?(.editSplit, error) }
  }

  /// Duplicate Split View (BH-126): a copy right after the split; focus does not move [I].
  func duplicate(split: NodeID) {
    do { try sidebar.duplicateSplit(split) } catch { onError?(.editSplit, error) }
  }

  /// Opt-click on the current plain tab (GS-032): a new tab with the same page becomes its pane on the right, side
  /// by side, and gets focus. A pane or a tab that is not current is left alone.
  func duplicateIntoSplit(_ tab: NodeID) {
    guard tab == currentNode, split(holding: tab) == nil, case .tab(_, let url, let title)? = sidebar.node(tab) else {
      return
    }
    do {
      let added = try sidebar.addToSplit(.new(url: url, title: title), target: tab, at: 1, orientation: .horizontal)
      activate(node: added.pane)
    } catch {
      onError?(.addPane, error)
    }
  }
}

// MARK: - Drag a sidebar tab onto the page (S7)

/// What dropping a sidebar tab on the page does (decision 11, GS-011, BH-116, BH-117).
enum SplitDrop: Equatable {
  /// The current plain tab and the dropped tab become a split at the current tab's place, the dropped tab at `index`
  /// (0: first, 1: second).
  case newSplit(target: NodeID, index: Int, orientation: SplitOrientation)
  /// The dropped tab joins the shown split at `index`, and all shares become equal (RT-35). The split's orientation
  /// stays, as for Add Left / Right / Top / Bottom Split [I].
  case addPane(split: NodeID, index: Int)
  /// A pane of the shown split moves from `from` to `to` (both final indexes); its factor follows it.
  case movePane(split: NodeID, from: Int, to: Int)
  /// The shown split is full: the drop shows "Cannot Add New Pane" (BH-116) and changes nothing.
  case full
}

/// The window side of drag-to-split: the drop overlay lives above the page only while a sidebar tab is dragged, its
/// preview shows the pane's future frame, and the drop becomes one source write. Like the menu actions, the drop
/// reads the current tab's split from the source.
extension ShellWindowController {
  func wireSplitDrag() {
    sidebarController.onNodeDragBegan = { [weak self] node in self?.sidebarDragBegan(node) }
    sidebarController.onNodeDragEnded = { [weak self] in self?.sidebarDragEnded() }
  }

  /// Puts the overlay above the page (the single card or the split container; both have the content area's frame).
  private func sidebarDragBegan(_ node: NodeID) {
    let overlay = splitState.dropOverlay ?? makeDropOverlay()
    overlay.frame = rootView.split.frame
    rootView.addSubview(overlay, positioned: .above, relativeTo: rootView.split)
    overlay.begin(node: node)
  }

  private func sidebarDragEnded() {
    guard let overlay = splitState.dropOverlay else { return }
    overlay.end()
    overlay.removeFromSuperview()
  }

  private func makeDropOverlay() -> SplitDropOverlayView {
    let overlay = SplitDropOverlayView(metrics: rootView.metrics)
    overlay.autoresizingMask = []
    overlay.onTarget = { [weak self] node, zone, bounds in
      self?.dropTarget(of: node, in: zone, bounds: bounds) ?? .none
    }
    overlay.onDrop = { [weak self] node, zone in self?.performDrop(of: node, in: zone) ?? false }
    splitState.dropOverlay = overlay
    return overlay
  }

  /// What a drop of `node` in `zone` does, nil when it does nothing: no current tab, `node` is not a tab, the current
  /// plain tab onto itself, or a pane dropped where it already is. The zone's side puts the tab first or last; its
  /// axis only matters for a new split [I] PARITY(NEEDS-RUNTIME-CHECK RT-32).
  func splitDrop(of node: NodeID, in zone: SplitDropZone) -> SplitDrop? {
    guard case .tab? = sidebar.node(node), let current = currentNode else { return nil }
    guard let split = split(holding: current) else {
      guard node != current else { return nil }
      return .newSplit(target: current, index: zone.isBefore ? 0 : 1, orientation: zone.orientation)
    }
    let panes = sidebar.children(of: .split(split))
    if let from = panes.firstIndex(of: node) {
      let to = zone.isBefore ? 0 : panes.count - 1
      return from == to ? nil : .movePane(split: split, from: from, to: to)
    }
    guard panes.count < SplitLayoutInfo.maximumPanes else { return .full }
    return .addPane(split: split, index: zone.isBefore ? 0 : panes.count)
  }

  /// The preview of a drop: the frame the pane gets in `bounds` (the content area) once the split shows, from the same
  /// `SplitLayout.frames` the split container uses.
  private func dropTarget(of node: NodeID, in zone: SplitDropZone, bounds: CGRect) -> SplitDropTarget {
    guard let drop = splitDrop(of: node, in: zone) else { return .none }
    let axis: SplitAxis
    var factors: [Double]
    let index: Int
    switch drop {
    case .full:
      return .full
    case .newSplit(_, let at, let orientation):
      (axis, factors, index) = (SplitLayout.axis(for: orientation), SplitLayout.equalShares(2), at)
    case .addPane(let split, let at):
      guard case .split(_, let layout)? = sidebar.node(split) else { return .none }
      let count = sidebar.children(of: .split(split)).count + 1
      (axis, factors, index) = (SplitLayout.axis(for: layout.orientation), SplitLayout.equalShares(count), at)
    case .movePane(let split, let from, let to):
      guard case .split(_, let layout)? = sidebar.node(split) else { return .none }
      factors = SplitLayout.normalized(layout.widthFactors, count: sidebar.children(of: .split(split)).count)
      factors.insert(factors.remove(at: from), at: to)
      (axis, index) = (SplitLayout.axis(for: layout.orientation), to)
    }
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    let frames = SplitLayout.frames(in: bounds, axis: axis, factors: factors, gap: rootView.split.gap, scale: scale)
    return frames.panes.indices.contains(index) ? .pane(frames.panes[index]) : .none
  }

  /// Performs a drop as one source write; the dropped tab gets focus. A full split shows "Cannot Add New Pane".
  private func performDrop(of node: NodeID, in zone: SplitDropZone) -> Bool {
    guard let drop = splitDrop(of: node, in: zone) else { return false }
    let mutation: SidebarMutation
    if case .movePane = drop { mutation = .editSplit } else { mutation = .addPane }
    do {
      switch drop {
      case .full:
        throw SplitEditError.splitFull
      case .newSplit(let target, let index, let orientation):
        try sidebar.addToSplit(.existing(node), target: target, at: index, orientation: orientation)
      case .addPane(let split, let index):
        try sidebar.addToSplit(.existing(node), target: split, at: index, orientation: .horizontal)
      case .movePane(_, let from, let to):
        try sidebar.movePane(node, to: to > from ? to + 1 : to)   // counted before the pane leaves its place
      }
    } catch {
      onError?(mutation, error)
      return false
    }
    activate(node: node)
    return true
  }
}
