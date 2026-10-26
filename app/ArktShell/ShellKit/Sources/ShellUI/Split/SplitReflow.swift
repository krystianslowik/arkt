import CoreGraphics
import Motion
import QuartzCore

/// The in-between frames of a pane close (#388): the panes that stay move from where they were to their new frames on
/// one spring, which runs in points along the longest edge move (`distance`), so its rest threshold is half a pixel of
/// real motion. Pure: the split container and the root view drive it and set the frames.
enum SplitReflow {
  /// Firm: settles in about a quarter second without a visible overshoot, like the other layout springs.
  static let parameters = SpringPreset.firm.parameters
  /// Reduce Motion: the frames change at once under a short crossfade.
  static let fadeDuration: CFTimeInterval = 0.15
  /// Core Animation files every transition under this key, whatever key it is added with.
  static let fadeKey = kCATransition

  /// `from` moved `progress` of the way to `to`, with every edge on the pixel grid at `scale`.
  static func frame(from: CGRect, to: CGRect, progress: CGFloat, scale: CGFloat) -> CGRect {
    let pixel = scale > 0 ? scale : 1
    func edge(_ a: CGFloat, _ b: CGFloat) -> CGFloat { ((a + (b - a) * progress) * pixel).rounded() / pixel }
    let minX = edge(from.minX, to.minX)
    let maxX = edge(from.maxX, to.maxX)
    let minY = edge(from.minY, to.minY)
    let maxY = edge(from.maxY, to.maxY)
    return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
  }

  /// The gaps between neighbouring `panes`: what the dividers cover while the panes move.
  static func dividers(between panes: [CGRect], axis: SplitAxis) -> [CGRect] {
    zip(panes, panes.dropFirst()).map { lead, next in
      switch axis {
      case .sideBySide:
        CGRect(x: lead.maxX, y: lead.minY, width: max(0, next.minX - lead.maxX), height: lead.height)
      case .stacked:
        CGRect(x: lead.minX, y: next.maxY, width: lead.width, height: max(0, lead.minY - next.maxY))
      }
    }
  }

  /// The longest distance any edge moves between `from` and `to` (pairs by index).
  static func distance(from: [CGRect], to: [CGRect]) -> Double {
    zip(from, to).reduce(0) { longest, pair in
      let (a, b) = pair
      let moves = [a.minX - b.minX, a.maxX - b.maxX, a.minY - b.minY, a.maxY - b.maxY].map { abs(Double($0)) }
      return max(longest, moves.max() ?? 0)
    }
  }

  /// The starting velocity (points per second along the new run) of a reflow that takes over from one interrupted at
  /// `progress` while moving at `velocity` (points per second along its `distance`). When both head for the same
  /// frames, what was left of the old run is the whole new one, so the panes keep their speed.
  static func carriedVelocity(_ velocity: Double, distance: Double, progress: Double, newDistance: Double) -> Double {
    let remaining = 1 - progress
    guard velocity.isFinite, distance > 0, newDistance > 0, remaining > 0.05 else { return 0 }
    return velocity / distance / remaining * newDistance
  }

  /// Reduce Motion's variant: a short crossfade over whatever `layer` shows next.
  @MainActor
  static func crossfade(_ layer: CALayer?) {
    let fade = CATransition()
    fade.type = .fade
    fade.duration = fadeDuration
    fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)   // strong ease-out
    layer?.add(fade, forKey: nil)
  }
}
