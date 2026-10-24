import AppKit
import EngineAPI

/// A Today node archived once its pages have closed (week-3 Decision 11).
struct PendingArchive {
  /// The node's engine tabs that have not reported `.tabClosed` yet.
  var tabs: Set<TabID>
  /// The node held the current tab when the close was asked for; its successor becomes current afterwards.
  let heldCurrent: Bool
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
    case .windowClosed:
      // Its tabs reported `.tabClosed(reason: .windowClosing)` already (contract rule 11).
      engineWindow = nil
      engineActiveTab = nil
      tabObservation = nil
      windowObservation = nil
      pendingArchives = [:]
      expectsEngineReactivation = false
      refreshExtensions()
      window?.close()
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
    let url = snapshot.url ?? Self.blankPage
    let title = snapshot.title.isEmpty ? (url.host() ?? url.absoluteString) : snapshot.title
    let node: NodeID
    do {
      guard let space = sidebarController.currentSpace ?? createSpace() else {
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
  }

  /// The row of an engine tab whose first URL is not known yet; the tab's `.urlChanged` replaces it.
  // A constant literal that always parses.
  static let blankPage = URL(string: "about:blank")!

  /// The engine made `tab` its active tab. The shell follows (an extension's `chrome.tabs.update`, an engine tab
  /// opened in the foreground), except for the engine's own pick after the current tab closed: the shell has chosen
  /// the successor, and the engine is told again.
  func engineDidActivate(_ tab: TabID, node: NodeID) {
    engineActiveTab = tab
    guard tab != currentTab else { return }
    if expectsEngineReactivation {
      expectsEngineReactivation = false
      if let currentTab { engine.activateTab(currentTab) }
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
       engine.activeTab(in: engineWindow) == engineActiveTab {
      expectsEngineReactivation = false
    }
  }

  /// The user stayed on the page: the tab stays, and the archive that waited for it is dropped.
  func closeWasCancelled(_ tab: TabID, node: NodeID) {
    sidebarController.setClosing(node, false)
    for (target, pending) in pendingArchives where pending.tabs.contains(tab) {
      pendingArchives[target] = nil
      for other in pending.tabs { if let node = nodeByTab[other] { sidebarController.setClosing(node, false) } }
    }
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
    archive(target, heldCurrent: pending.heldCurrent)
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

  /// The commands the shell implements: New Tab opens the command bar, Close Tab archives or closes the current tab.
  /// The rest of the W3-8 table joins with the menu (part D).
  func claim(_ command: EngineCommand) -> CommandClaim? {
    switch command {
    case .newTab: CommandClaim(isEnabled: true)
    case .closeTab: CommandClaim(isEnabled: currentNode != nil)
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
