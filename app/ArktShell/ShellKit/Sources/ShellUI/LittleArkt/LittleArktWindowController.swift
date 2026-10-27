import AppKit
import EngineAPI

/// A Little Arkt window (#314, docs/design/little-arkt.md): a small window with the brand frame around one page, whose
/// one action moves the page into a Space ("Open in <Space>", or "Open as Tab" for a popup). It hosts one engine
/// window through `engineHost`, built by `ShellWindowSet.host(for:)` for popups.
///
/// The engine owns the close: the close button, Cmd-W and Close Window animate the window out and ask the engine,
/// which closes the tabs and reports `.windowClosed`; a page that closes its popup (`window.close()`) arrives the same
/// way and fades the window out. Open in flies a snapshot of the page into the main window's content card
/// (`LittleArktFlight`, #352) and moves the tab at rest (`EngineClient.moveTab`); the engine then closes the emptied
/// window. Without the flight (Reduce Motion, no main window the user can see) the window fades out, then the tab
/// moves.
///
/// A responder after the window (`nextResponder`), so the main menu's Archive Tab (`closeTab:`) reaches it.
@MainActor
public final class LittleArktWindowController: NSResponder, NSWindowDelegate {
  private enum Phase: Equatable {
    /// Built inside the engine's window construction; not shown until its window is announced.
    case pending
    case open
    /// Fading out before the page moves to the main window.
    case handingOff
    /// The snapshot flies to the main window; the page moves when it lands.
    case flying
    /// The page went to the main window; the engine closes this window.
    case handedOff
    /// Animating out for a close the user asked for; the engine is asked when the motion ends.
    case closing
    case closed
  }

  public let engine: any EngineClient
  public let isPopup: Bool
  let window: LittleArktWindow
  let rootView: LittleArktRootView
  public let engineHost: LittleArktEngineHost
  public private(set) var engineWindow: EngineWindowID?
  /// The tab whose page the card shows.
  public private(set) var shownTab: TabID?
  private(set) var lastTransition: LittleArktTransition?
  private var phase = Phase.pending
  private let animator = LittleArktAnimator(scene: .rest)
  private var tabObservation: EngineObservation?
  private var windowObservation: EngineObservation?
  /// The engine closed the window while it was still moving out; it closes when the motion ends.
  private var engineClosed = false
  /// The Open in flight while it runs, through its crossfade.
  private(set) var flight: LittleArktFlight?
  private var snapshotTask: Task<Void, Never>?

  // MARK: Hooks (set by ShellWindowSet)

  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The Space "Open in" goes to: the frontmost main window's Space; nil while no main window has one.
  var targetSpace: @MainActor () -> SidebarSpaceInfo? = { nil }
  /// The Spaces the chooser lists, in sidebar order.
  var spaces: @MainActor () -> [SidebarSpaceInfo] = { [] }
  /// Moves `tab` into the main window as the first Today tab of `space` (nil: the target Space); false when it could
  /// not, and the page stays here.
  var onOpenIn: @MainActor (TabID, SpaceID?) -> Bool = { _, _ in false }
  /// The user resized the window: new windows use the size (BH-142).
  var onResize: @MainActor (CGSize) -> Void = { _ in }
  /// The window closed; the set forgets it.
  var onClosed: @MainActor (LittleArktWindowController) -> Void = { _ in }
  /// The open main window Open in flies to; nil takes today's path (which opens one).
  var flightDestination: @MainActor () -> (any LittleArktFlightDestination)? = { nil }
  /// Whether the main window can take the flight (minimized, another desktop, full screen); Reduce Motion is added.
  var mainWindowConditions: @MainActor (NSWindow) -> LittleArktFlightConditions = {
    LittleArktFlightConditions(window: $0)
  }
  /// Schedules the flight's watchdog checks (tests inject a clock of their own); nil: the real clock.
  var flightWatchdog: LittleArktFlightWatchdog?
  /// The page's frame for the flight; nil asks the engine (`snapshot(of:)`).
  var snapshotSource: (@MainActor (TabID) async -> LittleArktSnapshot?)?
  /// Tests turn this off and step the motion and the flight by hand.
  var drivesDisplayLink = true {
    didSet { animator.drivesDisplayLink = drivesDisplayLink }
  }
  /// The clock the window's own motion reads (tests set it by hand).
  var motionClock: @MainActor () -> CFTimeInterval {
    get { animator.now }
    set { animator.now = newValue }
  }

  var topBar: LittleArktTopBar { rootView.topBar }
  var card: ContentCardView { rootView.card }
  public var isClosed: Bool { phase == .closed }
  var isAnimating: Bool { animator.isRunning }
  /// What the window's own motion shows now.
  var currentScene: LittleArktScene { animator.currentScene }
  var contentLayer: CALayer? { rootView.layer }

  init(engine: any EngineClient, isPopup: Bool, frame: CGRect) {
    self.engine = engine
    self.isPopup = isPopup
    window = LittleArktWindow(contentRect: frame)
    rootView = LittleArktRootView(frame: CGRect(origin: .zero, size: frame.size))
    engineHost = LittleArktEngineHost(window: window, cardView: rootView.card)
    super.init()
    window.contentView = rootView
    window.setFrame(frame, display: false)
    window.delegate = self
    window.nextResponder = self
    window.commandHost = engineHost
    window.onKeyEquivalent = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
    engineHost.controller = self
    topBar.openButton.target = self
    topBar.openButton.action = #selector(openInAction(_:))
    topBar.chooserButton.target = self
    topBar.chooserButton.action = #selector(showChooser(_:))
    topBar.copyButton.target = self
    topBar.copyButton.action = #selector(copyLink(_:))
    animator.onFrame = { [weak self] scene in self?.present(scene) }
    refreshTopBar()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: Engine window

  /// The engine window this controller's host was handed to, once announced: its page is mounted, the window comes
  /// forward as key (the main window does not) and appears.
  func adopt(engineWindow id: EngineWindowID) {
    guard engineWindow == nil, phase == .pending else { return }
    engineWindow = id
    tabObservation = engine.observe(window: id) { [weak self] event in self?.handle(event) }
    windowObservation = engine.observeWindows { [weak self] event in
      guard let self, event.windowID == self.engineWindow, case .windowClosed = event else { return }
      self.engineWindowClosed()
    }
    if let active = engine.activeTab(in: id) { mount(active) }
    phase = .open
    let reduce = reduceMotion()
    animator.jump(to: LittleArktMotion.appearStart(reduceMotion: reduce))
    window.makeKeyAndOrderFront(nil)
    run(.appear) { _ in }
  }

  private func handle(_ event: EngineEvent) {
    switch event {
    case .tabCreated(let tab) where shownTab == nil, .activeTabChanged(let tab):
      guard phase == .open || phase == .pending else { return }
      mount(tab)
    case .urlChanged(let tab, _) where tab == shownTab:
      refreshTopBar()
    case .titleChanged(let tab, let title) where tab == shownTab:
      window.title = title
    case .tabClosed(let tab, _) where tab == shownTab:
      shownTab = nil
      if card.contentView?.isDescendant(of: rootView) == true { card.setContent(nil) }
      flight?.abort(.pageClosed)                              // nothing left to land; the engine closes the window
    default:
      break
    }
  }

  private func mount(_ tab: TabID) {
    guard let view = engine.contentView(for: tab) else { return }
    shownTab = tab
    card.setContent(view)
    window.title = engine.snapshot(of: tab)?.title ?? ""
    refreshTopBar()
    if window.isKeyWindow { engine.focusPage(of: tab) }
  }

  /// Its tabs closed already (contract rule 11). A window the user closed or handed off is already moving out; a
  /// popup the page closed fades out now (0.12 s).
  private func engineWindowClosed() {
    engineWindow = nil
    tabObservation = nil
    windowObservation = nil
    engineHost.onCloseRequested = nil
    engineHost.forward = nil
    switch phase {
    case .closing where !animator.isRunning:
      finishClose()                                         // the close motion ended before the engine answered
    case .closing, .handingOff, .flying:
      engineClosed = true
    case .handedOff where flight != nil:
      engineClosed = true                                   // closes when the flight's crossfade ends
      window.orderOut(nil)
    case .handedOff, .pending:
      finishClose()
    case .open:
      phase = .closing
      engineClosed = true
      run(.fadeOut) { [weak self] _ in self?.finishClose() }
    case .closed:
      break
    }
  }

  private func finishClose() {
    guard phase != .closed else { return }
    phase = .closed
    rootView.removeToolTipsInSubtree()                      // a tool tip shown at the close goes with it (#301)
    window.orderOut(nil)
    window.close()
    onClosed(self)
  }

  // MARK: Close (Cmd-W, close button, Close Window)

  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard engineWindow != nil else { return phase == .pending || phase == .closed }
    requestClose()
    return false
  }

  public func windowWillClose(_ notification: Notification) {
    rootView.removeToolTipsInSubtree()
    flight?.abort(.smallWindowClosing)                        // the page lands in the main window first
    guard phase != .closed else { return }
    phase = .closed
    onClosed(self)
  }

  /// The main menu's Archive Tab (Cmd-W) closes the window (KB-080). Archiving under the Little Arkt source comes
  /// with the Archive's source (follow-up).
  @objc public func closeTab(_ sender: Any?) {
    window.performClose(sender)
  }

  /// Scale 0.97 and fade (`firmFast`), then the engine closes the window. A page that would ask before leaving
  /// (`beforeunload`) is asked at once, without the motion, so its prompt is never on an invisible window.
  func requestClose() {
    if phase == .flying {
      flight?.abort(.closeRequested)                          // the page lands now, never stranded in a hidden window
      if phase == .handedOff { return }                       // the engine closes the emptied window
    }
    guard phase == .open, engineWindow != nil else { return }
    if let shownTab, engine.snapshot(of: shownTab)?.wouldHoldClose == true {
      engineHost.onCloseRequested?()
      return
    }
    phase = .closing
    run(.close) { [weak self] _ in
      guard let self else { return }
      if !self.engineClosed { self.engineHost.onCloseRequested?() }   // an in-process engine may close at once
      if self.engineClosed || self.engineWindow == nil { self.finishClose() }
    }
  }

  // MARK: Open in (Cmd-O, KB-076)

  @objc private func openInAction(_ sender: Any?) { openIn() }

  /// The page moves into the target Space of the main window, as the first Today tab, selected, with its history
  /// and state (BH-136). With an open main window the user can see, the page flies there (`beginFlight`); otherwise
  /// this window fades out (0.12 s), then the tab moves.
  func openIn(space: SpaceID? = nil) {
    guard phase == .open, let tab = shownTab else { return }
    if beginFlight(tab, space: space) { return }
    phase = .handingOff
    run(.fadeOut) { [weak self] completed in
      guard completed else { return }
      self?.commitOpenIn(tab, space: space)
    }
  }

  private func commitOpenIn(_ tab: TabID, space: SpaceID?) {
    guard phase == .handingOff else { return }
    let spaceName = self.spaceName(space)
    card.releaseContent()                                   // the main window's card takes the page's view
    guard onOpenIn(tab, space) else {
      phase = .open
      if let view = engine.contentView(for: tab) { card.setContent(view) }
      run(.appear) { _ in }
      return
    }
    handedOff(spaceName: spaceName)
  }

  private func spaceName(_ space: SpaceID?) -> String? {
    (space.flatMap { id in spaces().first { $0.id == id } } ?? targetSpace())?.title
  }

  private func handedOff(spaceName: String?) {
    phase = .handedOff
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
      .announcement: LittleArktCopy.announcement(spaceName: isPopup ? nil : spaceName),
      .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
    if flight == nil, engineClosed || engineWindow == nil { finishClose() }
  }

  // MARK: Open in flight (#352)

  /// Flies the page's snapshot from this card into the open main window's content card, from wherever this window's
  /// motion has the card now (an Open in during the appear picks up its scale and opacity). The row appears in the
  /// main window's sidebar at once (drawn by the flight); the page moves at rest. False when the flight does not
  /// apply: no open main window, one the user cannot see, Reduce Motion, or a row the sidebar refuses.
  private func beginFlight(_ tab: TabID, space: SpaceID?) -> Bool {
    guard let destination = flightDestination(), let mainWindow = destination.flightWindow else { return false }
    var conditions = mainWindowConditions(mainWindow)
    conditions.reduceMotion = conditions.reduceMotion || reduceMotion()
    guard conditions.allowsFlight, let target = destination.flightCardFrame else { return false }
    rootView.layoutSubtreeIfNeeded()
    let scene = animator.currentScene
    let source = LittleArktFlightGeometry.visibleCard(card.frame, in: rootView.bounds, scene: scene,
                                                      windowOrigin: window.frame.origin)
    guard let node = destination.beginReceiving(tab, in: space) else { return false }
    let level = NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue,
                                             max(window.level.rawValue, mainWindow.level.rawValue) + 1))
    let flight = LittleArktFlight(source: source, scale: scene[.scale], opacity: scene[.opacity], target: target,
                                  span: window.frame.union(mainWindow.frame), level: level,
                                  flavor: ThemeFlavor(appearance: mainWindow.effectiveAppearance))
    flight.drivesDisplayLink = drivesDisplayLink
    let spaceName = self.spaceName(space)
    flight.onStart = { [weak self, weak mainWindow] in
      guard let self else { return }
      self.window.ignoresMouseEvents = true                   // the page underneath is hidden from here on
      self.run(.fadeOut) { _ in }                             // the small frame fades at once (0.12 s)
      mainWindow?.orderFront(nil)                             // the main window comes forward at the start
    }
    flight.onRoom = { [weak destination] room, row in destination?.presentArrival(of: node, room: room, appear: row) }
    flight.onLand = { [weak self, weak destination] in
      self?.landFlight(tab, node: node, destination: destination, spaceName: spaceName)
    }
    flight.onAbort = { [weak self, weak destination] reason in
      self?.flightAborted(reason, tab, node: node, destination: destination, spaceName: spaceName)
    }
    flight.onFinish = { [weak self] in self?.flightFinished() }
    flight.watchdog = flightWatchdog
    self.flight = flight
    phase = .flying
    snapshotTask = Task { [weak self] in
      guard let self else { return }
      let snapshot: LittleArktSnapshot?
      if let source = self.snapshotSource {
        snapshot = await source(tab)
      } else {
        snapshot = await self.snapshot(of: tab)
      }
      self.flight?.snapshotArrived(snapshot)
    }
    flight.start(on: mainWindow.contentView)
    return true
  }

  /// The page's current frame from the engine, uncapped (`.fullFrame`), decoded off the main actor.
  private func snapshot(of tab: TabID) async -> LittleArktSnapshot? {
    guard let page = await engine.pageImage(of: tab, .fullFrame) else { return nil }
    return await LittleArktSnapshot.decode(page)
  }

  /// At rest: the page moves once, into the main card at its final size; the snapshot stays over it until its
  /// first frame there.
  private func landFlight(_ tab: TabID, node: NodeID,
                          destination: (any LittleArktFlightDestination)?, spaceName: String?) {
    guard phase == .flying else { return }
    snapshotTask?.cancel()
    snapshotTask = nil
    card.releaseContent()                                   // the main window's card takes the page's view
    if destination?.finishReceiving(tab, node: node, clearingPrevious: true) == true {
      handedOff(spaceName: spaceName)
      return
    }
    // The main window went away mid-flight: the page stays here (another window would add a second row for it).
    keepPage(tab, node: node, destination: destination)
  }

  /// The flight ended early (`LittleArktFlight.abort`). The page lands in the main window without the flight, stays
  /// here when that window is going away, or, when the page closed itself, there is nothing to land.
  private func flightAborted(_ reason: LittleArktFlightAbort, _ tab: TabID, node: NodeID,
                             destination: (any LittleArktFlightDestination)?, spaceName: String?) {
    guard phase == .flying else { return }
    switch reason {
    case .mainWindowClosed:
      snapshotTask?.cancel()
      snapshotTask = nil
      keepPage(tab, node: node, destination: destination)
    case .pageClosed:
      snapshotTask?.cancel()
      snapshotTask = nil
      destination?.cancelReceiving(tab, node: node)
      phase = .handedOff                                      // the engine closes this window; no appear on it
      if engineClosed || engineWindow == nil { finishClose() }
    case .mainWindowMiniaturized, .framesStopped, .appTerminating, .smallWindowClosing, .closeRequested:
      landFlight(tab, node: node, destination: destination, spaceName: spaceName)
    }
  }

  /// The page stays in this window: the row made for it goes, and the window comes back.
  private func keepPage(_ tab: TabID, node: NodeID, destination: (any LittleArktFlightDestination)?) {
    destination?.cancelReceiving(tab, node: node)
    phase = .open
    window.ignoresMouseEvents = false
    if let view = engine.contentView(for: tab) { card.setContent(view) }
    run(.appear) { _ in }
  }

  private func flightFinished() {
    flight = nil
    guard phase == .handedOff, engineClosed || engineWindow == nil else { return }
    finishClose()
  }

  // MARK: Space chooser (Cmd-Opt-O, KB-077)

  @objc func showChooser(_ sender: Any?) {
    guard phase == .open else { return }
    let menu = NSMenu(title: LittleArktCopy.chooseSpace)
    let heading = NSMenuItem(title: LittleArktCopy.chooserHeading, action: nil, keyEquivalent: "")
    heading.isEnabled = false
    menu.addItem(heading)
    let target = targetSpace()?.id
    for space in spaces() {
      let item = NSMenuItem(title: space.title, action: #selector(chooseSpace(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = space.id
      item.image = LittleArktTopBar.swatchImage(space.theme.baseColors)
      if space.id == target {
        item.keyEquivalent = "o"
        item.keyEquivalentModifierMask = .command
      }
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let copy = NSMenuItem(title: LittleArktCopy.copyLink, action: #selector(copyLink(_:)), keyEquivalent: "")
    copy.target = self
    menu.addItem(copy)
    let anchor = topBar.chooserButton
    menu.popUp(positioning: nil, at: Self.menuOrigin(below: anchor), in: anchor)
  }

  /// 4 pt below `view`'s bottom edge, in its own coordinates (a button is flipped).
  static func menuOrigin(below view: NSView) -> NSPoint {
    NSPoint(x: view.bounds.minX, y: view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4)
  }

  @objc private func chooseSpace(_ sender: NSMenuItem) {
    openIn(space: sender.representedObject as? SpaceID)
  }

  @objc func copyLink(_ sender: Any?) {
    guard let tab = shownTab, let url = engine.snapshot(of: tab)?.url else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
  }

  private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
    guard event.charactersIgnoringModifiers?.lowercased() == "o" else { return false }
    switch flags {
    case [.command]:
      openIn()
      return true
    case [.command, .option]:
      showChooser(nil)
      return true
    default:
      return false
    }
  }

  // MARK: Top bar

  /// The host and the primary action. Called on every URL change and when the main window's Space may have changed.
  func refreshTopBar() {
    let url = shownTab.flatMap { engine.snapshot(of: $0)?.url }
    let target = targetSpace()
    topBar.configure(host: LittleArktCopy.host(of: url), fullURL: url?.absoluteString ?? "",
                     secure: url?.scheme == "https",
                     openLabel: LittleArktCopy.openLabel(isPopup: isPopup, spaceName: target?.title),
                     openHelp: LittleArktCopy.openHelp(isPopup: isPopup, spaceName: target?.title),
                     accent: !isPopup, swatch: target?.theme.baseColors ?? [])
  }

  public func windowDidBecomeKey(_ notification: Notification) {
    refreshTopBar()
  }

  public func windowDidEndLiveResize(_ notification: Notification) {
    onResize(window.frame.size)
  }

  // MARK: Motion

  private func run(_ transition: LittleArktTransition, completion: @escaping (Bool) -> Void) {
    lastTransition = transition
    animator.run(LittleArktMotion.targets(for: transition, reduceMotion: reduceMotion()),
                 label: "transition", in: rootView, completion: completion)
  }

  /// Opacity on the window, so the system shadow fades with the content; lift and scale on the content layer. The
  /// window's frame never moves.
  private func present(_ scene: LittleArktScene) {
    guard let layer = rootView.layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.transform = LittleArktMotion.transform(for: scene, in: rootView.bounds)
    CATransaction.commit()
    window.alphaValue = CGFloat(min(max(scene[.opacity], 0), 1))
    if scene == .rest { window.invalidateShadow() }
  }

  /// Settles the running transition at once (tests).
  func finishMotion() {
    animator.settleNow()
  }
}
