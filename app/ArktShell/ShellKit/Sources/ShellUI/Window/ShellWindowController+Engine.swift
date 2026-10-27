import AppKit
import EngineAPI

/// A Today node archived once its pages have closed (week-3 Decision 11).
struct PendingArchive {
  /// The node's engine tabs that have not reported `.tabClosed` yet.
  var tabs: Set<TabID>
  /// The node held the current tab when the close was asked for; its successor becomes current afterwards.
  let heldCurrent: Bool
  /// The Space the close started in; a held close cannot restore a successor in another selected Space.
  let space: SpaceID?
}

// MARK: - Engine window

/// The window side of the engine's windows (week-3 plan, W3-7 A and B): one engine window per shell window, created on
/// the first tab or adopted from a host provider, its tab events routed by window (`observe(window:)`), engine tabs
/// turned into Today rows, activation kept in step both ways, and the commands the shell claims.
extension ShellWindowController {
  /// The engine window, created now when there is none yet (decision 4: on the first tab).
  func ensureEngineWindow() -> EngineWindowID {
    if let engineWindow { return engineWindow }
    let id = engine.createWindow(host: engineHost)
    attach(id)
    return id
  }

  /// For a window built by an engine host provider: the engine window this controller's `engineHost` was handed to,
  /// once its `.windowOpened` arrived. Tabs the engine already put in it become Today rows, and its active tab is
  /// shown. The provider's owner pairs hosts with `.windowOpened` events; the engine does not tell a host its id.
  public func adopt(engineWindow id: EngineWindowID) {
    guard engineWindow == nil else { return }
    attach(id)
    for tab in engine.tabIDs where nodeByTab[tab] == nil && engine.snapshot(of: tab)?.window == id {
      engineDidCreateTab(tab)
    }
    if currentTab == nil, let active = engine.activeTab(in: id), let node = nodeByTab[active] {
      activate(node: node)
    }
  }

  private func attach(_ id: EngineWindowID) {
    engineWindow = id
    tabObservation = engine.observe(window: id) { [weak self] event in self?.handle(event) }
    windowObservation = engine.observeWindows { [weak self] event in
      guard let self, event.windowID == self.engineWindow else { return }
      self.handleWindow(event)
    }
    refreshExtensions()
  }

  private func handleWindow(_ event: EngineWindowEvent) {
    switch event {
    case .windowOpened:
      break
    case .extensionActionsChanged:
      refreshExtensions()
    case .windowClosed(_, let reason):
      // Its tabs reported `.tabClosed` already (contract rule 11). A window whose last page moved to another window
      // (#300) or closed (#386) stays open without an engine window when the engine closed the emptied window
      // (`.lastTabClosed`); the next page it shows makes a new one. Every other close takes the window with it: the
      // user's (close button, Close Window), an extension's (`chrome.windows.remove`, #401) and quitting.
      let keepsWindow = reason == .lastTabClosed && keepsWindowWithoutEngine && !isWindowCloseRequested
      keepsWindowWithoutEngine = false
      engineWindow = nil
      engineActiveTab = nil
      isWindowCloseRequested = false
      stampsShownTabsOnWindowClose = false
      tabObservation = nil
      windowObservation = nil
      pendingArchives = [:]
      expectsEngineReactivation = false
      refreshExtensions()
      let reshow = nodeToReshow
      nodeToReshow = nil
      guard keepsWindow else {
        window?.close()
        return
      }
      // A page opened in the closing window went with it (#386): the row still current shows it again.
      if let reshow, sidebar.node(reshow) != nil, sidebarController.current == nil { activate(node: reshow) }
    }
  }

  // MARK: Engine tabs

  /// A tab the engine opened on its own in this window (`window.open`, a link with `target=_blank`,
  /// `chrome.tabs.create`) becomes a Today tab in the current Space. Tabs this window created (origin `.client`) are
  /// mapped by the call that created them. A tab the sidebar refuses is closed, so no live tab is left without a row.
  func engineDidCreateTab(_ tab: TabID) {
    guard let snapshot = engine.snapshot(of: tab), snapshot.origin == .engine,
          snapshot.window != nil, snapshot.window == engineWindow else { return }
    expectsEngineReactivation = false
    guard !isWindowCloseRequested else {                  // the window is going away: no row that would outlive it
      engine.closeTab(tab, mode: .skipUnloadHandlers)
      return
    }
    if let opener = snapshot.opener, nodeByTab[opener] != nil || opener == peek.session?.tab {
      // Opened by a tab of this window (#345): a `target=_blank` link can become a Peek. Its URL and activation
      // arrive as their own events after the creation, in the same batch, so the window decides one turn later.
      DispatchQueue.main.async { [weak self] in self?.placeOpenedTab(tab) }
      return
    }
    addTodayRow(for: tab, snapshot: snapshot)
  }

  /// An engine tab opened by another tab of this window, once its first events are in: the Peek takes it, or it
  /// becomes a Today row, selected when the engine made it the active tab.
  private func placeOpenedTab(_ tab: TabID) {
    guard nodeByTab[tab] == nil, peek.session?.tab != tab, let snapshot = engine.snapshot(of: tab),
          snapshot.window != nil, snapshot.window == engineWindow else { return }
    guard !isWindowCloseRequested else {
      engine.closeTab(tab, mode: .skipUnloadHandlers)
      return
    }
    if peek.adoptOpenedTab(snapshot) { return }
    addTodayRow(for: tab, snapshot: snapshot)
    if let node = nodeByTab[tab], let engineWindow, engine.latestActiveTab(in: engineWindow) == tab {
      activate(node: node)
    }
  }

  private func addTodayRow(for tab: TabID, snapshot: TabSnapshot) {
    let url = snapshot.url ?? Self.blankPage
    let title = snapshot.title.isEmpty ? (url.host() ?? url.absoluteString) : snapshot.title
    let node: NodeID
    do {
      guard let space = sidebarController.currentSpace ?? createFirstSpace() else {
        engine.closeTab(tab, mode: .skipUnloadHandlers)
        return
      }
      node = try sidebar.addTab(url: url, title: title, in: .today(space))
    } catch {
      onError?(.addTab, error)
      engine.closeTab(tab, mode: .skipUnloadHandlers)
      return
    }
    tabsByNode[node] = tab
    nodeByTab[tab] = node
    sidebarController.markLoaded(node: node)
    replay(snapshot, into: node)
    announceCreation(.tab)                                          // BH-006
  }

  /// The first Space, created for an engine tab on a first run (#327). Showing the new, still empty Space runs
  /// `showEmptySpace()`, which takes the engine's latest selection as acknowledged so a late report cannot leave a
  /// Space the user picked. Here nobody picked anything: the latest selection is this batch's own tab, whose
  /// `.activeTabChanged` is still queued, and it must show the page. The acknowledgement from before is kept.
  private func createFirstSpace() -> SpaceID? {
    let acknowledged = engineActiveTab
    defer { engineActiveTab = acknowledged }
    return createSpace()
  }

  /// The row of an engine tab whose first URL is not known yet; the tab's `.urlChanged` replaces it.
  // A constant literal that always parses.
  static let blankPage = URL(string: "about:blank")!

  /// Ignore the engine's next pick of an active tab other than the shell's, for `reactivationGrace`.
  func expectEngineReactivation() {
    expectsEngineReactivation = true
    reactivationGeneration += 1
    let generation = reactivationGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.reactivationGrace) { [weak self] in
      guard let self, self.reactivationGeneration == generation else { return }
      self.expectsEngineReactivation = false
    }
  }

  /// How long after its active tab closed an engine activation is taken for the engine's own pick. [I]
  static let reactivationGrace: TimeInterval = 1

  /// Remember the request before calling: events can arrive synchronously. Always forward, even when a cached
  /// selection agrees; the native selection may already differ and activation also carries focus semantics.
  func activateEngineTab(_ tab: TabID) {
    engineActiveTab = tab
    engine.activateTab(tab)
  }

  /// The engine made `tab` its active tab. The shell follows (an extension's `chrome.tabs.update`, an engine tab
  /// opened in the foreground), except for the engine's own pick after the current tab closed: the shell has chosen
  /// the successor, and the engine is told again.
  func engineDidActivate(_ tab: TabID, node: NodeID) {
    guard let engineWindow, engine.latestActiveTab(in: engineWindow) == tab else { return }
    if tab == engineActiveTab {
      // An in-process engine can still report its automatic successor after this acknowledgement in the same
      // delivery. Retire the expectation after delivery, rather than swallowing a later activation for a full grace
      // period. Duplicate reports must not reopen a page after the user selected an empty Space.
      if expectsEngineReactivation {
        let generation = reactivationGeneration
        DispatchQueue.main.async { [weak self] in
          guard let self, self.reactivationGeneration == generation, self.engineActiveTab == tab else { return }
          self.expectsEngineReactivation = false
        }
      }
      return
    }
    engineActiveTab = tab
    if expectsEngineReactivation {
      expectsEngineReactivation = false
      if let currentTab { activateEngineTab(currentTab) }
      return
    }
    activate(node: node)
  }

  // MARK: Held closes (Decision 11)

  /// Rows whose close the engine holds behind a leave-site prompt show their closing state.
  func markHeldCloses(_ tabs: [TabID]) {
    for tab in tabs {
      guard let node = nodeByTab[tab], engine.snapshot(of: tab)?.isClosing == true else { continue }
      sidebarController.setClosing(node, true)
    }
    // An unheld close of the current tab has run the engine's reactivation already when `closeTab` returns
    // (in-process engines); nothing more will come.
    if expectsEngineReactivation, let engineWindow, let engineActiveTab,
       engine.latestActiveTab(in: engineWindow) == engineActiveTab {
      expectsEngineReactivation = false
    }
  }

  /// The user stayed on the page: the tab stays, and the archive that waited for it is dropped. A tab whose row was
  /// removed while the prompt was up (Delete Space, an import merge) closes now without a prompt, so no live tab is
  /// left without a row.
  func closeWasCancelled(_ tab: TabID, node: NodeID) {
    isWindowCloseRequested = false
    stampsShownTabsOnWindowClose = false                  // the tabs stayed visible: nothing to stamp
    sidebarController.setClosing(node, false)
    forgetClose(of: node)                                           // nothing to reopen (#346)
    for (target, pending) in pendingArchives where pending.tabs.contains(tab) {
      pendingArchives[target] = nil
      for other in pending.tabs { if let node = nodeByTab[other] { sidebarController.setClosing(node, false) } }
    }
    if sidebar.node(node) == nil { engine.closeTab(tab, mode: .skipUnloadHandlers) }
  }

  /// One page of a pending archive closed; the node is archived after its last one. False when no archive waited
  /// for `tab`.
  func pendingArchiveTabClosed(_ tab: TabID) -> Bool {
    guard let target = pendingArchives.first(where: { $0.value.tabs.contains(tab) })?.key,
          var pending = pendingArchives[target] else { return false }
    pending.tabs.remove(tab)
    guard pending.tabs.isEmpty else {
      pendingArchives[target] = pending
      return true
    }
    pendingArchives[target] = nil
    if sidebar.node(target) != nil {                 // gone: nothing to archive
      archive(target, heldCurrent: pending.heldCurrent && pending.space == currentSpace)
    }
    return true
  }

  /// Nodes auto-archive must skip this pass (Decision 11): a tab whose close would be held by a leave-site prompt, or
  /// is held now, and the split it is a pane of. The next pass tries again.
  public var nodesHoldingClose: Set<NodeID> {
    var result: Set<NodeID> = []
    for (node, tab) in tabsByNode {
      guard let snapshot = engine.snapshot(of: tab), snapshot.wouldHoldClose || snapshot.isClosing else { continue }
      result.insert(node)
      if case .split(let split)? = sidebar.parent(of: node) { result.insert(split) }
    }
    return result
  }

  // MARK: Commands (Decision 9)

  /// The commands the shell implements (week-3 results, W3-8 step 3): New Tab opens the command bar, Close Tab
  /// archives or closes the current tab, New Window opens a shell window, Close Window asks the engine through the
  /// close button's path. Every other command is the engine's.
  func claim(_ command: EngineCommand) -> CommandClaim? {
    switch command {
    case .newTab: CommandClaim(isEnabled: true)
    case .closeTab: CommandClaim(isEnabled: currentNode != nil)
    case PendingEngineCommands.newWindow: CommandClaim(isEnabled: onNewWindow != nil)
    case .closeWindow: CommandClaim(isEnabled: window != nil)
    case .find, .findNext, .findPrevious: claimFind(command)         // #134
    case .downloads, .history:                                         // #132: the native Library
      onShowLibrary.map { _ in CommandClaim(isEnabled: true) }
    default: nil
    }
  }

  func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool {
    switch command {
    case .newTab:
      newTab(nil)
      return true
    case .closeTab:
      closeTab(nil)
      return true
    case PendingEngineCommands.newWindow:
      guard let onNewWindow else { return false }
      onNewWindow()
      return true
    case .closeWindow:
      guard let window else { return false }
      window.performClose(nil)                            // windowShouldClose: the engine decides
      return true
    case .find, .findNext, .findPrevious:
      return performFind(command)
    case .downloads, .history:
      guard let onShowLibrary else { return false }
      onShowLibrary(command == .downloads ? .downloads : .history)
      return true
    default:
      return false
    }
  }

  // MARK: Extensions (Decision 10)

  /// The Extensions control, only for an engine that runs extensions.
  func wireExtensions() {
    guard engine is any EngineExtensions else { return }
    let button = ExtensionsButton()
    button.onRun = { [weak self] id in self?.runExtensionAction(id) }
    extensionsButton = button
    sidebarController.view.extensionsButton = button
    refreshExtensions()
  }

  /// The window's actions; none before the engine window exists or after it closed.
  func refreshExtensions() {
    guard let button = extensionsButton, let extensions = engine as? any EngineExtensions else { return }
    button.actions = engineWindow.map { extensions.extensionActions(in: $0) } ?? []
  }

  private func runExtensionAction(_ id: String) {
    guard let engineWindow, let button = extensionsButton,
          let extensions = engine as? any EngineExtensions else { return }
    extensions.runExtensionAction(id, in: engineWindow, anchor: button)
  }
}
