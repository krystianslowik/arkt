import AppKit
import EngineAPI
import Motion

/// The Pages list's motion (#668, design/private-pages, Motion), as data. A row added or closed: the rows below move
/// 0.20 s on `firm` and a new row fades in. The close and mute buttons fade in on hover, 0.12 s. Reduce Motion: opacity
/// only, the rows jump. Only the layers' position and opacity animate; the frames are final at once.
enum PrivatePagesMotion {
  /// The design system's `firm` curve (as `SidebarBannerMotion.firm`).
  static let firm = MotionCurve(0.25, 1, 0.5, 1)
  static let buttonFade: CFTimeInterval = 0.12
  static let moveKey = "privatePageMove"
  static let fadeKey = "privatePageFade"

  struct Step: Equatable {
    /// The rows below an added or closed row move on `curve`; false: they jump.
    var movesRows: Bool
    var duration: CFTimeInterval
    var curve: MotionCurve
    /// A new row's fade in.
    var fadeDuration: CFTimeInterval
  }

  static func rows(reduceMotion: Bool) -> Step {
    Step(movesRows: !reduceMotion, duration: 0.20, curve: firm, fadeDuration: 0.20)
  }

  /// Fades `layer` in from clear over `duration`; its model opacity stays 1.
  static func fadeIn(_ layer: CALayer?, duration: CFTimeInterval) {
    guard let layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = duration
    fade.timingFunction = firm.timingFunction
    layer.add(fade, forKey: fadeKey)
  }
}

/// A row of the Pages list: a 16 pt favicon, the title on one line truncating at the tail, then the trailing buttons:
/// the mute button while the page plays sound or is muted (always shown), and the close button while the row is
/// hovered. The shown page's row is the current row (`tabCurrent`, the current tab row's shadow in light); a hovered
/// row takes `sidebarItemHovered`. VoiceOver reads the row as a button named by the title (the shown page's row reads
/// as selected), with its buttons as children: "Mute <title>" or "Unmute <title>", and "Close <title>".
@MainActor
final class PrivatePageRowView: NSView {
  static let padding: CGFloat = 9
  static let gap: CGFloat = 9
  static let faviconRadius: CGFloat = 4
  static let buttonRadius: CGFloat = 4
  static let buttonSize: CGFloat = 16

  let tab: TabID
  let faviconView = NSImageView()
  let titleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 13)
    label.lineBreakMode = .byTruncatingTail
    label.usesSingleLineMode = true
    label.cell?.truncatesLastVisibleLine = true
    label.cell?.isScrollable = false
    label.setAccessibilityElement(false)
    return label
  }()
  let muteButton = PrivatePageRowButton()
  let closeButton = PrivatePageRowButton()
  private let background = CALayer()
  var onPress: (@MainActor (TabID) -> Void)?
  var onClose: (@MainActor (TabID) -> Void)?
  var onToggleMute: (@MainActor (TabID) -> Void)?
  private(set) var content: PrivatePageRowContent?
  private var favicon: NSImage?
  private(set) var isHovered = false
  private var hoverArea: NSTrackingArea?

  var flavor: ThemeFlavor = .light {
    didSet { if flavor != oldValue { applyStyle() } }
  }

  init(tab: TabID) {
    self.tab = tab
    super.init(frame: .zero)
    wantsLayer = true
    background.cornerRadius = SidebarMetrics.rowCornerRadius
    background.cornerCurve = .continuous
    background.shadowRadius = ShellTokens.rowLiftShadow.radius
    background.shadowOffset = ShellTokens.rowLiftShadow.flippedOffset   // a sublayer of this flipped view
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    faviconView.wantsLayer = true
    faviconView.layer?.cornerRadius = Self.faviconRadius
    faviconView.layer?.masksToBounds = true
    faviconView.setAccessibilityElement(false)
    addSubview(faviconView)
    addSubview(titleLabel)
    muteButton.target = self
    muteButton.action = #selector(toggleMute(_:))
    muteButton.isHidden = true
    addSubview(muteButton)
    closeButton.target = self
    closeButton.action = #selector(close(_:))
    closeButton.alphaValue = 0
    closeButton.respondsOnlyWhenVisible = true
    addSubview(closeButton)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityIdentifier(AXID.PrivatePages.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  var isShown: Bool { content?.isShown ?? false }

  func apply(_ content: PrivatePageRowContent, favicon: NSImage?) {
    let changed = content != self.content
    self.content = content
    if favicon != nil || content.favicon == nil { self.favicon = favicon }
    guard changed else { return }
    let title = content.displayTitle
    titleLabel.stringValue = title
    setAccessibilityLabel(title)
    setAccessibilitySelected(content.isShown)
    muteButton.isHidden = content.audio == .silent
    muteButton.symbolName = content.audio.symbolName
    muteButton.isPressedLook = content.audio == .muted
    muteButton.setAccessibilityLabel("\(content.audio.toggleTitle) \(title)")
    muteButton.toolTip = content.audio.tooltip
    closeButton.symbolName = "xmark"
    closeButton.symbolSize = SidebarMetrics.closeButtonGlyphSize
    closeButton.setAccessibilityLabel("Close \(title)")
    closeButton.toolTip = "Close"
    applyStyle()
    needsLayout = true
  }

  func setFavicon(_ image: NSImage?) {
    favicon = image
    applyFavicon()
  }

  /// The pointer is over the row: the hovered fill and the close button, which fades in.
  func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    closeButton.alphaValue = hovered ? 1 : 0
    if hovered { PrivatePagesMotion.fadeIn(closeButton.layer, duration: PrivatePagesMotion.buttonFade) }
    applyStyle()
    needsLayout = true
  }

  /// The row's fill now: current, hovered or none.
  var backgroundFill: RGBA? {
    if isShown { return ShellTokens.tabCurrent.resolve(flavor) }
    return isHovered ? ShellTokens.sidebarItemHovered.resolve(flavor) : nil
  }

  override func accessibilityChildren() -> [Any]? {
    muteButton.isHidden ? [closeButton] : [muteButton, closeButton]
  }

  private func applyFavicon() {
    guard let content else { return }
    faviconView.image = favicon ?? SidebarGlyphs.letter(for: content.title, url: content.url, flavor: flavor,
                                                         size: SidebarMetrics.faviconSize, scale: shellBackingScale)
  }

  private func applyStyle() {
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    muteButton.flavor = flavor
    closeButton.flavor = flavor
    applyFavicon()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    background.backgroundColor = backgroundFill?.cgColor
    let shadow = ShellTokens.rowLiftShadow.color.resolve(flavor)
    background.shadowColor = shadow.cgColor
    background.shadowOpacity = isShown && shadow.alpha > 0 ? 1 : 0
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    // Below the subviews' layers, which AppKit adds after this one: the fill never covers the favicon or the title.
    if let layer, layer.sublayers?.first !== background { layer.insertSublayer(background, at: 0) }
    background.frame = bounds
    background.shadowPath = CGPath(roundedRect: bounds, cornerWidth: SidebarMetrics.rowCornerRadius,
                                   cornerHeight: SidebarMetrics.rowCornerRadius, transform: nil)
    CATransaction.commit()
    let icon = SidebarMetrics.faviconSize
    faviconView.frame = NSRect(x: Self.padding, y: ((bounds.height - icon) / 2).rounded(), width: icon, height: icon)
    // Trailing buttons from the right edge: the close button while hovered, then the mute button while it shows.
    let size = Self.buttonSize
    let buttonY = ((bounds.height - size) / 2).rounded()
    var trailing = bounds.width - Self.padding
    if isHovered {
      closeButton.frame = NSRect(x: trailing - size, y: buttonY, width: size, height: size)
      trailing = closeButton.frame.minX - Self.gap
    } else {
      closeButton.frame = NSRect(x: bounds.width - Self.padding - size, y: buttonY, width: size, height: size)
    }
    if !muteButton.isHidden {
      muteButton.frame = NSRect(x: trailing - size, y: buttonY, width: size, height: size)
      trailing = muteButton.frame.minX - Self.gap
    }
    let titleX = faviconView.frame.maxX + Self.gap
    let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
    titleLabel.frame = NSRect(x: titleX, y: ((bounds.height - titleHeight) / 2).rounded(),
                              width: max(0, trailing - titleX), height: titleHeight)
  }

  // MARK: Pointer

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) { setHovered(true) }
  override func mouseExited(with event: NSEvent) { setHovered(false) }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    onPress?(tab)
  }

  override func accessibilityPerformPress() -> Bool {
    onPress?(tab)
    return true
  }

  @objc private func toggleMute(_ sender: Any?) { onToggleMute?(tab) }
  @objc private func close(_ sender: Any?) { onClose?(tab) }
}

/// A row's 16 pt mute or close button: a symbol in `secondaryText`, radius 4, with the `sidebarItemHovered` fill while
/// pressed (a muted page's mute button keeps it).
@MainActor
final class PrivatePageRowButton: NSButton {
  var symbolName: String? { didSet { if symbolName != oldValue { applyImage() } } }
  /// The glyph's box: 14 pt for the speaker, 10 pt for the xmark.
  var symbolSize: CGFloat = 14 { didSet { if symbolSize != oldValue { applyImage() } } }
  var isPressedLook = false { didSet { if isPressedLook != oldValue { applyFill() } } }
  var flavor: ThemeFlavor = .light {
    didSet {
      guard flavor != oldValue else { return }
      applyImage()
      applyFill()
    }
  }
  /// The close button takes clicks only while it shows (the row is hovered); VoiceOver reaches it always.
  var respondsOnlyWhenVisible = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    title = ""
    refusesFirstResponder = true
    wantsLayer = true
    layer?.cornerRadius = PrivatePageRowView.buttonRadius
    layer?.cornerCurve = .continuous
    setAccessibilityRole(.button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func hitTest(_ point: NSPoint) -> NSView? {
    if respondsOnlyWhenVisible, alphaValue == 0 { return nil }
    return super.hitTest(point)
  }

  override func highlight(_ flag: Bool) {
    super.highlight(flag)
    applyFill(highlighted: flag)
  }

  private func applyImage() {
    image = symbolName.map {
      SymbolImageCache.shared.symbol($0, box: symbolSize, color: ShellTokens.secondaryText.resolve(flavor),
                                     scale: shellBackingScale)
    }
  }

  private func applyFill(highlighted: Bool = false) {
    let filled = isPressedLook || highlighted
    layer?.backgroundColor = filled ? ShellTokens.sidebarItemHovered.resolve(flavor).cgColor : nil
  }
}
