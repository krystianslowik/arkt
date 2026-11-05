import AppKit

/// The URL bar: the active tab's address. One class serves the sidebar (host only, under the traffic lights, in a
/// rounded pill) and the Toolbar (full URL as plain centered text, no fill, border or radius, as Arc 1.168 draws it). A press opens the command bar prefilled with the URL (the owner
/// wires `onPress` to Cmd-L, KB-002; a click presses on mouse up inside); right-click or Ctrl-click offers
/// Show / Hide Toolbar (BH-031, GS-042). A site glyph before the text opens the page info panel instead (#582). Frames
/// are set by the owner; the label and glyph are laid out here. Text changes only when the URL does.
@MainActor
public final class URLBarView: NSView {
  public enum Style: Sendable {
    /// `AddressText.host`: the sidebar URL bar.
    case host
    /// `AddressText.full`: the Toolbar.
    case full
  }

  /// Whether the bar shows the host only or the full URL (#80: the Toolbar switches live).
  public var style: Style {
    didSet {
      guard style != oldValue else { return }
      refreshText()
    }
  }
  /// The sidebar bar draws a rounded pill and natural-aligned text; the Toolbar bar is centered plain text.
  private let showsPill: Bool
  /// The active tab's URL; nil while no tab is shown.
  public var url: URL? {
    didSet { if url != oldValue { refreshText() } }
  }
  /// What the bar shows for `url` (also the accessibility value).
  public private(set) var displayedText = ""
  /// Picks the context menu's title.
  public var isToolbarVisible = false
  /// Click, or VoiceOver press.
  public var onPress: (@MainActor () -> Void)?
  /// The context menu's Show / Hide Toolbar item.
  public var onToggleToolbar: (@MainActor () -> Void)?
  /// The page's site glyph at the text's leading edge (#582): a lock, a warning or a file, as the page info panel's
  /// connection line shows it. Nil hides it: no page, a page of the browser itself (the pill stays inert), or an engine
  /// without page info.
  public var siteSymbol: String? {
    didSet {
      guard siteSymbol != oldValue else { return }
      siteGlyph.image = siteSymbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
      siteGlyph.isHidden = siteGlyph.image == nil
      setAccessibilityCustomActions(siteGlyph.isHidden ? nil : [
        NSAccessibilityCustomAction(name: "Show Site Controls") { [weak self] in
          MainActor.assumeIsolated { self?.onPressSiteGlyph?() }
          return true
        },
      ])
      needsLayout = true
    }
  }
  /// A click on the site glyph, or VoiceOver's Show Site Controls: the page info panel.
  public var onPressSiteGlyph: (@MainActor () -> Void)?
  public var flavor: ThemeFlavor = .light {
    didSet { if flavor != oldValue { applyColors() } }
  }

  /// The bars' only font; it never changes.
  private static let font = NSFont.systemFont(ofSize: SidebarMetrics.urlBarFontSize, weight: .medium)
  /// One line of `font`, measured once for every bar instead of on each layout pass.
  static let labelHeight: CGFloat = {
    let probe = NSTextField(labelWithString: "")
    probe.font = font
    return ceil(probe.intrinsicContentSize.height)
  }()

  let label = NSTextField(labelWithString: "")
  let siteGlyph = NSImageView()
  static let siteGlyphSize: CGFloat = 14
  static let siteGlyphGap: CGFloat = 6
  /// Which part a left mouse down landed on; cleared on its mouse up.
  private enum Press { case bar, siteGlyph }
  private var press: Press?
  private var isHovered = false {
    didSet { if isHovered != oldValue { needsDisplay = true } }
  }
  private var hoverArea: NSTrackingArea?

  public init(style: Style) {
    self.style = style
    self.showsPill = style == .host
    super.init(frame: .zero)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layer?.cornerCurve = .continuous
    label.font = Self.font
    label.lineBreakMode = showsPill ? .byTruncatingTail : .byTruncatingMiddle
    label.alignment = showsPill ? .natural : .center
    label.maximumNumberOfLines = 1
    label.cell?.usesSingleLineMode = true
    label.autoresizingMask = []
    label.setAccessibilityElement(false)
    addSubview(label)
    siteGlyph.imageScaling = .scaleProportionallyUpOrDown
    siteGlyph.symbolConfiguration = .init(pointSize: 11, weight: .medium)
    siteGlyph.isHidden = true
    siteGlyph.setAccessibilityElement(false)
    addSubview(siteGlyph)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel("Address")
    setAccessibilityHelp("Opens the command bar with this address")
    setAccessibilityValue("")
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var wantsUpdateLayer: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }

  private func refreshText() {
    let text = style == .host ? AddressText.host(url) : AddressText.full(url)
    guard text != displayedText else { return }
    displayedText = text
    label.stringValue = text
    if !siteGlyph.isHidden { needsLayout = true }      // the Toolbar's glyph sits just before the text
    toolTip = url?.absoluteString
    setAccessibilityValue(text)
    NSAccessibility.post(element: self, notification: .valueChanged)
  }

  private func applyColors() {
    label.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    siteGlyph.contentTintColor = label.textColor
    needsDisplay = true
  }

  public override func updateLayer() {
    guard let layer, showsPill else { return }   // the Toolbar's URL is plain text
    layer.cornerRadius = SidebarMetrics.urlBarCornerRadius
    let token = isHovered ? ShellTokens.sidebarItemHovered : ShellTokens.sidebarItemBackground
    layer.backgroundColor = token.resolve(flavor).cgColor
  }

  public override func layout() {
    super.layout()
    let inset = showsPill ? SidebarMetrics.urlBarTextInset : 0
    let height = Self.labelHeight
    let y = ((bounds.height - height) / 2).rounded()
    let available = max(0, bounds.width - 2 * inset)
    guard !siteGlyph.isHidden else {
      label.frame = NSRect(x: inset, y: y, width: available, height: height)
      return
    }
    let glyph = Self.siteGlyphSize
    let lead = glyph + Self.siteGlyphGap
    // The pill keeps the glyph at its leading inset; the centered Toolbar text carries it just before the text.
    let textWidth = min(ceil(label.attributedStringValue.size().width) + 4, max(0, available - lead))
    let start = showsPill ? inset : max(inset, ((bounds.width - lead - textWidth) / 2).rounded())
    siteGlyph.frame = NSRect(x: start, y: ((bounds.height - glyph) / 2).rounded(), width: glyph, height: glyph)
    let labelX = start + lead
    label.frame = NSRect(x: labelX, y: y, width: showsPill ? max(0, bounds.width - inset - labelX) : textWidth,
                         height: height)
  }

  /// Where a click opens the page info panel: the glyph and the bar's height around it, up to the text.
  var siteGlyphHitRect: NSRect {
    guard !siteGlyph.isHidden else { return .zero }
    let minX = max(0, siteGlyph.frame.minX - Self.siteGlyphGap)
    return NSRect(x: minX, y: 0, width: siteGlyph.frame.maxX + Self.siteGlyphGap / 2 - minX, height: bounds.height)
  }

  // MARK: Events

  /// The label never takes the click. `point` is in the superview's coordinates.
  public override func hitTest(_ point: NSPoint) -> NSView? {
    !isHidden && frame.contains(point) ? self : nil
  }

  /// Presses on mouse up, like a button: releasing outside the bar cancels.
  public override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control) {
      NSMenu.popUpContextMenu(contextMenu(), with: event, for: self)
      return
    }
    press = siteGlyphHitRect.contains(convert(event.locationInWindow, from: nil)) ? .siteGlyph : .bar
  }

  public override func mouseUp(with event: NSEvent) {
    guard let press else { return }
    self.press = nil
    let point = convert(event.locationInWindow, from: nil)
    switch press {
    case .siteGlyph: if siteGlyphHitRect.contains(point) { onPressSiteGlyph?() }
    case .bar: if bounds.contains(point) { onPress?() }
    }
  }

  public override func menu(for event: NSEvent) -> NSMenu? { contextMenu() }

  /// Show / Hide Toolbar, titled for the current state. Built fresh for each request.
  public func contextMenu() -> NSMenu {
    let menu = NSMenu()
    let item = NSMenuItem(title: ToolbarSetting.menuTitle(isVisible: isToolbarVisible),
                          action: #selector(toggleToolbarFromMenu(_:)), keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return menu
  }

  @objc private func toggleToolbarFromMenu(_ sender: Any?) { onToggleToolbar?() }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  public override func mouseEntered(with event: NSEvent) { isHovered = true }
  public override func mouseExited(with event: NSEvent) { isHovered = false }

  // MARK: Accessibility

  public override func accessibilityPerformPress() -> Bool {
    onPress?()
    return true
  }

  public override func accessibilityPerformShowMenu() -> Bool {
    contextMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
    return true
  }
}
