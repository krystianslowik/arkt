import AppKit
import Motion

/// Horizontal strip of Space pages (flipped). Two-finger horizontal swipes move the strip with the
/// fingers (rubber-banded past the first and last Space) and settle on a spring with the release
/// velocity (BH-035, GS-001); `go(to:)` animates keyboard and dot switches (KB-033..035).
/// Per frame only the strip's origin moves; page contents are never laid out during a swipe.
@MainActor
public final class SpacePagerView: NSView {
  /// Spring for the settle. TODO(parity): which spring preset Arc uses for Space paging.
  public static let settlePreset = SpringPreset.firmSlow

  public private(set) var pages: [NSView] = []
  /// The last settled page.
  public private(set) var index = 0
  /// The page a running settle heads to (`index` when idle).
  public private(set) var targetIndex = 0
  public private(set) var isTracking = false
  /// Pacing of the last finished interaction (swipe or `go(to:)`).
  public private(set) var lastPacing: FrameStats?

  /// Continuous page position on every strip move (1.25 = a quarter of the way from page 1 to 2).
  public var onPosition: (@MainActor (CGFloat) -> Void)?
  /// A swipe or `go(to:)` came to rest on a page (not called for `jump(to:)` or interrupted settles).
  public var onSettle: (@MainActor (Int) -> Void)?
  /// Test hook: called after `onSettle`.
  @_spi(Smoke) public var onSettleForTesting: (@MainActor (Int) -> Void)?

  let strip = NSView(frame: .zero)
  private let driver = SpringDriver()
  let pacer = FramePacer()
  private var pacerSession = 0
  private(set) var offset: CGFloat = 0
  /// Page the current drag is measured from, and the finger translation since it began.
  private var dragBase = 0
  private var translation: CGFloat = 0
  private var tracker = VelocityTracker()
  private var lock = ScrollAxisLock<NSEvent>()
  private var laidOutWidth: CGFloat = 0

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
    strip.wantsLayer = true
    strip.autoresizingMask = []
    addSubview(strip)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  private var pageWidth: CGFloat { bounds.width }
  /// Before the first layout (zero width) this is the target page.
  public var position: CGFloat {
    pageWidth > 0 ? PagingMath.position(offset: offset, pageWidth: pageWidth) : CGFloat(targetIndex)
  }

  // MARK: Pages

  /// Replaces the strip's pages and shows `index` without animating.
  public func setPages(_ newPages: [NSView], index newIndex: Int) {
    for page in pages where !newPages.contains(where: { $0 === page }) { page.removeFromSuperview() }
    for page in newPages where page.superview !== strip {
      page.autoresizingMask = []
      strip.addSubview(page)
    }
    pages = newPages
    needsLayout = true
    jump(to: newIndex)
  }

  public override func layout() {
    super.layout()
    let width = pageWidth
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    strip.frame = NSRect(x: offset, y: 0, width: CGFloat(pages.count) * width, height: bounds.height)
    for (i, page) in pages.enumerated() {
      let frame = NSRect(x: CGFloat(i) * width, y: 0, width: width, height: bounds.height)
      if page.frame != frame { page.frame = frame }
    }
    CATransaction.commit()
    if width != laidOutWidth {
      laidOutWidth = width
      // A resize mid-settle snaps to the target; the spring's distance is stale.
      if driver.isRunning {
        let target = targetIndex
        stopSettle()
        index = target
        settled(target)
      }
      if !isTracking { apply(offset: -CGFloat(index) * width) }
    }
  }

  private func apply(offset newOffset: CGFloat) {
    offset = newOffset
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    strip.setFrameOrigin(NSPoint(x: newOffset, y: 0))
    CATransaction.commit()
    updatePageVisibility()
    onPosition?(position)
  }

  /// Offscreen pages stay out of accessibility and the key loop: at rest only the current page is
  /// shown; while the strip moves, only the two pages around the position.
  private func updatePageVisibility() {
    guard !pages.isEmpty else { return }
    let last = pages.count - 1
    let visible: ClosedRange<Int>
    if isTracking || driver.isRunning || frozenTarget != nil, position.isFinite {
      let p = position
      let lower = min(max(Int(p.rounded(.down)), 0), last)
      visible = lower...min(max(Int(p.rounded(.up)), 0), last)
    } else {
      let current = min(max(index, 0), last)
      visible = current...current
    }
    for (i, page) in pages.enumerated() {
      let hidden = !visible.contains(i)
      if page.isHidden != hidden { page.isHidden = hidden }
    }
  }

  // MARK: Programmatic

  /// Shows page `target` immediately (cancels any swipe or settle; no `onSettle`).
  public func jump(to target: Int) {
    let clamped = pages.isEmpty ? 0 : min(max(target, 0), pages.count - 1)
    stopSettle()
    endPacing()
    isTracking = false
    frozenTarget = nil
    index = clamped
    targetIndex = clamped
    apply(offset: -CGFloat(clamped) * pageWidth)
  }

  /// Animates to page `target` (keyboard, Ctrl-N, dots). A running settle hands its velocity over.
  public func go(to target: Int) {
    guard !pages.isEmpty else { return }
    let clamped = min(max(target, 0), pages.count - 1)
    if isTracking { return }                               // the fingers own the strip
    frozenTarget = nil
    if !driver.isRunning && clamped == index && offset == -CGFloat(index) * pageWidth { return }
    let velocity = stopSettle()?.velocity ?? 0
    pacerSession = pacer.begin("space-key", in: self)
    settle(to: clamped, velocity: CGFloat(velocity))
  }

  /// Stops a running settle (ending its pacing) and returns the spring's last state.
  @discardableResult
  private func stopSettle() -> (value: Double, velocity: Double)? {
    guard driver.isRunning else { return nil }
    let state = driver.stop()
    endPacing()
    return state
  }

  private func endPacing() {
    if let stats = pacer.end(session: pacerSession) { lastPacing = stats }
  }

  /// Leaving the window ends any interaction (the pacer's display link would otherwise keep ticking).
  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { stopInteraction() }
  }

  /// Ends any swipe, settle and pacing where they are (window closing; the views stay in the window).
  public func stopInteraction() {
    stopSettle()
    endPacing()
    isTracking = false
    frozenTarget = nil
  }

  private func settle(to target: Int, velocity: CGFloat) {
    let velocity = velocity.isFinite ? velocity : 0
    targetIndex = target
    let session = pacerSession
    driver.animate(in: self, from: Double(offset), to: Double(-CGFloat(target) * pageWidth),
                   initialVelocity: Double(velocity), parameters: Self.settlePreset.parameters,
                   onUpdate: { [weak self] value in self?.apply(offset: CGFloat(value)) },
                   completion: { [weak self] finished in
                     guard let self, finished else { return }
                     if let stats = self.pacer.end(session: session) { self.lastPacing = stats }
                     self.index = target
                     self.updatePageVisibility()
                     self.settled(target)
                   })
  }

  private func settled(_ target: Int) {
    onSettle?(target)
    onSettleForTesting?(target)
  }

  // MARK: Tracking (scrollWheel and scripted swipes share these)
  // `@_spi(Smoke)` only limits who else may call these; the one outside caller (the app's SmokeRunner) is compiled
  // into Debug and Profile builds only.

  @_spi(Smoke) public func beginTracking() {
    guard !pages.isEmpty, pageWidth > 0 else { return }
    stopSettle()                                           // the spring hands over its current offset
    frozenTarget = nil
    let base = min(max(Int(position.rounded()), 0), pages.count - 1)
    dragBase = base
    translation = offset + CGFloat(base) * pageWidth
    tracker.reset()
    isTracking = true
    pacerSession = pacer.begin("space-swipe", in: self)
  }

  @_spi(Smoke) public func track(delta: CGFloat, at time: Double) {
    guard isTracking else { return }
    translation += delta
    tracker.add(delta: delta, at: time)
    apply(offset: PagingMath.offset(index: dragBase, translation: translation, pageWidth: pageWidth,
                                    count: pages.count))
  }

  @_spi(Smoke) public func endTracking() {
    guard isTracking else { return }
    isTracking = false
    let velocity = tracker.velocity
    let target = PagingMath.targetIndex(current: dragBase, translation: translation, velocity: velocity,
                                        pageWidth: pageWidth, count: pages.count)
    settle(to: target, velocity: velocity)
  }

  // MARK: Gesture start (fingers touch down before the axis is known)

  /// Target of a settle frozen by fingers touching down; nil when nothing is frozen.
  private(set) var frozenTarget: Int?

  /// Fingers touched the trackpad: freeze a running settle where it is, so a swipe can catch it.
  func gestureMayBegin() {
    guard !isTracking, driver.isRunning else { return }
    let target = targetIndex
    stopSettle()
    frozenTarget = target
  }

  /// The gesture turned out vertical (or ended without moving): let a frozen settle finish.
  func gestureEndedWithoutPaging() {
    guard let target = frozenTarget, !isTracking else { return }
    frozenTarget = nil
    pacerSession = pacer.begin("space-resume", in: self)
    settle(to: target, velocity: 0)
  }

  public override func scrollWheel(with event: NSEvent) {
    if event.momentumPhase != [] { return }                // the spring owns deceleration
    guard event.phase != [] else { super.scrollWheel(with: event); return }
    let starts = event.phase.contains(.began) || event.phase.contains(.mayBegin)
    let ends = event.phase.contains(.ended) || event.phase.contains(.cancelled)
    if starts { gestureMayBegin() }
    let ready = lock.feed(event, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, starts: starts, ends: ends)
    switch lock.axis {
    case .horizontal: for e in ready { handleHorizontal(e) }
    case .vertical: if !ready.isEmpty { gestureEndedWithoutPaging() }   // vertical over the title: no paging
    case .undecided: break
    }
  }

  private func handleHorizontal(_ event: NSEvent) {
    // Follow the fingers under both scroll-direction settings.
    let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
      if !isTracking { return }
      track(delta: dx, at: event.timestamp)
      endTracking()
      return
    }
    if !isTracking { beginTracking() }
    if dx != 0 { track(delta: dx, at: event.timestamp) }
  }

  // MARK: Testing

  func setPositionForTesting(_ position: CGFloat) {
    apply(offset: -position * pageWidth)
  }
}
