import AppKit
import Motion
import QuartzCore

/// Where the rows draw while the Clear control above Today archives them (#413, design/clear-today-tabs): every
/// archived row collapses upward at once (it fades, lifts 6 pt and shrinks to 0.38 of its height from its top edge),
/// and every row below follows by the height already gone, so the kept rows slide up with the same spring. Reduce
/// Motion fades the archived rows in place and moves nothing. Pure math over row indexes, like `FolderMotionLayout`;
/// the outline applies it as layer transforms, never frames.
enum TodayClearLayout {
  /// How far an archived row lifts as it leaves, in points.
  static let lift: CGFloat = 6
  /// The height an archived row shrinks to, as a share of its own, about its top edge.
  static let endScaleY: CGFloat = 0.38

  /// Adds the exit to `row`'s style. `gone` runs from 0 (every row in place) to 1 (the archived rows collapsed); a
  /// spring may overshoot it a little, which moves the rows but never draws a negative opacity or an inverted row.
  /// `block` holds the archived rows; `moves` is false under Reduce Motion.
  static func apply(to style: inout FolderMotionLayout.RowStyle, atRow row: Int, block: FolderMotionLayout.Block,
                    gone: Double, moves: Bool) {
    let shown = CGFloat(1 - min(max(gone, 0), 1))
    let above = block.countAbove(row)
    let archived = above < block.rows.count && block.rows[above] == row
    if archived { style.alpha *= shown }
    guard moves else { return }
    style.offsetY -= CGFloat(gone) * block.goneAbove[above]
    if archived {
      style.offsetY -= CGFloat(gone) * lift
      style.scaleY *= 1 - (1 - endScaleY) * (1 - shown)
    }
  }
}

/// The one spring of a Clear (#413): the archived rows leave together (`gone` 0 to 1), or come back together on Undo
/// (1 to 0), on the `firm` preset and the outline's display link. Reduce Motion replaces the spring with an opacity
/// fade of `FadeDuration.standard` on the system ease-out. A page not on screen does not move: a leave completes at
/// once and a return draws at rest.
@MainActor
final class TodayClearMotion {
  static let parameters = SpringPreset.firm.parameters
  /// `gone` runs in thousandths on the spring, so `SpringRun`'s point thresholds settle it finely enough.
  private static let springScale = 1000.0

  enum Direction { case leaving, returning }

  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Off in tests, which present frames on their own clock with `presentFrame()`.
  var drivesFramesItself = true
  /// Each frame, and once more at rest when the motion ends.
  var onFrame: (@MainActor () -> Void)?

  /// The rows in motion; empty at rest.
  private(set) var rows: Set<NodeID> = [] { didSet { rowsGeneration &+= 1 } }
  /// Moves on every change of `rows`, so the outline recaptures their row indexes only then.
  private(set) var rowsGeneration = 0
  private(set) var direction: Direction?
  /// Captured when the motion starts: a fade in place instead of the spring.
  private(set) var fades = false
  private var run: SpringRun?
  private var start: CFTimeInterval = 0
  private var completion: (@MainActor () -> Void)?
  private var link: CADisplayLink?

  var isRunning: Bool { direction != nil }

  isolated deinit { link?.invalidate() }

  /// Whether the motion may run in `view`: on screen. Reduce Motion still fades.
  func canAnimate(in view: NSView) -> Bool {
    guard let window = view.window, window.isVisible else { return false }
    return !view.isHiddenOrHasHiddenAncestor
  }

  /// Sends `rows` off (`.leaving`) or brings them back (`.returning`). `completion` runs once the motion ends, after
  /// the last frame at rest; off screen it runs at once.
  func start(_ direction: Direction, rows: Set<NodeID>, in view: NSView,
             completion: (@MainActor () -> Void)? = nil) {
    guard !rows.isEmpty, canAnimate(in: view) else {
      completion?()
      return
    }
    self.rows = rows
    self.direction = direction
    self.completion = completion
    fades = reduceMotion()
    start = now()
    run = fades ? nil : SpringRun(from: direction == .leaving ? 0 : Self.springScale,
                                  to: direction == .leaving ? Self.springScale : 0,
                                  initialVelocity: 0, parameters: Self.parameters, start: start)
    startLinkIfNeeded(in: view)
    onFrame?()
  }

  /// How far the rows have gone now: 0 in place, 1 collapsed; nil at rest.
  func gone() -> Double? {
    guard let direction else { return nil }
    let t = now()
    if let run { return run.frame(at: t).value / Self.springScale }
    let faded = MotionCurve.systemEaseOut.value(at: (t - start) / FadeDuration.standard)
    return direction == .leaving ? faded : 1 - faded
  }

  private var isSettled: Bool {
    let t = now()
    if let run { return run.frame(at: t).done }
    return t - start >= FadeDuration.standard
  }

  /// Presents the frame for now; a settled motion ends.
  func presentFrame() {
    guard isRunning else { return }
    if isSettled { finish() } else { onFrame?() }
  }

  /// Ends the motion at its target now.
  func settleNow() {
    guard isRunning else { return }
    finish()
  }

  /// Every row draws at rest first, then `completion` runs, in the same turn: a leave's rows leave the outline in the
  /// same Core Animation transaction that resets the rows below, so nothing jumps.
  private func finish() {
    let done = completion
    direction = nil
    run = nil
    completion = nil
    rows = []
    link?.invalidate()
    link = nil
    onFrame?()
    done?()
  }

  private func startLinkIfNeeded(in view: NSView) {
    guard drivesFramesItself, link == nil else { return }
    let link = view.displayLink(target: TodayClearLinkTarget(motion: self),
                                selector: #selector(TodayClearLinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }
}

/// Display-link target that does not retain the motion.
@MainActor
private final class TodayClearLinkTarget: NSObject {
  weak var motion: TodayClearMotion?
  init(motion: TodayClearMotion) { self.motion = motion }
  @objc func tick(_ link: CADisplayLink) {
    guard let motion else { link.invalidate(); return }
    motion.presentFrame()
  }
}
