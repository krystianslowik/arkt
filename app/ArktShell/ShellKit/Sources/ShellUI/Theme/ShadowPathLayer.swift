import QuartzCore

/// A layer whose `shadowPath` is always its own rounded shape: the bounds with `cornerRadius` corners. Without a path
/// Core Animation derives the shadow from the layer's alpha in an offscreen pass, every frame the layer moves or
/// fades (#604). The path is rebuilt whenever the bounds (or `frame`) or the corner radius change, so a resize or a
/// relayout never leaves a stale shadow behind.
///
/// The path follows the bounds' own animation: when a bounds change is not animated (actions off, as the controls set
/// their geometry), the path changes at once too; when it is, the path animates in the same transaction.
///
/// The path has circular corners. For the small radii and soft, faint shadows that use it, that is indistinguishable
/// from a layer drawn with `.continuous` corners.
final class ShadowPathLayer: CALayer {
  override var bounds: CGRect {
    didSet { if bounds != oldValue { updateShadowPath() } }
  }

  override var cornerRadius: CGFloat {
    didSet { if cornerRadius != oldValue { updateShadowPath() } }
  }

  override func action(forKey event: String) -> (any CAAction)? {
    guard event == "shadowPath" else { return super.action(forKey: event) }
    // Animate the path only when the bounds would animate now.
    guard super.action(forKey: "bounds") != nil else { return nil }
    return super.action(forKey: event)
  }

  /// The shape the shadow is cast from, for `bounds` with `cornerRadius` corners (clamped to a capsule).
  static func shadowPath(for bounds: CGRect, cornerRadius: CGFloat) -> CGPath? {
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let radius = max(0, min(cornerRadius, bounds.width / 2, bounds.height / 2))
    return CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
  }

  private func updateShadowPath() {
    shadowPath = Self.shadowPath(for: bounds, cornerRadius: cornerRadius)
  }
}
