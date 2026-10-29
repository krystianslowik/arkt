import AppKit
import Motion

// The pieces of the browser data import views (#514): the style (the everyday sheet or the first run's Hero entry),
// text, the status glyphs, the bars, the checkbox and a row. Frames are set directly; nothing here changes a frame
// while it animates (transform and opacity only).

// MARK: - Style

struct ImportPalette {
  var text: NSColor
  var secondary: NSColor
  var hairline: NSColor
  /// The recessed list field (the sheet); clear in the Hero entry, which has no card.
  var field: NSColor
  var checkFill: NSColor
  var checkInk: NSColor
  var track: NSColor
  var fill: NSColor
  var accent: NSColor
  var halo: [NSShadow]

  @MainActor
  static func sheet(flavor: ThemeFlavor, increaseContrast: Bool) -> ImportPalette {
    func color(_ token: TokenPair) -> NSColor { token.resolve(flavor).nsColor() }
    return ImportPalette(
      text: color(ShellTokens.primaryText), secondary: color(ShellTokens.secondaryText),
      hairline: color(increaseContrast ? BrandTokens.brandHairlineContrast : BrandTokens.brandHairline),
      field: color(ArchiveTokens.listField), checkFill: color(BrandTokens.brandTextPrimary),
      checkInk: color(BrandTokens.surfaceBrand), track: color(BrandTokens.brandControlFillPressed),
      fill: color(BrandTokens.brandTextPrimary), accent: color(BrandTokens.accentText), halo: [])
  }

  @MainActor
  static func hero(_ appearance: OnboardingAppearance) -> ImportPalette {
    ImportPalette(
      text: appearance.textPrimary, secondary: appearance.textSecondary, hairline: appearance.hairline, field: .clear,
      checkFill: appearance.textPrimary, checkInk: appearance.surface, track: appearance.controlFillPressed,
      fill: appearance.textPrimary, accent: appearance.accentText, halo: appearance.halo)
  }
}

@MainActor
struct ImportViewStyle {
  enum Kind { case sheet, hero }

  var kind: Kind
  var palette: ImportPalette
  var reduceMotion: Bool
  /// The Hero entry in a window shorter than 700 pt.
  var compact = false

  var isHero: Bool { kind == .hero }
  var glyphSize: CGFloat { isHero ? (compact ? 20 : 22) : 16 }
  var rowHeight: CGFloat { isHero ? (compact ? 44 : 52) : 36 }
  var rowHeightWithDetail: CGFloat { isHero ? (compact ? 58 : 68) : 44 }
  var rowInset: CGFloat { isHero ? 8 : 12 }
  var glyphGap: CGFloat { isHero ? 16 : 12 }
  var rowBarHeight: CGFloat { isHero ? 4 : 3 }
  var overallBarHeight: CGFloat { 6 }
  var hairlineWidth: CGFloat { isHero ? 1 : 0.5 }
  var groupGap: CGFloat { isHero ? (compact ? 14 : 22) : 16 }
  var headingGap: CGFloat { isHero ? 6 : 6 }

  static func sheet(for view: NSView, reduceMotion: Bool? = nil) -> ImportViewStyle {
    ImportViewStyle(
      kind: .sheet,
      palette: .sheet(flavor: ThemeFlavor(appearance: view.effectiveAppearance),
                      increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast),
      reduceMotion: reduceMotion ?? ArchiveMotion.reduceMotion())
  }

  static func hero(_ appearance: OnboardingAppearance, compact: Bool) -> ImportViewStyle {
    ImportViewStyle(kind: .hero, palette: .hero(appearance), reduceMotion: appearance.reduceMotion, compact: compact)
  }
}

// MARK: - Text

enum ImportTextRole {
  case title, subtitle, eyebrow, heading, name, detail, count, status, note, progressLead, progressTrail
}

enum ImportTone { case primary, secondary, accent }

/// One piece of text: the system font in the sheet, the brand face (rendered once, with the halo) in the Hero entry.
@MainActor
final class ImportText: NSView {
  /// A value switches between the count face and the status face.
  var role: ImportTextRole { didSet { if role != oldValue { brand?.role = Self.brandRole(role); refresh() } } }
  private(set) var style: ImportViewStyle
  var text = "" { didSet { if text != oldValue { refresh() } } }
  var tone: ImportTone = .primary { didSet { if tone != oldValue { refresh() } } }
  /// The part of the text drawn heavier (the Keychain line's "Choose Allow, not Always Allow").
  var emphasis: String? { didSet { if emphasis != oldValue { refresh() } } }
  var alignment: NSTextAlignment { didSet { if alignment != oldValue { refresh() } } }
  private let field: NSTextField?
  private let brand: BrandLabel?

  init(role: ImportTextRole, style: ImportViewStyle, alignment: NSTextAlignment = .left, accessible: Bool = false) {
    self.role = role
    self.style = style
    self.alignment = alignment
    if style.isHero {
      field = nil
      brand = BrandLabel(role: Self.brandRole(role), color: style.palette.text)
    } else {
      let field = NSTextField(wrappingLabelWithString: "")
      field.isSelectable = false
      field.allowsDefaultTighteningForTruncation = false
      field.usesSingleLineMode = false
      self.field = field
      brand = nil
    }
    super.init(frame: .zero)
    if let field { addSubview(field) }
    if let brand {
      brand.compact = style.compact
      brand.halo = style.palette.halo
      brand.emphasisColor = style.palette.text
      addSubview(brand)
    }
    refresh()
    setAccessibilityElement(accessible)
    field?.setAccessibilityElement(accessible)
    brand?.setAccessibilityElement(accessible)
    if accessible { setAccessibilityRole(.staticText) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  private static func brandRole(_ role: ImportTextRole) -> BrandType.Role {
    switch role {
    case .title: .dataTitle
    case .subtitle: .lede
    case .eyebrow, .heading: .eyebrow
    case .name: .dataRow
    case .detail, .progressTrail: .dataDetail
    case .count: .dataCount
    case .status: .dataStatus
    case .note: .dataNote
    case .progressLead: .dataProgress
    }
  }

  private var isSingleLine: Bool {
    switch role {
    case .name, .detail, .count, .status, .heading, .eyebrow, .progressLead, .progressTrail: true
    case .title, .subtitle, .note: false
    }
  }

  private func systemFont() -> NSFont {
    switch role {
    case .title: .systemFont(ofSize: 15, weight: .semibold)
    case .subtitle, .detail, .note, .progressTrail, .eyebrow: .systemFont(ofSize: 12)
    case .heading: .systemFont(ofSize: 12, weight: .semibold)
    case .name: .systemFont(ofSize: 13, weight: .medium)
    case .progressLead: .systemFont(ofSize: 13, weight: .semibold)
    case .count, .status: .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    }
  }

  private var color: NSColor {
    switch tone {
    case .primary: style.palette.text
    case .secondary: style.palette.secondary
    case .accent: style.palette.accent
    }
  }

  func apply(style: ImportViewStyle) {
    self.style = style
    brand?.halo = style.palette.halo
    brand?.emphasisColor = style.palette.text
    refresh()
  }

  private func refresh() {
    if let brand {
      brand.text = text
      brand.color = color
      brand.alignment = alignment
      brand.emphasis = emphasis.map { [$0] } ?? []
      return
    }
    guard let field else { return }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = isSingleLine ? .byTruncatingTail : .byWordWrapping
    if role == .note { paragraph.lineSpacing = 2 }
    let font = systemFont()
    let result = NSMutableAttributedString(string: text, attributes: [
      .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
    ])
    if let emphasis, let range = Optional(result.mutableString.range(of: emphasis)), range.location != NSNotFound {
      result.addAttributes([.font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                            .foregroundColor: style.palette.text], range: range)
    }
    field.attributedStringValue = result
    field.lineBreakMode = isSingleLine ? .byTruncatingTail : .byWordWrapping
    field.maximumNumberOfLines = isSingleLine ? 1 : 0
  }

  /// The size the text takes in `width`: single-line text never exceeds it (the sheet truncates, the Hero wraps).
  func fitting(width: CGFloat) -> NSSize {
    guard !text.isEmpty else { return .zero }
    if let brand {
      brand.maxWidth = max(1, width)
      let size = brand.textSize
      return NSSize(width: ceil(size.width), height: ceil(size.height))
    }
    guard let field else { return .zero }
    let bounds = NSRect(x: 0, y: 0, width: isSingleLine ? 10_000 : max(1, width), height: 10_000)
    let size = field.cell?.cellSize(forBounds: bounds) ?? .zero
    return NSSize(width: min(ceil(size.width), width), height: ceil(size.height))
  }

  /// Sets the frame to the fitted size at (`x`, `y`) inside `width` (`alignment` decides where it sits in it) and
  /// returns the size.
  @discardableResult
  func place(x: CGFloat, y: CGFloat, width: CGFloat) -> NSSize {
    let size = fitting(width: width)
    let originX: CGFloat = switch alignment {
    case .right: x + width - size.width
    case .center: x + (width - size.width) / 2
    default: x
    }
    frame = NSRect(x: originX.rounded(), y: y.rounded(), width: size.width, height: size.height)
    let content = NSRect(origin: .zero, size: size)
    field?.frame = content
    brand?.frame = content
    isHidden = text.isEmpty
    return size
  }
}

// MARK: - Glyph

/// The 16 pt (22 pt in the Hero entry) slot at a row's leading edge while importing and in the result: done (a check
/// in a ring), working (an arc), waiting (a dashed ring), skipped (a dash in a ring) and not imported (an exclamation
/// in a ring, never red: nothing here is destructive). Color is never the only signal: the row's value says it in words.
@MainActor
final class ImportGlyphView: NSView {
  private let ring = CAShapeLayer()
  private let mark = CAShapeLayer()
  private let arc = CAShapeLayer()
  private(set) var shown: BrowserDataImportRow.Leading?
  private var style: ImportViewStyle

  init(style: ImportViewStyle) {
    self.style = style
    super.init(frame: .zero)
    wantsLayer = true
    layer?.masksToBounds = false
    for shape in [ring, mark, arc] {
      shape.fillColor = nil
      shape.lineCap = .round
      shape.lineJoin = .round
      layer?.addSublayer(shape)
    }
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {}

  var isSpinning: Bool { arc.animation(forKey: "spin") != nil }

  func apply(style: ImportViewStyle) {
    self.style = style
    if let shown { set(shown, animated: false, force: true) }
  }

  func set(_ leading: BrowserDataImportRow.Leading, animated: Bool, force: Bool = false) {
    let previous = shown
    // The same glyph again (a progress event for a row that keeps working) must not restart its spin.
    if previous == leading, !force { return }
    shown = leading
    let palette = style.palette
    let size = style.glyphSize
    let stroke: CGFloat = style.isHero ? 2 : 1.5
    let box = CGRect(x: 0, y: 0, width: size, height: size)
    let circle = CGPath(ellipseIn: box.insetBy(dx: stroke / 2, dy: stroke / 2), transform: nil)
    OnboardingMotion.set {
      for shape in [ring, mark, arc] {
        shape.frame = box
        shape.lineWidth = stroke
      }
      ring.path = circle
      ring.lineDashPattern = nil
      mark.path = nil
      arc.path = nil
      ring.opacity = 1
      stopSpinning()
      switch leading {
      case .checkbox:
        ring.opacity = 0
      case .done:
        ring.strokeColor = palette.text.cgColor
        mark.strokeColor = palette.text.cgColor
        mark.path = Self.check(size)
      case .working:
        ring.strokeColor = palette.secondary.withAlphaComponent(0.35).cgColor
        arc.strokeColor = palette.text.cgColor
        let radius = (size - stroke) / 2
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: radius, startAngle: -.pi / 2, endAngle: 0,
                    clockwise: false)
        arc.path = path
      case .waiting:
        ring.strokeColor = palette.secondary.cgColor
        ring.lineDashPattern = [NSNumber(value: Double(size) * 0.14), NSNumber(value: Double(size) * 0.17)]
      case .skipped:
        ring.strokeColor = palette.secondary.cgColor
        mark.strokeColor = palette.secondary.cgColor
        let path = CGMutablePath()
        path.move(to: CGPoint(x: size * 0.3, y: size / 2))
        path.addLine(to: CGPoint(x: size * 0.7, y: size / 2))
        mark.path = path
      case .notImported:
        ring.strokeColor = palette.secondary.cgColor
        mark.strokeColor = palette.secondary.cgColor
        let path = CGMutablePath()
        path.move(to: CGPoint(x: size / 2, y: size * 0.27))
        path.addLine(to: CGPoint(x: size / 2, y: size * 0.55))
        path.move(to: CGPoint(x: size / 2, y: size * 0.74))
        path.addLine(to: CGPoint(x: size / 2, y: size * 0.745))
        mark.path = path
      }
    }
    if leading == .working, !style.reduceMotion { startSpinning() }
    guard animated, previous != leading, leading == .done, let layer else { return }
    // A type finished: the check pops from scale 0.8 on `springyFast`; under Reduce Motion it cross-fades in.
    if style.reduceMotion {
      OnboardingMotion.set { layer.opacity = 0 }
      OnboardingMotion.animate(layer, "opacity", to: Float(1), duration: 0.15)
    } else {
      layer.add(SpringAnimationFactory.make(keyPath: "transform.scale", from: 0.8, to: 1,
                                            parameters: SpringPreset.springyFast.parameters), forKey: "pop")
    }
  }

  private func startSpinning() {
    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
    spin.fromValue = 0
    spin.toValue = -2 * Double.pi
    spin.duration = 0.9
    spin.repeatCount = .infinity
    spin.isRemovedOnCompletion = false
    arc.add(spin, forKey: "spin")
  }

  private func stopSpinning() { arc.removeAnimation(forKey: "spin") }

  static func check(_ size: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: size * 0.29, y: size * 0.52))
    path.addLine(to: CGPoint(x: size * 0.44, y: size * 0.66))
    path.addLine(to: CGPoint(x: size * 0.71, y: size * 0.36))
    return path
  }
}

// MARK: - Bar

/// A progress bar: a track and a fill that scales from its leading edge (transform only). While `sweeping`, a soft
/// highlight crosses it every 1.4 s. Under Reduce Motion the fill moves in tenths without animation and nothing
/// sweeps: the count beside it is the indicator.
@MainActor
final class ImportBarView: NSView {
  private let track = CALayer()
  private let fill = CALayer()
  private let sweep = CAGradientLayer()
  private var style: ImportViewStyle
  private(set) var fraction: Double = 0
  private(set) var isSweeping = false
  /// The fraction as drawn: the step it was quantized to under Reduce Motion.
  private(set) var displayedFraction: Double = 0

  init(style: ImportViewStyle) {
    self.style = style
    super.init(frame: .zero)
    wantsLayer = true
    layer?.addSublayer(track)
    track.masksToBounds = true
    track.addSublayer(fill)
    track.addSublayer(sweep)
    fill.anchorPoint = CGPoint(x: 0, y: 0.5)
    sweep.startPoint = CGPoint(x: 0, y: 0.5)
    sweep.endPoint = CGPoint(x: 1, y: 0.5)
    sweep.opacity = 0
    setAccessibilityElement(false)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {}

  func apply(style: ImportViewStyle) {
    self.style = style
    restyle()
    set(fraction: fraction, animated: false, sweeping: isSweeping)
  }

  private func restyle() {
    OnboardingMotion.set {
      track.backgroundColor = style.palette.track.cgColor
      fill.backgroundColor = style.palette.fill.cgColor
      sweep.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.45).cgColor,
                      NSColor.white.withAlphaComponent(0).cgColor]
    }
  }

  func set(fraction value: Double, animated: Bool, sweeping: Bool) {
    fraction = min(1, max(0, value.isNaN ? 0 : value))
    displayedFraction = style.reduceMotion && fraction < 1 ? (fraction * 10).rounded(.down) / 10 : fraction
    let scale = CGFloat(displayedFraction)
    let move = animated && !style.reduceMotion
    if move {
      OnboardingMotion.animate(fill, "transform.scale.x", to: scale, duration: 0.25)
    } else {
      OnboardingMotion.set { fill.setValue(scale, forKeyPath: "transform.scale.x") }
      fill.removeAnimation(forKey: "transform.scale.x")
    }
    updateSweep(sweeping && !style.reduceMotion)
  }

  private func updateSweep(_ on: Bool) {
    guard on != isSweeping else { return }
    isSweeping = on
    if on {
      sweep.opacity = 1
      let slide = CABasicAnimation(keyPath: "transform.translation.x")
      slide.fromValue = -sweep.bounds.width
      slide.toValue = bounds.width
      slide.duration = 1.4
      slide.repeatCount = .infinity
      slide.isRemovedOnCompletion = false
      sweep.add(slide, forKey: "sweep")
    } else {
      sweep.removeAnimation(forKey: "sweep")
      sweep.opacity = 0
    }
  }

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      track.frame = bounds
      track.cornerRadius = bounds.height / 2
      fill.bounds = CGRect(origin: .zero, size: bounds.size)
      fill.position = CGPoint(x: 0, y: bounds.height / 2)
      sweep.frame = CGRect(x: 0, y: 0, width: min(60, bounds.width / 3), height: bounds.height)
    }
    if isSweeping {
      isSweeping = false
      updateSweep(true)
    }
  }
}

// MARK: - Checkbox

/// The consent checkbox: 16 pt, radius 4.5, graphite fill (ivory in dark) with an inverted check when on. Mustard is
/// never a checkbox fill: it stays on the one primary pill. Space toggles; the system focus ring; VoiceOver reads a
/// checkbox with the row's label ("Spaces and tabs, 213"), its value and the note as help.
@MainActor
final class ImportCheckbox: NSView {
  var onToggle: (@MainActor (Bool) -> Void)?
  private(set) var isOn = false
  private(set) var isEnabled = true
  private let box = CALayer()
  private let tick = CAShapeLayer()
  private var style: ImportViewStyle

  init(style: ImportViewStyle) {
    self.style = style
    super.init(frame: .zero)
    wantsLayer = true
    layer?.addSublayer(box)
    tick.fillColor = nil
    tick.lineCap = .round
    tick.lineJoin = .round
    box.addSublayer(tick)
    focusRingType = .exterior
    setAccessibilityElement(true)
    setAccessibilityRole(.checkBox)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { isEnabled }
  override var canBecomeKeyView: Bool { isEnabled && !isHidden }
  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() {}

  func apply(style: ImportViewStyle) {
    self.style = style
    restyle()
  }

  func set(isOn: Bool, isEnabled: Bool, animated: Bool) {
    let changed = self.isOn != isOn
    self.isOn = isOn
    self.isEnabled = isEnabled
    setAccessibilityValue(isOn ? 1 : 0)
    setAccessibilityEnabled(isEnabled)
    restyle()
    // Nothing animates on a keyboard action; a pointer toggle fades the check in 150 ms (instant under Reduce Motion).
    if changed, animated, !style.reduceMotion {
      OnboardingMotion.animate(tick, "opacity", to: Float(isOn ? 1 : 0), duration: 0.15)
    }
  }

  private func restyle() {
    let palette = style.palette
    OnboardingMotion.set {
      box.cornerRadius = 4.5
      box.cornerCurve = .continuous
      box.backgroundColor = (isOn ? palette.checkFill : NSColor.clear).cgColor
      box.borderWidth = isOn ? 0 : 1.5
      box.borderColor = palette.secondary.cgColor
      tick.strokeColor = palette.checkInk.cgColor
      tick.lineWidth = 1.8
      tick.opacity = isOn ? 1 : 0
      layer?.opacity = isEnabled ? 1 : 0.4
    }
  }

  override func layout() {
    super.layout()
    OnboardingMotion.set {
      box.frame = bounds
      tick.frame = bounds
      tick.path = ImportGlyphView.check(min(bounds.width, bounds.height))
    }
  }

  /// A checkbox that takes focus scrolls into view (the Hero entry scrolls when the window is short).
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { scrollToVisible(bounds.insetBy(dx: -8, dy: -12)) }
    return accepted
  }

  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: 4.5, yRadius: 4.5).fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  private func toggle() {
    guard isEnabled else { return }
    set(isOn: !isOn, isEnabled: isEnabled, animated: false)
    onToggle?(isOn)
  }

  override func mouseUp(with event: NSEvent) {
    if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { toggle() }
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " { toggle() } else { super.keyDown(with: event) }
  }

  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    toggle()
    return true
  }
}

// MARK: - Row

/// One row: a checkbox or a status glyph, the name with an optional detail under it, an optional bar under the name
/// while it works, and the count or status at the trailing edge. The name truncates before the value does.
@MainActor
final class ImportRowView: NSView {
  let kind: BrowserDataKind
  private(set) var style: ImportViewStyle
  let checkbox: ImportCheckbox
  let glyph: ImportGlyphView
  let nameText: ImportText
  let detailText: ImportText
  let valueText: ImportText
  let bar: ImportBarView
  private let hairline = CALayer()
  private(set) var row: BrowserDataImportRow?
  var showsHairline = false { didSet { needsLayout = true } }
  var onToggle: (@MainActor (BrowserDataKind, Bool) -> Void)?

  init(kind: BrowserDataKind, style: ImportViewStyle) {
    self.kind = kind
    self.style = style
    checkbox = ImportCheckbox(style: style)
    glyph = ImportGlyphView(style: style)
    nameText = ImportText(role: .name, style: style)
    detailText = ImportText(role: .detail, style: style)
    valueText = ImportText(role: .count, style: style, alignment: .right)
    bar = ImportBarView(style: style)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.addSublayer(hairline)
    for view in [glyph, checkbox, nameText, detailText, valueText, bar] as [NSView] { addSubview(view) }
    let identifier = AXID.BrowserDataImport.row(kind.identifier)
    checkbox.setAccessibilityIdentifier(identifier)
    setAccessibilityIdentifier(identifier)
    checkbox.onToggle = { [weak self] isOn in
      guard let self else { return }
      onToggle?(kind, isOn)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  func apply(style: ImportViewStyle) {
    self.style = style
    for text in [nameText, detailText, valueText] { text.apply(style: style) }
    checkbox.apply(style: style)
    glyph.apply(style: style)
    bar.apply(style: style)
    if let row { apply(row, animated: false) }
    needsLayout = true
  }

  func apply(_ row: BrowserDataImportRow, animated: Bool, counting: Bool = false) {
    self.row = row
    nameText.text = row.title
    nameText.tone = row.isDimmed ? .secondary : .primary
    detailText.text = row.detail ?? ""
    detailText.tone = .secondary
    valueText.text = row.value
    valueText.tone = row.isDimmed ? .secondary : .primary
    // Counts (and finished counts) take the count face; words and "x of y" the status face.
    switch row.leading {
    case .checkbox, .done: valueText.role = .count
    default: valueText.role = .status
    }
    // A type with nothing in it is the one row that fades; the others say it in words.
    var faded = false
    if case .checkbox(_, let isEnabled) = row.leading, !isEnabled, !counting { faded = true }
    for text in [nameText, detailText, valueText] { text.alphaValue = faded ? 0.5 : 1 }
    switch row.leading {
    case .checkbox(let isOn, let isEnabled):
      checkbox.isHidden = false
      glyph.isHidden = true
      checkbox.set(isOn: isOn, isEnabled: isEnabled, animated: animated)
      checkbox.setAccessibilityLabel(row.accessibilityLabel)
      checkbox.setAccessibilityHelp(row.accessibilityDescription)
      setAccessibilityElement(false)
    default:
      checkbox.isHidden = true
      glyph.isHidden = false
      glyph.set(row.leading, animated: animated)
      // A progress or result row is one status: "History, 30,854 of 48,210".
      setAccessibilityElement(true)
      setAccessibilityRole(.staticText)
      setAccessibilityLabel(row.accessibilityLabel)
    }
    if let fraction = row.barFraction {
      bar.isHidden = false
      bar.set(fraction: fraction, animated: animated, sweeping: { if case .working = row.leading { true } else { false } }())
    } else {
      bar.isHidden = true
      bar.set(fraction: 0, animated: false, sweeping: false)
    }
    needsLayout = true
  }

  /// The height this row takes.
  var preferredHeight: CGFloat {
    guard let row else { return style.rowHeight }
    return row.detail == nil ? style.rowHeight : style.rowHeightWithDetail
  }

  override func layout() {
    super.layout()
    let inset = style.rowInset
    let slot = style.glyphSize
    let leadingX = inset
    let textX = leadingX + slot + style.glyphGap
    let slotY = ((preferredHeight - slot) / 2).rounded()
    glyph.frame = NSRect(x: leadingX, y: slotY, width: slot, height: slot)
    checkbox.frame = glyph.frame
    let valueMax = max(60, (bounds.width - textX - inset) * 0.55)
    let valueSize = valueText.fitting(width: valueMax)
    valueText.place(x: bounds.width - inset - valueSize.width, y: 0, width: valueSize.width)
    let nameWidth = max(40, bounds.width - textX - inset - valueSize.width - 12)
    let barOn = !bar.isHidden
    let nameHeight = nameText.fitting(width: nameWidth).height
    let detailHeight = detailText.fitting(width: nameWidth).height
    let barGap: CGFloat = 5
    var stack = nameHeight
    if detailHeight > 0 { stack += 2 + detailHeight }
    if barOn { stack += barGap + style.rowBarHeight }
    let top = ((preferredHeight - stack) / 2).rounded()
    nameText.place(x: textX, y: top, width: nameWidth)
    var next = top + nameHeight
    if detailHeight > 0 {
      detailText.place(x: textX, y: next + 2, width: nameWidth)
      next += 2 + detailHeight
    }
    if barOn {
      let barWidth = max(40, bounds.width - textX - inset - valueSize.width - 24)
      bar.frame = NSRect(x: textX, y: (next + barGap).rounded(), width: barWidth, height: style.rowBarHeight)
    }
    // The value sits on the name's baseline row (the first line), centered when there is no detail.
    let valueY = detailHeight > 0 || barOn ? top + (nameHeight - valueSize.height) / 2 : (preferredHeight - valueSize.height) / 2
    valueText.frame.origin.y = valueY.rounded()
    OnboardingMotion.set {
      hairline.backgroundColor = style.palette.hairline.cgColor
      hairline.isHidden = !showsHairline
      hairline.frame = CGRect(x: textX, y: bounds.height - style.hairlineWidth,
                              width: max(0, bounds.width - textX - inset), height: style.hairlineWidth)
    }
  }
}
