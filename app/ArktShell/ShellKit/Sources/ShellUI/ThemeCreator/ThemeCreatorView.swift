import AppKit
import Motion

/// The Space theme creator popover (#410, design/theme-creator/README.md): a 300 pt porcelain or graphite surface
/// with an arrow on its leading edge, holding the header (Space name and colour-count button), the colour pad, the
/// Texture row with its amount slider, and the Opacity slider. No primary action: every change applies live.
///
/// AppKit and Core Animation, frames set directly. The controller (`ThemeCreatorController`) owns the state; this
/// view lays it out and reports input.
@MainActor
final class ThemeCreatorView: NSView {
  let titleLabel = NSTextField(labelWithString: "")
  let countButton = ThemeColourCountButton(frame: .zero)
  let pad = ThemePadView(frame: .zero)
  let textureLabel = NSTextField(labelWithString: "Texture")
  let swatches = ThemeTextureSwatchesView(frame: .zero)
  let amountSlider = ThemeSliderView(label: "Texture amount", identifier: AXID.ThemeCreator.amount)
  let opacityLabel = NSTextField(labelWithString: "Opacity")
  let opacitySlider = ThemeSliderView(label: "Opacity", identifier: AXID.ThemeCreator.opacity)
  /// Escape, from any control.
  var onCancel: (() -> Void)?

  /// Focus rings show once the keyboard is used in the popover.
  private(set) var keyboardFocusVisible = false
  private let surface = CAShapeLayer()
  private let dropShadow = CAShapeLayer()
  private let contactShadow = CAShapeLayer()
  private let amountGradient = CAGradientLayer()
  private let opacityChecker = CALayer()
  private let opacityGradient = CAGradientLayer()
  private(set) var flavor: ThemeFlavor = .light

  override init(frame: NSRect) {
    super.init(frame: NSRect(x: frame.minX, y: frame.minY, width: ThemeCreatorMetrics.width,
                             height: ThemeCreatorMetrics.height))
    wantsLayer = true
    layer?.masksToBounds = false
    for sublayer in [contactShadow, dropShadow, surface] {
      sublayer.actions = ["path": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "shadowPath": NSNull()]
      layer?.addSublayer(sublayer)
    }
    surface.lineWidth = 0.5
    dropShadow.fillColor = CGColor.black
    contactShadow.fillColor = CGColor.black
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail
    for label in [textureLabel, opacityLabel] { label.font = .systemFont(ofSize: 12, weight: .semibold) }
    for label in [titleLabel, textureLabel, opacityLabel] {
      label.setAccessibilityElement(label === titleLabel)
      addSubview(label)
    }
    let amountMask = CAGradientLayer()
    amountMask.startPoint = CGPoint(x: 0, y: 0.5)
    amountMask.endPoint = CGPoint(x: 1, y: 0.5)
    amountMask.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)]
    amountGradient.mask = amountMask
    amountSlider.trackContent.addSublayer(amountGradient)
    opacityGradient.startPoint = CGPoint(x: 0, y: 0.5)
    opacityGradient.endPoint = CGPoint(x: 1, y: 0.5)
    opacitySlider.trackContent.addSublayer(opacityChecker)
    opacitySlider.trackContent.addSublayer(opacityGradient)
    for view in [countButton, pad, swatches, amountSlider, opacitySlider] as [NSView] { addSubview(view) }
    for control in [countButton, swatches, amountSlider, opacitySlider] as [ThemeFocusableView] { wireFocus(control) }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilitySubrole(.dialog)
    setAccessibilityLabel("Space Theme")
    setAccessibilityIdentifier(AXID.ThemeCreator.popover)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  /// Every control shares the focus-ring rule and Escape.
  func wireFocus(_ control: ThemeFocusableView) {
    control.focusVisible = { [weak self] in self?.keyboardFocusVisible ?? false }
    control.onCancel = { [weak self] in self?.onCancel?() }
    control.onKeyboardUse = { [weak self] in self?.keyboardWasUsed() }
  }

  private func keyboardWasUsed() {
    guard !keyboardFocusVisible else { return }
    keyboardFocusVisible = true
    (window?.firstResponder as? ThemeFocusableView)?.refreshFocusRing()
  }

  override func cancelOperation(_ sender: Any?) { onCancel?() }

  /// The popover does not pass clicks through to the window behind it.
  override func mouseDown(with event: NSEvent) {}

  // MARK: - Layout

  override func layout() {
    super.layout()
    let m = ThemeCreatorMetrics.self
    let contentWidth = bounds.width - 2 * m.padding
    var y = m.padding
    let titleHeight = titleLabel.intrinsicContentSize.height
    titleLabel.frame = NSRect(x: m.padding + m.titleInsetX, y: y + (m.headerHeight - titleHeight) / 2,
                              width: contentWidth - m.titleInsetX - m.buttonSize.width - 8, height: titleHeight)
    countButton.frame = NSRect(x: bounds.width - m.padding - 2 - m.buttonSize.width,
                               y: y + (m.headerHeight - m.buttonSize.height) / 2, width: m.buttonSize.width,
                               height: m.buttonSize.height)
    y += m.headerHeight + m.headerGap
    pad.frame = NSRect(x: m.padding, y: y, width: ThemePad.size.width, height: ThemePad.size.height)
    y += ThemePad.size.height
    let controlX = m.padding + m.controlInsetX
    let controlWidth = contentWidth - 2 * m.controlInsetX
    for (label, slider, trailing) in [(textureLabel, amountSlider, swatches as NSView?),
                                      (opacityLabel, opacitySlider, nil)] {
      y += m.sectionGap
      let labelHeight = label.intrinsicContentSize.height
      label.frame = NSRect(x: controlX, y: y + (m.labelRow - labelHeight) / 2, width: 120, height: labelHeight)
      if let trailing {
        let width = ThemeTextureSwatchesView.width
        trailing.frame = NSRect(x: controlX + controlWidth - width, y: y - 4, width: width, height: m.labelRow + 8)
      }
      y += m.labelRow + m.labelGap
      slider.frame = NSRect(x: controlX, y: y, width: controlWidth, height: m.sliderHeight)
      y += m.sliderHeight
    }
    layoutSurface()
    layoutTrackPreviews()
  }

  private func layoutSurface() {
    let path = Self.surfacePath(size: bounds.size)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in [surface, dropShadow, contactShadow] {
      sublayer.frame = bounds
      sublayer.path = path
    }
    let token = ShellTokens.overlayShadow
    dropShadow.shadowPath = path
    dropShadow.shadowColor = token.color.resolve(flavor).cgColor
    dropShadow.shadowOpacity = 1
    dropShadow.shadowRadius = token.radius
    dropShadow.shadowOffset = CGSize(width: 0, height: token.offsetY)
    contactShadow.shadowPath = path
    contactShadow.shadowColor = token.contactColor.resolve(flavor).cgColor
    contactShadow.shadowOpacity = 1
    contactShadow.shadowRadius = token.contactRadius
    contactShadow.shadowOffset = CGSize(width: 0, height: token.contactOffsetY)
    let fill = ShellTokens.themePopoverSurface.resolve(flavor).cgColor
    surface.fillColor = fill
    surface.strokeColor = ShellTokens.overlayEdge.resolve(flavor).cgColor
    // The shadow casters are hidden under the surface; only their shadows show.
    dropShadow.fillColor = fill
    contactShadow.fillColor = fill
    CATransaction.commit()
  }

  /// A rounded rectangle with the arrow on its leading edge, level with the header.
  static func surfacePath(size: CGSize) -> CGPath {
    let m = ThemeCreatorMetrics.self
    let r = m.cornerRadius
    let arrowY = m.arrowCenterY, half = m.arrowHalfBase, tip = m.arrowDepth
    let path = CGMutablePath()
    path.move(to: CGPoint(x: r, y: 0))
    path.addLine(to: CGPoint(x: size.width - r, y: 0))
    path.addArc(tangent1End: CGPoint(x: size.width, y: 0), tangent2End: CGPoint(x: size.width, y: r), radius: r)
    path.addLine(to: CGPoint(x: size.width, y: size.height - r))
    path.addArc(tangent1End: CGPoint(x: size.width, y: size.height),
                tangent2End: CGPoint(x: size.width - r, y: size.height), radius: r)
    path.addLine(to: CGPoint(x: r, y: size.height))
    path.addArc(tangent1End: CGPoint(x: 0, y: size.height), tangent2End: CGPoint(x: 0, y: size.height - r), radius: r)
    path.addLine(to: CGPoint(x: 0, y: arrowY + half))
    // The arrow: softened at its tip.
    path.addQuadCurve(to: CGPoint(x: -tip, y: arrowY), control: CGPoint(x: -tip * 0.55, y: arrowY + half * 0.3))
    path.addQuadCurve(to: CGPoint(x: 0, y: arrowY - half), control: CGPoint(x: -tip * 0.55, y: arrowY - half * 0.3))
    path.addLine(to: CGPoint(x: 0, y: r))
    path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
    path.closeSubpath()
    return path
  }

  private func layoutTrackPreviews() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in [amountGradient, opacityChecker, opacityGradient] {
      sublayer.frame = amountSlider.trackContent.bounds
    }
    amountGradient.mask?.frame = amountGradient.bounds
    CATransaction.commit()
  }

  // MARK: - State

  /// Shows `model` in `flavor`. `animated`: dots added or removed animate (not a drag frame).
  func apply(_ model: ThemeCreatorModel, title: String, flavor: ThemeFlavor, animated: Bool) {
    let flavorChanged = flavor != self.flavor
    self.flavor = flavor
    titleLabel.stringValue = title
    setAccessibilityTitle(title)
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    for label in [textureLabel, opacityLabel] { label.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor() }
    let stored = model.theme.baseColors
    let dotColors = model.dots.map(\.color)
    let surfaceColor = ShellTokens.themePopoverSurface.resolve(flavor)
    countButton.update(colors: dotColors, flavor: flavor, surface: surfaceColor, animated: animated)
    pad.update(points: model.dots.map(\.point), colors: dotColors, animated: animated)
    swatches.update(selected: model.theme.textureKind, flavor: flavor)
    amountSlider.setValue(model.theme.noiseFactor)
    amountSlider.isEnabled = model.isAmountEnabled
    opacitySlider.setValue(model.theme.opacity)
    for slider in [amountSlider, opacitySlider] { slider.applyColors(flavor) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    // The amount track previews the selected texture (or the last one) fading in from left to right.
    let texture = model.theme.textureKind ?? .grain
    amountGradient.backgroundColor = ThemeTextureInk.pattern(texture, dark: flavor == .dark)
    // The opacity track shows the colours fading in over a checkerboard.
    opacityChecker.backgroundColor = ThemeTextureInk.checkerboard(ShellTokens.sidebarItemHovered.resolve(flavor))
    let ends = stored.isEmpty ? dotColors : stored
    let colors = ends.count > 1 ? [ends[0], ends[ends.count - 1]] : ends
    var stops: [CGColor] = [(colors.first ?? .white(1)).cgColor.copy(alpha: 0) ?? CGColor.clear]
    var locations: [NSNumber] = [0]
    if colors.count > 1 {
      stops += [colors[0].cgColor, colors[1].cgColor]
      locations += [0.6, 1]
    } else if let only = colors.first {
      stops.append(only.cgColor)
      locations.append(1)
    }
    opacityGradient.colors = stops
    opacityGradient.locations = locations
    CATransaction.commit()
    if flavorChanged { needsLayout = true }
    layoutSurface()
  }

  // MARK: - Keyboard order

  /// Tab order: colour-count button, dots, texture swatches, Texture amount, Opacity.
  func updateKeyViewLoop() {
    var chain: [NSView] = [countButton]
    chain += pad.dots
    chain += [swatches, amountSlider, opacitySlider]
    for (view, next) in zip(chain, chain.dropFirst() + [chain[0]]) { view.nextKeyView = next }
    for dot in pad.dots { wireFocus(dot) }
  }
}
