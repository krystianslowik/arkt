import AppKit
import Motion
import QuartzCore

/// The bar's fades as data (design/command-bar/README.md, Motion): it appears fully laid out on the first frame and
/// fades in, with no scale; it fades out in 0.1 s. Opacity only. Reduce Motion keeps both: it drops movement, and a
/// fade is not movement. The selection slide is `CommandBarSelectionMotion`.
enum CommandBarMotion {
  struct Curve: Equatable {
    var c1x: Double, c1y: Double, c2x: Double, c2y: Double
    init(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double) {
      self.c1x = c1x; self.c1y = c1y; self.c2x = c2x; self.c2y = c2y
    }
  }

  struct Fade: Equatable {
    var fromOpacity: Float
    var toOpacity: Float
    var duration: Double
    var curve: Curve
  }

  /// The strong ease-out the rest of the shell's overlays use.
  static let strongEaseOut = Curve(0.23, 1, 0.32, 1)

  static let appear = Fade(fromOpacity: 0, toOpacity: 1, duration: 0.1, curve: strongEaseOut)
  static let dismiss = Fade(fromOpacity: 1, toOpacity: 0, duration: 0.1, curve: strongEaseOut)

  static func entrance(reduceMotion: Bool) -> Fade { appear }
  static func exit(reduceMotion: Bool) -> Fade { dismiss }

  /// The layer animation for `fade`: opacity, removed on completion (the model value is set by the caller).
  static func animation(_ fade: Fade) -> CABasicAnimation {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = fade.fromOpacity
    animation.toValue = fade.toOpacity
    animation.duration = fade.duration
    animation.timingFunction = CAMediaTimingFunction(controlPoints: Float(fade.curve.c1x), Float(fade.curve.c1y),
                                                     Float(fade.curve.c2x), Float(fade.curve.c2y))
    animation.isRemovedOnCompletion = true
    return animation
  }
}

/// The selection fill and tick sliding to the new row, on an interruptible spring (design/command-bar/README.md,
/// Motion): "retargeted if the key repeats mid-flight". The indicator's frame is always the target row; this reports
/// how far behind the target it is drawn (`offset(toward:)`, applied as a layer transform, so no layout per frame).
/// Reduce Motion moves it instantly. Driven by a display link; tests present frames on their own clock with
/// `presentFrame()`.
@MainActor
final class CommandBarSelectionMotion {
  /// A key repeats quickly and the move is spatial: a firm spring that settles in about 0.15 s with no visible
  /// overshoot.
  static let parameters = SpringPreset.firmFast.parameters

  private enum Key: Hashable, Sendable { case y }

  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Off in tests, which present frames on their own clock with `presentFrame()`.
  var drivesFramesItself = true
  /// Each presented frame, and once more when the motion ends.
  var onFrame: (@MainActor () -> Void)?

  private var field = SpringField<Key>()
  private var link: CADisplayLink?

  var isRunning: Bool { !field.keys.isEmpty }

  isolated deinit { link?.invalidate() }

  /// Sends the fill from row y `oldY` to `newY`. A move in flight continues from where the fill is now, with its
  /// velocity. Reduce Motion, or a bar not on screen, moves at once.
  func move(from oldY: Double, to newY: Double, in view: NSView? = nil) {
    if reduceMotion() { settleNow(); return }
    field.retarget(.y, to: newY, from: oldY, at: now(), parameters: Self.parameters)
    if let view { startLinkIfNeeded(in: view) }
  }

  /// How far the fill is drawn from `target` (the row it is moving to), negative above it; nil when it is not moving.
  func offset(toward target: Double) -> Double? {
    field.value(of: .y, at: now()).map { $0 - target }
  }

  /// Presents the frame for now; once the spring has settled the motion ends and the fill sits on its row.
  func presentFrame() {
    if field.settledKeys(at: now()).count == field.keys.count { field = SpringField() }
    onFrame?()
    stopLinkIfIdle()
  }

  /// Ends the motion with the fill on its row (Reduce Motion, new results, the bar closing).
  func settleNow() {
    guard isRunning else { return }
    field = SpringField()
    onFrame?()
    stopLinkIfIdle()
  }

  private func startLinkIfNeeded(in view: NSView) {
    guard drivesFramesItself, link == nil else { return }
    let link = view.displayLink(target: CommandBarSelectionMotionLinkTarget(motion: self),
                                selector: #selector(CommandBarSelectionMotionLinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func stopLinkIfIdle() {
    guard !isRunning else { return }
    link?.invalidate()
    link = nil
  }
}

/// Display-link target that does not retain the motion.
@MainActor
private final class CommandBarSelectionMotionLinkTarget: NSObject {
  weak var motion: CommandBarSelectionMotion?
  init(motion: CommandBarSelectionMotion) { self.motion = motion }
  @objc func tick(_ link: CADisplayLink) {
    guard let motion else { link.invalidate(); return }
    motion.presentFrame()
  }
}
