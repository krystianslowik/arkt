import AppKit
import QuartzCore

/// What a progress view does with a new value: the tween it started and the animation it added, for tests and for the
/// ring to read.
struct ProgressStep: Equatable {
  var from: Double
  var to: Double
  var animated: Bool
}

/// The 3 pt bar of an active row: a track and a graphite fill whose layer scales along x from its leading edge, so the
/// change is a transform (design/downloads, Motion). Every update eases to the new value in 0.5 s, linearly, from where
/// it is; Reduce Motion jumps. A progress indicator to VoiceOver, with min, max and value.
@MainActor
final class ProgressBarView: NSView {
  private let track = CALayer()
  private let fill = CALayer()
  private(set) var tween = ProgressTween()
  /// The clock the tween reads; tests give it a number they step by hand.
  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The last value set, nil for an unknown size (no fill).
  private(set) var fraction: Double?
  private(set) var lastStep: ProgressStep?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    for layer in [track, fill] {
      layer.cornerCurve = .continuous
      self.layer?.addSublayer(layer)
    }
    fill.anchorPoint = CGPoint(x: 0, y: 0.5)
    setAccessibilityElement(true)
    setAccessibilityRole(.progressIndicator)
    setAccessibilityMinValue(0)
    setAccessibilityMaxValue(1)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  /// The value shown now (the tween at the clock), for tests.
  var shownFraction: Double { tween.value(at: now()) }

  /// Sets the progress. A nil fraction shows the track alone.
  func setFraction(_ value: Double?) {
    fraction = value
    let target = min(max(value ?? 0, 0), 1)
    let from = tween.retarget(to: target, at: now(), reduceMotion: reduceMotion())
    let animated = !reduceMotion() && window != nil && from != target
    lastStep = ProgressStep(from: from, to: target, animated: animated)
    let transform = CATransform3DMakeScale(CGFloat(target), 1, 1)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fill.transform = transform
    CATransaction.commit()
    fill.removeAnimation(forKey: "progress")
    if animated {
      let animation = CABasicAnimation(keyPath: "transform.scale.x")
      animation.fromValue = from
      animation.toValue = target
      animation.duration = DownloadsMotion.progressDuration
      animation.timingFunction = CAMediaTimingFunction(name: .linear)
      fill.add(animation, forKey: "progress")
    }
    setAccessibilityValue(target)
    setAccessibilityValueDescription(value.map { "\(Int($0 * 100)) percent" } ?? "Downloading")
  }

  /// The animation on the fill, for tests.
  var fillAnimation: CABasicAnimation? { fill.animation(forKey: "progress") as? CABasicAnimation }

  private func restyle() {
    let flavor = archiveFlavor
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    track.backgroundColor = DownloadsTokens.progressTrack.resolve(flavor).cgColor
    fill.backgroundColor = DownloadsTokens.progressFill.resolve(flavor).cgColor
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    track.frame = bounds
    track.cornerRadius = bounds.height / 2
    fill.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    fill.position = CGPoint(x: 0, y: bounds.midY)
    fill.cornerRadius = bounds.height / 2
    CATransaction.commit()
  }
}

/// The ring on the Library button: a track circle and a graphite arc that fills clockwise from twelve o'clock, 2.2 pt
/// wide. The arc's `strokeEnd` eases to each new value in 0.5 s, linearly, from where it is; Reduce Motion jumps.
@MainActor
final class ProgressRing {
  /// The layer to add to the button; it holds the track and the arc.
  let layer = CALayer()
  private let track = CAShapeLayer()
  private let arc = CAShapeLayer()
  private(set) var tween = ProgressTween()
  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  private(set) var lastStep: ProgressStep?
  /// Whether the arc is on screen now (a ring has one only while something downloads or just finished).
  var showsRing = false {
    didSet {
      guard showsRing != oldValue else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      track.opacity = showsRing ? 1 : 0
      arc.opacity = showsRing ? 1 : 0
      CATransaction.commit()
    }
  }

  init() {
    for shape in [track, arc] {
      shape.fillColor = nil
      shape.lineWidth = DownloadsMetrics.ringLineWidth
      shape.opacity = 0
      layer.addSublayer(shape)
    }
    arc.lineCap = .round
    arc.strokeEnd = 0
  }

  /// Frames and the circle, once the layer has its size.
  func layoutRing() {
    let inset = DownloadsMetrics.ringLineWidth / 2
    let bounds = layer.bounds
    let rect = bounds.insetBy(dx: inset, dy: inset)
    // Twelve o'clock, clockwise: a path that starts at the top and goes around the way the arc fills.
    let path = CGMutablePath()
    path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .pi / 2,
                endAngle: .pi / 2 - 2 * .pi, clockwise: true)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for shape in [track, arc] {
      shape.frame = bounds
      shape.path = path
    }
    CATransaction.commit()
  }

  func restyle(flavor: ThemeFlavor) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    track.strokeColor = DownloadsTokens.progressTrack.resolve(flavor).cgColor
    arc.strokeColor = DownloadsTokens.progressFill.resolve(flavor).cgColor
    CATransaction.commit()
  }

  var shownFraction: Double { tween.value(at: now()) }

  var arcAnimation: CABasicAnimation? { arc.animation(forKey: "progress") as? CABasicAnimation }
  /// The arc's resting stroke end (the model value), for tests.
  var arcStrokeEnd: Double { Double(arc.strokeEnd) }

  func setFraction(_ value: Double, attached: Bool) {
    let target = min(max(value, 0), 1)
    let from = tween.retarget(to: target, at: now(), reduceMotion: reduceMotion())
    let animated = !reduceMotion() && attached && from != target
    lastStep = ProgressStep(from: from, to: target, animated: animated)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    arc.strokeEnd = CGFloat(target)
    CATransaction.commit()
    arc.removeAnimation(forKey: "progress")
    if animated {
      let animation = CABasicAnimation(keyPath: "strokeEnd")
      animation.fromValue = from
      animation.toValue = target
      animation.duration = DownloadsMotion.progressDuration
      animation.timingFunction = CAMediaTimingFunction(name: .linear)
      arc.add(animation, forKey: "progress")
    }
  }
}
