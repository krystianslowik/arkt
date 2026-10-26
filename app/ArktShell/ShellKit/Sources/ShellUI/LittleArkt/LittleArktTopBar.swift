import AppKit
import Motion

/// The Little Arkt top bar (docs/design/little-arkt.md, Layout): 40 pt, the traffic lights at x 12, the lock and the
/// page's host from x 80, then Copy Link and the "Open in <Space>" split button 8 pt from the right edge. The bar
/// drags the window. AppKit views with frames set directly; no Auto Layout.
@MainActor
final class LittleArktTopBar: WindowDragView {
  let lockView = NSImageView()
  let hostLabel = NSTextField(labelWithString: "")
  let copyButton = LittleArktIconButton(symbol: "link", label: LittleArktCopy.copyLink)
  let openButton = LittleArktSegmentButton()
  let chooserButton = LittleArktSegmentButton()
  private let split = NSView()
  private let divider = CALayer()

  /// The mustard fill ("Open in <Space>"), or the quiet style for a popup's "Open as Tab".
  private(set) var usesAccent = true
  private var swatchColors: [RGBA] = []

  static let hostX: CGFloat = 80
  static let rightInset: CGFloat = 8
  static let controlHeight: CGFloat = 26
  static let gap: CGFloat = 4

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    lockView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
    lockView.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
    lockView.setAccessibilityElement(false)
    hostLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    hostLabel.lineBreakMode = .byTruncatingMiddle
    hostLabel.cell?.truncatesLastVisibleLine = true
    hostLabel.setAccessibilityIdentifier(AXID.LittleArkt.host)
    copyButton.setAccessibilityIdentifier(AXID.LittleArkt.copyLink)
    copyButton.toolTip = LittleArktCopy.copyLink
    openButton.font = .systemFont(ofSize: 12, weight: .semibold)
    openButton.imagePosition = .imageLeading
    openButton.setAccessibilityIdentifier(AXID.LittleArkt.open)
    chooserButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
    chooserButton.imagePosition = .imageOnly
    chooserButton.setAccessibilityLabel(LittleArktCopy.chooseSpace)
    chooserButton.setAccessibilityHelp("Command-Option-O")
    chooserButton.toolTip = LittleArktCopy.chooseSpace
    chooserButton.setAccessibilityIdentifier(AXID.LittleArkt.chooser)
    split.wantsLayer = true
    split.layer?.cornerRadius = 8
    split.layer?.cornerCurve = .continuous
    split.layer?.masksToBounds = true
    split.layer?.addSublayer(divider)
    split.addSubview(openButton)
    split.addSubview(chooserButton)
    for view in [lockView, hostLabel, copyButton, split] as [NSView] { addSubview(view) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var wantsUpdateLayer: Bool { true }

  /// The host, its full URL as help and tooltip, and the primary action's label and swatch.
  func configure(host: String, fullURL: String, openLabel: String, openHelp: String, accent: Bool,
                 swatch: [RGBA]) {
    hostLabel.stringValue = host
    hostLabel.toolTip = fullURL
    hostLabel.setAccessibilityLabel(host.isEmpty ? "" : "\(host), secure")
    hostLabel.setAccessibilityHelp(fullURL)
    openButton.title = openLabel
    openButton.setAccessibilityHelp(openHelp)
    openButton.toolTip = openHelp
    usesAccent = accent
    swatchColors = swatch
    openButton.image = accent && !swatch.isEmpty ? Self.swatchImage(swatch) : nil
    needsDisplay = true
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let height = bounds.height
    let y = ((height - Self.controlHeight) / 2).rounded()
    let openWidth = ceil(openButton.intrinsicContentSize.width) + 20
    let chooserWidth: CGFloat = 22
    let splitWidth = openWidth + 1 + chooserWidth
    let splitX = bounds.maxX - Self.rightInset - splitWidth
    split.frame = CGRect(x: splitX, y: y, width: splitWidth, height: Self.controlHeight)
    openButton.frame = CGRect(x: 0, y: 0, width: openWidth, height: Self.controlHeight)
    chooserButton.frame = CGRect(x: openWidth + 1, y: 0, width: chooserWidth, height: Self.controlHeight)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    divider.frame = CGRect(x: openWidth, y: 0, width: 1, height: Self.controlHeight)
    CATransaction.commit()
    copyButton.frame = CGRect(x: splitX - Self.gap - Self.controlHeight, y: y, width: Self.controlHeight,
                              height: Self.controlHeight)
    lockView.frame = CGRect(x: Self.hostX, y: ((height - 12) / 2).rounded(), width: 12, height: 12)
    let labelX = lockView.frame.maxX + 7
    let labelHeight = ceil(hostLabel.intrinsicContentSize.height)
    hostLabel.frame = CGRect(x: labelX, y: ((height - labelHeight) / 2).rounded(),
                             width: max(0, copyButton.frame.minX - 8 - labelX), height: labelHeight)
  }

  override func updateLayer() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    let fill = usesAccent ? BrandTokens.accent.resolve(flavor) : ShellTokens.sidebarItemBackground.resolve(flavor)
    let text = usesAccent ? BrandTokens.onAccent.resolve(flavor) : ShellTokens.primaryText.resolve(flavor)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    split.layer?.backgroundColor = fill.cgColor
    var line = usesAccent ? BrandTokens.onAccent.resolve(flavor) : ShellTokens.primaryText.resolve(flavor)
    line.alpha = usesAccent ? 0.18 : 0.10
    divider.backgroundColor = line.cgColor
    CATransaction.commit()
    for button in [openButton, chooserButton] {
      button.textColor = text.littleArktColor
      button.hoverFill = usesAccent ? BrandTokens.accentHighlight.resolve(flavor) : nil
      button.pressedFill = usesAccent ? BrandTokens.accentPressed.resolve(flavor)
        : ShellTokens.sidebarItemBackground.resolve(flavor)
    }
    hostLabel.textColor = ShellTokens.primaryText.resolve(flavor).littleArktColor
    lockView.contentTintColor = ShellTokens.secondaryText.resolve(flavor).littleArktColor
    copyButton.contentTintColor = ShellTokens.sidebarForeground.resolve(flavor).littleArktColor
    copyButton.hoverFill = ShellTokens.sidebarItemBackground.resolve(flavor)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  /// The target Space's theme as a 10 pt swatch with 3 pt corners and a hairline (the prototype's `.sw`).
  static func swatchImage(_ colors: [RGBA]) -> NSImage {
    let size = NSSize(width: 10, height: 10)
    return NSImage(size: size, flipped: false) { rect in
      let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 3, yRadius: 3)
      let stops = colors.count == 1 ? [colors[0], colors[0]] : colors
      NSGradient(colors: stops.map { NSColor(cgColor: $0.cgColor) ?? .clear })?.draw(in: path, angle: -45)
      NSColor.black.withAlphaComponent(0.25).setStroke()
      path.lineWidth = 0.5
      path.stroke()
      return true
    }
  }
}

// MARK: - Controls

/// One segment of the split button: its own hover and pressed fill over the split's background, and a 0.97 press
/// scale (feedback, `firmFast`).
@MainActor
final class LittleArktSegmentButton: NSButton {
  var textColor: NSColor = .labelColor { didSet { applyTitleColor() } }
  var hoverFill: RGBA?
  var pressedFill: RGBA?
  private var hovering = false { didSet { refreshFill() } }
  private var tracking: NSTrackingArea?

  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false
    bezelStyle = .shadowlessSquare
    wantsLayer = true
    setButtonType(.momentaryChange)
    focusRingType = .exterior
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var title: String { didSet { applyTitleColor() } }
  override var mouseDownCanMoveWindow: Bool { false }

  private func applyTitleColor() {
    guard !title.isEmpty else { return }
    attributedTitle = NSAttributedString(string: title, attributes: [
      .font: font ?? .systemFont(ofSize: 12, weight: .semibold), .foregroundColor: textColor,
    ])
    contentTintColor = textColor
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) { hovering = true }
  override func mouseExited(with event: NSEvent) { hovering = false }

  override func mouseDown(with event: NSEvent) {
    press(true)
    super.mouseDown(with: event)                 // tracks until mouse up and sends the action
    press(false)
  }

  /// The pressed fill and a 0.97 scale about the center (AppKit keeps the layer's anchor at its corner), on a
  /// `firmFast` spring from wherever the last press left it.
  private func press(_ down: Bool) {
    guard let layer else { return }
    layer.backgroundColor = (down ? pressedFill : (hovering ? hoverFill : nil))?.cgColor
    let target = centeredScale(down ? 0.97 : 1)
    let current = layer.presentation()?.transform ?? layer.transform
    let p = SpringPreset.firmFast.parameters
    let spring = CASpringAnimation(keyPath: "transform")
    spring.mass = p.mass
    spring.stiffness = p.stiffness
    spring.damping = p.damping
    spring.fromValue = NSValue(caTransform3D: current)
    spring.toValue = NSValue(caTransform3D: target)
    spring.duration = max(p.settlingDuration(), spring.settlingDuration)
    layer.transform = target
    layer.add(spring, forKey: "press")
  }

  private func centeredScale(_ scale: CGFloat) -> CATransform3D {
    let t = CATransform3DMakeTranslation(bounds.width * (1 - scale) / 2, bounds.height * (1 - scale) / 2, 0)
    return CATransform3DScale(t, scale, scale, 1)
  }

  private func refreshFill() {
    layer?.backgroundColor = (hovering ? hoverFill : nil)?.cgColor
  }
}

/// A 26 pt icon button (Copy Link): `sidebarForeground`, `sidebarItemBackground` on hover.
@MainActor
final class LittleArktIconButton: NSButton {
  var hoverFill: RGBA?
  private var tracking: NSTrackingArea?

  init(symbol: String, label: String) {
    super.init(frame: .zero)
    isBordered = false
    wantsLayer = true
    layer?.cornerRadius = 7
    layer?.cornerCurve = .continuous
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
    imagePosition = .imageOnly
    setAccessibilityLabel(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = hoverFill?.cgColor }
  override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
}

extension RGBA {
  /// The token as an `NSColor`, for text and symbol tints.
  var littleArktColor: NSColor { NSColor(cgColor: cgColor) ?? .labelColor }
}
