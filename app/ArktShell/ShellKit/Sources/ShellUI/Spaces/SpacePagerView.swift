import AppKit
import Motion

/// A pager page that can build its on-screen rows when asked (#297). The pager puts the page where AppKit will
/// tile it (see `preparePageForDisplay`): a page parked offscreen has an empty visible rect, and rows realized
/// in that state are swept on a later pass (`_removeRowsBeingAnimatedOff`), so the table must be tiled while it
/// intersects the visible area.
@MainActor
public protocol SpacePagerPage: AnyObject {
  func constructVisibleRowsForDisplay()
}

/// Horizontal strip of Space pages (flipped). Two-finger horizontal swipes move the strip with the
/// fingers (rubber-banded past the first and last Space) and settle on a spring with the release
/// velocity (BH-035, GS-001); `go(to:)` animates keyboard and dot switches (KB-033..035).
/// Per frame only the strip's layer moves (a translation, #24): the strip view's frame stays where it was last synced,
/// so AppKit does not invalidate visible rects, tracking areas, layout or display under it on every frame.
/// AppKit's view geometry (hit testing, the coordinates every view converts events with, tracking areas, accessibility
/// frames) catches up with the layer (`syncStripFrame()`) at rest and whenever input needs it mid-motion: a hit test
/// (a click, the start of a scroll gesture, a drag), a pointer move over the pager and a backing change. The cost is
/// paid once per such input, never per display frame.
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
  /// A settle spring is running.
  var isSettling: Bool { driver.isRunning }
  /// Pacing of the last finished interaction (swipe or `go(to:)`).
  public private(set) var lastPacing: FrameStats?

  /// Continuous page position on every strip move (1.25 = a quarter of the way from page 1 to 2).
  public var onPosition: (@MainActor (CGFloat) -> Void)?
  /// A swipe or `go(to:)` came to rest on a page (not called for `jump(to:)` or interrupted settles).
  public var onSettle: (@MainActor (Int) -> Void)?
  /// Test hook: called after `onSettle`.
  @_spi(Smoke) public var onSettleForTesting: (@MainActor (Int) -> Void)?

  let strip = NSView(frame: .zero)
  /// Tests: force the Reduce Motion path on (true) or off (false) whatever the system setting; nil follows it.
  var reduceMotionForTesting: Bool?
  /// Internal so GUI tests can present settle frames at chosen times (`tick(at:)`) instead of waiting on the display.
  private(set) lazy var driver = SpringDriver(reduceMotion: { [weak self] in
    self?.reduceMotionForTesting ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  })
  private var pointerArea: NSTrackingArea?
  let pacer = FramePacer()
  private var pacerSession = 0
  private(set) var offset: CGFloat = 0
  /// Page the current drag is measured from, and the finger translation since it began.
  private var dragBase = 0
  private var translation: CGFloat = 0
  private var tracker = VelocityTracker()
  private var lock = ScrollAxisLock<NSEvent>()
  private var laidOutWidth: CGFloat = 0
  /// How many presented frames of a motion a pointer move waits between two strip syncs (#295): at 120 Hz this is
  /// about 25 ms. The first move of a settle still syncs, and a hit test never waits (a click must land on what is
  /// drawn under the pointer).
  static let pointerSyncFrameInterval = 3
  /// Presented frames of the current (or last) motion: the clock for `pointerSyncFrameInterval`.
  private var motionFrames = 0
  /// `motionFrames` at the last pointer-move sync.
  private var lastPointerSyncFrame = -SpacePagerView.pointerSyncFrameInterval
  /// Tests: how many times the strip view geometry was synced (clicks, pointer moves, rest, backing changes).
  private(set) var stripFrameSyncsForTesting = 0

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
    // A removed page leaves the set, so a new page that reuses its address is still prepared (#297).
    preparedPages.formIntersection(newPages.map(ObjectIdentifier.init))
    needsLayout = true
    jump(to: newIndex)
    // A page added mid-session (a new Space) gets its rows now, in this pass; the window-open case has no
    // width yet and is caught by the first layout below (#297).
    for i in pages.indices { preparePageForDisplay(i) }
  }

  public override func layout() {
    super.layout()
    let width = pageWidth
    // No explicit CATransaction here or in `apply`: as the outermost transaction of a display-link pass, its commit
    // would flush AppKit's whole display cycle (window layout, view display) synchronously. Backing layers of views
    // do not animate implicitly, so the implicit transaction commits these changes at the end of the pass.
    strip.frame = NSRect(x: offset, y: 0, width: CGFloat(pages.count) * width, height: bounds.height)
    strip.layer?.setAffineTransform(.identity)
    unparkPages()
    for (i, page) in pages.enumerated() {
      let frame = NSRect(x: CGFloat(i) * width, y: 0, width: width, height: bounds.height)
      if page.frame != frame { page.frame = frame }
    }
    if width != laidOutWidth {
      laidOutWidth = width
      // A resize mid-settle snaps to the target; the spring's distance is stale.
      if driver.isRunning {
        let target = targetIndex
        stopSettle()
        index = target
        settled(target)
      }
      if isTracking {
        apply(offset: PagingMath.offset(index: dragBase, translation: translation, pageWidth: width,
                                        count: pages.count))
      } else {
        apply(offset: -CGFloat(index) * width)
      }
      // First layout (window open) and resizes: the parked pages realize their visible rows here, never in a
      // switch's frames (#297). Pages with rows already are a cheap check.
      for i in pages.indices { preparePageForDisplay(i) }
    }
  }

  private func apply(offset newOffset: CGFloat) {
    offset = newOffset
    if strip.layer == nil || !(isTracking || driver.isRunning) {
      syncStripFrame()
    } else {
      motionFrames += 1
      // Pixel-aligned, so text and glyphs stay sharp mid-swipe; the final offset is page-aligned anyway.
      let scale = shellBackingScale
      let shift = ((newOffset - strip.frame.origin.x) * scale).rounded() / scale
      strip.layer?.setAffineTransform(CGAffineTransform(translationX: shift, y: 0))
    }
    updatePageVisibility()
    parkShownPagesIfNeeded()
    onPosition?(position)
  }

  /// Moves the strip view to `offset` and clears the layer translation (one implicit transaction, so the two never
  /// show apart). Called whenever the strip comes to rest and when input needs the geometry mid-motion, so hit
  /// testing, tracking areas and accessibility frames match what is on screen. A running settle or swipe carries on
  /// from the new frame: the next `apply` translates the layer relative to it. While the strip moves the origin is
  /// rounded to whole backing pixels, so the translations that follow stay pixel-aligned for the rest of the motion
  /// (#295); at rest the exact offset is kept.
  private func syncStripFrame() {
    unparkPages()
    stripFrameSyncsForTesting += 1
    var x = offset
    if isTracking || driver.isRunning {
      let scale = shellBackingScale
      x = (x * scale).rounded() / scale
    }
    if strip.frame.origin.x != x { strip.setFrameOrigin(NSPoint(x: x, y: 0)) }
    if let layer = strip.layer, !layer.affineTransform().isIdentity { layer.setAffineTransform(.identity) }
  }

  /// The strip, or a page parked in its visible slot, shows somewhere other than where its view frame says (a layer
  /// translation is applied).
  private var stripGeometryIsStale: Bool {
    guard let layer = strip.layer else { return false }
    return !layer.affineTransform().isIdentity || !parkedPages.isEmpty
  }

  /// Pages shown mid-motion that sit in the strip's visible slot in AppKit's view geometry (#415), with a layer
  /// translation that shows them at their own place in the strip.
  private var parkedPages: [NSView] = []

  /// Pages that were parked when a sync unpacked them and still need parking again: the sync is exact for the hit
  /// test or hover that asked for it, and the next presented frame restores the text drawing of #415 (#295).
  private var pagesToRepark: Set<Int> = []

  /// Shows page `i` mid-motion where AppKit draws it (#415). The strip moves on its layer, so its view frame still
  /// says where it last rested: a page that comes into view lies outside the pager in AppKit's geometry, its text
  /// fields have an empty visible rect, and AppKit draws no text there (images, which are layer contents, still
  /// show). So the page's view frame takes the slot the pager shows at rest (`-strip.frame.minX`, the slot of the
  /// page the strip rests on) and a layer translation puts it back where it belongs in the strip. Nothing else moves:
  /// the strip frame and the page the strip rests on keep their geometry, so their text stays drawn. One frame move
  /// per page a motion shows (the shown range only grows); `syncStripFrame` puts the page back.
  private func parkInVisibleSlot(_ page: NSView, at i: Int) {
    guard let layer = page.layer else { return }
    let slot = -strip.frame.origin.x
    guard page.frame.origin.x != slot else { return }
    page.setFrameOrigin(NSPoint(x: slot, y: page.frame.origin.y))
    layer.setAffineTransform(CGAffineTransform(translationX: CGFloat(i) * pageWidth - slot, y: 0))
    parkedPages.append(page)
  }

  /// Returns parked pages to their own slots and clears their translations; a page that left the strip only loses
  /// its translation.
  private func unparkPages() {
    guard !parkedPages.isEmpty else {
      if !(isTracking || driver.isRunning) { pagesToRepark.removeAll() }
      return
    }
    for page in parkedPages {
      if let i = pages.firstIndex(where: { $0 === page }) {
        page.setFrameOrigin(NSPoint(x: CGFloat(i) * pageWidth, y: page.frame.origin.y))
      }
      page.layer?.setAffineTransform(.identity)
    }
    // The sync that asked for this is exact for its hit test or hover. A motion goes on from the new frame, and its
    // next pass parks these pages again so their text keeps drawing (#415, #295).
    if isTracking || driver.isRunning {
      pagesToRepark = Set(parkedPages.compactMap { page in
        pages.firstIndex(where: { $0 === page })
      })
    } else {
      pagesToRepark.removeAll()
    }
    parkedPages.removeAll()
  }

  /// Parks the pages a sync unpacked, on the next presented frame (#295). The page that was visible before the
  /// motion is not in the set: it draws in its own frame, which the sync made current.
  private func parkShownPagesIfNeeded() {
    guard isTracking || driver.isRunning, !pagesToRepark.isEmpty else { return }
    for i in pagesToRepark where pages.indices.contains(i) && !pages[i].isHidden {
      parkInVisibleSlot(pages[i], at: i)
    }
    pagesToRepark.removeAll()
  }

  /// Pages whose visible rows were built already. Legitimately tiled rows survive being parked again; a page
  /// leaves the set only by leaving `pages` (#297).
  private var preparedPages: Set<ObjectIdentifier> = []

  /// Builds a hidden page's visible rows before a switch shows it (#297), off the frame that shows it: the strip
  /// is slid so the page intersects the visible area, the page tiles its table, and everything is put back, all
  /// inside this run of the run loop, so nothing paints and the user sees nothing. Rows built this way survive
  /// being parked again; rows built while the visible rect is empty do not. Goes through no counter: nothing
  /// becomes visible, so `updatePageVisibility`'s churn accounting is untouched.
  private func preparePageForDisplay(_ i: Int) {
    guard pages.indices.contains(i), pageWidth > 0 else { return }
    let view = pages[i]
    guard let page = view as? SpacePagerPage, view.isHidden else { return }
    guard preparedPages.insert(ObjectIdentifier(view)).inserted else { return }
    if stripGeometryIsStale { syncStripFrame() }
    let origin = strip.frame.origin
    strip.setFrameOrigin(NSPoint(x: -CGFloat(i) * pageWidth, y: origin.y))
    page.constructVisibleRowsForDisplay()
    strip.setFrameOrigin(origin)
  }

  /// Whether a hit test made for `event` needs the view geometry to match the screen. Every click, drag, cursor or
  /// accessibility hit test does; of scroll events only the first of a gesture (`mayBegin`, `began`) and discrete wheel
  /// clicks do. The changed-phase and momentum events of a gesture stream at display rate, and the pager's own
  /// `scrollWheel` handles them wherever they land; syncing on each would bring the per-frame geometry updates back.
  static func hitTestNeedsCurrentGeometry(for event: NSEvent?) -> Bool {
    guard let event, event.type == .scrollWheel else { return true }
    if event.momentumPhase != [] { return false }
    if event.phase == [] { return true }
    return event.phase.contains(.mayBegin) || event.phase.contains(.began)
  }

  /// Mid-motion, a hit test inside the pager first brings the view geometry to where the strip shows: the view it
  /// returns is the one drawn under the point, and that view converts the event with its real on-screen frame (a
  /// table picks the row under the pointer, not the row the stale frame puts there). The motion goes on.
  public override func hitTest(_ point: NSPoint) -> NSView? {
    if stripGeometryIsStale, frame.contains(point), Self.hitTestNeedsCurrentGeometry(for: window?.currentEvent) {
      syncStripFrame()
    }
    return super.hitTest(point)
  }

  /// The pager's own pointer-move area. The pager never moves while the strip does, so this area is not rebuilt per
  /// frame; the rows' areas are, after a sync.
  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerArea { removeTrackingArea(pointerArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self,
                              userInfo: nil)
    addTrackingArea(area)
    pointerArea = area
  }

  /// A pointer moving over the strip mid-motion would otherwise enter and leave rows by their stale tracking areas
  /// (hover on a row the pointer is not over): the sync rebuilds them where the rows show and resyncs hover. During a
  /// motion a moving pointer can arrive on every displayed frame, and each sync is a frame move, a tracking-area
  /// rebuild and a window-server pointer query, so after the first move of the motion at most one move per
  /// `pointerSyncFrameInterval` presented frames syncs (#295). Nothing happens at rest, where the settle already
  /// synced the exact frame. The event is not passed up the responder chain; it was generated for this view's own
  /// area.
  public override func mouseMoved(with event: NSEvent) {
    guard stripGeometryIsStale else { return }
    guard motionFrames - lastPointerSyncFrame >= Self.pointerSyncFrameInterval else { return }
    lastPointerSyncFrame = motionFrames
    syncStripFrame()
  }

  /// A backing change (the window moved to a display with another scale or color space) makes AppKit update the
  /// geometry of the layers it backs views with, which can reset the strip layer's transform before the next frame
  /// rewrites it. Syncing first leaves nothing in the transform to lose; the next frame aligns to the new scale.
  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    if stripGeometryIsStale { syncStripFrame() }
  }

  /// Horizontal on-screen translation of the strip's layer relative to its view frame (0 at rest).
  var stripLayerShiftForTesting: CGFloat { strip.layer?.affineTransform().tx ?? 0 }

  /// Pages shown since the strip started moving (nil at rest).
  private var shownWhileMoving: ClosedRange<Int>?
  /// How many times each page index was shown or hidden (tests: a moving strip must not toggle a page back and forth).
  private(set) var pageVisibilityChangesForTesting: [Int: Int] = [:]

  /// Offscreen pages stay out of accessibility and the key loop: at rest only the current page is
  /// shown; while the strip moves, the pages around the position. While it moves the shown range only grows (#24):
  /// showing or hiding a page updates the tracking areas of every row in it, and each update makes the row's host
  /// ask the window server where the pointer is, a blocking round trip, so a settle that oscillates around a page
  /// must not toggle the page it passes on every swing. An extra page in the overshoot is clipped by the pager.
  private func updatePageVisibility() {
    guard !pages.isEmpty else { return }
    let last = pages.count - 1
    let visible: ClosedRange<Int>
    if isTracking || driver.isRunning || frozenTarget != nil, position.isFinite {
      let p = position
      let lower = min(max(Int(p.rounded(.down)), 0), last)
      let around = lower...min(max(Int(p.rounded(.up)), 0), last)
      // Clamped: the page list may have shrunk since the range was recorded.
      let shown = shownWhileMoving.map {
        min($0.lowerBound, around.lowerBound)...min(max($0.upperBound, around.upperBound), last)
      }
      visible = shown ?? around
      shownWhileMoving = visible
    } else {
      // `targetIndex`, not `index`: with Reduce Motion the spring presents its final value before its completion
      // sets `index`, and showing the old page for that one call would hide and show the destination again.
      let current = min(max(targetIndex, 0), last)
      visible = current...current
      shownWhileMoving = nil
    }
    for (i, page) in pages.enumerated() {
      let hidden = !visible.contains(i)
      if page.isHidden != hidden {
        if !hidden, isTracking || driver.isRunning { parkInVisibleSlot(page, at: i) }
        page.isHidden = hidden
        pageVisibilityChangesForTesting[i, default: 0] += 1
      }
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
    // The strip passes over every page between here and the target (and the settle's overshoot can show one
    // more): build their rows now, off the animation frames (#297). Already-built pages cost a lookup.
    for i in (min(index, clamped) - 1)...(max(index, clamped) + 1) { preparePageForDisplay(i) }
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
    targetIndex = index
    syncStripFrame()
    updatePageVisibility()
  }

  private func settle(to target: Int, velocity: CGFloat) {
    let velocity = velocity.isFinite ? velocity : 0
    motionFrames = 0
    lastPointerSyncFrame = -Self.pointerSyncFrameInterval
    targetIndex = target
    let session = pacerSession
    driver.animate(in: self, from: Double(offset), to: Double(-CGFloat(target) * pageWidth),
                   initialVelocity: Double(velocity), parameters: Self.settlePreset.parameters,
                   onUpdate: { [weak self] value in self?.apply(offset: CGFloat(value)) },
                   completion: { [weak self] finished in
                     guard let self, finished else { return }
                     if let stats = self.pacer.end(session: session) { self.lastPacing = stats }
                     self.index = target
                     self.syncStripFrame()
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
    motionFrames = 0
    lastPointerSyncFrame = -Self.pointerSyncFrameInterval
    translation = PagingMath.initialTranslation(offset: offset, index: base, pageWidth: pageWidth, count: pages.count)
    tracker.reset()
    isTracking = true
    // A swipe shows the neighbours first, and the settle's overshoot can show one page past the target:
    // build two pages each way before the first moving frame (#297). Already-built pages cost a lookup.
    for i in (base - 2)...(base + 2) { preparePageForDisplay(i) }
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
    // A fling passes every page between here and the target: build their rows before the settle's frames (#297).
    for i in (min(dragBase, target) - 1)...(max(dragBase, target) + 1) { preparePageForDisplay(i) }
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
    // The frozen strip may rest under the fingers for any time, so its geometry is synced once here (a no-op when the
    // hit test of the gesture's first scroll event already did it): one frame move, the shown rows' tracking areas
    // rebuilt on AppKit's next update pass and one coalesced hover resync per host, once per touch-down.
    syncStripFrame()
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
