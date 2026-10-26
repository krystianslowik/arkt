import AppKit

// MARK: - Swatches

/// Six (seven on the import path) round theme swatches, 40 pt, 12 apart (section 6.3). A radio group: the row takes
/// keyboard focus as one control and the arrows move the selection; each swatch is a radio button for VoiceOver.
@MainActor
final class SwatchRowView: NSView {
  static let diameter: CGFloat = 40
  static let gap: CGFloat = 12

  var appearanceModel: OnboardingAppearance { didSet { swatchViews.forEach { $0.appearanceModel = appearanceModel } } }
  /// A click or an arrow key chose swatch `index`.
  var onSelect: (@MainActor (Int) -> Void)?
  private(set) var swatchViews: [SwatchView] = []
  private var selected = 0

  init(appearance: OnboardingAppearance) {
    self.appearanceModel = appearance
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    setAccessibilityLabel(OnboardingCopy.themeGroupLabel)
    setAccessibilityIdentifier(AXID.Onboarding.swatches)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  func configure(_ theme: OnboardingTheme) {
    if swatchViews.count != theme.swatches.count {
      swatchViews.forEach { $0.removeFromSuperview() }
      swatchViews = theme.swatches.indices.map { index in
        let view = SwatchView(appearance: appearanceModel)
        view.onPress = { [weak self] in self?.choose(index) }
        addSubview(view)
        return view
      }
      needsLayout = true
    }
    for (index, swatch) in theme.swatches.enumerated() {
      swatchViews[index].configure(swatch, flavor: theme.appearance)
    }
    select(theme.selected, animated: true)
  }

  func select(_ index: Int, animated: Bool) {
    selected = index
    for (i, view) in swatchViews.enumerated() { view.setSelected(i == index, animated: animated) }
    updateFocus()
  }

  private func choose(_ index: Int) {
    onSelect?(index)
  }

  override var intrinsicContentSize: NSSize {
    let count = CGFloat(swatchViews.count)
    return NSSize(width: count * Self.diameter + max(count - 1, 0) * Self.gap, height: Self.diameter)
  }

  override func layout() {
    super.layout()
    for (index, view) in swatchViews.enumerated() {
      view.frame = NSRect(x: CGFloat(index) * (Self.diameter + Self.gap), y: 0, width: Self.diameter,
                          height: Self.diameter)
    }
  }

  override func keyDown(with event: NSEvent) {
    switch event.specialKey {
    case .leftArrow?, .upArrow?: move(by: -1)
    case .rightArrow?, .downArrow?: move(by: 1)
    default:
      if event.charactersIgnoringModifiers == " " { return }
      super.keyDown(with: event)
    }
  }

  private func move(by delta: Int) {
    guard !swatchViews.isEmpty else { return }
    let count = swatchViews.count
    choose(((selected + delta) % count + count) % count)
  }

  override func becomeFirstResponder() -> Bool {
    hasFocus = true
    updateFocus()
    return true
  }

  override func resignFirstResponder() -> Bool {
    hasFocus = false
    updateFocus()
    return true
  }

  private var hasFocus = false

  private func updateFocus() {
    for (index, view) in swatchViews.enumerated() { view.setFocused(hasFocus && index == selected) }
  }

  override func accessibilityChildren() -> [Any]? { swatchViews }
}

/// One swatch: the theme gradient in a circle, a 2 pt ring 5 pt outside when selected (opacity 160 ms, scale 0.92 to
/// 1 over 220 ms, M6), a small badge on the imported Space's own swatch, and a press scale of 0.95.
@MainActor
final class SwatchView: NSView {
  var appearanceModel: OnboardingAppearance { didSet { restyle() } }
  var onPress: (@MainActor () -> Void)?

  private let disc = CALayer()
  private let gradient = CAGradientLayer()
  private let rim = CALayer()
  private let ring = CAShapeLayer()
  private let focus = CAShapeLayer()
  private let badge = CALayer()
  private var isSelected = false
  private var title = ""

  init(appearance: OnboardingAppearance) {
    self.appearanceModel = appearance
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)
    gradient.masksToBounds = true
    rim.borderWidth = 1
    rim.borderColor = NSColor.black.withAlphaComponent(0.1).cgColor
    for shape in [ring, focus] {
      shape.fillColor = nil
      shape.opacity = 0
    }
    disc.addSublayer(gradient)
    disc.addSublayer(rim)
    layer?.addSublayer(focus)
    layer?.addSublayer(ring)
    layer?.addSublayer(disc)
    layer?.addSublayer(badge)
    badge.isHidden = true
    setAccessibilityElement(true)
    setAccessibilityRole(.radioButton)
    setAccessibilityIdentifier(AXID.Onboarding.swatch)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  func configure(_ swatch: OnboardingTheme.Swatch, flavor: ThemeFlavor) {
    title = swatch.title
    setAccessibilityLabel(swatch.title)
    let colors = swatch.theme(flavor).baseColors.map(\.cgColor)
    OnboardingMotion.animate(gradient, "colors", to: colors.count > 1 ? colors : colors + colors, duration: 0.28)
    badge.isHidden = !swatch.isOwn
  }

  func setSelected(_ selected: Bool, animated: Bool) {
    isSelected = selected
    setAccessibilityValue(selected ? 1 : 0)
    let duration = animated ? 1.0 : 0
    OnboardingMotion.animate(ring, "opacity", to: Float(selected ? 1 : 0), duration: 0.16 * duration)
    if appearanceModel.reduceMotion {
      OnboardingMotion.set { ring.transform = CATransform3DIdentity }
    } else {
      let scale = selected ? 1 : 0.92
      OnboardingMotion.animate(ring, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)),
                               duration: 0.22 * duration)
    }
  }

  func setFocused(_ focused: Bool) {
    OnboardingMotion.animate(focus, "opacity", to: Float(focused ? 1 : 0), duration: 0.12)
  }

  private func restyle() {
    OnboardingMotion.set {
      ring.strokeColor = appearanceModel.focusRing.cgColor
      ring.lineWidth = 2
      focus.strokeColor = appearanceModel.focusRing.withAlphaComponent(0.5).cgColor
      focus.lineWidth = appearanceModel.focusRingWidth
      badge.backgroundColor = appearanceModel.surface.cgColor
      badge.borderColor = appearanceModel.hairline.cgColor
      badge.borderWidth = 1
    }
  }

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      disc.bounds = bounds
      disc.position = center
      disc.cornerRadius = bounds.width / 2
      gradient.frame = disc.bounds
      gradient.cornerRadius = bounds.width / 2
      rim.frame = disc.bounds
      rim.cornerRadius = bounds.width / 2
      let size = bounds.size
      func circle(_ outset: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: -outset, y: -outset, width: size.width + outset * 2,
                                 height: size.height + outset * 2), transform: nil)
      }
      for shape in [ring, focus] {
        shape.bounds = bounds
        shape.position = center
      }
      ring.path = circle(6)
      focus.path = circle(9)
      badge.frame = CGRect(x: bounds.width - 12, y: bounds.height - 12, width: 14, height: 14)
      badge.cornerRadius = 7
    }
  }

  override func mouseDown(with event: NSEvent) {
    pressScale(0.95)
  }

  override func mouseUp(with event: NSEvent) {
    pressScale(1)
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
  }

  private func pressScale(_ scale: CGFloat) {
    guard !appearanceModel.reduceMotion else { return }
    OnboardingMotion.animate(disc, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)),
                             duration: 0.16)
  }

  override func accessibilityPerformPress() -> Bool {
    onPress?()
    return true
  }
}

// MARK: - Appearance

/// The segmented pill "Light" / "Dark" beside the swatches: track `brandControlFill`, thumb `surfaceBrand` with a
/// hairline, sliding 300 ms on the drawer curve (M6). Disabled at 40 % while an own gradient is selected.
@MainActor
final class AppearanceSegmentView: NSView {
  static let segmentWidth: CGFloat = 70
  static let segmentHeight: CGFloat = 36
  static let inset: CGFloat = 4

  var appearanceModel: OnboardingAppearance { didSet { restyle() } }
  var onChange: (@MainActor (ThemeFlavor) -> Void)?
  var isEnabled = true {
    didSet {
      layer?.opacity = isEnabled ? 1 : 0.4
      segments.forEach { $0.setAccessibilityEnabled(isEnabled) }
    }
  }
  private(set) var value: ThemeFlavor = .light

  private let thumb = CALayer()
  private let focus = CAShapeLayer()
  private let segments: [AppearanceSegment]

  init(appearance: OnboardingAppearance) {
    self.appearanceModel = appearance
    segments = [AppearanceSegment(flavor: .light, title: OnboardingCopy.light, identifier: AXID.Onboarding.appearanceLight),
                AppearanceSegment(flavor: .dark, title: OnboardingCopy.dark, identifier: AXID.Onboarding.appearanceDark)]
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    layer?.addSublayer(thumb)
    focus.fillColor = nil
    focus.opacity = 0
    layer?.addSublayer(focus)
    for segment in segments {
      segment.onPress = { [weak self] flavor in self?.choose(flavor) }
      addSubview(segment)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    setAccessibilityLabel(OnboardingCopy.appearanceLabel)
    setAccessibilityIdentifier(AXID.Onboarding.appearance)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { isEnabled }
  override var canBecomeKeyView: Bool { isEnabled }
  override var mouseDownCanMoveWindow: Bool { false }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Self.segmentWidth * 2 + Self.inset * 2, height: Self.segmentHeight + Self.inset * 2)
  }

  func setValue(_ flavor: ThemeFlavor, animated: Bool) {
    value = flavor
    for segment in segments { segment.setChecked(segment.flavor == flavor, appearance: appearanceModel) }
    let x = flavor == .light ? 0 : Self.segmentWidth
    let transform = NSValue(caTransform3D: CATransform3DMakeTranslation(x, 0, 0))
    let duration = animated && !appearanceModel.reduceMotion ? 0.3 : 0
    OnboardingMotion.animate(thumb, "transform", to: transform, duration: duration, timing: OnboardingMotion.drawer)
  }

  private func choose(_ flavor: ThemeFlavor) {
    guard isEnabled else { return }
    onChange?(flavor)
  }

  private func restyle() {
    OnboardingMotion.set {
      layer?.backgroundColor = appearanceModel.controlFill.cgColor
      layer?.borderColor = appearanceModel.hairline.cgColor
      layer?.borderWidth = 1
      thumb.backgroundColor = appearanceModel.surface.cgColor
      thumb.borderColor = appearanceModel.hairline.cgColor
      thumb.borderWidth = 1
      thumb.shadowColor = NSColor.black.cgColor
      thumb.shadowOpacity = 0.12
      thumb.shadowRadius = 1
      thumb.shadowOffset = CGSize(width: 0, height: -1)
      focus.strokeColor = appearanceModel.focusRing.cgColor
      focus.lineWidth = appearanceModel.focusRingWidth
    }
    for segment in segments { segment.setChecked(segment.flavor == value, appearance: appearanceModel) }
  }

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      layer?.cornerRadius = bounds.height / 2
      thumb.frame = CGRect(x: Self.inset, y: Self.inset, width: Self.segmentWidth, height: Self.segmentHeight)
      thumb.cornerRadius = Self.segmentHeight / 2
      let ringRect = bounds.insetBy(dx: -3 - appearanceModel.focusRingWidth / 2, dy: -3 - appearanceModel.focusRingWidth / 2)
      focus.path = CGPath(roundedRect: ringRect, cornerWidth: ringRect.height / 2, cornerHeight: ringRect.height / 2,
                          transform: nil)
    }
    for (index, segment) in segments.enumerated() {
      segment.frame = NSRect(x: Self.inset + CGFloat(index) * Self.segmentWidth, y: Self.inset,
                             width: Self.segmentWidth, height: Self.segmentHeight)
    }
  }

  override func keyDown(with event: NSEvent) {
    switch event.specialKey {
    case .leftArrow?, .upArrow?: choose(.light)
    case .rightArrow?, .downArrow?: choose(.dark)
    default:
      if event.charactersIgnoringModifiers == " " {
        choose(value == .light ? .dark : .light)
        return
      }
      super.keyDown(with: event)
    }
  }

  override func becomeFirstResponder() -> Bool {
    OnboardingMotion.animate(focus, "opacity", to: Float(1), duration: 0.12)
    return true
  }

  override func resignFirstResponder() -> Bool {
    OnboardingMotion.animate(focus, "opacity", to: Float(0), duration: 0.12)
    return true
  }

  override func accessibilityChildren() -> [Any]? { segments }
}

/// One segment of the appearance control: a radio button for VoiceOver, its label drawn in a layer.
@MainActor
final class AppearanceSegment: NSView {
  let flavor: ThemeFlavor
  let title: String
  var onPress: (@MainActor (ThemeFlavor) -> Void)?
  private let label = CALayer()

  init(flavor: ThemeFlavor, title: String, identifier: String) {
    self.flavor = flavor
    self.title = title
    super.init(frame: .zero)
    wantsLayer = true
    label.anchorPoint = .zero
    layer?.addSublayer(label)
    setAccessibilityElement(true)
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel(title)
    setAccessibilityIdentifier(identifier)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  func setChecked(_ checked: Bool, appearance: OnboardingAppearance) {
    setAccessibilityValue(checked ? 1 : 0)
    let style = BrandType.Style(weight: .demiBold, size: 14, leading: nil, trackingEm: 0, uppercase: false,
                                tabular: false)
    let text = NSAttributedString(string: title, attributes: BrandType.attributes(
      style, color: checked ? appearance.textPrimary : appearance.textSecondary))
    let size = BrandTextRenderer.measure(text, maxWidth: 1000)
    let image = BrandTextRenderer.image(text, size: size, halo: [])
    OnboardingMotion.set {
      BrandTextRenderer.apply(image, to: label, glyphSize: size, halo: false, scale: window?.backingScaleFactor ?? 2)
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      label.position = CGPoint(x: ((bounds.width - label.bounds.width) / 2).rounded(),
                               y: ((bounds.height - label.bounds.height) / 2).rounded())
    }
  }

  override func mouseUp(with event: NSEvent) {
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?(flavor) }
  }

  override func accessibilityPerformPress() -> Bool {
    onPress?(flavor)
    return true
  }
}

// MARK: - Option pill

/// The Extensions step's option (section 6.5): a 46 pt pill in `brandControlFill` with a hairline and a 20 pt round
/// check that fills mustard with a graphite tick. A checkbox for VoiceOver; Space and a click toggle it.
@MainActor
final class OptionPillView: NSView {
  static let height: CGFloat = 46

  var appearanceModel: OnboardingAppearance { didSet { restyle() } }
  var onToggle: (@MainActor (Bool) -> Void)?
  private(set) var isOn = false
  private let body = CALayer()
  private let check = CALayer()
  private let tick = CAShapeLayer()
  private let label = CALayer()
  private let focus = CAShapeLayer()
  private let title: String

  init(title: String, appearance: OnboardingAppearance) {
    self.title = title
    self.appearanceModel = appearance
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    focus.fillColor = nil
    focus.opacity = 0
    tick.fillColor = nil
    tick.lineWidth = 2
    tick.lineCap = .round
    tick.lineJoin = .round
    tick.opacity = 0
    label.anchorPoint = .zero
    check.addSublayer(tick)
    body.addSublayer(check)
    body.addSublayer(label)
    layer?.addSublayer(focus)
    layer?.addSublayer(body)
    setAccessibilityElement(true)
    setAccessibilityRole(.checkBox)
    setAccessibilityLabel(title)
    setAccessibilityIdentifier(AXID.Onboarding.webStore)
    setAccessibilityValue(0)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  private var titleSize: NSSize {
    BrandTextRenderer.measure(BrandType.attributed(title, role: .option, color: .black), maxWidth: 10_000)
  }

  override var intrinsicContentSize: NSSize { NSSize(width: 14 + 20 + 12 + ceil(titleSize.width) + 20, height: Self.height) }

  func setOn(_ on: Bool) {
    isOn = on
    setAccessibilityValue(on ? 1 : 0)
    restyle()
  }

  private func restyle() {
    let text = BrandType.attributed(title, role: .option, color: appearanceModel.textPrimary, alignment: .left)
    let size = titleSize
    let image = BrandTextRenderer.image(text, size: size, halo: [])
    OnboardingMotion.set {
      body.backgroundColor = appearanceModel.controlFill.cgColor
      body.borderColor = appearanceModel.hairline.cgColor
      body.borderWidth = 1
      check.backgroundColor = isOn ? appearanceModel.accent.cgColor : NSColor.clear.cgColor
      check.borderColor = appearanceModel.textSecondary.cgColor
      check.borderWidth = isOn ? 0 : 1.5
      tick.strokeColor = BrandTokens.Palette.graphite.cgColor
      focus.strokeColor = appearanceModel.focusRing.cgColor
      focus.lineWidth = appearanceModel.focusRingWidth
      BrandTextRenderer.apply(image, to: label, glyphSize: size, halo: false, scale: window?.backingScaleFactor ?? 2)
    }
    OnboardingMotion.animate(tick, "opacity", to: Float(isOn ? 1 : 0), duration: 0.15)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      body.bounds = bounds
      body.position = CGPoint(x: bounds.midX, y: bounds.midY)
      body.cornerRadius = bounds.height / 2
      check.frame = CGRect(x: 14, y: (bounds.height - 20) / 2, width: 20, height: 20)
      check.cornerRadius = 10
      let path = CGMutablePath()
      path.move(to: CGPoint(x: 5.5, y: 10.5))
      path.addLine(to: CGPoint(x: 8.8, y: 13.6))
      path.addLine(to: CGPoint(x: 14.5, y: 6.8))
      tick.path = path
      tick.frame = check.bounds
      label.position = CGPoint(x: 46, y: ((bounds.height - label.bounds.height) / 2).rounded())
      let ringRect = bounds.insetBy(dx: -3 - appearanceModel.focusRingWidth / 2, dy: -3 - appearanceModel.focusRingWidth / 2)
      focus.path = CGPath(roundedRect: ringRect, cornerWidth: ringRect.height / 2, cornerHeight: ringRect.height / 2,
                          transform: nil)
    }
  }

  private func toggle() {
    setOn(!isOn)
    onToggle?(isOn)
  }

  override func mouseDown(with event: NSEvent) { pressScale(0.97) }

  override func mouseUp(with event: NSEvent) {
    pressScale(1)
    if bounds.contains(convert(event.locationInWindow, from: nil)) { toggle() }
  }

  private func pressScale(_ scale: CGFloat) {
    guard !appearanceModel.reduceMotion else { return }
    OnboardingMotion.animate(body, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)),
                             duration: 0.16)
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " {
      toggle()
      return
    }
    // Arrows belong to the control and never change the step (section 10).
    if [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(event.specialKey) { return }
    super.keyDown(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    OnboardingMotion.animate(focus, "opacity", to: Float(1), duration: 0.12)
    return true
  }

  override func resignFirstResponder() -> Bool {
    OnboardingMotion.animate(focus, "opacity", to: Float(0), duration: 0.12)
    return true
  }

  override func accessibilityPerformPress() -> Bool {
    toggle()
    return true
  }
}
