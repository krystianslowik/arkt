import AppKit
import EngineAPI

/// A sidebar mutation the window asked for; `ShellWindowController.onError` reports which one failed.
public enum SidebarMutation: Hashable, Sendable {
  case addTab
  case addSpace
  /// A pane was added to a split, or a split created (`SidebarSource.addToSplit`).
  case addPane
  /// Any other split write: separate, expand, reorder, widths, orientation, duplicate.
  case editSplit
}

/// Owns the shell window and wires it to the engine. Grows through C3-C6.
@MainActor
public final class ShellWindowController: NSWindowController, NSWindowDelegate {
  public let engine: any EngineClient
  public let rootView: ShellRootView
  public let sidebar: any SidebarSource
  public let sidebarController: SidebarController
  public let commandBar: CommandBarController
  /// Non-blocking notices over the bottom of the content card.
  public let toasts: ToastPresenter
  /// Shown in the content card while this window's profile has no Space (decision 3).
  let emptyState = EmptyStateView(frame: .zero)
  /// Arc's sidebar file exists (existence check only); shows "Import from Arc" in the empty state.
  public var isArcImportAvailable = false { didSet { emptyState.showsImport = isArcImportAvailable } }
  /// "Import from Arc" in the empty state.
  public var onImportFromArc: (@MainActor () -> Void)?
  /// "New Space" in the empty state. Default: creates a Space named `newSpaceTitle`.
  public var onNewSpace: (@MainActor () -> Void)?
  /// Name of a Space created by "New Space" or by Cmd-T with no Space.
  public static let newSpaceTitle = "Space"               // [I] product wording, see open questions
  public var isShowingEmptyState: Bool { sidebarController.spaces.isEmpty }
  private var commandBarPrewarmed = false
  /// The focused tab: the shown plain tab, or the focused pane of a shown split (decision 7).
  public internal(set) var currentTab: TabID?
  /// The engine reported a favicon for a sidebar node (nil: cleared); the app persists it. Called for favicons
  /// caught up from the snapshot when a tab is created and for later `.faviconChanged` events.
  public var onFaviconChanged: (@MainActor (NodeID, Data?) -> Void)?
  /// A sidebar mutation failed (for example `addTab` into a location the model refuses). Default: a toast whose
  /// text names the failed mutation (`errorText(for:error:)`).
  public var onError: (@MainActor (SidebarMutation, any Error) -> Void)?
  /// Engine tabs are created lazily, when a sidebar node is first shown (`openEngineTab(for:)`).
  private(set) var tabsByNode: [NodeID: TabID] = [:]
  private var nodeByTab: [TabID: NodeID] = [:]
  private var observation: EngineObservation?
  /// Closes the engine tabs of nodes that left the sidebar, whatever removed them.
  private var sidebarObservation: SidebarObservation?
  /// Today items to archive (the app's ArchiveCoordinator); Cmd-W on a Today tab calls it. Nil: Cmd-W on a Today tab
  /// does nothing.
  public var onArchive: (@MainActor ([NodeID]) -> Void)?
  /// A tab stopped being visible in this window: another tab became current, or the window closed (decision 10; the
  /// app stamps `lastActiveAt`).
  public var onTabHidden: (@MainActor (NodeID) -> Void)?
  /// The tabs this window shows: the current one, every pane with a page of a shown split, or none.
  public var visibleNodes: Set<NodeID> { Set(shownNodes) }
  /// `visibleNodes` in pane order; changed only through `setShown(_:)` and `.tabClosed`.
  private var shownNodes: [NodeID] = []
  var currentNode: NodeID? { currentTab.flatMap { nodeByTab[$0] } }
  /// Split View window state (S4): the shown split, last focused and closed panes. Window lifetime, not persisted.
  var splitState = SplitWindowState()
  /// Toolbar on or off (KB-018, BH-032). The app passes one backed by user defaults; the default is ephemeral.
  public let toolbarSetting: ToolbarSetting

  /// `toolbarSetting` defaults to an in-memory setting so windows built without one (tests, the smoke) never
  /// write user defaults.
  public init(engine: any EngineClient, sidebar: any SidebarSource,
              metrics: ShellMetrics = .standard, toolbarSetting: ToolbarSetting = .ephemeral()) {
    let window = ShellWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800))
    // Symbol bitmaps at the shell window's scale, before the first row or button draws. A later scale change
    // re-renders the views' glyphs (viewDidChangeBackingProperties) and prewarms again below.
    SymbolImageCache.shared.prewarm(scale: window.backingScaleFactor)
    self.engine = engine
    self.sidebar = sidebar
    let sidebarController = SidebarController(source: sidebar, topBarHeight: metrics.sidebarTopBarHeight)
    self.sidebarController = sidebarController
    window.metrics = metrics
    let root = ShellRootView(metrics: metrics, sidebar: sidebarController.view)
    self.rootView = root
    self.commandBar = CommandBarController(parent: window)
    self.toasts = ToastPresenter()
    self.toolbarSetting = toolbarSetting
    super.init(window: window)
    let toastView = ToastView(frame: .zero)
    toastView.presenter = toasts
    root.card.toastView = toastView
    toasts.view = toastView
    onError = { [weak self] mutation, error in
      self?.toasts.show(Toast(text: Self.errorText(for: mutation, error: error)))
    }
    onNewSpace = { [weak self] in self?.createSpace() }
    emptyState.onNewSpace = { [weak self] in self?.onNewSpace?() }
    emptyState.onImport = { [weak self] in self?.onImportFromArc?() }
    window.contentView = root
    window.delegate = self
    sidebarController.onActivate = { [weak self] node in self?.show(node: node) }
    sidebarController.onClose = { [weak self] node in self?.close(node: node) }       // hover X (GS-043)
    sidebarController.onNewTab = { [weak self] in self?.commandBar.toggle(.newTab) }      // sidebar "+" = Cmd-T
    commandBar.onOpen = { [weak self] url, target in
      switch target {
      case .currentTab, .newTab: self?.open(url, inNewTab: target == .newTab)
      case .newSplitPane: self?.openInNewSplitPane(url)                                 // KB-070, BH-117
      }
    }
    commandBar.onReload = { [weak self] in                                                // KB-004, BH-102
      guard let self, let tab = self.currentTab else { return }
      self.engine.reload(tab)
    }
    commandBar.onSwitch = { [weak self] node in self?.activate(node: node) }
    commandBar.openTabsProvider = { [weak self] in self?.openTabs() ?? [] }
    wireAddressBars()
    wireSplit()
    observation = engine.observe { [weak self] event in self?.handle(event) }
    // A removed Space's nodes emit no structure change, so `.spaceRemoved` checks too.
    sidebarObservation = sidebar.observe { [weak self] change in
      switch change {
      case .structure, .spaceRemoved: self?.closeEngineTabsOfRemovedNodes()
      case .node, .spaceAdded, .spaceMoved, .spaceChanged: break
      }
      self?.splitSourceDidChange(change)
    }
    // Space theme: the pager's continuous position drives the crossfade (design section 2).
    sidebarController.onSpacePosition = { [weak self, weak root] position in
      root?.themeBackground.setPosition(position)
      self?.refreshToastFlavor()
    }
    sidebarController.onSpacesChanged = { [weak self] _ in
      self?.refreshThemes()
      self?.updateEmptyState()
    }
    refreshThemes()
    updateEmptyState()
    root.themeBackground.setPosition(sidebarController.view.pager.position)
    // Open with the first tab of the first Space so the card shows a real page.
    if let space = sidebarController.currentSpace, let first = sidebarController.tabToRestore(in: space) {
      sidebarController.activate(node: first)
    }
    reapplyTrafficLights()
  }

  public func activate(node: NodeID) { sidebarController.activate(node: node) }
  /// The sidebar URL bar (BH-031, GS-042).
  public var urlBar: URLBarView { sidebarController.view.urlBar }
  public var pager: SpacePagerView { sidebarController.view.pager }
  public var themeBackground: ThemeBackgroundView { rootView.themeBackground }
  public var currentSpace: SpaceID? { sidebarController.currentSpace }

  private func refreshThemes() {
    // One theme per paged Space, so theme index == page index even if a Space lookup fails.
    rootView.themeBackground.themes = sidebarController.spaces.map {
      sidebar.space($0)?.theme ?? SpaceThemeInfo(baseColors: [.white(1)], isDark: false)
    }
    refreshToastFlavor()
  }

  /// Toasts follow the flavor of the Space the pager is nearest to.
  private func refreshToastFlavor() {
    let themes = rootView.themeBackground.themes
    guard !themes.isEmpty else { return }
    let index = min(max(Int(pager.position.rounded()), 0), themes.count - 1)
    toasts.view?.flavor = themes[index].flavor
  }

  /// The default error toast's text for a failed `mutation`. A full split says "Cannot Add New Pane" (BH-116).
  public static func errorText(for mutation: SidebarMutation, error: any Error) -> String {
    switch mutation {
    case .addTab: "Couldn't add the tab."
    case .addSpace: "Couldn't create a Space."
    case .addPane, .editSplit:
      // Arc's toast for a full split; the generic text is [I].
      error as? SplitEditError == .splitFull ? "Cannot Add New Pane" : "Couldn't change the Split View."
    }
  }

  // MARK: Spaces

  /// Creates a Space named `newSpaceTitle`; it becomes current through `.spaceAdded`. Reports a failure via `onError`.
  @discardableResult
  func createSpace() -> SpaceID? {
    do { return try sidebar.addSpace(title: Self.newSpaceTitle) } catch { onError?(.addSpace, error); return nil }
  }

  private func updateEmptyState() {
    rootView.card.setEmptyState(isShowingEmptyState ? emptyState : nil)
  }

  /// Cmd-Opt-Right (KB-033).
  @objc public func nextSpace(_ sender: Any?) { sidebarController.nextSpace() }
  /// Cmd-Opt-Left (KB-034).
  @objc public func previousSpace(_ sender: Any?) { sidebarController.previousSpace() }
  /// Ctrl-1 ... Ctrl-9 (KB-035, BH-041): the menu item's tag is the zero-based Space index.
  @objc public func goToSpace(_ sender: Any?) {
    guard let tag = (sender as? NSMenuItem)?.tag else { return }
    sidebarController.goToSpace(at: tag)
  }
  public func rowState(for node: NodeID) -> TabRowState { sidebarController.rowState(for: node) }

  // MARK: URL bar and Toolbar

  public var isToolbarVisible: Bool { toolbarSetting.isVisible }

  /// Cmd-Shift-D (KB-018, BH-032), the View menu and the URL bars' context menu (BH-031, GS-042).
  /// Every window sharing the setting, this one included, applies the change as an observer.
  @objc public func toggleToolbar(_ sender: Any?) {
    toolbarSetting.isVisible.toggle()
  }

  private func applyToolbarVisibility() {
    let visible = toolbarSetting.isVisible
    rootView.card.showsToolbar = visible
    sidebarController.view.showsURLBar = !visible   // Arc hides the sidebar URL bar while the Toolbar is on
    urlBar.isToolbarVisible = visible
    rootView.card.toolbar.urlBar.isToolbarVisible = visible
    configurePaneToolbars()
  }

  private func wireAddressBars() {
    let toolbar = rootView.card.toolbar
    for bar in [urlBar, toolbar.urlBar] {
      bar.onPress = { [weak self] in self?.openLocation(nil) }                        // same as Cmd-L, KB-002
      bar.onToggleToolbar = { [weak self] in self?.toggleToolbar(nil) }
    }
    toolbar.onBack = { [weak self] in
      guard let self, let tab = self.toolbarTab else { return }
      self.engine.goBack(tab)
    }
    toolbar.onForward = { [weak self] in
      guard let self, let tab = self.toolbarTab else { return }
      self.engine.goForward(tab)
    }
    toolbar.onReload = { [weak self] in
      guard let self, let tab = self.toolbarTab else { return }
      self.engine.reload(tab)
    }
    toolbarSetting.addObserver(self)
    applyToolbarVisibility()
  }

  /// Both URL bars show the current tab's URL from the engine snapshot (nil: no tab shown). In a split that is the
  /// focused pane; each pane card's own Toolbar is refreshed by `configurePaneToolbars()`.
  func refreshAddress() {
    let url = currentTab.flatMap { engine.snapshot(of: $0)?.url }
    urlBar.url = url
    rootView.card.toolbar.urlBar.url = url
    refreshToolbarHistory()
  }

  /// The tab the Toolbar's Back, Forward and Reload act on and show the history of: the current tab, which in a split
  /// is the focused pane, so the history follows the same tab as `refreshAddress()`'s URL (#79). A pane card's own
  /// Toolbar acts on its own pane (`configurePaneToolbars()`).
  private var toolbarTab: TabID? { currentTab }

  /// Back and Forward follow `toolbarTab`'s `canGoBack` / `canGoForward` (engine contract rule 8).
  private func refreshToolbarHistory() {
    let snapshot = toolbarTab.flatMap { engine.snapshot(of: $0) }
    rootView.card.toolbar.setHistory(canGoBack: snapshot?.canGoBack ?? false,
                                     canGoForward: snapshot?.canGoForward ?? false)
  }

  // MARK: Close tab

  /// Cmd-W (KB-008). A Today tab is archived (BH-071) and the nearest sibling below, else above, becomes current; with
  /// none left the card stays empty and the window open (BH-073). A pane archives alone and its split shrinks (user
  /// decision 4, PARITY(NEEDS-RUNTIME-CHECK BH-123)). A pinned tab or Favorite closes its page and keeps its row
  /// (BH-067, BH-048 [I]). Without a current tab nothing happens (BH-069, a second Cmd-W unpinning, is
  /// NEEDS-RUNTIME-CHECK and not implemented).
  @objc public func closeTab(_ sender: Any?) {
    guard let node = currentNode else { return }
    close(node: node)
  }

  /// Closes a tab, pane or split the way Cmd-W closes the current tab; the hover X (GS-043) and the rows' VoiceOver
  /// action call it for every row except a pane row, whose X removes the pane from its split (BH-121). Today: archived (a split as one unit), and when it held the current tab the
  /// nearest sibling becomes current. Pinned and Favorites: the pages close and the rows stay. Folders are ignored.
  public func close(node: NodeID) {
    let tabs: [NodeID]
    switch sidebar.node(node) {
    case .tab?: tabs = [node]
    case .split?: tabs = sidebar.children(of: .split(node))
    case .folder?, nil: return
    }
    switch sidebar.section(containing: node) {
    case .today?:
      let holdsCurrent = currentNode.map(tabs.contains) ?? false
      let next = holdsCurrent ? successor(of: node) : nil   // resolved while the node is still in place
      onArchive?([node])
      guard sidebar.node(node) == nil else { return }
      if let next, sidebar.node(next) != nil { activate(node: next) }
    case .pinned?, .favorites?:
      for tab in tabs.compactMap({ tabsByNode[$0] }) {
        engine.closeTab(tab)                  // `.tabClosed` clears the card and the row state
      }
    default:
      return
    }
  }

  /// The tab to show after `node` leaves: the first tab of the nearest sibling below, else above. With no such sibling
  /// inside a split or folder, the container's siblings are tried; never another section.
  private func successor(of node: NodeID) -> NodeID? {
    var current = node
    for _ in 0..<64 {                       // depth guard against a malformed source
      guard let location = sidebar.parent(of: current) else { return nil }
      let siblings = sidebar.children(of: location)
      if let index = siblings.firstIndex(of: current) {
        let candidates = siblings[(index + 1)...] + siblings[..<index].reversed()
        if let tab = candidates.lazy.compactMap({ self.sidebar.firstTab(at: $0) }).first { return tab }
      }
      guard let container = location.containerNode else { return nil }
      current = container
    }
    return nil
  }

  /// Engine tabs of nodes the sidebar no longer holds are closed; `.tabClosed` then drops the mappings. Runs inside
  /// change delivery, so it must not mutate the sidebar (closing a tab does not).
  private func closeEngineTabsOfRemovedNodes() {
    for (node, tab) in tabsByNode where sidebar.node(node) == nil { engine.closeTab(tab) }
  }

  // MARK: Command bar

  /// Cmd-T (KB-001, BH-100); Cmd-T while open closes (KB-003, BH-103).
  @objc public func newTab(_ sender: Any?) { commandBar.toggle(.newTab) }
  /// Cmd-L prefilled with the current URL (KB-002, BH-101); Cmd-L while open closes (KB-003, BH-103).
  @objc public func openLocation(_ sender: Any?) {
    commandBar.toggle(.currentTab(currentTab.flatMap { engine.snapshot(of: $0)?.url }))
  }

  /// Cmd-T: new Today tab in the current Space (BH-100). Cmd-L: navigate the current tab (BH-101).
  func open(_ url: URL, inNewTab: Bool) {
    if inNewTab || currentTab == nil {
      // Cmd-T with no Space creates the Space first, then the tab (decision 3) [I].
      guard let space = sidebarController.currentSpace ?? createSpace() else { return }
      do {
        let node = try sidebar.addTab(url: url, title: url.host() ?? url.absoluteString, in: .today(space))
        activate(node: node)
      } catch {
        onError?(.addTab, error)
      }
    } else if let tab = currentTab {
      engine.navigate(tab, to: url)
    }
  }

  private func openTabs() -> [CommandBarResults.OpenTab] {
    guard let space = sidebarController.currentSpace else { return [] }
    return CommandBarResults.openTabs(in: sidebar, space: space)
  }

  /// Shows `node` in the content area: a pane shows its whole split (`showSplit`), anything else the single card.
  func show(node: NodeID) {
    if case .split(let split)? = sidebar.parent(of: node) {
      showSplit(split, focus: node)
      return
    }
    guard let tab = openEngineTab(for: node) else { return }
    hideSplit()
    currentTab = tab
    rootView.card.setContent(engine.contentView(for: tab))
    setShown([node])                                            // only once the card really switches
    refreshAddress()
  }

  /// The engine tab of `node`, created on first use. Every engine tab the window creates comes from here, so the
  /// sidebar's loaded state (Favorite X, #82) stays exact: created pages are marked loaded, and `.tabClosed` calls
  /// `deactivate(node:)` (#156 review).
  func openEngineTab(for node: NodeID) -> TabID? {
    if let existing = tabsByNode[node] { return existing }
    guard case .tab(_, let url, _)? = sidebar.node(node) else { return nil }
    let tab = engine.createTab(url: url)
    tabsByNode[node] = tab
    nodeByTab[tab] = node
    sidebarController.markLoaded(node: node)
    // Events emitted inside createTab arrived before the mapping existed; catch up from the snapshot.
    if let snapshot = engine.snapshot(of: tab) { replay(snapshot, into: node) }
    return tab
  }

  /// The engine tab already open for `node`, if any.
  func engineTab(of node: NodeID) -> TabID? { tabsByNode[node] }

  /// Records what the content area shows and reports the nodes that left it (decision 10). The sidebar draws the
  /// shown nodes other than the current one as `.contentVisible`.
  func setShown(_ nodes: [NodeID]) {
    let hidden = shownNodes.filter { !nodes.contains($0) }
    shownNodes = nodes
    sidebarController.visible = Set(nodes)
    for node in hidden { onTabHidden?(node) }
  }

  private func replay(_ snapshot: TabSnapshot, into node: NodeID) {
    guard case .tab(_, let url, let title)? = sidebar.node(node) else { return }
    let newURL = snapshot.url.flatMap { $0 == url ? nil : $0 }
    let newTitle = snapshot.title.isEmpty || snapshot.title == title ? nil : snapshot.title
    if newURL != nil || newTitle != nil { sidebar.updateTab(node, url: newURL, title: newTitle) }
    if let favicon = snapshot.faviconData { faviconChanged(favicon, for: node) }
  }

  private func faviconChanged(_ data: Data?, for node: NodeID) {
    sidebarController.setFavicon(data, for: node)
    onFaviconChanged?(node, data)
  }

  private func handle(_ event: EngineEvent) {
    guard let node = nodeByTab[event.tabID] else { return }
    switch event {
    case .titleChanged(_, let title) where !title.isEmpty:
      sidebar.updateTab(node, url: nil, title: title)
    case .urlChanged(let tab, let url):
      if let url { sidebar.updateTab(node, url: url, title: nil) }
      if tab == currentTab { refreshAddress() }
      refreshPaneToolbar(of: node)
    case .faviconChanged(_, let data):
      faviconChanged(data, for: node)
    case .historyChanged(let tab, _, _):
      if tab == toolbarTab { refreshToolbarHistory() }
      refreshPaneToolbar(of: node)
    case .tabClosed(let tab):
      tabsByNode[node] = nil
      nodeByTab[tab] = nil
      let wasCurrent = currentTab == tab
      shownNodes.removeAll { $0 == node }                     // a closed page is not hidden, it is gone
      sidebarController.visible.remove(node)
      if wasCurrent { currentTab = nil }
      if splitState.panes.contains(node) {
        sidebarController.deactivate(node: node)
        paneDidClose(node, wasFocused: wasCurrent)
      } else {
        if wasCurrent { rootView.card.setContent(nil); refreshAddress() }
        sidebarController.deactivate(node: node)
        hiddenPaneDidClose(node)
      }
    default:
      break
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func reapplyTrafficLights() {
    (window as? ShellWindow)?.layoutTrafficLights(sidebarWidth: rootView.effectiveSidebarWidth)
  }

  // AppKit resets the standard buttons on each of these.
  public func windowDidResize(_ notification: Notification) { reapplyTrafficLights() }
  public func windowDidEndLiveResize(_ notification: Notification) { reapplyTrafficLights() }
  public func windowWillExitFullScreen(_ notification: Notification) { reapplyTrafficLights() }
  public func windowDidExitFullScreen(_ notification: Notification) { reapplyTrafficLights() }
  public func windowDidBecomeKey(_ notification: Notification) {
    reapplyTrafficLights()
    if !commandBarPrewarmed { commandBarPrewarmed = true; commandBar.prewarm() }
  }
  public func windowDidResignKey(_ notification: Notification) { reapplyTrafficLights() }
  public func windowDidChangeBackingProperties(_ notification: Notification) {
    reapplyTrafficLights()
    if let scale = window?.backingScaleFactor { SymbolImageCache.shared.prewarm(scale: scale) }   // cache hits if warm
  }
  public func windowDidDeminiaturize(_ notification: Notification) { reapplyTrafficLights() }
  /// The shown tabs, every pane of a split, stop being visible (decision 10). The command bar's display link retains
  /// its controller; release it with the window.
  public func windowWillClose(_ notification: Notification) {
    for node in shownNodes { onTabHidden?(node) }
    removePaneMouseMonitor()
    commandBar.invalidate()
    pager.stopInteraction()        // a closed window's views keep their display links
  }
}

extension ShellWindowController: NSMenuItemValidation {
  /// Titles the Toggle Toolbar item for the current state (KB-018) and validates the Split View items (S5). Every
  /// other item stays enabled, as it was before this controller validated menu items.
  public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if let enabled = validateSplitMenuItem(menuItem) { return enabled }
    if menuItem.action == #selector(toggleToolbar(_:)) {
      menuItem.title = ToolbarSetting.menuTitle(isVisible: isToolbarVisible)
    }
    return true
  }
}

extension ShellWindowController: ToolbarSettingObserver {
  public func toolbarSettingDidChange(_ setting: ToolbarSetting) { applyToolbarVisibility() }
}
