import AppKit
import Motion

// MARK: - Metrics and motion

/// Sizes of the theme creator popover (design/theme-creator/README.md, "Layout"), in points.
enum ThemeCreatorMetrics {
  static let width: CGFloat = 300
  static let padding: CGFloat = 14
  static let cornerRadius: CGFloat = 18
  /// The arrow on the leading edge: how far its tip stands out, and half its base.
  static let arrowDepth: CGFloat = 7
  static let arrowHalfBase: CGFloat = 8
  static let headerHeight: CGFloat = 24
  static let headerGap: CGFloat = 10
  static let titleInsetX: CGFloat = 4
  static let buttonSize = CGSize(width: 30, height: 22)
  static let buttonRadius: CGFloat = 7
  static let buttonSwatch: CGFloat = 12
  static let padRadius: CGFloat = 16
  static let dot: CGFloat = 26
  static let dotDragged: CGFloat = 34
  static let dotRing: CGFloat = 3
  static let linkWidth: CGFloat = 1.5
  static let sectionGap: CGFloat = 16
  static let labelRow: CGFloat = 18
  static let labelGap: CGFloat = 8
  static let controlInsetX: CGFloat = 4
  static let sliderHeight: CGFloat = 24
  static let track: CGFloat = 10
  static let knob: CGFloat = 24
  static let swatch: CGFloat = 18
  static let swatchGap: CGFloat = 6
  static let swatchRingGap: CGFloat = 2
  static let swatchRing: CGFloat = 1.5

  /// Content height: header, pad, Texture (label row and slider), Opacity.
  static var height: CGFloat {
    padding + headerHeight + headerGap + ThemePad.size.height
      + 2 * (sectionGap + labelRow + labelGap + sliderHeight) + padding
  }

  /// The arrow's centre, from the top: level with the header's title.
  static var arrowCenterY: CGFloat { padding + headerHeight / 2 }
}

/// Motion of the theme creator (README, "Motion"): transform and opacity only.
public enum ThemeCreatorMotion {
  /// Popover open: scale 0.96 to 1 and fade in from the arrow.
  static let openScale: CGFloat = 0.96
  static let open = SpringPreset.springyFast.parameters
  /// Popover close: fade out.
  static let closeDuration: TimeInterval = 0.12
  /// Dot pick-up and release.
  static let pickUp = SpringPreset.springyExtraFast.parameters
  /// A second dot springing out of the first.
  static let secondDot = SpringPreset.springy.parameters
  /// A dot removed: shrinks and fades.
  static let removeDuration: TimeInterval = 0.15
  /// A text tone flip cross-fades the sidebar.
  public static let toneFlipDuration: TimeInterval = 0.2
  /// Small state changes inside the popover (the colour-count button's swatches, a dot leaving the pad).
  static let stateDuration: TimeInterval = 0.2
  /// The strong ease-out for entering and state changes.
  @MainActor static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }
}

// MARK: - Focus

/// A control in the theme creator that takes keyboard focus. The system focus ring is drawn only once the keyboard
/// is in use (`ThemeCreatorView.keyboardFocusVisible`), so opening the popover with the first dot focused shows no
/// ring until a key is pressed.
@MainActor
class ThemeFocusableView: NSView {
  /// Set by the popover: whether focus rings show.
  var focusVisible: () -> Bool = { false }
  /// Escape anywhere in the popover closes it.
  var onCancel: (() -> Void)?
  /// A key reached a control: the popover starts showing focus rings.
  var onKeyboardUse: (() -> Void)?

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }

  override func becomeFirstResponder() -> Bool {
    refreshFocusRing()
    return true
  }

  override func resignFirstResponder() -> Bool {
    refreshFocusRing()
    return true
  }

  func refreshFocusRing() {
    focusRingType = focusVisible() ? .default : .none
    noteFocusRingMaskChanged()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: focusRingRect, xRadius: focusRingRadius, yRadius: focusRingRadius).fill()
  }

  /// The shape the focus ring follows.
  var focusRingRect: NSRect { bounds }
  var focusRingRadius: CGFloat { bounds.height / 2 }

  override func keyDown(with event: NSEvent) {
    onKeyboardUse?()
    if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
      onCancel?()
      return
    }
    if handleKey(event) { return }
    if event.keyCode == 48 {                                    // Tab, Shift-Tab: the popover's key view loop
      if event.isShiftDown { window?.selectPreviousKeyView(self) } else { window?.selectNextKeyView(self) }
      return
    }
    super.keyDown(with: event)
  }

  /// The control's own keys; false passes the event on (Tab moves focus).
  func handleKey(_ event: NSEvent) -> Bool { false }

  override func cancelOperation(_ sender: Any?) { onCancel?() }
}

extension NSEvent {
  /// The arrow this key is, if any.
  var themePadArrow: ThemePad.Arrow? {
    switch keyCode {
    case 123: .left
    case 124: .right
    case 125: .down
    case 126: .up
    default: nil
    }
  }

  var isShiftDown: Bool { modifierFlags.contains(.shift) }
}

// MARK: - Slider

/// A 0...1 slider of the popover: a 10 pt track with a preview painted in it, and a 24 pt white knob. A pointer
/// drag reports `.began`, `.changed` and `.ended`; arrows step 5 % (`.keyboard`, which plays no haptic).
@MainActor
final class ThemeSliderView: ThemeFocusableView {
  enum Phase { case began, changed, ended, keyboard }

  private(set) var value: Double = 0
  var isEnabled = true {
    didSet {
      alphaValue = isEnabled ? 1 : 0.4
      setAccessibilityEnabled(isEnabled)
    }
  }
  var onChange: ((Double, Phase) -> Void)?
  /// Painted inside the track, under the edge.
  let trackContent = CALayer()
  private let track = CALayer()
  private let trackEdge = CALayer()
  private let knob = CALayer()
  private let knobEdge = CALayer()
  private var dragging = false
  private static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(),
                                                      "backgroundColor": NSNull(), "colors": NSNull(),
                                                      "frame": NSNull(), "hidden": NSNull(), "opacity": NSNull()]

  init(label: String, identifier: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    track.cornerRadius = ThemeCreatorMetrics.track / 2
    track.masksToBounds = true
    trackEdge.cornerRadius = ThemeCreatorMetrics.track / 2
    trackEdge.borderWidth = 0.5
    knob.cornerRadius = ThemeCreatorMetrics.knob / 2
    knob.backgroundColor = CGColor.white
    knob.shadowColor = CGColor.black
    knob.shadowOpacity = 0.25
    knob.shadowRadius = 3
    knob.shadowOffset = CGSize(width: 0, height: -2)
    knobEdge.cornerRadius = ThemeCreatorMetrics.knob / 2
    knobEdge.borderWidth = 0.5
    knobEdge.borderColor = CGColor(gray: 0, alpha: 0.2)
    for sublayer in [track, trackContent, trackEdge, knob, knobEdge] { sublayer.actions = Self.noActions }
    track.addSublayer(trackContent)
    layer?.addSublayer(track)
    layer?.addSublayer(trackEdge)
    layer?.addSublayer(knob)
    knob.addSublayer(knobEdge)
    setAccessibilityElement(true)
    setAccessibilityRole(.slider)
    setAccessibilityLabel(label)
    setAccessibilityIdentifier(identifier)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func setValue(_ newValue: Double) {
    value = min(max(newValue, 0), 1)
    setAccessibilityValue(Self.percent(value))
    needsLayout = true
  }

  static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) percent" }

  func applyColors(_ flavor: ThemeFlavor) {
    track.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
    trackEdge.borderColor = flavor == .dark ? CGColor(gray: 1, alpha: 0.12) : CGColor(gray: 0, alpha: 0.14)
  }

  override func layout() {
    super.layout()
    let trackY = (bounds.height - ThemeCreatorMetrics.track) / 2
    let trackRect = CGRect(x: 0, y: trackY, width: bounds.width, height: ThemeCreatorMetrics.track)
    track.frame = trackRect
    trackEdge.frame = trackRect
    trackContent.frame = track.bounds
    for preview in trackContent.sublayers ?? [] {
      preview.frame = trackContent.bounds
      preview.mask?.frame = preview.bounds
    }
    let knobSize = ThemeCreatorMetrics.knob
    knob.frame = CGRect(x: bounds.width * value - knobSize / 2, y: (bounds.height - knobSize) / 2, width: knobSize,
                        height: knobSize)
    knobEdge.frame = knob.bounds
  }

  override var focusRingRect: NSRect { knob.frame }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    dragging = true
    report(event, .began)
  }

  override func mouseDragged(with event: NSEvent) {
    guard dragging else { return }
    report(event, .changed)
  }

  override func mouseUp(with event: NSEvent) {
    guard dragging else { return }
    dragging = false
    report(event, .ended)
  }

  private func report(_ event: NSEvent, _ phase: Phase) {
    let x = convert(event.locationInWindow, from: nil).x
    onChange?(Double(min(max(x / max(bounds.width, 1), 0), 1)), phase)
  }

  override func handleKey(_ event: NSEvent) -> Bool {
    guard isEnabled, let arrow = event.themePadArrow else { return false }
    let step = event.isShiftDown ? 0.1 : 0.05
    switch arrow {
    case .left, .down: onChange?(max(value - step, 0), .keyboard)
    case .right, .up: onChange?(min(value + step, 1), .keyboard)
    }
    return true
  }

  override func accessibilityPerformIncrement() -> Bool {
    guard isEnabled else { return false }
    onChange?(min(value + 0.05, 1), .keyboard)
    return true
  }

  override func accessibilityPerformDecrement() -> Bool {
    guard isEnabled else { return false }
    onChange?(max(value - 0.05, 0), .keyboard)
    return true
  }

  override var acceptsFirstResponder: Bool { isEnabled }
  override var canBecomeKeyView: Bool { isEnabled }
}

// MARK: - Colour-count button

/// The header's colour-count button: two overlapping swatches of the current colours ("Use one colour"), or one
/// swatch and a "+" ("Add a second colour").
@MainActor
final class ThemeColourCountButton: ThemeFocusableView {
  var onPress: (() -> Void)?
  private let first = CALayer()
  private let second = CALayer()
  private let plus = CATextLayer()
  private(set) var colourCount = 1
  private var shownColors: [RGBA] = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = ThemeCreatorMetrics.buttonRadius
    for swatch in [second, first] {
      swatch.cornerRadius = ThemeCreatorMetrics.buttonSwatch / 2
      swatch.borderWidth = 1.5
      layer?.addSublayer(swatch)
    }
    plus.string = "+"
    plus.fontSize = 12
    plus.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    plus.alignmentMode = .center
    plus.contentsScale = 2
    layer?.addSublayer(plus)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityIdentifier(AXID.ThemeCreator.colourCount)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var focusRingRadius: CGFloat { ThemeCreatorMetrics.buttonRadius }

  override func layout() {
    super.layout()
    layoutSwatches(animated: false)
  }

  func update(colors: [RGBA], flavor: ThemeFlavor, surface: RGBA, animated: Bool) {
    colourCount = colors.count
    shownColors = colors
    layer?.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
    plus.foregroundColor = ShellTokens.secondaryText.resolve(flavor).cgColor
    plus.contentsScale = window?.backingScaleFactor ?? 2
    for swatch in [first, second] { swatch.borderColor = surface.cgColor }
    layoutSwatches(animated: animated)
    setAccessibilityLabel(colors.count < 2 ? "Add a second colour" : "Use one colour")
  }

  private func layoutSwatches(animated: Bool) {
    let colors = shownColors
    CATransaction.begin()
    CATransaction.setDisableActions(!animated)
    CATransaction.setAnimationDuration(ThemeCreatorMotion.stateDuration)
    CATransaction.setAnimationTimingFunction(ThemeCreatorMotion.easeOut)
    let size = ThemeCreatorMetrics.buttonSwatch
    let y = (bounds.height - size) / 2
    let one = colors.count < 2
    first.frame = CGRect(x: one ? 5 : 6, y: y, width: size, height: size)
    second.frame = CGRect(x: 12, y: y, width: size, height: size)
    first.backgroundColor = colors.first?.cgColor
    second.backgroundColor = (colors.count > 1 ? colors[1] : colors.first)?.cgColor
    second.opacity = one ? 0 : 1
    plus.opacity = one ? 1 : 0
    plus.frame = CGRect(x: bounds.width - 4 - 10, y: y - 1, width: 10, height: 16)
    CATransaction.commit()
  }

  override func mouseDown(with event: NSEvent) {
    pressFeedback(true)
  }

  override func mouseUp(with event: NSEvent) {
    pressFeedback(false)
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
  }

  /// A press scales the button to 0.96 and back (feedback, 0.12 s).
  private func pressFeedback(_ down: Bool) {
    guard let layer else { return }
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    var transform = CATransform3DIdentity
    if down {
      transform = CATransform3DTranslate(transform, center.x, center.y, 0)
      transform = CATransform3DScale(transform, 0.96, 0.96, 1)
      transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
    }
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.12)
    CATransaction.setAnimationTimingFunction(ThemeCreatorMotion.easeOut)
    layer.transform = transform
    CATransaction.commit()
  }

  override func handleKey(_ event: NSEvent) -> Bool {
    guard event.charactersIgnoringModifiers == " " || event.keyCode == 36 || event.keyCode == 76 else { return false }
    onPress?()
    return true
  }

  override func accessibilityPerformPress() -> Bool {
    onPress?()
    return true
  }
}

// MARK: - Texture swatches

/// The texture radio group: None, Grain, Sand, Denim, Tweed. One tab stop; arrows move the selection.
@MainActor
final class ThemeTextureSwatchesView: ThemeFocusableView {
  /// The swatches, in order; nil is None.
  static let choices: [ThemeTexture?] = [nil, .grain, .sand, .denim, .tweed]
  static func title(_ texture: ThemeTexture?) -> String { texture.map { $0.rawValue.capitalized } ?? "None" }

  /// A swatch was picked by the pointer (`true`) or the keyboard.
  var onSelect: ((ThemeTexture?, _ byPointer: Bool) -> Void)?
  private(set) var selected: ThemeTexture?
  private var fills: [CALayer] = []
  private var inks: [CALayer] = []
  private let ring = CALayer()
  private var elements: [ThemeSwatchElement] = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = false
    for _ in Self.choices {
      let fill = CALayer()
      fill.cornerRadius = ThemeCreatorMetrics.swatch / 2
      fill.masksToBounds = true
      fill.borderWidth = 0.5
      let ink = CALayer()
      ink.contentsGravity = .topLeft
      fill.addSublayer(ink)
      layer?.addSublayer(fill)
      fills.append(fill)
      inks.append(ink)
    }
    ring.borderWidth = ThemeCreatorMetrics.swatchRing
    ring.cornerRadius = (ThemeCreatorMetrics.swatch + 2 * (ThemeCreatorMetrics.swatchRingGap
                                                           + ThemeCreatorMetrics.swatchRing)) / 2
    layer?.addSublayer(ring)
    setAccessibilityElement(true)
    setAccessibilityRole(.radioGroup)
    setAccessibilityLabel("Texture")
    setAccessibilityIdentifier(AXID.ThemeCreator.textures)
    elements = Self.choices.enumerated().map { index, texture in
      let element = ThemeSwatchElement(index: index, title: Self.title(texture), group: self)
      return element
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Total width of the five swatches.
  static var width: CGFloat {
    CGFloat(choices.count) * ThemeCreatorMetrics.swatch + CGFloat(choices.count - 1) * ThemeCreatorMetrics.swatchGap
  }

  func swatchFrame(_ index: Int) -> CGRect {
    let x = CGFloat(index) * (ThemeCreatorMetrics.swatch + ThemeCreatorMetrics.swatchGap)
    return CGRect(x: x, y: (bounds.height - ThemeCreatorMetrics.swatch) / 2, width: ThemeCreatorMetrics.swatch,
                  height: ThemeCreatorMetrics.swatch)
  }

  func update(selected: ThemeTexture?, flavor: ThemeFlavor) {
    self.selected = selected
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let scale = window?.backingScaleFactor ?? 2
    for (index, texture) in Self.choices.enumerated() {
      fills[index].frame = swatchFrame(index)
      fills[index].backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
      fills[index].borderColor = flavor == .dark ? CGColor(gray: 1, alpha: 0.14) : CGColor(gray: 0, alpha: 0.18)
      inks[index].frame = fills[index].bounds
      inks[index].contents = texture.flatMap { ThemeTextureInk.image($0, dark: flavor == .dark) }
      inks[index].contentsScale = scale
    }
    let index = Self.choices.firstIndex(of: selected) ?? 0
    let out = ThemeCreatorMetrics.swatchRingGap + ThemeCreatorMetrics.swatchRing
    ring.frame = swatchFrame(index).insetBy(dx: -out, dy: -out)
    ring.borderColor = NSColor.controlAccentColor.cgColor
    CATransaction.commit()
    for (offset, element) in elements.enumerated() { element.isSelected = offset == index }
    setAccessibilityValue(Self.title(selected))
  }

  override func layout() {
    super.layout()
    update(selected: selected, flavor: ThemeFlavor(appearance: effectiveAppearance))
  }

  override var focusRingRect: NSRect {
    let index = Self.choices.firstIndex(of: selected) ?? 0
    return swatchFrame(index)
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let index = Self.choices.indices.first(where: { swatchFrame($0).insetBy(dx: -3, dy: -3).contains(point) })
    else { return }
    select(index, byPointer: true)
  }

  func select(_ index: Int, byPointer: Bool) {
    guard Self.choices.indices.contains(index) else { return }
    onSelect?(Self.choices[index], byPointer)
  }

  override func handleKey(_ event: NSEvent) -> Bool {
    guard let arrow = event.themePadArrow else { return false }
    let current = Self.choices.firstIndex(of: selected) ?? 0
    let count = Self.choices.count
    switch arrow {
    case .left, .up: select((current + count - 1) % count, byPointer: false)
    case .right, .down: select((current + 1) % count, byPointer: false)
    }
    return true
  }

  override func accessibilityChildren() -> [Any]? { elements }

  func accessibilityFrame(ofSwatch index: Int) -> NSRect {
    guard let window else { return .zero }
    return window.convertToScreen(convert(swatchFrame(index), to: nil))
  }
}

/// One texture swatch for accessibility: a radio button that selects on press. Its getters override
/// `NSAccessibilityElement` methods, which the SDK does not isolate; AppKit calls them on the main thread, where they
/// reach the main-actor swatch view (as `AXProxyRows` does).
final class ThemeSwatchElement: NSAccessibilityElement {
  let index: Int
  weak var group: ThemeTextureSwatchesView?
  var isSelected = false

  @MainActor
  init(index: Int, title: String, group: ThemeTextureSwatchesView) {
    self.index = index
    self.group = group
    super.init()
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel(title)
    setAccessibilityIdentifier(AXID.ThemeCreator.texture)
    setAccessibilityParent(group)
  }

  override func accessibilityValue() -> Any? { isSelected ? 1 : 0 }

  override func accessibilityFrame() -> NSRect {
    guard Thread.isMainThread else { return .zero }
    let index = index, group = group
    return MainActor.assumeIsolated { group?.accessibilityFrame(ofSwatch: index) ?? .zero }
  }

  override func accessibilityPerformPress() -> Bool {
    guard Thread.isMainThread else { return false }
    let index = index, group = group
    MainActor.assumeIsolated { group?.select(index, byPointer: false) }
    return true
  }
}

// MARK: - Texture previews

/// The texture tiles as ink for the swatches and the amount track: black (light) or white (dark) at the texture's
/// darkening, scaled so every texture's average ink is `averageInk`: loud sand and quiet grain read alike at 18 pt.
/// Built once per texture and tone.
@MainActor
enum ThemeTextureInk {
  private static var cache: [String: CGImage] = [:]
  private static var patterns: [String: CGColor] = [:]
  /// The average ink alpha of a preview.
  nonisolated static let averageInk = 0.16

  /// The preview, once `ThemeCreatorImages.prepare(scale:)` built it; nil before.
  static func image(_ texture: ThemeTexture, dark: Bool) -> CGImage? { cache[key(texture, dark: dark)] }

  nonisolated static func key(_ texture: ThemeTexture, dark: Bool) -> String { "\(texture.rawValue)-\(dark)" }

  static func store(_ images: [String: CGImage]) { cache.merge(images) { $1 } }

  /// Builds a preview; synthesizes the texture tile, so it runs off the main thread (`ThemeCreatorImages`).
  nonisolated static func makeImage(_ texture: ThemeTexture, dark: Bool) -> CGImage? {
    let tile = texture.tile(scale: 2)
    var pixels = [UInt8](repeating: 0, count: tile.pixels * tile.pixels * 4)
    let ink: UInt8 = dark ? 255 : 0
    let stretch = min(averageInk / max(1 - texture.meanFactor, 0.01), 2.5)
    for (index, factor) in tile.bytes.enumerated() {
      let alpha = min(max((1 - Double(factor) / 255) * stretch, 0), 1)
      let a = UInt8((alpha * 255).rounded())
      let premultiplied = UInt8((Double(ink) * alpha).rounded())
      pixels[index * 4] = premultiplied
      pixels[index * 4 + 1] = premultiplied
      pixels[index * 4 + 2] = premultiplied
      pixels[index * 4 + 3] = a
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    return CGImage(width: tile.pixels, height: tile.pixels, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: tile.pixels * 4, space: space,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  /// The ink as a repeating pattern, 100 pt per tile.
  static func pattern(_ texture: ThemeTexture, dark: Bool) -> CGColor? {
    let key = key(texture, dark: dark)
    if let cached = patterns[key] { return cached }
    guard let image = image(texture, dark: dark) else { return nil }
    let points = CGFloat(ThemeTexture.tilePoints)
    let color = NSColor(patternImage: NSImage(cgImage: image, size: NSSize(width: points, height: points))).cgColor
    patterns[key] = color
    return color
  }

  /// An 8 pt checkerboard of `fill` on clear, for the opacity track.
  static func checkerboard(_ fill: RGBA) -> CGColor {
    let key = "checker-\(fill.red)-\(fill.green)-\(fill.blue)-\(fill.alpha)"
    if let cached = patterns[key] { return cached }
    let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { _ in
      fill.nsColor().setFill()
      NSRect(x: 0, y: 0, width: 4, height: 4).fill()
      NSRect(x: 4, y: 4, width: 4, height: 4).fill()
      return true
    }
    let color = NSColor(patternImage: image).cgColor
    patterns[key] = color
    return color
  }
}
