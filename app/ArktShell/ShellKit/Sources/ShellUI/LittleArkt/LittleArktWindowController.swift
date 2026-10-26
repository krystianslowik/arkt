import AppKit
import EngineAPI

/// A Little Arkt window (#314, docs/design/little-arkt.md): a small window with the brand frame around one page, whose
/// one action moves the page into a Space ("Open in <Space>", or "Open as Tab" for a popup). It hosts one engine
/// window through `engineHost`, built by `ShellWindowSet.host(for:)` for popups.
///
/// The engine owns the close: the close button, Cmd-W and Close Window animate the window out and ask the engine,
/// which closes the tabs and reports `.windowClosed`; a page that closes its popup (`window.close()`) arrives the same
/// way and fades the window out. Open in fades the window out (the no-flight path), then the main window takes the
/// tab (`EngineClient.moveTab`) and the engine closes the emptied window.
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

  var topBar: LittleArktTopBar { rootView.topBar }
  var card: ContentCardView { rootView.card }
  public var isClosed: Bool { phase == .closed }
  var isAnimating: Bool { animator.isRunning }
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
    case .closing, .handingOff:
      engineClosed = true
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
  /// and state (BH-136). The no-flight path for now: this window fades out (0.12 s), then the tab moves.
  func openIn(space: SpaceID? = nil) {
    guard phase == .open, let tab = shownTab else { return }
    phase = .handingOff
    run(.fadeOut) { [weak self] completed in
      guard completed else { return }
      self?.commitOpenIn(tab, space: space)
    }
  }

  private func commitOpenIn(_ tab: TabID, space: SpaceID?) {
    guard phase == .handingOff else { return }
    let spaceName = (space.flatMap { id in spaces().first { $0.id == id } } ?? targetSpace())?.title
    card.releaseContent()                                   // the main window's card takes the page's view
    guard onOpenIn(tab, space) else {
      phase = .open
      if let view = engine.contentView(for: tab) { card.setContent(view) }
      run(.appear) { _ in }
      return
    }
    phase = .handedOff
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
      .announcement: LittleArktCopy.announcement(spaceName: isPopup ? nil : spaceName),
      .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
    if engineClosed || engineWindow == nil { finishClose() }
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
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.minY - 4), in: anchor)
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
