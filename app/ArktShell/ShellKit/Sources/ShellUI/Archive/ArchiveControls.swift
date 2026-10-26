import AppKit

// MARK: - Motion

/// The Archive window's two small motions (design section 10), both transform or opacity only.
@MainActor
enum ArchiveMotion {
  /// The strong ease-out of the design system: `cubic-bezier(0.23, 1, 0.32, 1)`.
  static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
  /// Press feedback on a pill: scale 0.97 for 160 ms.
  static let pressDuration: CFTimeInterval = 0.16
  static let pressScale: CGFloat = 0.97
  /// The chip strip fades in and out in 150 ms; layout never animates.
  static let fadeDuration: CFTimeInterval = 0.15
  /// Test seam and Reduce Motion: AppKit's setting unless overridden.
  static var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  static func animate(_ layer: CALayer, _ keyPath: String, to value: Any, duration: CFTimeInterval) {
    let from = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.setValue(value, forKeyPath: keyPath)
    CATransaction.commit()
    let animation = CABasicAnimation(keyPath: keyPath)
    animation.fromValue = from
    animation.toValue = value
    animation.duration = duration
    animation.timingFunction = easeOut
    layer.add(animation, forKey: keyPath)
  }

  static func set(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
  }
}

extension NSView {
  /// Light or dark, from the view's effective appearance (the Archive window follows the system).
  var archiveFlavor: ThemeFlavor { ThemeFlavor(appearance: effectiveAppearance) }
}

extension NSControl {
  /// AppKit exposes a control through its cell, so the label goes on both.
  func setArchiveAccessibilityLabel(_ label: String?) {
    setAccessibilityLabel(label)
    cell?.setAccessibilityLabel(label)
  }

  func setArchiveAccessibilityValue(_ value: String?) {
    setAccessibilityValue(value)
    cell?.setAccessibilityValue(value)
  }
}

// MARK: - Pill button

/// The brand's pills, shared by the Archive window (design section 2), the dialogs and the toasts (alerts design 3.2,
/// 4.2): the mustard primary (Restore, Try Again), and neutral pills (Got It, Cancel, a toast's Undo) whose title may
/// be destructive (Clear Archive, Delete Space). A real `NSButton`, so Space, VoiceOver's press, the key view loop and
/// the system focus ring work; the cell draws nothing and layers draw the pill. Colors follow the effective
/// appearance, so a host sets `appearance` to choose the flavor (a toast takes its Space theme's).
@MainActor
final class ArchivePillButton: NSButton {
  enum Style { case primary, neutral, destructive }

  /// Size and type of a pill. `archive`: the Archive window's (13 pt, medium for neutral pills). `dialog`: 28 high,
  /// 13 semibold, padding 16, at least 76 wide. `toastAction`: 24 high, 12 semibold, padding 12.
  struct Metrics: Equatable {
    var height: CGFloat
    var fontSize: CGFloat
    /// Nil: semibold for the primary, medium otherwise (the Archive's pills).
    var weight: NSFont.Weight?
    var padding: CGFloat
    /// Nil: twice the height.
    var minWidth: CGFloat?
    var pressScale: CGFloat

    static func archive(height: CGFloat = ArchiveMetrics.pillHeight) -> Metrics {
      Metrics(height: height, fontSize: 13, weight: nil, padding: 16, minWidth: nil, pressScale: 0.97)
    }

    static let dialog = Metrics(height: 28, fontSize: 13, weight: .semibold, padding: 16, minWidth: 76, pressScale: 0.97)
    static let toastAction = Metrics(height: 24, fontSize: 12, weight: .semibold, padding: 12, minWidth: 0,
                                     pressScale: 0.96)
  }

  let style: Style
  let metrics: Metrics
  private var pillHeight: CGFloat { metrics.height }
  /// A key drawn after the title at half strength (the Peek toast's Reopen, #346); nil: none.
  var shortcut: String? { didSet { restyle(); invalidateIntrinsicContentSize() } }
  /// A 1 pt edge (Increase Contrast on a toast's pill); nil: none.
  var edge: RGBA? { didSet { restyle() } }
  private let body = CALayer()
  private let label = CATextLayer()
  private var hovering = false
  private(set) var pressing = false
  private var tracking: NSTrackingArea?

  convenience init(style: Style, title: String, height: CGFloat = ArchiveMetrics.pillHeight) {
    self.init(style: style, title: title, metrics: .archive(height: height))
  }

  init(style: Style, title: String, metrics: Metrics) {
    self.style = style
    self.metrics = metrics
    super.init(frame: .zero)
    let cell = ArchivePillCell()
    cell.owner = self
    self.cell = cell
    self.title = title
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    focusRingType = .default
    wantsLayer = true
    layer?.masksToBounds = false
    body.cornerCurve = .continuous
    label.alignmentMode = .center
    label.truncationMode = .end
    body.addSublayer(label)
    layer?.addSublayer(body)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var title: String { didSet { restyle(); invalidateIntrinsicContentSize() } }
  /// The opacity while disabled; Settings dims the whole row control itself and sets 1.
  var disabledOpacity: Float = 0.4 { didSet { restyle() } }
  override var isEnabled: Bool { didSet { restyle() } }
  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  private var titleFont: NSFont {
    .systemFont(ofSize: metrics.fontSize, weight: metrics.weight ?? (style == .primary ? .semibold : .medium))
  }

  private var displayedTitle: NSAttributedString {
    let color = displayedTitleColor.nsColor()
    let text = NSMutableAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: color])
    if let shortcut {
      text.append(NSAttributedString(string: " " + shortcut, attributes: [
        .font: NSFont.systemFont(ofSize: metrics.fontSize, weight: .medium),
        .foregroundColor: color.withAlphaComponent(0.5),
      ]))
    }
    return text
  }

  /// The drawn title, the key included (tests).
  var displayedTitleText: String { displayedTitle.string }

  override var intrinsicContentSize: NSSize {
    let width = ceil(displayedTitle.size().width) + 2 * metrics.padding
    return NSSize(width: max(width, metrics.minWidth ?? pillHeight * 2), height: pillHeight)
  }

  /// The fill drawn now, for tests: mustard for an enabled primary (hover and pressed shades), the neutral fill
  /// otherwise, and the quiet fill for a disabled primary (a disabled primary is not mustard).
  var displayedFill: RGBA {
    let flavor = archiveFlavor
    switch style {
    case .primary where isEnabled:
      return (pressing ? BrandTokens.accentPressed : hovering ? BrandTokens.accentHighlight : BrandTokens.accent)
        .resolve(flavor)
    case .primary:
      return ShellTokens.sidebarItemBackground.resolve(flavor)
    case .neutral, .destructive:
      return (hovering && isEnabled ? ShellTokens.sidebarItemBackground : ShellTokens.sidebarItemHovered)
        .resolve(flavor)
    }
  }

  var displayedTitleColor: RGBA {
    let flavor = archiveFlavor
    switch style {
    case .primary: return isEnabled ? BrandTokens.onAccent.resolve(flavor) : ShellTokens.primaryText.resolve(flavor)
    case .neutral: return ShellTokens.primaryText.resolve(flavor)
    case .destructive: return ArchiveTokens.destructiveText.resolve(flavor)
    }
  }

  private func restyle() {
    let scale = window?.backingScaleFactor ?? 2
    ArchiveMotion.set {
      body.backgroundColor = displayedFill.cgColor
      body.borderColor = edge?.cgColor
      body.borderWidth = edge == nil ? 0 : 1
      label.string = displayedTitle
      label.contentsScale = scale
      layer?.opacity = isEnabled ? 1 : disabledOpacity
    }
    needsLayout = true
  }

  override func layout() {
    super.layout()
    ArchiveMotion.set {
      body.bounds = bounds
      body.position = CGPoint(x: bounds.midX, y: bounds.midY)
      body.cornerRadius = bounds.height / 2
      let lineHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
      let inset = min(8, metrics.padding / 2)
      label.frame = CGRect(x: inset, y: ((bounds.height - lineHeight) / 2).rounded(),
                           width: max(0, bounds.width - 2 * inset), height: lineHeight)
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    restyle()
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    restyle()
  }

  /// Follows the cell's highlight while the pointer is down: the pressed fill, plus the metrics' press scale for 160 ms
  /// ease-out (feedback; Reduce Motion keeps the fill change only). A destructive or neutral pill keeps its hover fill
  /// while pressed (no pressed fill under destructive text, alerts design 3.2).
  fileprivate func setPressed(_ pressed: Bool) {
    guard isEnabled, pressed != pressing else { return }
    pressing = pressed
    restyle()
    guard !ArchiveMotion.reduceMotion() else { return }
    let scale = pressed ? metrics.pressScale : 1
    ArchiveMotion.animate(body, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)),
                          duration: ArchiveMotion.pressDuration)
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " {
      performClick(nil)
      return
    }
    super.keyDown(with: event)
  }
}

/// Draws nothing but the focus ring mask (a capsule) and reports highlight changes to its button.
@MainActor
final class ArchivePillCell: NSButtonCell {
  weak var owner: ArchivePillButton?

  override var isHighlighted: Bool {
    didSet { owner?.setPressed(isHighlighted) }
  }

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}

  override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
    let radius = cellFrame.height / 2
    NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius).fill()
  }

  override func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect { cellFrame }
}

// MARK: - Text link

/// A quiet text button (Clear Archive..., Clear Filters, Open Settings): 12 pt, no fill and no bezel. A destructive
/// link is `destructiveText` and underlines on hover; a secondary one turns `primaryText` on hover. Accessibility
/// reads it as a button.
@MainActor
final class ArchiveLinkButton: NSButton {
  enum Style { case secondary, destructive }

  let style: Style
  /// 12 pt in the Archive window, 13 pt as a dialog's footer link.
  let fontSize: CGFloat
  private var hovering = false
  private var tracking: NSTrackingArea?

  init(style: Style, title: String, fontSize: CGFloat = 12) {
    self.style = style
    self.fontSize = fontSize
    super.init(frame: .zero)
    self.title = title
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    focusRingType = .default
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var title: String { didSet { restyle() } }
  override var isEnabled: Bool { didSet { restyle() } }
  override var mouseDownCanMoveWindow: Bool { false }
  /// The opacity while disabled; Settings dims the whole row control itself and sets 1.
  var disabledOpacity: Float = 0.4 { didSet { restyle() } }

  var displayedColor: RGBA {
    let flavor = archiveFlavor
    switch style {
    case .destructive: return ArchiveTokens.destructiveText.resolve(flavor)
    case .secondary: return (hovering ? ShellTokens.primaryText : ShellTokens.secondaryText).resolve(flavor)
    }
  }

  private func restyle() {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: displayedColor.nsColor(),
    ]
    if style == .destructive, hovering, isEnabled { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
    attributedTitle = NSAttributedString(string: title, attributes: attributes)
    alphaValue = isEnabled ? 1 : CGFloat(disabledOpacity)
    setArchiveAccessibilityLabel(title.replacingOccurrences(of: "...", with: ""))
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    restyle()
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    restyle()
  }
}

// MARK: - Filter button

/// The 32 x 32 filter button at the trailing edge of the title bar: `line.3.horizontal.decrease` in
/// `sidebarForeground`, `sidebarItemBackground` on hover; while any filter is on it keeps the `sidebarItemHovered`
/// fill and the glyph turns `primaryText`.
@MainActor
final class ArchiveFilterButton: NSButton {
  var isActive = false { didSet { if isActive != oldValue { restyle() } } }
  private var hovering = false
  private var tracking: NSTrackingArea?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    title = ""
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    imagePosition = .imageOnly
    focusRingType = .default
    wantsLayer = true
    layer?.cornerRadius = ArchiveMetrics.fieldRadius
    layer?.cornerCurve = .continuous
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  var displayedFill: RGBA? {
    let flavor = archiveFlavor
    if isActive { return ShellTokens.sidebarItemHovered.resolve(flavor) }
    return hovering ? ShellTokens.sidebarItemBackground.resolve(flavor) : nil
  }

  private func restyle() {
    let flavor = archiveFlavor
    let color = (isActive ? ShellTokens.primaryText : ShellTokens.sidebarForeground).resolve(flavor)
    image = SymbolImageCache.shared.symbol("line.3.horizontal.decrease", box: 16, color: color,
                                           scale: window?.backingScaleFactor ?? 2)
    ArchiveMotion.set { layer?.backgroundColor = displayedFill?.cgColor }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }

  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: ArchiveMetrics.fieldRadius, yRadius: ArchiveMetrics.fieldRadius).fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    restyle()
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    restyle()
  }
}

// MARK: - Search field

/// The search field, drawn like the sidebar's URL pill rather than a stock bezel: 32 high, radius 9,
/// `sidebarItemBackground`, a 14 pt magnifier in `sidebarForeground` at 10 leading, 13 pt text, and the system
/// focus ring around the pill.
@MainActor
final class ArchiveSearchField: NSSearchField {
  /// The placeholder text.
  var placeholder = "Search Archive" { didSet { restyle() } }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    let cell = ArchiveSearchFieldCell(textCell: "")
    cell.isEditable = true
    cell.isScrollable = true
    cell.usesSingleLineMode = true
    cell.wraps = false
    cell.sendsWholeSearchString = false
    cell.sendsSearchStringImmediately = true
    self.cell = cell
    isBezeled = false
    isBordered = false
    drawsBackground = false
    focusRingType = .default
    font = .systemFont(ofSize: 13)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }

  func restyle() {
    let flavor = archiveFlavor
    let scale = window?.backingScaleFactor ?? 2
    textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
      .font: NSFont.systemFont(ofSize: 13), .foregroundColor: ShellTokens.secondaryText.resolve(flavor).nsColor(),
    ])
    guard let cell = cell as? ArchiveSearchFieldCell else { return }
    cell.fill = ShellTokens.sidebarItemBackground.resolve(flavor)
    cell.edge = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
      ? ArchiveTokens.increasedContrastEdge.resolve(flavor) : nil
    cell.searchButtonCell?.image = SymbolImageCache.shared.symbol(
      "magnifyingglass", box: 14, color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
    cell.searchButtonCell?.alternateImage = nil
    cell.cancelButtonCell?.image = SymbolImageCache.shared.symbol(
      "xmark.circle.fill", box: 14, color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
    cell.cancelButtonCell?.alternateImage = nil
    needsDisplay = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    restyle()
  }
}

@MainActor
final class ArchiveSearchFieldCell: NSSearchFieldCell {
  var fill = RGBA.black(0.05)
  private static let leading: CGFloat = 10
  private static let glyph: CGFloat = 14
  private static let glyphToText: CGFloat = 7
  private static let trailing: CGFloat = 8
  private static let cancel: CGFloat = 16

  /// Increase Contrast: a 1 pt edge around the pill.
  var edge: RGBA?

  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    fill.nsColor().setFill()
    let radius = ArchiveMetrics.fieldRadius
    NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius).fill()
    if let edge {
      edge.nsColor().setStroke()
      let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5,
                              yRadius: radius - 0.5)
      path.lineWidth = 1
      path.stroke()
    }
    drawInterior(withFrame: cellFrame, in: controlView)
  }

  override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
    let radius = ArchiveMetrics.fieldRadius
    NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius).fill()
  }

  override func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect { cellFrame }

  override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.minX + Self.leading, y: rect.minY + ((rect.height - Self.glyph) / 2).rounded(),
           width: Self.glyph, height: Self.glyph)
  }

  override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.maxX - Self.trailing - Self.cancel, y: rect.minY + ((rect.height - Self.cancel) / 2).rounded(),
           width: Self.cancel, height: Self.cancel)
  }

  /// One text line, vertically centered between the magnifier and the clear button.
  override func searchTextRect(forBounds rect: NSRect) -> NSRect {
    let x = rect.minX + Self.leading + Self.glyph + Self.glyphToText
    let lineHeight = ceil((font ?? .systemFont(ofSize: 13)).boundingRectForFont.height)
    let height = min(rect.height, lineHeight)
    return NSRect(x: x, y: rect.minY + ((rect.height - height) / 2).rounded(),
                  width: max(0, rect.maxX - Self.trailing - Self.cancel - 4 - x), height: height)
  }

  override func drawingRect(forBounds rect: NSRect) -> NSRect { searchTextRect(forBounds: rect) }

  /// The field editor sits where the text is drawn, between the magnifier and the clear button.
  override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                     event: NSEvent?) {
    super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
               event: event)
  }

  override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                       start selStart: Int, length selLength: Int) {
    super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
                 start: selStart, length: selLength)
  }
}
