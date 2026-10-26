import AppKit
import EngineAPI

/// Reopen the most recently closed tab or Peek (#346, #110: BH-074, BH-150, KB-010, KB-011, KB-079). One stack per
/// window (`reopenStack`) holds both, most recent on top; Cmd-Shift-T (File > Reopen Closed Tab) and Cmd-Z when no
/// text is being edited (`ReopenUndoRouter`) take the top one back, and repeating walks back further.
///
/// Each closed page is parked first: `duplicateTab` makes a copy with its back and forward history that is never
/// shown, so it never loads, plays or runs, and the page itself closes as before. Reopening maps the copy to the row
/// again (a Today row comes back from the archive record, at the place it had), or puts it back in the Peek. Without
/// a copy (the engine refused, or it closed with its window) the row reopens its stored URL, as a restore from the
/// Archive does.
extension ShellWindowController {
  /// Something can be reopened: a close on the stack, or a Peek still on its way out.
  public var canReopenClosed: Bool { peek.isClosing || !reopenStack.isEmpty }

  /// File > Reopen Closed Tab (Cmd-Shift-T, KB-010).
  @objc public func reopenClosedTab(_ sender: Any?) { reopenClosed() }

  /// Takes the most recent close back. A Peek still closing turns around where it is; otherwise the top of the stack
  /// reopens, skipping items whose row is gone for good. True when something came back.
  @discardableResult
  public func reopenClosed() -> Bool {
    defer { toasts.dismiss(PeekController.closedToast) }
    if peek.reverseClose() { return true }
    while let item = reopenStack.pop() {
      if case .batch(let batch) = item { dismissUndoToast(of: batch.id) }
      if reopen(item) { return true }
    }
    return false
  }

  // MARK: Undo toast (alerts design, decision 3)

  /// Shows `toast` (an undo kind) for batch `id`: its Undo brings back exactly that batch, wherever it is on the stack;
  /// Cmd-Z takes the top of the stack, which is the same batch until something else closes.
  func showUndoToast(_ toast: Toast, batch id: UUID) {
    undoToastBatch = id
    toasts.show(toast) { [weak self] in self?.undo(batch: id) }
  }

  /// The undo toast's action. True when something came back.
  @discardableResult
  func undo(batch id: UUID) -> Bool {
    guard let batch = reopenStack.remove(batch: id) else { return false }
    dismissUndoToast(of: id)
    return reopen(.batch(batch))
  }

  private func dismissUndoToast(of id: UUID) {
    guard undoToastBatch == id else { return }
    undoToastBatch = nil
    toasts.dismiss { $0.kind == .undo }
  }

  /// Rows an auto-archive pass took (BH-085): one batch on the stack, so Cmd-Z and the toast's Undo restore them from
  /// the Archive at the top of Today. Shows `toast` when given (two or more tabs, decision 3).
  public func rememberAutoArchived(_ nodes: [NodeID], toast: Toast?) {
    guard !nodes.isEmpty else { return }
    let mark = reopenStack.beginBatch()
    for node in nodes {
      remember(.node(ClosedNode(node: node, isArchived: true, location: nil, index: nil, parked: [:])))
    }
    let id = UUID()
    reopenStack.collapse(since: mark, into: id)
    closeParked(reopenStack.endBatch())
    if let toast { showUndoToast(toast, batch: id) }
  }

  // MARK: Closing

  /// A user close of `node` (Cmd-W, the row's X, a bulk archive) is about to close `pages`: parks a copy of each and
  /// puts the close on the stack. A Today row goes to the Archive; a pinned tab or Favorite keeps its row.
  func rememberClose(of node: NodeID, pages: [NodeID], archived: Bool) {
    var parked: [NodeID: TabID] = [:]
    for page in pages {
      guard let tab = tabsByNode[page], let copy = park(tab) else { continue }
      parked[page] = copy
    }
    let location = sidebar.parent(of: node)
    let index = location.flatMap { sidebar.children(of: $0).firstIndex(of: node) }
    remember(.node(ClosedNode(node: node, isArchived: archived, location: location, index: index,
                              splitShare: splitShare(of: node, at: location, index: index), parked: parked)))
  }

  /// A pane's share of its split, so a reopen gives it back (#403); nil for any other row.
  private func splitShare(of node: NodeID, at location: SidebarLocation?, index: Int?) -> Double? {
    guard case .split(let split)? = location, let index, case .split(_, let layout)? = sidebar.node(split) else {
      return nil
    }
    let shares = SplitLayout.normalized(layout.widthFactors, count: sidebar.children(of: .split(split)).count)
    return shares.indices.contains(index) ? shares[index] : nil
  }

  /// The close of `node` was cancelled at a leave-site prompt (Decision 11): it never happened. A pane's close is
  /// remembered on its split.
  func forgetClose(of node: NodeID) {
    var closed = reopenStack.remove(node: node)
    if closed.isEmpty, case .split(let split)? = sidebar.parent(of: node) { closed = reopenStack.remove(node: split) }
    closeParked(closed)
  }

  /// A closed Peek. `withSource`: its source tab's close closed it, so it rides on that close when it is on the
  /// stack and both come back together.
  func rememberClosedPeek(_ closed: ClosedPeek, withSource: Bool) {
    if withSource, let source = closed.sourceNode, reopenStack.attach(closed, to: source) { return }
    remember(.peek(closed))
  }

  /// An unloaded copy of `tab`, with its history, that takes no part in the window: no row, no activation.
  func park(_ tab: TabID) -> TabID? {
    guard let copy = engine.duplicateTab(tab) else { return nil }
    parkedTabs.insert(copy)
    return copy
  }

  private func remember(_ item: ClosedItem) {
    closeParked(reopenStack.push(item))
  }

  func closeParked(_ tabs: [TabID]) {
    for tab in tabs {
      parkedTabs.remove(tab)
      engine.closeTab(tab, mode: .skipUnloadHandlers)
    }
  }

  /// Engine events of tabs without a row that concern parked copies. True when `event` was about one.
  func handleParkedTabEvent(_ event: EngineEvent) -> Bool {
    guard parkedTabs.contains(event.tabID) else { return false }
    switch event {
    case .tabClosed(let tab, _):
      // Its window closed, or the stack let it go: an item still holding it reopens without history.
      parkedTabs.remove(tab)
      reopenStack.forget(parked: tab)
    case .activeTabChanged(let tab):
      // Chromium makes a duplicate its window's active tab, after the shell may have picked another (a new Peek's
      // tab): what the shell last asked for stays active, else the current tab.
      guard let engineWindow, engine.latestActiveTab(in: engineWindow) == tab,
            let mine = [engineActiveTab, currentTab].compactMap({ $0 }).first(where: { !parkedTabs.contains($0) })
      else { break }
      activateEngineTab(mine)
    default:
      break
    }
    return true
  }

  // MARK: Reopening

  private func reopen(_ item: ClosedItem) -> Bool {
    switch item {
    case .peek(let closed):
      return reopen(closed)
    case .node(let closed):
      return reopen(closed)
    case .batch(let batch):
      // Newest close first, as single undos would run, so each row lands back at the index it left. Nothing is
      // activated on the way: only the row that held the current tab (closed last, so first back) is shown again, and
      // only when its page was parked, so undoing an auto-archive pass loads no page.
      var reopened = false
      var shown: (node: NodeID, peek: ClosedPeek?)?
      for closed in batch.nodes.reversed() {
        guard let node = reopen(closed, activating: false) else { continue }
        reopened = true
        if shown == nil, closed.node == batch.nodes.last?.node, !closed.parked.isEmpty {
          shown = (node, closed.peek)
        } else if let parked = closed.peek?.parked {
          closeParked([parked])                       // a Peek comes back only over the row that is shown
        }
      }
      if let shown {
        activate(node: shown.node)
        if let peek = shown.peek { reopen(peek) }
      }
      return reopened
    }
  }

  private func reopen(_ closed: ClosedNode) -> Bool {
    reopen(closed, activating: true) != nil
  }

  /// Puts the row back and maps its parked pages to it; shows it when `activating`. The row, or nil when it is gone.
  private func reopen(_ closed: ClosedNode, activating: Bool) -> NodeID? {
    guard let node = restoredNode(for: closed) else {
      closeParked(ClosedItem.node(closed).parkedTabs)
      return nil
    }
    for (page, copy) in closed.parked {
      parkedTabs.remove(copy)
      if node == closed.node, case .tab? = sidebar.node(page), tabsByNode[page] == nil,
         engine.snapshot(of: copy) != nil {
        adoptParked(copy, as: page)
      } else {
        engine.closeTab(copy, mode: .skipUnloadHandlers)
      }
    }
    guard activating else { return node }
    activate(node: node)
    if let peekClosed = closed.peek { reopen(peekClosed) }
    return node
  }

  /// The row the close took: back from the Archive at its old place, or still in the sidebar (a pinned tab or a
  /// Favorite, or a Today row the user already restored from the Archive). Nil when it is gone.
  private func restoredNode(for closed: ClosedNode) -> NodeID? {
    if sidebar.node(closed.node) != nil { return closed.node }
    guard closed.isArchived, let node = onReopenArchived?(closed.node), sidebar.node(node) != nil else { return nil }
    if case .split(let split)? = closed.location {
      putBack(node, into: split, index: closed.index, share: closed.splitShare)
    } else {
      putBack(node, at: closed.location, index: closed.index)
    }
    return node
  }

  /// A pane goes back into its split, at its old index with its old share (#403), when that split still exists and
  /// has room; otherwise it stays where the restore put it, a Today tab. The panes on screen reflow when the split
  /// is the one shown.
  private func putBack(_ node: NodeID, into split: NodeID, index: Int?, share: Double?) {
    guard case .split(_, let layout)? = sidebar.node(split), case .tab? = sidebar.node(node),
          sidebar.parent(of: node) != .split(split) else { return }
    let before = sidebar.children(of: .split(split))
    let factors = SplitLayout.normalized(layout.widthFactors, count: before.count)
    let at = min(max(index ?? before.count, 0), before.count)
    do {
      try sidebar.addToSplit(.existing(node), target: split, at: at, orientation: layout.orientation)
    } catch {
      return                                                    // full, or refused: a Today tab, as before #403
    }
    if splitState.split == split { splitState.reflowAfterReopen = (split, node) }
    // A refused factor write leaves the equal shares `addToSplit` gave; the pane is back either way.
    try? sidebar.setSplitWidthFactors(split, SplitLayout.inserting(share: share, at: at, into: factors))
  }

  /// A restore lands on top of Today (`Archiver.restore`); a reopen puts the row back where it was.
  private func putBack(_ node: NodeID, at location: SidebarLocation?, index: Int?) {
    guard let location, case .today = location, let index, sidebar.parent(of: node) == location,
          let current = sidebar.children(of: location).firstIndex(of: node), current != index else { return }
    let last = sidebar.children(of: location).count - 1
    let target = min(index, last)
    // `moveNode` measures the index before the node leaves its place.
    try? sidebar.moveNode(node, to: location, at: target > current ? target + 1 : target)
  }

  private func adoptParked(_ tab: TabID, as node: NodeID) {
    tabsByNode[node] = tab
    nodeByTab[tab] = node
    sidebarController.markLoaded(node: node)
    if let snapshot = engine.snapshot(of: tab) { replay(snapshot, into: node) }
  }

  /// A closed Peek over its source: the source row is shown first (the Peek closed with it, or Tab Handoff moved it),
  /// else the Peek comes back over the current tab. False when there is no tab to put it over.
  @discardableResult
  private func reopen(_ closed: ClosedPeek) -> Bool {
    if let source = closed.sourceNode, sidebar.node(source) != nil, currentNode != source,
       !visibleNodes.contains(source) {
      activate(node: source)
    }
    let sourceTab = closed.sourceNode.flatMap { tabsByNode[$0] } ?? currentTab
    if let copy = closed.parked { parkedTabs.remove(copy) }
    guard let sourceTab else {
      if let copy = closed.parked { engine.closeTab(copy, mode: .skipUnloadHandlers) }
      return false
    }
    peek.reopen(closed, over: sourceTab)
    return true
  }
}
