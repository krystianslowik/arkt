import AppKit

/// The URL bar: the active tab's address. One class serves the sidebar (host only, under the traffic lights, in a
/// rounded pill) and the Toolbar (full URL as plain centered text, no fill, border or radius, as Arc 1.168 draws it). A press opens the command bar prefilled with the URL (the owner
/// wires `onPress` to Cmd-L, KB-002; a click presses on mouse up inside); right-click or Ctrl-click offers
/// Show / Hide Toolbar (BH-031, GS-042). Frames are set by the owner; the label is laid out here. Text changes only
/// when the URL does.
@MainActor
public final class URLBarView: NSView {
  public enum Style: Sendable {
    /// `AddressText.host`: the sidebar URL bar.
    case host
    /// `AddressText.full`: the Toolbar.
    case full
  }

  public let style: Style
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
  /// A left mouse down landed on the bar and its mouse up has not arrived yet.
  private var isTrackingPress = false
  private var isHovered = false {
    didSet { if isHovered != oldValue { needsDisplay = true } }
  }
  private var hoverArea: NSTrackingArea?

  public init(style: Style) {
    self.style = style
    super.init(frame: .zero)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layer?.cornerCurve = .continuous
    label.font = Self.font
    label.lineBreakMode = style == .host ? .byTruncatingTail : .byTruncatingMiddle
    label.alignment = style == .host ? .natural : .center
    label.maximumNumberOfLines = 1
    label.cell?.usesSingleLineMode = true
    label.autoresizingMask = []
    label.setAccessibilityElement(false)
    addSubview(label)
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
    toolTip = url?.absoluteString
    setAccessibilityValue(text)
    NSAccessibility.post(element: self, notification: .valueChanged)
  }

  private func applyColors() {
    label.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    needsDisplay = true
  }

  public override func updateLayer() {
    guard let layer, style == .host else { return }   // the Toolbar's URL is plain text
    layer.cornerRadius = SidebarMetrics.urlBarCornerRadius
    let token = isHovered ? ShellTokens.sidebarItemHovered : ShellTokens.sidebarItemBackground
    layer.backgroundColor = token.resolve(flavor).cgColor
  }

  public override func layout() {
    super.layout()
    let inset = style == .host ? SidebarMetrics.urlBarTextInset : 0
    let height = Self.labelHeight
    label.frame = NSRect(x: inset, y: ((bounds.height - height) / 2).rounded(),
                         width: max(0, bounds.width - 2 * inset), height: height)
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
    isTrackingPress = true
  }

  public override func mouseUp(with event: NSEvent) {
    guard isTrackingPress else { return }
    isTrackingPress = false
    if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
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
