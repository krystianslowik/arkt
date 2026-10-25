import AppKit
import Motion

/// Hosts the sidebar column above the content card (#102).
///
/// Docked (`isDocked`, the sidebar is shown) it is the plain column at the window's left edge: no backdrop, corner,
/// border or shadow, and the Space theme behind it is the root's own. Undocked (Cmd-S or the edge drag hid the
/// sidebar, BH-001 and BH-002) it is a floating card inset from the window's edges with its own copy of the Space theme,
/// hidden until the pointer reaches the window's left edge (BH-004, GS-018). Then it slides out over the page on a
/// spring and slides back once the pointer leaves it.
///
/// Motion is transform and opacity on this view's layer only (`SidebarRevealMotion`): the frame is set at rest, never
/// per frame, so a reveal does no layout, display or tracking-area work. The spring is interruptible: turning around
/// mid-flight starts the new spring from the presented offset and velocity. Reduce Motion fades in place instead of
/// sliding. Each reveal and conceal is measured by a `FramePacer` (`lastPacing`, the frame-time gate).
///
/// Delay and dismissal are PARITY(NEEDS-RUNTIME-CHECK RT-10): Arc's rules are unknown (BH-004).
@MainActor
public final class SidebarOverlayView: NSView {
  /// How long the pointer rests at the edge before the overlay comes out, so a pointer passing by (or reaching for
  /// the window's resize edge) does not flash it. PARITY(NEEDS-RUNTIME-CHECK RT-10).
  public static let defaultRevealDelay: Duration = .milliseconds(100)
  /// How long the pointer may be outside before the overlay goes back, so a quick overshoot does not dismiss it.
  /// PARITY(NEEDS-RUNTIME-CHECK RT-10).
  public static let defaultConcealDelay: Duration = .milliseconds(250)

  public let sidebar: SidebarContainerView
  /// Clips the backdrop and the sidebar to the overlay's rounded corners and draws its hairline border.
  let clip = NSView(frame: .zero)
  /// The Space theme behind the overlay; the root's theme background mirrors into it.
  let backdrop = ThemeBackgroundView(frame: .zero)

  /// The sidebar is shown (docked) rather than hidden. Docking or undocking is instant: Cmd-S is a keyboard action.
  public var isDocked = true {
    didSet {
      guard isDocked != oldValue else { return }
      settle(revealed: false)
      applyChrome()
    }
  }
  /// The overlay is out, or heading out.
  public private(set) var isRevealed = false
  public var isAnimating: Bool { driver.isRunning }
  /// Pacing of the last finished reveal or conceal.
  public private(set) var lastPacing: FrameStats?
  /// 0 concealed to 1 revealed, on every frame and when docking (1). The root fades the traffic lights with it.
  public var onRevealProgress: (@MainActor (CGFloat) -> Void)?
  /// Test hook: a reveal (true) or conceal (false) came to rest.
  @_spi(Smoke) public var onSettleForTesting: (@MainActor (Bool) -> Void)?

  var revealDelay = SidebarOverlayView.defaultRevealDelay
  var concealDelay = SidebarOverlayView.defaultConcealDelay
  /// Whether the pointer is over the overlay right now (a conceal waits while it is).
  lazy var pointerIsInside: @MainActor () -> Bool = { [weak self] in
    guard let self, let window = self.window else { return false }
    let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    return self.bounds.contains(point)
  }
  /// A mouse button is down: a drag out of the overlay (a tab to the page) or the edge drag that hid it.
  var mouseButtonsDown: @MainActor () -> Bool = { NSEvent.pressedMouseButtons != 0 }
  /// Tests: force the Reduce Motion variant on (true) or off (false); nil follows the system setting.
  var reduceMotionForTesting: Bool?

  /// The spring drives `offset` in points. Reduce Motion is the fade variant below, not the driver's jump.
  private lazy var driver = SpringDriver(reduceMotion: { false })
  let pacer = FramePacer()
  private var pacerSession = 0
  /// Points from the resting place: 0 revealed, `concealedOffset` fully off the window.
  private var offset: CGFloat = 0
  private var pending: Task<Void, Never>?
  private var exitArea: NSTrackingArea?

  public init(sidebar: SidebarContainerView) {
    self.sidebar = sidebar
    super.init(frame: .zero)
    wantsLayer = true
    clip.wantsLayer = true
    backdrop.isHidden = true
    for view in [backdrop, sidebar] {
      view.autoresizingMask = []
      clip.addSubview(view)
    }
    clip.autoresizingMask = []
    addSubview(clip)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var wantsUpdateLayer: Bool { true }

  var offsetForTesting: CGFloat { offset }

  private var reducesMotion: Bool {
    reduceMotionForTesting ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  private var concealedOffset: CGFloat { SidebarRevealMotion.concealedOffset(overlayFrame: frame) }

  // MARK: Layout

  public override func layout() {
    super.layout()
    clip.frame = bounds
    backdrop.frame = clip.bounds
    sidebar.frame = clip.bounds
    layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                               transform: nil)
    // A concealed overlay stays fully off the window whatever its new size.
    if !isDocked, !isRevealed, !driver.isRunning { offset = concealedOffset }
    present()
  }

  public override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsLayout = true
  }

  private var cornerRadius: CGFloat { isDocked ? 0 : ShellMetrics.standard.cardCornerRadius }

  public override func updateLayer() {
    applyChrome()
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  /// Docked: nothing of its own. Undocked: backdrop, rounded clip, hairline border (the card's) and a shadow.
  private func applyChrome() {
    guard let layer, let clipLayer = clip.layer else { return }
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    let floating = !isDocked
    backdrop.isHidden = !floating
    clipLayer.cornerRadius = cornerRadius
    clipLayer.cornerCurve = .continuous
    clipLayer.masksToBounds = floating
    clipLayer.borderWidth = floating ? 1 / max(window?.backingScaleFactor ?? 2, 1) : 0
    clipLayer.borderColor = ShellTokens.cardBorder.resolve(flavor).cgColor
    layer.shadowOpacity = floating ? 1 : 0
    layer.shadowColor = ShellTokens.sidebarOverlayShadow.resolve(flavor).cgColor
    layer.shadowRadius = SidebarRevealMotion.shadowRadius
    layer.shadowOffset = CGSize(width: 0, height: -2)
    layer.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                              transform: nil)
  }

  // MARK: Pointer (GS-018)

  /// The pointer reached the window's left edge: the overlay comes out after `revealDelay`. Ignored while docked or
  /// while a button is held (the edge drag that just hid the sidebar ends there).
  public func pointerReachedEdge() {
    guard !isDocked else { return }
    if isRevealed { cancelPending(); return }      // came back to the edge from the overlay
    guard !mouseButtonsDown() else { return }
    schedule(after: revealDelay) { [weak self] in
      guard let self, !self.isDocked, !self.mouseButtonsDown() else { return }
      self.reveal()
    }
  }

  /// The pointer left the edge strip: before the overlay came out, nothing happens; after, it goes back unless the
  /// pointer moved onto it (the strip is in the gutter left of the overlay, so leaving the window also lands here).
  public func pointerLeftEdge() {
    if isRevealed { pointerLeft() } else { cancelPending() }
  }

  /// The pointer left the overlay: it goes back after `concealDelay`, unless the pointer returned or a button is held
  /// (then it checks again when the button comes up).
  public func pointerLeft() {
    guard !isDocked, isRevealed else { return }
    schedule(after: concealDelay) { [weak self] in self?.concealIfAbandoned() }
  }

  public func pointerEntered() { if isRevealed { cancelPending() } }

  private func concealIfAbandoned() {
    guard !isDocked, isRevealed, !pointerIsInside() else { return }
    if mouseButtonsDown() {
      schedule(after: .milliseconds(100)) { [weak self] in self?.concealIfAbandoned() }
      return
    }
    conceal()
  }

  private func schedule(after delay: Duration, _ body: @escaping @MainActor () -> Void) {
    cancelPending()
    pending = Task { @MainActor [weak self] in
      if delay > .zero {
        do { try await Task.sleep(for: delay) } catch { return }
      } else {
        await Task.yield()
      }
      guard !Task.isCancelled else { return }
      self?.pending = nil
      body()
    }
  }

  private func cancelPending() {
    pending?.cancel()
    pending = nil
  }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let exitArea { removeTrackingArea(exitArea) }
    exitArea = nil
    guard !isDocked else { return }
    let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self,
                              userInfo: nil)
    addTrackingArea(area)
    exitArea = area
  }

  public override func mouseEntered(with event: NSEvent) { pointerEntered() }
  public override func mouseExited(with event: NSEvent) { pointerLeft() }

  // MARK: Motion (BH-004)

  /// Slides the overlay out on `SidebarRevealMotion.revealPreset` (or fades it in under Reduce Motion).
  public func reveal() {
    guard !isDocked else { return }
    cancelPending()
    guard !isRevealed || driver.isRunning else { return }
    isRevealed = true
    animate(to: 0, preset: SidebarRevealMotion.revealPreset)
  }

  /// Slides the overlay back off the window's left edge.
  public func conceal() {
    guard !isDocked else { return }
    cancelPending()
    guard isRevealed else { return }
    isRevealed = false
    animate(to: concealedOffset, preset: SidebarRevealMotion.concealPreset)
  }

  private func animate(to target: CGFloat, preset: SpringPreset) {
    // An interrupted spring hands over where it is and how fast it moves.
    let state = driver.stop()
    let from = state.map { CGFloat($0.value) } ?? offset
    let velocity = state?.velocity ?? 0
    offset = from
    if isHidden { isHidden = false }
    present()
    let revealing = isRevealed
    pacerSession = pacer.begin(revealing ? "sidebar-reveal" : "sidebar-conceal", in: self)
    let session = pacerSession
    driver.animate(in: self, from: Double(from), to: Double(target), initialVelocity: velocity,
                   parameters: preset.parameters,
                   onUpdate: { [weak self] value in
                     self?.offset = CGFloat(value)
                     self?.present()
                   },
                   completion: { [weak self] finished in
                     guard let self else { return }
                     if let stats = self.pacer.end(session: session) { self.lastPacing = stats }
                     guard finished else { return }
                     self.settle(revealed: revealing)
                     self.onSettleForTesting?(revealing)
                   })
  }

  /// Puts the overlay at rest: docked or revealed at its place, or concealed and hidden.
  private func settle(revealed: Bool) {
    if driver.isRunning { driver.stop() }
    pacer.end(session: pacerSession)
    cancelPending()
    isRevealed = revealed && !isDocked
    offset = isDocked || isRevealed ? 0 : concealedOffset
    isHidden = !isDocked && !isRevealed
    present()
    updateTrackingAreas()
  }

  /// Presents `offset`: a layer translation (or, under Reduce Motion, an opacity). Docked shows as is.
  private func present() {
    guard !isDocked else {
      if let layer, !layer.affineTransform().isIdentity { layer.setAffineTransform(.identity) }
      if alphaValue != 1 { alphaValue = 1 }
      onRevealProgress?(1)
      return
    }
    let p = SidebarRevealMotion.presentation(offset: offset, distance: -concealedOffset,
                                             reduceMotion: reducesMotion, scale: shellBackingScale)
    let transform = CGAffineTransform(translationX: p.translation, y: 0)
    if let layer, layer.affineTransform() != transform { layer.setAffineTransform(transform) }
    if alphaValue != p.alpha { alphaValue = p.alpha }
    onRevealProgress?(isHidden ? 0 : p.progress)
  }

  /// A backing change can reset the layer's geometry; present the current offset again.
  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    present()
  }

  /// The window closed: no display link or timer outlives it.
  func invalidate() {
    driver.stop()
    pacer.end()
    cancelPending()
  }
}
