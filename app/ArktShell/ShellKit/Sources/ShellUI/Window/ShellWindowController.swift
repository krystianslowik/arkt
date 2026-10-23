import AppKit
import EngineAPI

/// A sidebar mutation the window asked for; `ShellWindowController.onError` reports which one failed.
public enum SidebarMutation: Hashable, Sendable {
  case addTab
  case addSpace
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
  public private(set) var currentTab: TabID?
  /// The engine reported a favicon for a sidebar node (nil: cleared); the app persists it. Called for favicons
  /// caught up from the snapshot when a tab is created and for later `.faviconChanged` events.
  public var onFaviconChanged: (@MainActor (NodeID, Data?) -> Void)?
  /// A sidebar mutation failed (for example `addTab` into a location the model refuses). Default: a toast whose
  /// text names the failed mutation (`errorText(for:)`).
  public var onError: (@MainActor (SidebarMutation, any Error) -> Void)?
  /// Engine tabs are created lazily, on first activation of a sidebar node.
  private var tabsByNode: [NodeID: TabID] = [:]
  private var nodeByTab: [TabID: NodeID] = [:]
  private var observation: EngineObservation?

  public init(engine: any EngineClient, sidebar: any SidebarSource,
              metrics: ShellMetrics = .standard) {
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
    super.init(window: window)
    let toastView = ToastView(frame: .zero)
    toastView.presenter = toasts
    root.card.toastView = toastView
    toasts.view = toastView
    onError = { [weak self] mutation, _ in self?.toasts.show(Toast(text: Self.errorText(for: mutation))) }
    onNewSpace = { [weak self] in self?.createSpace() }
    emptyState.onNewSpace = { [weak self] in self?.onNewSpace?() }
    emptyState.onImport = { [weak self] in self?.onImportFromArc?() }
    window.contentView = root
    window.delegate = self
    sidebarController.onActivate = { [weak self] node in self?.show(node: node) }
    sidebarController.onNewTab = { [weak self] in self?.commandBar.toggle(.newTab) }      // sidebar "+" = Cmd-T
    commandBar.onOpen = { [weak self] url, inNewTab in self?.open(url, inNewTab: inNewTab) }
    commandBar.onReload = { [weak self] in                                                // KB-004, BH-102
      guard let self, let tab = self.currentTab else { return }
      self.engine.reload(tab)
    }
    commandBar.onSwitch = { [weak self] node in self?.activate(node: node) }
    commandBar.openTabsProvider = { [weak self] in self?.openTabs() ?? [] }
    observation = engine.observe { [weak self] event in self?.handle(event) }
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

  /// The default error toast's text for a failed `mutation`.
  public static func errorText(for mutation: SidebarMutation) -> String {
    switch mutation {
    case .addTab: "Couldn't add the tab."
    case .addSpace: "Couldn't create a Space."
    }
  }

  // MARK: Spaces

  /// Creates a Space named `newSpaceTitle`; it becomes current through `.spaces`. Reports a failure via `onError`.
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

  // MARK: Command bar

  /// Cmd-T (KB-001, BH-100); Cmd-T while open closes (KB-003, BH-103).
  @objc public func newTab(_ sender: Any?) { commandBar.toggle(.newTab) }
  /// Cmd-L prefilled with the current URL (KB-002, BH-101); Cmd-L while open closes (KB-003, BH-103).
  @objc public func openLocation(_ sender: Any?) {
    commandBar.toggle(.currentTab(currentTab.flatMap { engine.snapshot(of: $0)?.url }))
  }

  /// Cmd-T: new Today tab in the current Space (BH-100). Cmd-L: navigate the current tab (BH-101).
  private func open(_ url: URL, inNewTab: Bool) {
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

  private func show(node: NodeID) {
    let tab: TabID
    if let existing = tabsByNode[node] {
      tab = existing
    } else {
      guard case .tab(_, let url, _)? = sidebar.node(node) else { return }
      tab = engine.createTab(url: url)
      tabsByNode[node] = tab
      nodeByTab[tab] = node
      // Events emitted inside createTab arrived before the mapping existed; catch up from the snapshot.
      if let snapshot = engine.snapshot(of: tab) { replay(snapshot, into: node) }
    }
    currentTab = tab
    rootView.card.setContent(engine.contentView(for: tab))
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
    case .urlChanged(_, let url?):
      sidebar.updateTab(node, url: url, title: nil)
    case .faviconChanged(_, let data):
      faviconChanged(data, for: node)
    case .tabClosed(let tab):
      tabsByNode[node] = nil
      nodeByTab[tab] = nil
      if currentTab == tab { currentTab = nil; rootView.card.setContent(nil) }
      sidebarController.deactivate(node: node)
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
  /// The command bar's display link retains its controller; release it with the window.
  public func windowWillClose(_ notification: Notification) {
    commandBar.invalidate()
    pager.stopInteraction()        // a closed window's views keep their display links
  }
}
