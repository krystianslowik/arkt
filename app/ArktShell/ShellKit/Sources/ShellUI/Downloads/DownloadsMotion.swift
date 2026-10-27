import QuartzCore

/// Downloads motion (design/downloads, Motion), as data. Transform and opacity only; the progress fill's own change is a
/// 0.5 s linear ease on every update, retargeted from where it is. Reduce Motion keeps opacity changes and jumps the
/// progress to its value.
enum DownloadsMotion {
  /// A cubic-bezier as its four control numbers, so a test can read it.
  struct Curve: Equatable {
    var x1, y1, x2, y2: Float
    var timingFunction: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: x1, y1, x2, y2) }
  }

  /// The design system's `firm` curve for rows and cards.
  static let firm = Curve(x1: 0.25, y1: 1, x2: 0.5, y2: 1)
  /// The popover's `firm-fast` curve.
  static let firmFast = Curve(x1: 0.2, y1: 1, x2: 0.4, y2: 1)
  /// Strong ease-out for removals and the swap.
  static let easeOut = Curve(x1: 0.23, y1: 1, x2: 0.32, y2: 1)

  struct Step: Equatable {
    /// Points below the resting place at the start (rows) or 0.
    var offset: CGFloat
    var scale: CGFloat
    var duration: CFTimeInterval
    var curve: Curve
  }

  /// A row, card or popover row appears: opacity 0 to 1 and 8 pt up over 0.24 s; Reduce Motion fades in 0.15 s.
  static func rowAppears(reduceMotion: Bool) -> Step {
    reduceMotion ? Step(offset: 0, scale: 1, duration: 0.15, curve: easeOut)
      : Step(offset: 8, scale: 1, duration: 0.24, curve: firm)
  }

  /// The popover: scale 0.97 to 1 with its fade over 0.22 s; Reduce Motion fades in 0.15 s.
  static func popoverAppears(reduceMotion: Bool) -> Step {
    reduceMotion ? Step(offset: 0, scale: 1, duration: 0.15, curve: easeOut)
      : Step(offset: 0, scale: 0.97, duration: 0.22, curve: firmFast)
  }

  /// A row leaves: opacity to 0 over 0.16 s ease-out (the rows below move up in step); nothing else moves.
  static let removeDuration: CFTimeInterval = 0.16
  /// The bar and the actions swap with a 0.12 s cross-fade when a download finishes.
  static let swapDuration: CFTimeInterval = 0.12
  /// A pill presses to 0.97, an icon button to 0.94, in 0.12 s.
  static let pillPressScale: CGFloat = 0.97
  static let iconPressScale: CGFloat = 0.94
  static let pressDuration: CFTimeInterval = 0.12
  /// The popover's exit fade.
  static let popoverExitDuration: CFTimeInterval = 0.10
  /// The ring and the bar ease to each new value over this long, linearly.
  static let progressDuration: CFTimeInterval = 0.5
}

/// A progress value easing linearly to its latest target. A new target starts from the value shown at that moment, so a
/// fast stream of updates never jumps back and never waits for the last ease to finish. Pure: the clock is the caller's.
struct ProgressTween: Equatable {
  private(set) var from: Double
  private(set) var to: Double
  private(set) var start: CFTimeInterval
  let duration: CFTimeInterval

  init(value: Double = 0, duration: CFTimeInterval = DownloadsMotion.progressDuration) {
    from = value; to = value; start = 0; self.duration = duration
  }

  var target: Double { to }

  /// The value shown at `now`: linear from `from` to `to`.
  func value(at now: CFTimeInterval) -> Double {
    guard duration > 0 else { return to }
    let t = min(max((now - start) / duration, 0), 1)
    return from + (to - from) * t
  }

  func isSettled(at now: CFTimeInterval) -> Bool { now - start >= duration || from == to }

  /// Eases to `target` from what is shown at `now`; under Reduce Motion it jumps. Returns the value the ease starts
  /// from.
  @discardableResult
  mutating func retarget(to target: Double, at now: CFTimeInterval, reduceMotion: Bool) -> Double {
    let shown = reduceMotion ? target : value(at: now)
    from = shown
    to = target
    start = now
    return shown
  }
}
