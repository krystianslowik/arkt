import AppKit

/// The inset, rounded card that hosts the page. The outer view carries the shadow; `clipView` clips the
/// page to the continuous-corner radius and draws the hairline border. A CALayer border is composited
/// above sublayers, so page content never covers the hairline.
@MainActor
public final class ContentCardView: NSView {
  public let clipView = NSView()
  public private(set) var contentView: NSView?
  /// Covers the page inside `clipView` (rounded corners, hairline above it) while set; the first-run empty state.
  public private(set) var emptyStateView: NSView?
  /// Back / Forward / Reload and the full URL at the top of the page while `showsToolbar` (KB-018, BH-032).
  /// Inside `clipView`, so the card's corners clip it; the page and the empty state sit below it.
  public let toolbar = ContentToolbarView(frame: .zero)
  public var showsToolbar = false {
    didSet {
      guard showsToolbar != oldValue else { return }
      toolbar.isHidden = !showsToolbar
      needsLayout = true
    }
  }
  /// Drawn above the page (a sibling of `clipView`, added after it), centered near the bottom edge.
  var toastView: ToastView? {
    didSet {
      guard toastView !== oldValue else { return }
      oldValue?.removeFromSuperview()
      if let toastView { addSubview(toastView, positioned: .above, relativeTo: nil) }
      needsLayout = true
    }
  }
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
    toolbar.isHidden = true
    toolbar.autoresizingMask = []
    clipView.addSubview(toolbar)
    applyBorderWidth()
  }

  /// Where the page goes in `clipView`: everything below the Toolbar when it shows.
  private var contentFrame: CGRect { split.contentFrame }

  private var split: CardToolbarLayout {
    CardToolbarLayout.compute(bounds: clipView.bounds, toolbarVisible: showsToolbar,
                              toolbarHeight: ContentToolbarView.height)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var wantsUpdateLayer: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }

  /// Removes the previous content and installs `view` below the Toolbar, filling the rest of `clipView`
  /// (autoresizing, no constraints).
  public func setContent(_ view: NSView?) {
    if contentView === view { return }
    contentView?.removeFromSuperview()
    contentView = view
    guard let view else { return }
    view.translatesAutoresizingMaskIntoConstraints = true
    view.autoresizingMask = [.width, .height]
    view.frame = contentFrame
    clipView.addSubview(view, positioned: .below, relativeTo: nil)
  }

  /// Installs `view` above the page and the Toolbar, filling `clipView`, or removes the current one when nil.
  public func setEmptyState(_ view: NSView?) {
    if emptyStateView === view { return }
    emptyStateView?.removeFromSuperview()
    emptyStateView = view
    guard let view else { return }
    view.translatesAutoresizingMaskIntoConstraints = true
    view.autoresizingMask = [.width, .height]
    view.frame = clipView.bounds
    clipView.addSubview(view, positioned: .above, relativeTo: nil)
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
    let split = split
    toolbar.frame = split.toolbarFrame
    contentView?.frame = split.contentFrame
    emptyStateView?.frame = clipView.bounds
    layoutToast()
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

  /// Centered, `ToastView.bottomInset` above the bottom edge, at most `ToastView.maxWidth` wide.
  private func layoutToast() {
    guard let toastView else { return }
    let size = toastView.preferredSize(maxWidth: max(0, bounds.width - 2 * ToastView.bottomInset))
    toastView.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(),
                             y: ToastView.bottomInset, width: size.width, height: size.height)
  }

  /// One physical pixel at the current backing scale.
  private func applyBorderWidth() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    clipView.layer?.borderWidth = 1 / scale
  }
}
