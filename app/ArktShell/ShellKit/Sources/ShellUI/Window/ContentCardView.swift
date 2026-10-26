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
  /// Multiplies the hairline border's opacity. A split draws its focused pane at 1 and the others at 0.5 [I]
  /// PARITY(NEEDS-RUNTIME-CHECK RT-37).
  public var borderEmphasis: CGFloat = 1 {
    didSet { if borderEmphasis != oldValue { needsDisplay = true } }
  }
  /// The pane close (X) of a split pane (#388), above the page at the top trailing corner; nil on the single card.
  public private(set) var closeButton: SplitPaneCloseButton?
  /// A click (or VoiceOver press) on `closeButton`.
  var onClose: (@MainActor () -> Void)?
  /// False while the pane shows no page (a closed pane's placeholder): the X is hidden, out of the key loop and the
  /// accessibility tree.
  var allowsClose = true {
    didSet {
      guard allowsClose != oldValue else { return }
      if !allowsClose {
        // A hidden card gets no exit event: a reused card must not come back with a stale hover or focus.
        isHovered = false
        closeHasFocus = false
      }
      closeButton?.isHidden = !allowsClose
      refreshCloseReveal(animated: false)
    }
  }
  private var isHovered = false
  private var closeHasFocus = false
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
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Content.card)
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

  /// Forgets the content without removing it: another card mounts the same view next (Little Arkt's Open in moves
  /// the page's view to the main window), and removing it here could take it out of that card.
  public func releaseContent() {
    contentView = nil
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
    layoutCloseButton()
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
    var border = ShellTokens.cardBorder.resolve(flavor)
    border.alpha *= Double(borderEmphasis)
    clip.borderColor = border.cgColor
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

  // MARK: Pane close (#388)

  /// Adds the pane close button and the hover that shows it. Split panes only; once per card.
  func installCloseButton() {
    guard closeButton == nil else { return }
    let button = SplitPaneCloseButton(frame: .zero)
    button.target = self
    button.action = #selector(closeButtonPressed(_:))
    button.isHidden = !allowsClose
    button.onFocusChange = { [weak self] focused in
      self?.closeHasFocus = focused
      self?.refreshCloseReveal(animated: true)
    }
    addSubview(button, positioned: .above, relativeTo: clipView)          // above the page, below a toast
    closeButton = button
    // `.inVisibleRect` follows the card's frame, so a reflow moving the card every frame rebuilds nothing.
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                   owner: self, userInfo: nil))
    needsLayout = true
  }

  @objc private func closeButtonPressed(_ sender: Any?) { onClose?() }

  public override func mouseEntered(with event: NSEvent) {
    guard closeButton != nil else { return super.mouseEntered(with: event) }
    isHovered = true
    refreshCloseReveal(animated: true)
  }

  public override func mouseExited(with event: NSEvent) {
    guard closeButton != nil else { return super.mouseExited(with: event) }
    isHovered = false
    refreshCloseReveal(animated: true)
  }

  private func refreshCloseReveal(animated: Bool) {
    closeButton?.setRevealed(allowsClose && (isHovered || closeHasFocus), animated: animated)
  }

  /// Top trailing: centered in the Toolbar strip at the Toolbar's padding when it shows, else inset from the corner.
  private func layoutCloseButton() {
    guard let closeButton else { return }
    let size = SplitPaneCloseButton.size
    let top = showsToolbar ? ((ContentToolbarView.stripHeight - size) / 2).rounded() : SplitPaneCloseButton.inset
    let trailing = showsToolbar ? ContentToolbarView.horizontalPadding : SplitPaneCloseButton.inset
    let frame = CGRect(x: bounds.maxX - trailing - size, y: bounds.maxY - top - size, width: size, height: size)
    if closeButton.frame != frame { closeButton.frame = frame }
  }

  /// Centered, `ToastView.bottomInset` above the bottom edge, at most `ToastView.maxWidth` wide.
  private func layoutToast() {
    guard let toastView else { return }
    toastView.frame = toastView.frame(centeredIn: bounds)
  }

  /// One physical pixel at the current backing scale.
  private func applyBorderWidth() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    clipView.layer?.borderWidth = 1 / scale
  }
}
