import AppKit
import EngineAPI

/// A sidebar mutation the window asked for; `ShellWindowController.onError` reports which one failed.
public enum SidebarMutation: Hashable, Sendable {
  case addTab
  case addSpace
  /// A node moved between sections (BH-047: to Favorites, or a Favorite back to Pinned).
  case moveNode
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
  /// "New Space" in the empty state. Default: `newSpace(_:)` ("Space N" after the current Space, title open).
  public var onNewSpace: (@MainActor () -> Void)?
  /// Base of the "Space N" name given to a Space created by New Space or by Cmd-T with no Space (decision on #106).
  public static let newSpaceTitle = "Space"
  public var isShowingEmptyState: Bool { sidebarController.spaces.isEmpty }
  private var commandBarPrewarmed = false
  /// The focused tab: the shown plain tab, or the focused pane of a shown split (decision 7). The engine's active tab
  /// of this window follows it (week-3 Decision 6: extension `active` flags stay true).
  public internal(set) var currentTab: TabID? {
    didSet {
      guard let tab = currentTab, tab != oldValue else { return }
      activateEngineTab(tab)
      if let node = nodeByTab[tab] { tabSwitcher.noteViewed(node) }      // the recent-tab list (#103)
      saveSession()                                                      // #116
    }
  }
  /// What the engine sees of this window: the window, the card, the command and close seams.
  public let engineHost: ShellEngineHost
  /// The engine window this shell window hosts: created on the first tab (week-3 decision 4) or adopted from a host
  /// provider (`adopt(engineWindow:)`); nil again once the engine reports it closed.
  public internal(set) var engineWindow: EngineWindowID?
  /// Events of this window's tabs (`observe(window:)`) and of the window itself.
  var tabObservation: EngineObservation?
  var windowObservation: EngineObservation?
  /// Archives waiting for their tabs to close (week-3 Decision 11): the node to archive, the tabs still open, and
  /// whether it held the current tab when Cmd-W was pressed.
  var pendingArchives: [NodeID: PendingArchive] = [:]
  /// The last requested or accepted engine selection, also captured when an empty Space supersedes queued events.
  var engineActiveTab: TabID?
  /// The engine's active tab closed while the window still had tabs: the engine's own pick of the next active tab is
  /// not followed (the shell picks the successor), it is answered with the shell's current tab. In-process engines
  /// report their pick after the shell's own activation, Chromium one task later, and none when the pick is already
  /// the active tab, so the expectation also lapses after `reactivationGrace` (`expectEngineReactivation()`).
  var expectsEngineReactivation = false
  var reactivationGeneration = 0
  /// A close was requested for the whole window and is held behind a prompt: tabs the engine opens in it meanwhile get
  /// no row (they would outlive the window in the sidebar).
  var isWindowCloseRequested = false
  /// The close button asked the engine to close the window and the shown tabs are not stamped yet: they are stamped
  /// when the first page actually closes (`.tabClosed(reason: .windowClosing)`), so a close the user cancels at a
  /// leave-site prompt stamps nothing (decision 10; PR #274 review).
  var stampsShownTabsOnWindowClose = false
  /// The window closed. A closed controller is not shown again (its command bar and pager released their display
  /// links); the app builds a new window instead (#241: Dock reopen).
  public private(set) var isClosed = false
  /// Shown in the sidebar when the engine runs extensions (`EngineExtensions`).
  public internal(set) var extensionsButton: ExtensionsButton?
  /// The engine reported a favicon for a sidebar node (nil: cleared); the app persists it. Called for favicons
  /// caught up from the snapshot when a tab is created and for later `.faviconChanged` events.
  public var onFaviconChanged: (@MainActor (NodeID, Data?) -> Void)?
  /// A sidebar mutation failed (for example `addTab` into a location the model refuses). Default: a toast whose
  /// text names the failed mutation (`errorText(for:error:)`).
  public var onError: (@MainActor (SidebarMutation, any Error) -> Void)?
  /// Asks the other windows of the set for a row's live page (Tab Handoff, #300); set by `ShellWindowSet`. Nil: a
  /// window on its own, which always loads the page.
  var onTakeOverLiveTab: (@MainActor (NodeID) -> LiveTabHandoff)?
  /// The placeholder shown where a page moved to another window (#300); made on the first handoff.
  var handoffPlaceholder: HandoffPlaceholderView?
  /// This window let go of its last page: it moved to another window (#300), or it closed (#386; Chromium closes a
  /// `Browser` with its last tab). The engine may close the emptied engine window; when it reports that close as
  /// `.lastTabClosed`, this window stays open without one, and the next page it shows makes a new one (#401).
  var keepsWindowWithoutEngine = false
  /// The current row whose page went with an engine window this window keeps going without (#386): a page opened in
  /// the closing window, such as the sibling a Cmd-W makes current. It is shown again once that window has closed.
  var nodeToReshow: NodeID?
  /// Engine tabs are created lazily, when a sidebar node is first shown (`openEngineTab(for:)`).
  var tabsByNode: [NodeID: TabID] = [:]
  var nodeByTab: [TabID: NodeID] = [:]
  /// Where Copy Link writes and Paste URL as New Tab reads (#105); tests use a private pasteboard.
  var linkPasteboard: NSPasteboard = .general
  /// Closes the engine tabs of nodes that left the sidebar, whatever removed them.
  private var sidebarObservation: SidebarObservation?
  /// The window's appearance and Increase Contrast, for the Space themes (#410).
  var themeContextObserver: ThemeContextObserver?
  /// A tab dragged out of the sidebar over no window (GS-013): the window set opens a window at the screen point and
  /// shows the tab there, taking its page over (#300). Nil: the drag-out does nothing.
  var onDragOutToNewWindow: (@MainActor (NodeID, NSPoint) -> Void)?
  /// New Window (Cmd-N, `IDC_NEW_WINDOW`): set by the window set that owns this window. Nil: New Window is disabled.
  public var onNewWindow: (@MainActor () -> Void)?
  /// Today items to archive (the app's ArchiveCoordinator); Cmd-W on a Today tab calls it. Nil: Cmd-W on a Today tab
  /// does nothing.
  public var onArchive: (@MainActor ([NodeID]) -> Void)?
  /// Puts a Today row the user closed back from the Archive (the app's ArchiveCoordinator) and returns its node, for
  /// Reopen Closed Tab (#110, BH-074). Nil, or nil returned: the row stays in the Archive.
  public var onReopenArchived: (@MainActor (NodeID) -> NodeID?)?
  /// Closed tabs and Peeks, most recent on top (#346, #110); see `ShellWindowController+Reopen.swift`.
  var reopenStack = ReopenStack()
  /// Unloaded copies of closed pages that the stack holds (or is about to): tabs without a row that never show.
  var parkedTabs: Set<TabID> = []
  /// The reopen batch the visible undo toast belongs to; nil without one.
  var undoToastBatch: UUID?
  /// The Delete Space sheet while it is up.
  var spaceRemovalSheet: DialogSheet?
  /// Removes a Space (the app's ArchiveCoordinator: its pinned and Today items are archived, decision on #86); Delete
  /// Space calls it once `confirmSpaceRemoval` said yes. Nil: Delete Space is disabled.
  public var onRemoveSpace: (@MainActor (SpaceID) -> Void)?
  /// Asks before Delete Space removes a Space and calls back with the answer. Default: an alert sheet on the window.
  public var confirmSpaceRemoval: (@MainActor (SpaceRemovalPrompt, @escaping @MainActor (Bool) -> Void) -> Void)?
  /// A tab stopped being visible in this window: another tab became current, or the window closed (decision 10; the
  /// app stamps `lastActiveAt`).
  public var onTabHidden: (@MainActor (NodeID) -> Void)?
  /// The tabs the other windows of the set show, so Clear Today Tabs leaves them (#429). Set by the window set; nil
  /// (a lone window) reads as none.
  var otherWindowsVisibleNodes: (@MainActor () -> Set<NodeID>)?
  /// The tabs this window shows: the current one, every pane with a page of a shown split, or none.
  public var visibleNodes: Set<NodeID> { Set(shownNodes) }
  /// `visibleNodes` in pane order; changed only through `setShown(_:)` and `.tabClosed`.
  private(set) var shownNodes: [NodeID] = []
  var currentNode: NodeID? { currentTab.flatMap { nodeByTab[$0] } }
  /// Split View window state (S4): the shown split, last focused and closed panes. Window lifetime, not persisted.
  var splitState = SplitWindowState()
  /// Toolbar on or off (KB-018, BH-032). The app passes one backed by user defaults; the default is ephemeral.
  public let toolbarSetting: ToolbarSetting
  /// The first run (or Help > Welcome to Arkt) while it covers this window (`presentOnboarding`).
  public internal(set) var onboarding: OnboardingController?
  /// Peek (#313): link activations, the Peek over the source tab and its closes, Open as Tab and Add to Split View.
  public private(set) lazy var peek = PeekController(shell: self)
  /// A page's `alert()`, `confirm()` and `prompt()` as panels over the page (#400); see `+JavaScriptDialogs`.
  private(set) lazy var javaScriptDialogs = makeJavaScriptDialogPresenter()
  /// A site's camera, microphone, location or notifications request as a panel over the page (#400); see
  /// `+Permissions`.
  private(set) lazy var permissionPrompts = makePermissionPresenter()
  /// A tab's infobars as a strip at the top of its page (#400); see `+Infobars`.
  private(set) lazy var infobarStrips = makeInfobarPresenter()
  private(set) lazy var statusPill = makeStatusPillPresenter()
  /// The Ctrl-Tab switcher and this window's recent-tab list (#103).
  public let tabSwitcher = TabSwitcherController()
  /// Where the copy-link actions (#118) read and write; the app uses the general pasteboard, tests replace it.
  var pasteboard: NSPasteboard = .general
  /// Where the sidebar width and hidden state are saved on change (#331).
  let sidebarStateStore: SidebarWindowStateStore
  /// False for a window that is not the one a relaunch restores: its changes must not overwrite the saved state.
  var savesSidebarState = true
  /// Where the window's session (frame, Space, tabs) is saved on change (#116).
  let sessionStore: WindowSessionStore
  /// False for a window that is not the one a relaunch restores, and while a quit has written the final state.
  var savesSession = false
  /// The window's frame when it last entered full screen, saved in place of the screen-sized frame (#116).
  var frameBeforeFullScreen: CGRect?
  /// Scrolls the sidebar to a row a keyboard command landed on, with the overflow pill (BH-018).
  public let sidebarReveal = SidebarRevealer()
  /// How Cmd-1 ... Cmd-9 count (BH-014, BH-015). Defaults until the Settings window exists.
  public var tabNavigationSettings = TabNavigationSettings()

  /// `toolbarSetting` defaults to an in-memory setting so windows built without one (tests, the smoke) never
  /// write user defaults. `opensFirstTab` shows the first tab of the first Space at once, which creates the engine
  /// window; a window built by an engine host provider passes false, as a provider must not call the engine, and
  /// gets its window through `adopt(engineWindow:)`.
  public init(engine: any EngineClient, sidebar: any SidebarSource,
              metrics: ShellMetrics = .standard, toolbarSetting: ToolbarSetting = .ephemeral(),
              sidebarStateStore: SidebarWindowStateStore = .ephemeral(), sessionStore: WindowSessionStore = .ephemeral(),
              restoring session: WindowSessionState? = nil, savesSession: Bool = true,
              opensFirstTab: Bool = true) {
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
    self.sidebarStateStore = sidebarStateStore
    self.sessionStore = sessionStore
    self.engineHost = ShellEngineHost(window: window, cardView: root.card)
    super.init(window: window)
    root.onSidebarStateChange = { [weak self] in self?.saveSidebarState() }
    root.onLayout = { [weak self] in
      self?.javaScriptDialogs.layoutDidFinish()                                      // #400
      self?.permissionPrompts.layoutDidFinish()
      self?.infobarStrips.layoutDidFinish()
    }
    engineHost.controller = self
    window.commandHost = engineHost
    let toastView = ToastView(frame: .zero)
    toastView.presenter = toasts
    root.card.toastView = toastView
    toasts.view = toastView
    onError = { [weak self] mutation, error in
      self?.toasts.show(Toast(text: Self.errorText(for: mutation, error: error), kind: .error))
    }
    onNewSpace = { [weak self] in self?.newSpace(nil) }
    wireSpaceEntryPoints()
    confirmSpaceRemoval = { [weak self] prompt, answer in self?.presentSpaceRemovalSheet(prompt, answer: answer) }
    emptyState.onNewSpace = { [weak self] in self?.onNewSpace?() }
    emptyState.onImport = { [weak self] in self?.onImportFromArc?() }
    window.contentView = root
    window.delegate = self
    sidebarController.onActivate = { [weak self] node in self?.show(node: node) }
    sidebarController.onEmptySpace = { [weak self] in self?.showEmptySpace() }
    sidebarController.onClose = { [weak self] node in self?.close(node: node) }       // hover X (GS-043)
    sidebarController.onNewTab = { [weak self] in self?.commandBar.toggle(.newTab) }      // sidebar "+" = Cmd-T
    wireFavorites()                                   // Move To, the sidebar drop and the BH-049 unload
    wireSidebarDrop()                                 // drag and drop on the Space pages (#104)
    wirePinned()                                      // pin/unpin, reset, Replace Pin, Separate, the favicon click
    wireTabActions()                                  // the row context menus, multi-selection, empty-area click
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
    wireExtensions()                        // tab and window events start with the engine window (attach)
    wireTabNavigation()
    wireThemeDrawing()
    // A removed Space's nodes emit no structure change, so `.spaceRemoved` checks too.
    sidebarObservation = sidebar.observe { [weak self] change in
      switch change {
      case .structure, .spaceRemoved:
        self?.closeEngineTabsOfRemovedNodes()
        self?.tabSwitcher.sourceDidChange()
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
      NotificationCenter.default.post(name: SpacesMenu.listDidChangeNotification, object: self)   // #387
    }
    refreshThemes()
    updateEmptyState()
    root.themeBackground.setPosition(sidebarController.view.pager.position)
    // Open with the saved tab (#116), else the first tab of the first Space, so the card shows a real page.
    let restored = session.flatMap { restoreSession($0) }
    if opensFirstTab,
       let first = restored ?? sidebarController.currentSpace.flatMap({ sidebarController.tabToRestore(in: $0) }) {
      sidebarController.activate(node: first)
    }
    self.savesSession = savesSession        // after the opening tab: the set applies the saved frame next
    reapplyTrafficLights()
    _ = peek                                          // its click monitor records where links are clicked
  }

  public func activate(node: NodeID) { sidebarController.activate(node: node) }
  /// The sidebar URL bar (BH-031, GS-042).
  public var urlBar: URLBarView { sidebarController.view.urlBar }
  public var pager: SpacePagerView { sidebarController.view.pager }
  public var themeBackground: ThemeBackgroundView { rootView.themeBackground }
  public var currentSpace: SpaceID? { sidebarController.currentSpace }

  private func refreshThemes() {
    // Crossfade only when the current Space's theme changed; a reorder snaps (the pager already jumped).
    let crossfade = sidebarController.consumeThemeCrossfade()
    rootView.themeBackground.replaceThemes(drawnThemes(), crossfade: crossfade)
    refreshToastFlavor()
  }

  /// Toasts follow the theme of the Space the pager is nearest to: its flavor and its first color stop (BH-190,
  /// alerts design decision 2).
  private func refreshToastFlavor() {
    let themes = rootView.themeBackground.themes
    guard !themes.isEmpty else { return }
    let index = min(max(Int(pager.position.rounded()), 0), themes.count - 1)
    toasts.view?.theme = themes[index]
  }

  /// The default error toast's text for a failed `mutation`. A full split says "Cannot Add New Pane" (BH-116).
  public static func errorText(for mutation: SidebarMutation, error: any Error) -> String {
    switch mutation {
    case .addTab: "Couldn't add the tab."
    case .addSpace: "Couldn't create a Space."
    case .moveNode:
      // A full Favorites section names itself [I] (BH-046); every other failed move is generic.
      error as? SidebarMoveError == .favoritesFull ? "Favorites are full." : "Couldn't move the tab."
    case .addPane, .editSplit:
      // Arc's toast for a full split; the generic text is [I].
      error as? SplitEditError == .splitFull ? "Cannot Add New Pane" : "Couldn't change the Split View."
    }
  }

  // MARK: Spaces

  /// Creates a Space named "Space N" right after the current one, without showing it (`newSpace(_:)` is the user's
  /// New Space); the first Space becomes current through `.spaceAdded`. Reports a failure via `onError`.
  @discardableResult
  func createSpace() -> SpaceID? {
    do { return try sidebar.addSpace(title: nextSpaceTitle(), after: currentSpace) } catch {
      onError?(.addSpace, error)
      return nil
    }
  }

  private func updateEmptyState() {
    rootView.card.setEmptyState(isShowingEmptyState ? emptyState : nil)
  }

  /// Cmd-Opt-Right (KB-033).
  @objc public func nextSpace(_ sender: Any?) { sidebarController.nextSpace() }
  /// Cmd-Opt-Left (KB-034).
  @objc public func previousSpace(_ sender: Any?) { sidebarController.previousSpace() }
  /// GS-002, BH-035: mouse buttons 3 / 4 switch to the previous / next Space anywhere in the window (#98).
  public override func otherMouseDown(with event: NSEvent) {
    switch event.buttonNumber {
    case 3: previousSpace(nil)
    case 4: nextSpace(nil)
    default: super.otherMouseDown(with: event)
    }
  }
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
    rootView.card.toolbar.urlBar.style = toolbarSetting.showsFullURL ? .full : .host
    configurePaneToolbars()
  }

  private func wireAddressBars() {
    let toolbar = rootView.card.toolbar
    for bar in [urlBar, toolbar.urlBar] {
      bar.onPress = { [weak self] in self?.openLocation(nil) }                        // same as Cmd-L, KB-002
      bar.onToggleToolbar = { [weak self] in self?.toggleToolbar(nil) }
    }
    wireToolbarActions(toolbar) { [weak self] in self?.toolbarTab }
    toolbarSetting.addObserver(self)
    applyToolbarVisibility()
  }

  /// Wires Back, Forward, Reload, history menus (`GS-024`, `BH-166`) and modifier / middle clicks (`GS-025`, `GS-026`,
  /// `BH-027`, `BH-165`) on `toolbar` for the tab resolved by `tabProvider` (#81).
  func wireToolbarActions(_ toolbar: ContentToolbarView, tabProvider: @escaping @MainActor () -> TabID?) {
    toolbar.onBack = { [weak self] in
      guard let self, let tab = tabProvider() else { return }
      self.engine.goBack(tab)
    }
    toolbar.onForward = { [weak self] in
      guard let self, let tab = tabProvider() else { return }
      self.engine.goForward(tab)
    }
    toolbar.onReload = { [weak self] in
      guard let self, let tab = tabProvider() else { return }
      self.engine.reload(tab)
    }
    toolbar.historyProvider = { [weak self] in
      guard let self, let tab = tabProvider() else { return nil }
      return self.engine.history(of: tab)
    }
    toolbar.onSelectHistory = { [weak self] offset in
      guard let self, let tab = tabProvider() else { return }
      self.engine.goToHistory(tab, offset: offset)
    }
    toolbar.onBackInNewTab = { [weak self] in
      guard let self, let tab = tabProvider(), let entry = self.engine.history(of: tab)?.back.first else { return }
      self.openHistoryEntryInBackgroundTab(entry)
    }
    toolbar.onForwardInNewTab = { [weak self] in
      guard let self, let tab = tabProvider(), let entry = self.engine.history(of: tab)?.forward.first else { return }
      self.openHistoryEntryInBackgroundTab(entry)
    }
    toolbar.onDuplicateTab = { [weak self] in
      guard let self, let tab = tabProvider() else { return }
      self.duplicateTabWithHistory(tab)
    }
  }

  /// GS-025, BH-165: Cmd-click or middle-click on Back / Forward opens that history entry in a new background Today
  /// tab in the current Space without changing the active tab (#81).
  private func openHistoryEntryInBackgroundTab(_ entry: HistoryEntry) {
    guard let space = sidebarController.currentSpace ?? createSpace() else { return }
    let title = entry.title.isEmpty ? (entry.url.host() ?? entry.url.absoluteString) : entry.title
    do {
      _ = try sidebar.addTab(url: entry.url, title: title, in: .today(space))
      announceCreation(.tab)                                        // BH-006
    } catch {
      onError?(.addTab, error)
    }
  }

  /// GS-026, BH-027: Cmd-click Reload duplicates `tab` into a new Today tab including its back/forward history and
  /// activates the duplicate (#81).
  private func duplicateTabWithHistory(_ tab: TabID) {
    guard let snapshot = engine.snapshot(of: tab),
          let url = snapshot.url ?? nodeByTab[tab].flatMap({ sidebar.node($0) }).flatMap({
            if case .tab(_, let u, _) = $0 { return u }; return nil
          }),
          let space = sidebarController.currentSpace ?? createSpace() else { return }
    let fallbackTitle = nodeByTab[tab].flatMap({ sidebar.node($0) }).flatMap({
      if case .tab(_, _, let t) = $0 { return t }; return nil
    }) ?? (url.host() ?? url.absoluteString)
    let title = snapshot.title.isEmpty ? fallbackTitle : snapshot.title
    do {
      let copyNode = try sidebar.addTab(url: url, title: title, in: .today(space))
      if let copyTab = engine.duplicateTab(tab) {
        tabsByNode[copyNode] = copyTab
        nodeByTab[copyTab] = copyNode
        sidebarController.markLoaded(node: copyNode)
        if let copySnapshot = engine.snapshot(of: copyTab) { replay(copySnapshot, into: copyNode) }
      }
      activate(node: copyNode)
      announceCreation(.tab)                                        // BH-006
    } catch {
      onError?(.addTab, error)
    }
  }

  /// Both URL bars show the current tab's URL from the engine snapshot (nil: no tab shown). In a split that is the
  /// focused pane; each pane card's own Toolbar is refreshed by `configurePaneToolbars()`.
  func refreshAddress() {
    let url = peek.addressOverride ?? currentTab.flatMap { engine.snapshot(of: $0)?.url }
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
  /// (BH-067, BH-048 [I]). Closing the window's last page keeps the window open on the empty card, also when the
  /// engine closes its emptied engine window (#386). Without a current tab the window closes, as Close Window does
  /// (CF-03, "Close current tab or window"; BH-069, a second Cmd-W unpinning, is NEEDS-RUNTIME-CHECK and not
  /// implemented).
  @objc public func closeTab(_ sender: Any?) {
    if peek.isOpen { peek.close(.keyboard); return }                // KB-078: Cmd-W closes the Peek
    if closeSelection() { return }                                  // BH-072: a multi-selection closes at once
    guard let node = currentNode else {
      window?.performClose(sender)
      return
    }
    close(node: node)
  }

  /// Closes a tab, pane or split the way Cmd-W closes the current tab; the hover X (GS-043) and the rows' VoiceOver
  /// action call it for every row except a pane row, whose X removes the pane from its split (BH-121). Today: archived
  /// (a split as one unit), and when it held the current tab the nearest sibling becomes current. Pinned and
  /// Favorites: the pages close and the rows stay. Folders are ignored.
  ///
  /// The pages close first, honouring leave-site prompts (week-3 Decision 11): a Today node is archived only once
  /// every page it shows has closed. While a close is held the row shows its closing state and the page stays
  /// mounted (the prompt is tab-modal on it); a cancelled prompt keeps the tab and nothing is archived. Another close
  /// of a node already waiting does nothing.
  public func close(node: NodeID) {
    let tabs: [NodeID]
    switch sidebar.node(node) {
    case .tab?: tabs = [node]
    case .split?: tabs = sidebar.children(of: .split(node))
    case .folder?, nil: return
    }
    let open = tabs.compactMap { tabsByNode[$0] }
    switch sidebar.section(containing: node) {
    case .today?:
      guard pendingArchives[node] == nil else { return }
      rememberClose(of: node, pages: tabs, archived: true)               // BH-074: Cmd-Shift-T brings it back
      let holdsCurrent = currentNode.map(tabs.contains) ?? false
      guard !open.isEmpty else {
        archive(node, heldCurrent: holdsCurrent)
        return
      }
      // Registered before the first close: an unheld close reports `.tabClosed` before `closeTab` returns.
      pendingArchives[node] = PendingArchive(tabs: Set(open), heldCurrent: holdsCurrent,
                                             space: sidebar.spaceID(containing: node))
      for tab in open { engine.closeTab(tab, mode: .honourUnloadHandlers) }
    case .pinned?, .favorites?:
      if !open.isEmpty { rememberClose(of: node, pages: tabs, archived: false) }
      for tab in open {
        engine.closeTab(tab, mode: .honourUnloadHandlers)   // `.tabClosed` clears the card and the row state
      }
    default:
      return
    }
    markHeldCloses(open)
  }

  /// Archives `node` now. When it held the current tab and nothing became current meanwhile, the nearest sibling
  /// (resolved while the node is still in place) becomes current.
  func archive(_ node: NodeID, heldCurrent: Bool) {
    let space = sidebar.spaceID(containing: node)
    let next = heldCurrent && space == currentSpace ? successor(of: node) : nil
    onArchive?([node])
    guard sidebar.node(node) == nil else { return }
    if let next, sidebar.node(next) != nil, currentTab == nil, currentSpace == space { activate(node: next) }
  }

  /// The tab to show after `node` leaves: the first tab of the nearest sibling below, else above. With no such sibling
  /// inside a split or folder, the container's siblings are tried; never another section.
  private func successor(of node: NodeID) -> NodeID? {
    var current = node
    for _ in 0..<64 {                       // depth guard against a malformed source
      guard let location = sidebar.parent(of: current) else { return nil }
      let siblings = sidebar.children(of: location)
      if let index = siblings.firstIndex(of: current) {
        // A sibling whose own archive waits on its pages (a bulk close, BH-072) is leaving too.
        let candidates = (siblings[(index + 1)...] + siblings[..<index].reversed())
          .filter { pendingArchives[$0] == nil }
        if let tab = candidates.lazy.compactMap({ self.sidebar.firstTab(at: $0) }).first { return tab }
      }
      guard let container = location.containerNode else { return nil }
      current = container
    }
    return nil
  }

  /// Engine tabs of nodes the sidebar no longer holds are closed; `.tabClosed` then drops the mappings. Runs inside
  /// change delivery, so it must not mutate the sidebar (closing a tab does not). The row is already gone (auto-archive,
  /// Delete Space, an import merge), so nothing could show a leave-site prompt for it: these closes skip
  /// `beforeunload` and never hold, and no live tab outlives its row (week-3 Decision 11).
  private func closeEngineTabsOfRemovedNodes() {
    for (node, tab) in tabsByNode where sidebar.node(node) == nil { engine.closeTab(tab, mode: .skipUnloadHandlers) }
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
        // New Today tabs go on top (BH-079, decision on #293).
        let node = try sidebar.addTab(url: url, title: url.host() ?? url.absoluteString, in: .today(space), at: 0)
        activate(node: node)
        announceCreation(.tab)                                      // BH-006
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
  ///
  /// The first one creates this window's engine window (week-3 decision 4), and every tab lands in that window
  /// (the `in:` form of `createTab`), so with two windows a tab never opens in the other one. A row whose page is live
  /// in another window gets that page moved here instead (Tab Handoff, #300).
  func openEngineTab(for node: NodeID) -> TabID? {
    if let existing = tabsByNode[node] { return existing }
    guard case .tab(_, let url, _)? = sidebar.node(node) else { return nil }
    switch onTakeOverLiveTab?(node) ?? .notLive {                  // one loaded copy (BH-066)
    case .released(let tab, let dialog): return adoptHandedOffTab(tab, for: node, dialog: dialog)
    case .held: return nil
    case .notLive: break
    }
    let tab = engine.createTab(url: url, in: ensureEngineWindow())
    keepsWindowWithoutEngine = false
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
    peek.shownTabsDidChange()
    javaScriptDialogs.refresh()
    permissionPrompts.refresh()
    infobarStrips.refresh()
    statusPill.refresh()
  }

  func replay(_ snapshot: TabSnapshot, into node: NodeID) {
    guard case .tab(_, let url, let title)? = sidebar.node(node) else { return }
    // Pinned and Favorite nodes keep the pinned URL (BH-057, BH-048); only their title follows the page (BH-062).
    let tracksURL = Self.writesLiveURL(toSection: sidebar.section(containing: node))
    let newURL = tracksURL ? snapshot.url.flatMap { $0 == url ? nil : $0 } : nil
    let newTitle = snapshot.title.isEmpty || snapshot.title == title ? nil : snapshot.title
    if newURL != nil || newTitle != nil { sidebar.updateTab(node, url: newURL, title: newTitle) }
    if let favicon = snapshot.faviconData { faviconChanged(favicon, for: node) }
    showAudio(of: snapshot, in: node)                               // #364
  }

  private func faviconChanged(_ data: Data?, for node: NodeID) {
    sidebarController.setFavicon(data, for: node)
    onFaviconChanged?(node, data)
  }

  /// Events of this window's tabs (`observe(window:)`).
  func handle(_ event: EngineEvent) {
    switch event {
    case .dialogRequested, .dialogEnded:
      javaScriptDialogs.handle(event)                               // #400
      return
    case .permissionRequested, .permissionEnded:
      permissionPrompts.handle(event)
      return
    case .infobarsChanged:
      infobarStrips.handle(event)
      return
    case .targetURLChanged:
      statusPill.handle(event)                                      // #114: a Peek's page has no row, so before the map
      return
    default:
      break
    }
    guard let node = nodeByTab[event.tabID] else {
      if handleParkedTabEvent(event) { return }                     // a closed page's copy (#346)
      if case .tabCreated(let tab) = event { engineDidCreateTab(tab) }
      if case .activeTabChanged(let tab) = event {      // a tab without a row took it
        guard let engineWindow, engine.latestActiveTab(in: engineWindow) == tab else { return }
        engineActiveTab = tab
        expectsEngineReactivation = false
      }
      return
    }
    switch event {
    case .titleChanged(_, let title) where !title.isEmpty:
      sidebar.updateTab(node, url: nil, title: title)
    case .urlChanged(let tab, let url):
      // Pinned and Favorite nodes keep the pinned URL (BH-057, BH-048); Today nodes track the page.
      if let url, Self.writesLiveURL(toSection: sidebar.section(containing: node)) {
        sidebar.updateTab(node, url: url, title: nil)
      }
      if tab == currentTab { refreshAddress() }
      refreshPaneToolbar(of: node)
    case .faviconChanged(_, let data):
      faviconChanged(data, for: node)
    case .historyChanged(let tab, _, _):
      if tab == toolbarTab { refreshToolbarHistory() }
      refreshPaneToolbar(of: node)
    case .tabClosed(let tab, let reason):
      tabDidClose(tab, node: node, reason: reason)
    case .activeTabChanged(let tab):
      engineDidActivate(tab, node: node)
    case .closeCancelled(let tab):
      closeWasCancelled(tab, node: node)
    case .audibleChanged(let tab, _), .mutedChanged(let tab, _):
      audioChanged(tab, node: node)                                 // #364
    case .tabCreated, .titleChanged, .loadingChanged, .dialogRequested, .dialogEnded, .permissionRequested,
         .permissionEnded, .infobarsChanged:
      break                                                         // dialogs, prompts, infobars: routed above
    case .findResult:
      break                                                         // find in page: the shell UI follows (#134)
    case .targetURLChanged:
      break                                                         // routed above, before the row lookup (#114)
    }
  }

  /// A tab of this window closed (week-3 Decision 12). The page is gone in every case; what happens to its row
  /// depends on why:
  /// - `.windowClosing`, `.appTerminating`: unload only. Nothing in the sidebar changes and nothing else is shown or
  ///   opened (the window is going away). The close button reports the shown tabs hidden before it asks the engine
  ///   (decision 10), as `prepareForTermination` does before quit, so the closes themselves write nothing.
  /// - `.client`: as asked. A Today node waiting in `pendingArchives` is archived once its last page is gone.
  /// - `.page`, `.extension`: the page or an extension closed it; a Today row is archived, a Pinned or Favorite row
  ///   stays unloaded as after Cmd-W.
  private func tabDidClose(_ tab: TabID, node: NodeID, reason: CloseReason) {
    tabsByNode[node] = nil
    nodeByTab[tab] = nil
    let wasCurrent = currentTab == tab
    switch reason {
    case .windowClosing, .appTerminating:
      if reason == .windowClosing, stampsShownTabsOnWindowClose {
        stampsShownTabsOnWindowClose = false
        for shown in shownNodes { onTabHidden?(shown) }      // decision 10, before the first page leaves
      }
      shownNodes.removeAll { $0 == node }
      sidebarController.visible.remove(node)
      if wasCurrent { currentTab = nil; rootView.card.setContent(nil) }
      if wasCurrent, reason == .windowClosing, keepsWindowWithoutEngine, !isWindowCloseRequested {
        nodeToReshow = node                                  // #386: its page went with the emptied window
      }
      sidebarController.deactivate(node: node)
      return
    case .client, .page, .extension:
      break
    }
    // The last page of this window closed (#386). Set once the close is handled, after a successor was opened.
    let emptiedWindow = tabsByNode.isEmpty
    defer { if emptiedWindow { keepsWindowWithoutEngine = true } }
    shownNodes.removeAll { $0 == node }                     // a closed page is not hidden, it is gone
    sidebarController.visible.remove(node)
    if wasCurrent { currentTab = nil }
    if tab == engineActiveTab {
      engineActiveTab = nil
      if !tabsByNode.isEmpty { expectEngineReactivation() }  // the engine picks a next active tab; the shell does
    }
    if splitState.panes.contains(node) {
      sidebarController.deactivate(node: node)
      paneDidClose(node, wasFocused: wasCurrent)
    } else {
      if wasCurrent { rootView.card.setContent(nil); refreshAddress() }
      sidebarController.deactivate(node: node)
      hiddenPaneDidClose(node)
    }
    if pendingArchiveTabClosed(tab) { return }
    if reason != .client, case .today? = sidebar.section(containing: node) {
      archive(node, heldCurrent: wasCurrent)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func reapplyTrafficLights() {
    rootView.reapplyTrafficLights()
  }

  // AppKit resets the standard buttons on each of these.
  public func windowDidResize(_ notification: Notification) { reapplyTrafficLights() }
  public func windowDidEndLiveResize(_ notification: Notification) { reapplyTrafficLights() }
  public func windowWillEnterFullScreen(_ notification: Notification) { frameBeforeFullScreen = window?.frame }
  public func windowWillExitFullScreen(_ notification: Notification) { reapplyTrafficLights() }
  public func windowDidExitFullScreen(_ notification: Notification) { reapplyTrafficLights() }
  public func windowDidBecomeKey(_ notification: Notification) {
    reapplyTrafficLights()
    windowKeyStateChanged(isKey: true)               // BH-025
    if !commandBarPrewarmed { commandBarPrewarmed = true; commandBar.prewarm() }
  }
  public func windowDidResignKey(_ notification: Notification) {
    reapplyTrafficLights()
    windowKeyStateChanged(isKey: false)              // BH-025
    saveSession()                                    // #116: the frame
    tabSwitcher.windowDidResignKey()
  }
  public func windowDidChangeBackingProperties(_ notification: Notification) {
    reapplyTrafficLights()
    if let scale = window?.backingScaleFactor { SymbolImageCache.shared.prewarm(scale: scale) }   // cache hits if warm
  }
  public func windowDidDeminiaturize(_ notification: Notification) { reapplyTrafficLights() }
  /// The close button and Close Window (`performClose:`): with an engine window the engine decides
  /// (`onCloseRequested`): it closes the tabs, unload prompts first, and the window closes on its `.windowClosed`; a
  /// cancelled prompt keeps it open. Without one (no tab was ever shown) the window closes as before. The shown tabs
  /// are stamped once the first page closes, not here: a cancelled prompt leaves the stored sidebar as it was.
  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard engineWindow != nil, let request = engineHost.onCloseRequested else { return true }
    let open = Array(tabsByNode.values)
    saveSession()                                    // #116: before the tabs close
    isWindowCloseRequested = true
    stampsShownTabsOnWindowClose = true
    request()
    markHeldCloses(open)
    return false
  }

  /// The shown tabs, every pane of a split, stop being visible (decision 10). The command bar's display link retains
  /// its controller; release it with the window.
  public func windowWillClose(_ notification: Notification) {
    isClosed = true
    for node in shownNodes { onTabHidden?(node) }
    removePaneMouseMonitor()
    javaScriptDialogs.closeAll()
    permissionPrompts.closeAll()
    infobarStrips.closeAll()
    statusPill.closeAll()
    peek.invalidate()
    commandBar.invalidate()
    rootView.sidebarOverlay.invalidate()
    pager.stopInteraction()        // a closed window's views keep their display links
    onboarding?.windowVisibilityChanged(false)   // a first run closed mid-flow stops its stage's frames
    window?.contentView?.removeToolTipsInSubtree()   // a tool tip shown at the close goes with the window (#301)
  }
}

extension ShellWindowController: NSMenuItemValidation {
  /// Titles the Toggle Toolbar and Show / Hide Sidebar items for the current state (KB-018, KB-017) and validates the Split View items (S5) and Delete
  /// Space (#206). Every other item stays enabled, as it was before this controller validated menu items.
  public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if onboarding != nil { return false }               // the first run covers the browser
    if let enabled = validateCopyLinkMenuItem(menuItem) { return enabled }
    if let enabled = validateSplitMenuItem(menuItem) { return enabled }
    if let enabled = validateSpaceMenuItem(menuItem) { return enabled }
    if let enabled = validateSidebarMenuItem(menuItem) { return enabled }
    if let enabled = validatePinnedMenuItem(menuItem) { return enabled }
    if menuItem.action == #selector(reopenClosedTab(_:)) { return canReopenClosed }
    if menuItem.action == #selector(clearTodayTabs(_:)) { return canClearToday }       // KB-019 (#110)
    if menuItem.action == #selector(toggleToolbar(_:)) {
      menuItem.title = ToolbarSetting.menuTitle(isVisible: isToolbarVisible)
    }
    return true
  }
}

extension ShellWindowController: ToolbarSettingObserver {
  public func toolbarSettingDidChange(_ setting: ToolbarSetting) { applyToolbarVisibility() }
}
