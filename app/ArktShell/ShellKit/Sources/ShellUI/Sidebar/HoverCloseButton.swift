import AppKit

/// Fade timing of the hover close (X).
enum HoverCloseFade {
  /// Seconds to fade from `opacity` to `target` at the speed of a full fade (0 to 1) lasting `full` seconds, so an
  /// interrupted fade covers only the distance left.
  static func duration(from opacity: CGFloat, to target: CGFloat, full: Double) -> Double {
    let start = min(max(opacity, 0), 1)
    return full * Double(abs(target - start))
  }
}

/// The hover close (X) of sidebar rows and Favorite tiles (GS-043, #82): borderless, image only, and hidden (so
/// neither hit-tested nor in the accessibility tree) until shown. A fade that interrupts another starts from the
/// opacity on screen, and only the latest fade hides the button when it ends. Reduce Motion shows and hides it at once.
@MainActor
public final class HoverCloseButton: NSButton {
  /// Length of a full fade (0 to 1 or back).
  var fadeDuration = SidebarMetrics.closeButtonFadeDuration
  /// Read on every show or hide; tests replace it.
  var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Stands in for the presentation layer when set. Nil in the product, which reads the layer.
  var presentedOpacity: CGFloat?
  /// When set, a fade hands its completion here instead of running it at the end of the real duration. Nil in the
  /// product.
  var fadeFinisher: (@MainActor (@escaping @MainActor () -> Void) -> Void)?
  /// Bumped by every show or hide. A replaced fade's completion runs early; it applies only while it is the latest.
  private var generation = 0

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    imageScaling = .scaleNone
    autoresizingMask = []
    wantsLayer = true
    isHidden = true
    alphaValue = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// The opacity on screen: a running fade's current value, else the model value. A set `presentedOpacity` wins, so a
  /// test can name the value an interrupt starts from without waiting on the render server.
  var displayedOpacity: CGFloat {
    presentedOpacity ?? layer?.presentation().map { CGFloat($0.opacity) } ?? alphaValue
  }

  /// Fades to shown or hidden. Unanimated (or with Reduce Motion, or outside a window) the state is set at once and a
  /// running fade stops.
  func setShown(_ shown: Bool, animated: Bool) {
    generation &+= 1
    let target: CGFloat = shown ? 1 : 0
    let settled = !shown && isHidden
    guard animated, window != nil, !settled, !reducesMotion() else {
      layer?.removeAnimation(forKey: "opacity")
      alphaValue = target
      isHidden = !shown
      return
    }
    let start = displayedOpacity
    let fade = generation
    isHidden = false
    let finish: @MainActor () -> Void = { [weak self] in
      guard let self, self.generation == fade, !shown else { return }
      self.isHidden = true                            // a faded-out X takes no clicks
    }
    // The model is already the previous target, and the presentation layer lags when the main thread is busy.
    // Pin the from-value to the opacity on screen so an interrupt does not jump.
    startFade(from: start, to: target, duration: HoverCloseFade.duration(from: start, to: target, full: fadeDuration),
              completion: fadeFinisher == nil ? finish : nil)
    fadeFinisher?(finish)
  }

  /// Opacity only. The model lands on `target` immediately; the animation is what is on screen until it ends.
  private func startFade(from start: CGFloat, to target: CGFloat, duration: CFTimeInterval,
                         completion: (@MainActor () -> Void)?) {
    guard let layer else {
      alphaValue = target
      completion?()
      return
    }
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = NSNumber(value: Double(start))
    animation.toValue = NSNumber(value: Double(target))
    animation.duration = duration
    animation.timingFunction = NSAnimationContext.current.timingFunction
    CATransaction.begin()
    if let completion {
      CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
    }
    layer.add(animation, forKey: "opacity")
    CATransaction.setDisableActions(true)
    alphaValue = target
    CATransaction.commit()
  }
}
