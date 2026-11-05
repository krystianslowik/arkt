import AppKit
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

  // MARK: Presenting a card in flight (#602)
  //
  // A reflow sets each card's real frame once, at the layout's target, so a page is resized once, not per spring
  // frame. Per frame only layer properties change: a translation moves the card, and a rounded mask the size of the
  // in-between frame crops it. Nothing is scaled: the page, the Toolbar and the close button stay at their target
  // size, anchored at the card's top leading corner, and the card's growth reveals more of them (or its shrink
  // crops them). The mask also clips the card's shadow while it moves.

  /// The rect a card whose real frame is `real` is drawn in when the spring has it at `presented`: `presented`'s top
  /// leading corner, and no larger than `real` (content beyond the real frame does not exist). `flipped`: the
  /// superview's y axis runs down, so the top is `minY`.
  static func drawnFrame(presenting presented: CGRect, in real: CGRect, flipped: Bool) -> CGRect {
    let width = min(presented.width, real.width)
    let height = min(presented.height, real.height)
    let y = flipped ? presented.minY : presented.maxY - height
    return CGRect(x: presented.minX, y: y, width: width, height: height)
  }

  /// The translation (in the superview's coordinates) that moves a card whose real frame is `real` so its top
  /// leading corner sits at `drawn`'s.
  static func translation(drawing drawn: CGRect, in real: CGRect, flipped: Bool) -> CATransform3D {
    let dy = flipped ? drawn.minY - real.minY : drawn.maxY - real.maxY
    return CATransform3DMakeTranslation(drawn.minX - real.minX, dy, 0)
  }

  /// Draws `view` (real frame `real`) in `drawn`, or at rest when `drawn` is nil: translation and rounded mask set,
  /// or cleared. Only layer properties change; the caller disables implicit actions.
  @MainActor
  static func present(_ view: NSView, in drawn: CGRect?, cornerRadius: CGFloat) {
    guard let layer = view.layer else { return }
    guard let drawn else {
      if !CATransform3DIsIdentity(layer.transform) { layer.transform = CATransform3DIdentity }
      if layer.mask != nil { layer.mask = nil }
      return
    }
    let flipped = view.superview?.isFlipped ?? false
    let transform = translation(drawing: drawn, in: view.frame, flipped: flipped)
    if !CATransform3DEqualToTransform(layer.transform, transform) { layer.transform = transform }
    let mask = layer.mask ?? {
      let mask = CALayer()
      mask.backgroundColor = CGColor(gray: 0, alpha: 1)
      mask.cornerCurve = .continuous
      layer.mask = mask
      return mask
    }()
    mask.cornerRadius = cornerRadius
    // The drawn rect moved back by the translation lands on the real frame; in the view's coordinates it is the mask's
    // frame (AppKit keeps a view's layer space equal to the view's coordinates).
    let frame = view.superview.map { view.convert(drawn.offsetBy(dx: -transform.m41, dy: -transform.m42), from: $0) }
      ?? CGRect(origin: .zero, size: drawn.size)
    if mask.frame != frame { mask.frame = frame }
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
