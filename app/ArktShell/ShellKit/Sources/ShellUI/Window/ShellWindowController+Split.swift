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
  /// Panes whose page was closed while their node stayed (Cmd-W or the X on a Pinned or Favorite pane): they show a
  /// placeholder until clicked or activated, and showing the split again does not reopen them (decision 6) [I]
  /// PARITY(NEEDS-RUNTIME-CHECK RT-36). Forgotten when every pane of the split is closed.
  var closedPanes: Set<NodeID> = []
  /// A re-show after a source change is queued.
  var resyncPending = false
  /// The local mouse-down monitor that focuses the clicked pane.
  var mouseMonitor: Any?
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
    case .structure, .spaces:
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
    splitState.closedPanes = splitState.closedPanes.filter { sidebar.node($0) != nil }
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
