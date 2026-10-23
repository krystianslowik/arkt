import AppKit

/// The inset, rounded card that hosts the page. The outer view carries the shadow; `clipView` clips the
/// page to the continuous-corner radius and draws the hairline border. A CALayer border is composited
/// above sublayers, so page content never covers the hairline.
@MainActor
public final class ContentCardView: NSView {
  public let clipView = NSView()
  public private(set) var contentView: NSView?
  private let metrics: ShellMetrics

  public init(metrics: ShellMetrics = .standard) {
    self.metrics = metrics
    super.init(frame: .zero)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    clipView.wantsLayer = true
    clipView.autoresizingMask = [.width, .height]
    if let clip = clipView.layer {
      clip.cornerRadius = metrics.cardCornerRadius
      clip.cornerCurve = .continuous
      clip.masksToBounds = true
    }
    addSubview(clipView)
    applyBorderWidth()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var wantsUpdateLayer: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }

  /// Removes the previous content and installs `view` filling `clipView` (autoresizing, no constraints).
  public func setContent(_ view: NSView?) {
    if contentView === view { return }
    contentView?.removeFromSuperview()
    contentView = view
    guard let view else { return }
    view.translatesAutoresizingMaskIntoConstraints = true
    view.autoresizingMask = [.width, .height]
    view.frame = clipView.bounds
    clipView.addSubview(view)
  }

  public override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsLayout = true
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    clipView.frame = bounds
    contentView?.frame = clipView.bounds
    // An explicit shadow path avoids an offscreen pass to derive the shadow shape from content alpha.
    layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: metrics.cardCornerRadius,
                               cornerHeight: metrics.cardCornerRadius, transform: nil)
    CATransaction.commit()
  }

  public override func updateLayer() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    guard let layer, let clip = clipView.layer else { return }
    layer.shadowOpacity = flavor == .dark ? 0 : 1   // Shadow token is clear in dark; skip the shadow pass
    layer.shadowColor = ShellTokens.cardShadow.resolve(flavor).cgColor
    layer.shadowRadius = 3
    layer.shadowOffset = CGSize(width: 0, height: -1)
    clip.borderColor = ShellTokens.cardBorder.resolve(flavor).cgColor
    applyBorderWidth()
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyBorderWidth()
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    applyBorderWidth()
  }

  /// One physical pixel at the current backing scale.
  private func applyBorderWidth() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    clipView.layer?.borderWidth = 1 / scale
  }
}
