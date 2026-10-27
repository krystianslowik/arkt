import AppKit
import Motion

// MARK: - Motion

/// The Settings window's motion values (docs/design/settings.md, section 5). Transform and opacity only.
@MainActor
enum SettingsMotion {
  /// Test seam and Reduce Motion: AppKit's setting unless overridden.
  static var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// The on fill of a switch and the Appearance preview's URL pill cross-fade this long.
  static let crossFade: CFTimeInterval = 0.15
  /// The selected pane item's plate fades in this long after a click.
  static let plateFade: CFTimeInterval = 0.12
  /// A pane item scales to this while the pointer is down.
  static let paneItemPressScale: CGFloat = 0.96

  /// Animates `keyPath` of `layer` to `value` on `preset`, from the value on screen (interruptible), unless Reduce
  /// Motion is on (then it jumps).
  static func spring(_ layer: CALayer, _ keyPath: String, to value: Double, preset: SpringPreset,
                     reduceMotion: Bool) {
    let from = (layer.presentation()?.value(forKeyPath: keyPath) as? NSNumber)?.doubleValue
      ?? (layer.value(forKeyPath: keyPath) as? NSNumber)?.doubleValue ?? value
    ArchiveMotion.set { layer.setValue(value, forKeyPath: keyPath) }
    guard !reduceMotion, from != value else {
      layer.removeAnimation(forKey: keyPath)
      return
    }
    let animation = SpringAnimationFactory.make(keyPath: keyPath, from: from, to: value, parameters: preset.parameters)
    layer.add(animation, forKey: keyPath)
  }

  /// A plain fade of `layer`'s opacity to `value` from the value on screen.
  static func fade(_ layer: CALayer, to value: Float, duration: CFTimeInterval) {
    ArchiveMotion.animate(layer, "opacity", to: value, duration: duration)
  }
}

// MARK: - Switch

/// The settings switch (section 4): 32 x 20, a 16 pt knob. Off: `sidebarItemHovered` track, white knob. On: the
/// graphite `switchOn` fill (porcelain in dark) with the opposite knob. The knob moves on `springyFast`, the on fill
/// cross-fades 0.15 s, and the knob stretches to 1.12 from its leading edge while the pointer is down. A real
/// `NSButton`, so the key view loop, Space and VoiceOver's press work; VoiceOver reads it as a switch.
@MainActor
public final class SettingsSwitch: NSButton {
  /// Called after a click or Space changed the state.
  var onChange: (@MainActor (Bool) -> Void)?

  private let track = CALayer()
  private let onFill = CALayer()
  private let knob = CALayer()
  fileprivate private(set) var pressing = false

  public var isOn: Bool { state == .on }

  override init(frame frameRect: NSRect) {
    super.init(frame: NSRect(origin: frameRect.origin, size: SettingsMetrics.switchSize))
    let cell = SettingsSwitchCell()
    cell.owner = self
    self.cell = cell
    setButtonType(.switch)
    title = ""
    isBordered = false
    focusRingType = .default
    target = self
    action = #selector(toggled(_:))
    wantsLayer = true
    for layer in [track, onFill] {
      layer.cornerRadius = SettingsMetrics.switchSize.height / 2
      layer.cornerCurve = .continuous
    }
    knob.cornerRadius = SettingsMetrics.knob / 2
    knob.anchorPoint = CGPoint(x: 0, y: 0.5)          // stretches from its leading edge
    knob.shadowOffset = CGSize(width: 0, height: -1)
    knob.shadowRadius = 1
    track.addSublayer(onFill)
    track.addSublayer(knob)
    layer?.addSublayer(track)
    setAccessibilityRole(.checkBox)
    setAccessibilitySubrole(.switch)
    restyle(animated: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override public var intrinsicContentSize: NSSize { SettingsMetrics.switchSize }
  override public var mouseDownCanMoveWindow: Bool { false }
  override public var wantsUpdateLayer: Bool { true }
  override public func updateLayer() { restyle(animated: false) }

  /// Sets the state from the model (another window, the View menu): animated like a click.
  func setOn(_ on: Bool, animated: Bool) {
    guard on != isOn else { return }
    state = on ? .on : .off
    restyle(animated: animated)
  }

  @objc private func toggled(_ sender: Any?) {
    restyle(animated: true)
    onChange?(isOn)
  }

  override public func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " {
      performClick(nil)
      return
    }
    super.keyDown(with: event)
  }

  override public func accessibilityValue() -> Any? { NSNumber(value: isOn ? 1 : 0) }

  fileprivate func setPressed(_ pressed: Bool) {
    guard isEnabled, pressed != pressing else { return }
    pressing = pressed
    restyle(animated: true)
  }

  private var knobX: CGFloat {
    let travel = SettingsMetrics.switchSize.width - SettingsMetrics.knob - 4
    let stretch = pressing ? SettingsMetrics.knob * 0.12 : 0
    return 2 + (isOn ? travel - stretch : 0)
  }

  private func restyle(animated: Bool) {
    let flavor = archiveFlavor
    let reduce = SettingsMotion.reduceMotion()
    ArchiveMotion.set {
      track.frame = CGRect(origin: .zero, size: SettingsMetrics.switchSize)
      onFill.frame = track.bounds
      track.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
      onFill.backgroundColor = SettingsTokens.switchOn.resolve(flavor).cgColor
      knob.bounds = CGRect(x: 0, y: 0, width: SettingsMetrics.knob, height: SettingsMetrics.knob)
      knob.backgroundColor = (isOn ? SettingsTokens.switchKnobOn : SettingsTokens.switchKnobOff)
        .resolve(flavor).cgColor
      knob.shadowOpacity = isOn && flavor == .dark ? 0 : (flavor == .dark ? 0.40 : 0.22)
      knob.position.y = SettingsMetrics.switchSize.height / 2
    }
    let fill: Float = isOn ? 1 : 0
    if animated, onFill.opacity != fill {
      SettingsMotion.fade(onFill, to: fill, duration: SettingsMotion.crossFade)
    } else {
      ArchiveMotion.set { onFill.opacity = fill }
    }
    SettingsMotion.spring(knob, "position.x", to: Double(knobX), preset: .springyFast,
                          reduceMotion: reduce || !animated)
    SettingsMotion.spring(knob, "transform.scale.x", to: pressing ? 1.12 : 1, preset: .springyExtraFast,
                          reduceMotion: reduce || !animated)
  }

  override public func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle(animated: false)
  }

}

/// A button cell that draws nothing (layers draw the control) and masks the focus ring to a rounded rectangle.
@MainActor
class SettingsBlankCell: NSButtonCell {
  /// nil: a capsule.
  var focusRadius: CGFloat?

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}

  override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
    let radius = focusRadius ?? cellFrame.height / 2
    NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius).fill()
  }

  override func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect { cellFrame }
}

/// Reports the pointer-down highlight to the switch.
@MainActor
final class SettingsSwitchCell: SettingsBlankCell {
  weak var owner: SettingsSwitch?

  override var isHighlighted: Bool {
    didSet { owner?.setPressed(isHighlighted) }
  }
}

// MARK: - Pop-up button

/// A pop-up button in the sidebar URL pill's shape (section 4): 26 high, radius 8, `sidebarItemHovered`, no edge,
/// the title and a 9 pt chevron.up.chevron.down in `sidebarForeground`. Clicking shows a native menu.
@MainActor
public final class SettingsPopUpButton: NSButton {
  public private(set) var items: [String]
  public private(set) var selectedTitle: String
  var onChange: (@MainActor (String) -> Void)?
  private let body = CALayer()
  private let label = CATextLayer()
  private let chevron = CALayer()

  init(items: [String], selected: String) {
    self.items = items
    selectedTitle = selected
    super.init(frame: .zero)
    let cell = SettingsBlankCell()
    cell.focusRadius = SettingsMetrics.popUpRadius
    self.cell = cell
    title = ""
    isBordered = false
    setButtonType(.momentaryChange)
    focusRingType = .default
    wantsLayer = true
    target = self
    action = #selector(pressed(_:))
    body.cornerRadius = SettingsMetrics.popUpRadius
    body.cornerCurve = .continuous
    label.truncationMode = .end
    body.addSublayer(label)
    body.addSublayer(chevron)
    layer?.addSublayer(body)
    setAccessibilityRole(.popUpButton)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override public var mouseDownCanMoveWindow: Bool { false }
  override public var wantsUpdateLayer: Bool { true }
  override public func updateLayer() { restyle() }
  override public func accessibilityValue() -> Any? { selectedTitle }

  private static let font = NSFont.systemFont(ofSize: 13)

  override public var intrinsicContentSize: NSSize {
    let text = ceil((selectedTitle as NSString).size(withAttributes: [.font: Self.font]).width)
    return NSSize(width: 10 + text + 6 + 9 + 8, height: SettingsMetrics.popUpHeight)
  }

  @objc private func pressed(_ sender: Any?) {
    let menu = NSMenu()
    for title in items {
      let item = NSMenuItem(title: title, action: #selector(chose(_:)), keyEquivalent: "")
      item.target = self
      item.state = title == selectedTitle ? .on : .off
      menu.addItem(item)
    }
    menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: 0, y: bounds.height - 3), in: self)
  }

  @objc private func chose(_ sender: NSMenuItem) {
    guard sender.title != selectedTitle else { return }
    selectedTitle = sender.title
    restyle()
    invalidateIntrinsicContentSize()
    onChange?(selectedTitle)
  }

  private func restyle() {
    let flavor = archiveFlavor
    let scale = window?.backingScaleFactor ?? 2
    ArchiveMotion.set {
      body.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
      let increase = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
      body.borderWidth = increase ? 1 : 0
      body.borderColor = SettingsTokens.separatorIncreasedContrast.resolve(flavor).cgColor
      label.string = NSAttributedString(string: selectedTitle, attributes: [
        .font: Self.font, .foregroundColor: ShellTokens.primaryText.resolve(flavor).nsColor(),
      ])
      label.contentsScale = scale
      let image = SymbolImageCache.shared.symbol("chevron.up.chevron.down", box: 11, weight: .semibold,
                                                 color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
      chevron.contents = image.layerContents(forContentsScale: scale)
      chevron.contentsScale = scale
      chevron.contentsGravity = .resizeAspect
    }
    needsLayout = true
  }

  override public func layout() {
    super.layout()
    ArchiveMotion.set {
      body.frame = bounds
      let line = ceil(Self.font.ascender - Self.font.descender + Self.font.leading)
      label.frame = CGRect(x: 10, y: ((bounds.height - line) / 2).rounded(), width: max(0, bounds.width - 33),
                           height: line)
      chevron.frame = CGRect(x: bounds.width - 7 - 11, y: ((bounds.height - 11) / 2).rounded(), width: 11, height: 11)
    }
  }

  override public func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

}

// MARK: - Segmented control

/// "Websites use": a recessed track (radius 9, 2 inset, `sidebarItemHovered`) whose selected 80 x 24 segment lifts
/// on a `tabCurrent` plate (white 18 % in dark); the plate slides on `firm`.
@MainActor
final class SettingsSegmentedControl: NSControl {
  let segments: [String]
  private(set) var selectedIndex: Int
  var onChange: (@MainActor (Int) -> Void)?
  private let plate = CALayer()
  private let labels: [CATextLayer]
  static let segmentSize = NSSize(width: 80, height: 24)
  /// A segment's width: 80 pt, or wider for longer titles (Downloads' "Ask Where to Save").
  let segmentWidth: CGFloat

  init(segments: [String], selected: Int, segmentWidth: CGFloat = SettingsSegmentedControl.segmentSize.width) {
    self.segmentWidth = segmentWidth
    self.segments = segments
    selectedIndex = selected
    labels = segments.map { _ in CATextLayer() }
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 9
    layer?.cornerCurve = .continuous
    plate.cornerRadius = 7
    plate.cornerCurve = .continuous
    plate.anchorPoint = .zero
    plate.shadowOffset = CGSize(width: 0, height: -1)
    plate.shadowRadius = 1
    layer?.addSublayer(plate)
    labels.forEach {
      $0.alignmentMode = .center
      layer?.addSublayer($0)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: segmentWidth * CGFloat(segments.count) + 4, height: Self.segmentSize.height + 4)
  }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override func accessibilityValue() -> Any? { segments[selectedIndex] }

  /// Selects `index` as a click does (tests and the pane's own updates); no `onChange` call.
  func select(_ index: Int) {
    guard segments.indices.contains(index), index != selectedIndex else { return }
    selectedIndex = index
    restyle()
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    let x = convert(event.locationInWindow, from: nil).x - 2
    let index = min(max(Int(x / segmentWidth), 0), segments.count - 1)
    guard index != selectedIndex else { return }
    selectedIndex = index
    restyle()
    onChange?(index)
  }

  private func restyle() {
    let flavor = archiveFlavor
    let scale = window?.backingScaleFactor ?? 2
    ArchiveMotion.set {
      layer?.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
      plate.bounds = CGRect(origin: .zero, size: NSSize(width: segmentWidth, height: Self.segmentSize.height))
      plate.position.y = 2
      plate.backgroundColor = (flavor == .dark ? RGBA.white(0.18) : ShellTokens.tabCurrent.light).cgColor
      plate.shadowOpacity = flavor == .dark ? 0 : 0.10
      for (index, label) in labels.enumerated() {
        let selected = index == selectedIndex
        label.string = NSAttributedString(string: segments[index], attributes: [
          .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
          .foregroundColor: (selected ? ShellTokens.primaryText : ShellTokens.secondaryText).resolve(flavor).nsColor(),
        ])
        label.contentsScale = scale
        label.frame = CGRect(x: 2 + CGFloat(index) * segmentWidth, y: 2 + 4, width: segmentWidth,
                             height: 16)
      }
    }
    SettingsMotion.spring(plate, "position.x", to: Double(2 + CGFloat(selectedIndex) * segmentWidth),
                          preset: .firm, reduceMotion: SettingsMotion.reduceMotion() || window == nil)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}

// MARK: - Keycaps

/// Keycaps (section 4): 22 high, at least 22 wide, radius 6, 12 medium `primaryText` on `sidebarItemHovered`, 3 apart.
/// VoiceOver reads the keys as words ("Shift Command D").
@MainActor
final class SettingsKeycapsView: NSView {
  let keys: [String]
  private let capHeight: CGFloat
  private var caps: [(layer: CALayer, text: CATextLayer, width: CGFloat)] = []

  init(keys: [String], spoken: String, height: CGFloat = SettingsMetrics.keycapHeight) {
    self.keys = keys
    capHeight = height
    super.init(frame: .zero)
    wantsLayer = true
    for _ in keys {
      let cap = CALayer()
      cap.cornerRadius = 6 * height / SettingsMetrics.keycapHeight
      cap.cornerCurve = .continuous
      let text = CATextLayer()
      text.alignmentMode = .center
      cap.addSublayer(text)
      layer?.addSublayer(cap)
      caps.append((cap, text, 0))
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel(spoken)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private var font: NSFont { .systemFont(ofSize: 12 * capHeight / SettingsMetrics.keycapHeight, weight: .medium) }

  override var isFlipped: Bool { true }

  override var intrinsicContentSize: NSSize {
    let widths = caps.map(\.width)
    return NSSize(width: widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * 3, height: capHeight)
  }

  private func restyle() {
    let flavor = archiveFlavor
    let scale = window?.backingScaleFactor ?? 2
    var x: CGFloat = 0
    ArchiveMotion.set {
      for index in caps.indices {
        let key = keys[index]
        let textWidth = ceil((key as NSString).size(withAttributes: [.font: font]).width)
        let width = max(capHeight, textWidth + 12 * capHeight / SettingsMetrics.keycapHeight)
        caps[index].width = width
        let cap = caps[index].layer
        cap.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
        cap.frame = CGRect(x: x, y: 0, width: width, height: capHeight)
        let line = ceil(font.ascender - font.descender)
        caps[index].text.string = NSAttributedString(string: key, attributes: [
          .font: font, .foregroundColor: ShellTokens.primaryText.resolve(flavor).nsColor(),
        ])
        caps[index].text.contentsScale = scale
        caps[index].text.frame = CGRect(x: 0, y: ((capHeight - line) / 2).rounded(), width: width, height: line)
        x += width + 3
      }
    }
    invalidateIntrinsicContentSize()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }
}

// MARK: - Default capsule

/// "Default": the status shown instead of Make Default once Arkt is the default browser. Neutral (a status is not an
/// action): 24 high, radius 12, `sidebarItemHovered`, a 12 pt check and 12 semibold `primaryText`.
@MainActor
final class SettingsDefaultCapsule: NSView {
  private let check = NSImageView()
  private let label = NSTextField(labelWithString: "Default")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.cornerCurve = .continuous
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    addSubview(check)
    addSubview(label)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityLabel("Default browser")
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  override var intrinsicContentSize: NSSize {
    NSSize(width: 7 + 12 + 6 + ceil(label.intrinsicContentSize.width) + 10, height: 24)
  }

  override func layout() {
    super.layout()
    check.frame = NSRect(x: 7, y: 6, width: 12, height: 12)
    let size = label.intrinsicContentSize
    label.frame = NSRect(x: 25, y: ((bounds.height - size.height) / 2).rounded(), width: ceil(size.width),
                         height: size.height)
  }

  private func restyle() {
    let flavor = archiveFlavor
    layer?.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
    label.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    check.image = SymbolImageCache.shared.symbol("checkmark", box: 12, weight: .semibold,
                                                 color: ShellTokens.primaryText.resolve(flavor),
                                                 scale: window?.backingScaleFactor ?? 2)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}
