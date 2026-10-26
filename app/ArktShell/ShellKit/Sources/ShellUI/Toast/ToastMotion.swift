import Motion
import QuartzCore

/// Toast motion (docs/design/alerts-sheets-toasts.md, section 7), as data. A toast rises from the edge it lives on and
/// grows into place on `springyFast`, with a short ease-out fade; it leaves the way it came, a little, and faster
/// than it came. Reduce Motion keeps the fade only. Transform and opacity on the layer; layout never animates.
enum ToastMotion {
  struct Step: Equatable {
    /// Points below the resting place: where the entrance starts, or where the exit ends.
    var offset: CGFloat
    /// Scale at that end.
    var scale: CGFloat
    /// The transform's spring; nil: the transform eases over `fadeDuration` (or does not move at all).
    var spring: SpringParameters?
    var fadeDuration: CFTimeInterval
  }

  /// Strong ease-out, as the Peek's Reduce Motion fade. A new instance each time: the class is not Sendable.
  static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }

  static func enter(reduceMotion: Bool) -> Step {
    reduceMotion ? Step(offset: 0, scale: 1, spring: nil, fadeDuration: 0.15)
      : Step(offset: 12, scale: 0.96, spring: SpringPreset.springyFast.parameters, fadeDuration: 0.16)
  }

  static func exit(reduceMotion: Bool) -> Step {
    reduceMotion ? Step(offset: 0, scale: 1, spring: nil, fadeDuration: 0.15)
      : Step(offset: 6, scale: 0.98, spring: nil, fadeDuration: 0.15)
  }

  /// The layer transform for `offset` points down and `scale` about the center of `bounds`, for a layer whose anchor
  /// point is `anchor` (AppKit anchors a view's layer at its origin) in an unflipped superlayer.
  static func transform(offset: CGFloat, scale: CGFloat, bounds: CGRect, anchor: CGPoint) -> CATransform3D {
    guard offset != 0 || scale != 1 else { return CATransform3DIdentity }
    let cx = bounds.width / 2 - anchor.x * bounds.width
    let cy = bounds.height / 2 - anchor.y * bounds.height
    var t = CATransform3DMakeTranslation(cx, cy - offset, 0)
    t = CATransform3DScale(t, scale, scale, 1)
    return CATransform3DTranslate(t, -cx, -cy, 0)
  }
}
