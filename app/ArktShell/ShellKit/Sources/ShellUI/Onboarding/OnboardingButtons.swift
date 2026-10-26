import AppKit

/// The website's pills (section 4): the mustard primary, the glass secondary, and the quiet text buttons of the
/// footer. A real `NSButton`, so Return (the primary's key equivalent), Space, VoiceOver's press and the tab loop
/// work as for any button; the cell draws nothing and the layers draw the pill.
@MainActor
final class PillButton: NSButton {
  enum Style { case primary, glass, quiet }

  let style: Style
  var appearanceModel: OnboardingAppearance { didSet { if appearanceModel != oldValue { restyle() } } }
  var onPress: (@MainActor () -> Void)?

  private let body = CALayer()
  private let edge = CALayer()
  private let label = CALayer()
  private let ring = CAShapeLayer()
  private var hovering = false
  private var pressing = false
  private var showsFocus = false
  private var tracking: NSTrackingArea?

  static let height: CGFloat = 50
  static let quietHeight: CGFloat = 34
  static let minimumWidth: CGFloat = 132

  init(style: Style, title: String, appearance: OnboardingAppearance) {
    self.style = style
    self.appearanceModel = appearance
    super.init(frame: .zero)
    let cell = PillButtonCell()
    cell.owner = self
    self.cell = cell
    self.title = title
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    focusRingType = .none
    target = self
    action = #selector(pressed(_:))
    wantsLayer = true
    layer?.masksToBounds = false
    body.masksToBounds = false
    edge.borderWidth = 0
    ring.fillColor = nil
    ring.opacity = 0
    for sublayer in [ring, body] { layer?.addSublayer(sublayer) }
    body.addSublayer(edge)
    body.addSublayer(label)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var title: String { didSet { restyle() } }
  override var isEnabled: Bool { didSet { restyle() } }
  override var mouseDownCanMoveWindow: Bool { false }
  override var acceptsFirstResponder: Bool { isEnabled }
  override var canBecomeKeyView: Bool { isEnabled && !isHidden }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {}

  @objc private func pressed(_ sender: Any?) { onPress?() }

  // MARK: Size

  private var titleSize: NSSize {
    BrandTextRenderer.measure(BrandType.attributed(title, role: style == .quiet ? .quiet : .button, color: .black),
                              maxWidth: 10_000)
  }

  override var intrinsicContentSize: NSSize {
    switch style {
    case .primary, .glass:
      NSSize(width: max(Self.minimumWidth, ceil(titleSize.width) + 52), height: Self.height)
    case .quiet:
      NSSize(width: ceil(titleSize.width) + 28, height: Self.quietHeight)
    }
  }

  // MARK: Drawing

  private var fillColor: NSColor {
    let a = appearanceModel
    switch style {
    case .primary: return pressing ? a.accentPressed : (hovering ? a.accentHighlight : a.accent)
    case .glass: return pressing ? a.controlFillPressed : (hovering ? a.glassFillHover : a.glassFill)
    case .quiet: return pressing ? a.controlFillPressed : (hovering ? a.controlFill : .clear)
    }
  }

  private var titleColor: NSColor {
    switch style {
    case .primary: appearanceModel.onAccent
    case .glass: appearanceModel.textPrimary
    case .quiet: hovering || pressing ? appearanceModel.textPrimary : appearanceModel.textSecondary
    }
  }

  private func restyle() {
    let scale = window?.backingScaleFactor ?? 2
    let role: BrandType.Role = style == .quiet ? .quiet : .button
    let text = BrandType.attributed(title, role: role, color: titleColor)
    let size = titleSize
    let image = BrandTextRenderer.image(text, size: size, halo: [])
    OnboardingMotion.set {
      BrandTextRenderer.apply(image, to: label, glyphSize: size, halo: false, scale: scale)
      edge.borderColor = appearanceModel.glassEdge.cgColor
      edge.borderWidth = style == .glass ? appearanceModel.glassEdgeWidth : 0
      ring.strokeColor = appearanceModel.focusRing.cgColor
      ring.lineWidth = appearanceModel.focusRingWidth
      layer?.opacity = isEnabled ? 1 : 0.4
    }
    updateFill(animated: false)
    needsLayout = true
  }

  private func updateFill(animated: Bool) {
    let color = fillColor.cgColor
    if animated {
      OnboardingMotion.animate(body, "backgroundColor", to: color, duration: 0.15)
    } else {
      OnboardingMotion.set { body.backgroundColor = color }
    }
    restyleTitleColor()
  }

  private func restyleTitleColor() {
    guard style == .quiet else { return }
    let scale = window?.backingScaleFactor ?? 2
    let size = titleSize
    let image = BrandTextRenderer.image(BrandType.attributed(title, role: .quiet, color: titleColor), size: size,
                                        halo: [])
    OnboardingMotion.set { BrandTextRenderer.apply(image, to: label, glyphSize: size, halo: false, scale: scale) }
  }

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      body.bounds = bounds
      body.position = CGPoint(x: bounds.midX, y: bounds.midY)
      body.cornerRadius = bounds.height / 2
      edge.frame = body.bounds
      edge.cornerRadius = bounds.height / 2
      let size = label.bounds.size
      label.anchorPoint = .zero
      label.position = CGPoint(x: ((bounds.width - size.width) / 2).rounded(),
                               y: ((bounds.height - size.height) / 2).rounded())
      let outset = 3 + appearanceModel.focusRingWidth / 2
      let ringRect = bounds.insetBy(dx: -outset, dy: -outset)
      ring.path = CGPath(roundedRect: ringRect, cornerWidth: ringRect.height / 2, cornerHeight: ringRect.height / 2,
                         transform: nil)
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }

  // MARK: Hover, press, focus

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    guard isEnabled else { return }
    hovering = true
    updateFill(animated: true)
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    updateFill(animated: true)
  }

  /// The cell's highlight follows the pointer while it is down: press scale 0.97 for 160 ms ease-out, and under
  /// Reduce Motion only the pressed fill (M9).
  fileprivate func setPressed(_ pressed: Bool) {
    guard isEnabled, pressed != pressing else { return }
    pressing = pressed
    updateFill(animated: false)
    guard !appearanceModel.reduceMotion else { return }
    let scale = pressed ? 0.97 : 1
    OnboardingMotion.animate(body, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)),
                             duration: 0.16)
  }

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { setFocusShown(true) }
    return became
  }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { setFocusShown(false) }
    return resigned
  }

  private func setFocusShown(_ shown: Bool) {
    showsFocus = shown
    OnboardingMotion.animate(ring, "opacity", to: Float(shown ? 1 : 0), duration: 0.12)
  }

  override func keyDown(with event: NSEvent) {
    // Space presses the focused button (section 10); Return belongs to the default button.
    if event.charactersIgnoringModifiers == " " {
      performClick(nil)
      return
    }
    super.keyDown(with: event)
  }
}

/// Draws nothing (the button's layers draw the pill) and reports highlight changes to its button.
@MainActor
final class PillButtonCell: NSButtonCell {
  weak var owner: PillButton?

  override var isHighlighted: Bool {
    didSet { owner?.setPressed(isHighlighted) }
  }

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
  override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {}
}
