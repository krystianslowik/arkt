import AppKit
import EngineAPI

/// Every browser window of one sidebar and engine (week-3 plan, W3-7 part C): the windows the shell opens itself
/// (launch, New Window, a Dock reopen under FakeEngine) and the windows it builds for the engine's own requests (a
/// Dock reopen under Chromium, `chrome.windows.create`, a startup URL). The composition root owns one set and
/// supplies the app's hooks through `configure`.
///
/// A window built for an engine request (`host(for:)`) runs inside the engine's window construction, so it calls
/// nothing on the engine and is neither shown nor adopted until the engine announces the window it was handed to
/// (`.windowOpened`). The engine does not tell a host its id; the set matches the announced window's host
/// (`hostLookup`) against the windows it is waiting for, so a shell window that creates its own engine window
/// meanwhile is never taken for one of them.
@MainActor
public final class ShellWindowSet {
  /// The host an engine window was created with (`ChromiumEngine.host(of:)`); nil for a window this engine does not
  /// list.
  public typealias HostLookup = @MainActor (EngineWindowID) -> (any EngineWindowHosting)?

  public let engine: any EngineClient
  public let sidebar: any SidebarSource
  public let toolbarSetting: ToolbarSetting
  /// The saved sidebar width and hidden state (#331); `make` hands it to every window, and the first window adopts
  /// the stored state.
  public let sidebarStateStore: SidebarWindowStateStore
  /// The app's hooks on a new window (archive, stamps, favicons, import); runs before the window is shown.
  public var configure: (@MainActor (ShellWindowController) -> Void)?

  private let hostLookup: HostLookup?
  private var windows: [ShellWindowController] = []
  /// True once the session's first window adopted the saved sidebar state (#331); later windows keep the defaults.
  private var adoptedSavedSidebarState = false
  /// Built for an engine request, waiting for their window's `.windowOpened`.
  private var awaitingAdoption: [ShellWindowController] = []
  /// Most recently main last.
  private var mainOrder: [ObjectIdentifier] = []
  private var mainObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]
  private var windowObservation: EngineObservation?
  /// Little Arkt windows (#314), the frontmost last.
  private var littleArktWindows: [LittleArktWindowController] = []
  /// The size new Little Arkt windows get: the last one the user set (BH-142), for this session.
  private var littleArktSize = LittleArktLayout.defaultSize
  /// Reduce Motion for Little Arkt windows (tests set it).
  public var littleArktReduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  /// `hostLookup` is needed only for an engine that asks for windows of its own (a host provider); FakeEngine never
  /// does.
  public init(engine: any EngineClient, sidebar: any SidebarSource, toolbarSetting: ToolbarSetting = .ephemeral(),
              sidebarStateStore: SidebarWindowStateStore = .ephemeral(), hostLookup: HostLookup? = nil) {
    self.engine = engine
    self.sidebar = sidebar
    self.toolbarSetting = toolbarSetting
    self.sidebarStateStore = sidebarStateStore
    self.hostLookup = hostLookup
    windowObservation = engine.observeWindows { [weak self] event in
      guard case .windowOpened(let id) = event else { return }
      self?.windowOpened(id)
    }
  }

  /// The open windows, in the order they were built (a closed window is never shown again).
  public var controllers: [ShellWindowController] {
    for closed in windows where closed.isClosed {
      let id = ObjectIdentifier(closed)
      if let observer = mainObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
      mainOrder.removeAll { $0 == id }
    }
    windows.removeAll { $0.isClosed }
    return windows
  }

  /// The window app-level feedback goes to (toasts, the import summary): the one most recently main, else the first
  /// open one.
  public var primary: ShellWindowController? {
    let open = controllers
    for id in mainOrder.reversed() {
      if let controller = open.first(where: { ObjectIdentifier($0) == id }) { return controller }
    }
    return open.first
  }

  // MARK: Shell-created windows

  /// Builds, wires and shows a window. `opensFirstTab` shows the current Space's tab at once (launch); New Window
  /// passes false, so the new window gets its engine window with the first tab the user picks (decision 4) and no
  /// row is shown in two windows.
  @discardableResult
  public func openWindow(opensFirstTab: Bool = true) -> ShellWindowController {
    let anchor = primary?.window
    let controller = make(opensFirstTab: opensFirstTab)
    place(controller, near: anchor)
    controller.showWindow(nil)
    return controller
  }

  /// Dock reopen without an engine that asks for windows (FakeEngine; #241): the primary window comes back, or a new
  /// one when every window closed.
  @discardableResult
  public func reopen() -> ShellWindowController {
    if let primary {
      primary.showWindow(nil)
      return primary
    }
    return openWindow()
  }

  /// GS-013: a new window whose top-left corner is at `point` (screen coordinates), showing `node`. The page moves
  /// over from the window that had it, without a reload (#300).
  @discardableResult
  public func openWindow(showing node: NodeID, at point: NSPoint) -> ShellWindowController {
    let controller = make(opensFirstTab: false)
    controller.showWindow(nil)
    controller.window?.setFrameTopLeftPoint(point)   // after showing: the first show places a window itself
    controller.activate(node: node)
    return controller
  }

  // MARK: Engine-initiated windows

  /// The engine's host provider (`EngineWindowHostProvider`). A Dock reopen reuses an open window that has no engine
  /// window yet (no tab was shown, so the engine counts no window); every other request gets a new window in the
  /// opener's Space, else the primary window's, with the requested frame.
  public func host(for request: EngineWindowRequest) -> any EngineWindowHosting {
    if LittleArktRouting.opensInLittleArkt(request) { return makeLittleArkt(for: request).engineHost }
    if request.kind == .reopen, let reusable = controllers.first(where: { candidate in
      candidate.engineWindow == nil && !awaitingAdoption.contains { $0 === candidate }
    }) {
      awaitingAdoption.append(reusable)
      return reusable.engineHost
    }
    let space = targetSpace(for: request)
    let anchor = primary?.window
    let controller = make(opensFirstTab: false)
    if let space { controller.sidebarController.showSpace(space) }
    if let bounds = request.bounds {
      controller.window?.setFrame(bounds, display: false)
    } else {
      place(controller, near: anchor)
    }
    awaitingAdoption.append(controller)
    return controller.engineHost
  }

  private func targetSpace(for request: EngineWindowRequest) -> SpaceID? {
    let open = controllers
    if let opener = request.openerWindow, let source = open.first(where: { $0.engineWindow == opener }) {
      return source.currentSpace
    }
    return primary?.currentSpace
  }

  private func windowOpened(_ id: EngineWindowID) {
    awaitingAdoption.removeAll { $0.isClosed }
    if let host = hostLookup?(id), let little = littleArktWindows.first(where: { $0.engineHost === host }) {
      little.adopt(engineWindow: id)
      return
    }
    guard let host = hostLookup?(id),
          let index = awaitingAdoption.firstIndex(where: { $0.engineHost === host }) else { return }
    let controller = awaitingAdoption.remove(at: index)
    controller.adopt(engineWindow: id)
    controller.showWindow(nil)
  }

  // MARK: Little Arkt (#314)

  /// The open Little Arkt windows, the frontmost last.
  public var littleArkts: [LittleArktWindowController] {
    littleArktWindows.removeAll { $0.isClosed }
    return littleArktWindows
  }

  /// Built inside the engine's window construction: placed, wired and kept until its window is announced. A popup
  /// gets the frame its page asked for; otherwise the remembered size at the top-right, cascaded from the frontmost
  /// Little Arkt window.
  private func makeLittleArkt(for request: EngineWindowRequest) -> LittleArktWindowController {
    let screen = NSScreen.main ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: LittleArktLayout.defaultSize)
    let frame = request.bounds.map { LittleArktLayout.frame(forRequestedPage: $0, in: visible) }
      ?? LittleArktLayout.placement(size: littleArktSize, frontmost: littleArkts.last?.window.frame, in: visible)
    let little = LittleArktWindowController(engine: engine, isPopup: request.isPopup || request.kind == .page,
                                            frame: frame)
    little.reduceMotion = { [weak self] in self?.littleArktReduceMotion() ?? false }
    little.targetSpace = { [weak self] in self?.primary?.littleArktTargetSpace }
    little.spaces = { [weak self] in
      guard let self else { return [] }
      return self.sidebar.spaceOrder.compactMap { self.sidebar.space($0) }
    }
    little.onOpenIn = { [weak self] tab, space in
      guard let self else { return false }
      let target = self.primary ?? self.openWindow(opensFirstTab: false)
      return target.receiveMovedTab(tab, in: space)
    }
    little.onResize = { [weak self] size in self?.littleArktSize = size }
    little.onClosed = { [weak self] closed in self?.littleArktWindows.removeAll { $0 === closed } }
    littleArktWindows.append(little)
    return little
  }

  // MARK: Tab Handoff (#300, BH-066)

  /// The other window that has `node`'s page lets go of it for `taker`. Little Arkt windows have no rows.
  private func releaseLiveTab(of node: NodeID, for taker: ShellWindowController?) -> LiveTabHandoff {
    guard let holder = controllers.first(where: { $0 !== taker && $0.engineTab(of: node) != nil }) else {
      return .notLive
    }
    return holder.releaseLiveTab(of: node)
  }

  // MARK: Unions over the open windows

  /// The tabs any window shows (quit stamps them, decision 10).
  public var visibleNodes: Set<NodeID> {
    controllers.reduce(into: []) { $0.formUnion($1.visibleNodes) }
  }

  /// The tabs whose close a leave-site prompt would hold, in any window (Decision 11).
  public var nodesHoldingClose: Set<NodeID> {
    controllers.reduce(into: []) { $0.formUnion($1.nodesHoldingClose) }
  }

  /// What auto-archive skips this pass: every window's visible tabs and the tabs that would hold their close.
  public var autoArchiveExempt: Set<NodeID> {
    controllers.reduce(into: []) { result, controller in
      result.formUnion(controller.sidebarController.resolver.visible)
      result.formUnion(controller.nodesHoldingClose)
    }
  }

  // MARK: Building

  private func make(opensFirstTab: Bool) -> ShellWindowController {
    let controller = ShellWindowController(engine: engine, sidebar: sidebar, toolbarSetting: toolbarSetting,
                                           sidebarStateStore: sidebarStateStore, opensFirstTab: opensFirstTab)
    controller.onNewWindow = { [weak self] in self?.openWindow(opensFirstTab: false) }
    controller.onTakeOverLiveTab = { [weak self, weak controller] node in
      self?.releaseLiveTab(of: node, for: controller) ?? .notLive
    }
    controller.onDragOutToNewWindow = { [weak self] node, point in self?.openWindow(showing: node, at: point) }
    windows.append(controller)
    trackMain(controller)
    configure?(controller)
    // #331: the session's first window is the one a relaunch restores; it opens on the saved sidebar state. Later
    // windows (New Window, a Dock reopen) keep the defaults.
    if !adoptedSavedSidebarState {
      adoptedSavedSidebarState = true
      controller.adoptSavedSidebarState()
    }
    return controller
  }

  /// Centred when it is the first window, else cascaded from `anchor`.
  private func place(_ controller: ShellWindowController, near anchor: NSWindow?) {
    guard let window = controller.window else { return }
    guard let anchor, anchor.isVisible else {
      window.center()
      return
    }
    window.setFrameTopLeftPoint(anchor.cascadeTopLeft(from: NSPoint(x: anchor.frame.minX, y: anchor.frame.maxY)))
  }

  private func trackMain(_ controller: ShellWindowController) {
    guard let window = controller.window else { return }
    let id = ObjectIdentifier(controller)
    mainObservers[id] = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeMainNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.mainOrder.removeAll { $0 == id }
        self.mainOrder.append(id)
      }
    }
  }
}
