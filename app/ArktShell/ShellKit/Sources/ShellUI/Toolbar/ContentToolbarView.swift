import AppKit
import EngineAPI

/// Toolbar button (Back, Forward, Reload) that records click modifiers, handles middle-click (`buttonNumber == 2`),
/// and shows a history menu on right-click or long-press (#81, GS-024..026, BH-027, BH-165, BH-166).
@MainActor
public final class ToolbarNavigationButton: NSButton {
  public static let longPressDuration: Duration = .milliseconds(350)

  /// Modifier flags of the mouse-down currently firing the button's action.
  private(set) var clickModifiers: NSEvent.ModifierFlags = []
  /// Builds the history menu for right-click, long-press or VoiceOver Show Menu (nil for Reload or when disabled).
  var menuProvider: (@MainActor () -> NSMenu?)?
  /// Middle-click (`buttonNumber == 2`) action (Back / Forward open the entry in a new background Today tab).
  var onMiddleClick: (@MainActor () -> Void)?
  /// Presents the menu on long-press or VoiceOver Show Menu; tests replace it to inspect the menu without a modal loop.
  public var onShowHistoryMenu: (@MainActor (NSMenu) -> Void)?

  private var longPressTask: Task<Void, Never>?
  private var longPressTriggered = false
  private var isTrackingMiddleClick = false

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    onShowHistoryMenu = { [weak self] menu in
      guard let self else { return }
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.bounds.maxY), in: self)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override func mouseDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers == .control, let menu = menu(for: event) {
      onShowHistoryMenu?(menu)
      return
    }
    clickModifiers = modifiers
    longPressTriggered = false
    if isEnabled, modifiers.isEmpty, menuProvider != nil {
      longPressTask?.cancel()
      longPressTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: Self.longPressDuration)
        guard !Task.isCancelled else { return }
        self?.triggerLongPressMenu()
      }
    }
    super.mouseDown(with: event)
    longPressTask?.cancel()
    longPressTask = nil
    clickModifiers = []
    longPressTriggered = false
  }

  public override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
    guard !longPressTriggered else { return false }
    return super.sendAction(action, to: target)
  }

  public override func otherMouseDown(with event: NSEvent) {
    guard event.buttonNumber == 2, isEnabled, onMiddleClick != nil else {
      super.otherMouseDown(with: event)
      return
    }
    isTrackingMiddleClick = true
  }

  public override func otherMouseUp(with event: NSEvent) {
    guard event.buttonNumber == 2, isTrackingMiddleClick else {
      super.otherMouseUp(with: event)
      return
    }
    isTrackingMiddleClick = false
    if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) {
      onMiddleClick?()
    }
  }

  public override func menu(for event: NSEvent) -> NSMenu? {
    isEnabled ? menuProvider?() : nil
  }

  public override func accessibilityPerformShowMenu() -> Bool {
    guard isEnabled, let menu = menuProvider?() else { return false }
    onShowHistoryMenu?(menu)
    return true
  }

  private func triggerLongPressMenu() {
    guard isEnabled, let menu = menuProvider?() else { return }
    longPressTriggered = true
    onShowHistoryMenu?(menu)
  }

  // MARK: Test hooks

  func performClickWithModifiers(_ modifiers: NSEvent.ModifierFlags) {
    guard isEnabled else { return }
    clickModifiers = modifiers
    defer { clickModifiers = [] }
    _ = sendAction(action, to: target)
  }

  func performMiddleClick() {
    guard isEnabled else { return }
    onMiddleClick?()
  }

  func triggerLongPressForTesting() {
    triggerLongPressMenu()
    longPressTriggered = false
  }
}

/// The Toolbar at the top of the content card (Toggle Toolbar, Cmd-Shift-D; KB-018, BH-032): Back, Forward,
/// Reload and the full URL as plain text centered in the strip. Shown and laid out by `ContentCardView`; actions are
/// wired by the window controller. Geometry is Arc 1.168 (`docs/plans/2026-10-23-arc-measurements.md`).
/// Back and Forward are enabled only while the shown tab can move that way (`setHistory`, engine contract rule 8); a
/// disabled button sends no action and VoiceOver reads it as dimmed.
@MainActor
public final class ContentToolbarView: NSView {
  static let stripHeight: CGFloat = 32                   // Arc 1.168: card top to the hairline
  static let hairlineHeight: CGFloat = 1                 // Arc 1.168; color `ShellTokens.toolbarHairline`
  /// The strip and its hairline.
  public static let height: CGFloat = stripHeight + hairlineHeight
  static let buttonSize = CGSize(width: 32, height: 24)  // Arc 1.168: centered in the strip, 4 pt from the top
  static let buttonSpacing: CGFloat = 5                  // Arc 1.168: 37 pt pitch
  static let iconSize: CGFloat = 14                      // Arc 1.168, inferred from the glyph boxes
  static let horizontalPadding: CGFloat = 5              // Arc 1.168: card edge to the first and last button
  /// The URL's press target, as tall as the buttons. Arc 1.168 draws no pill: plain text in a 16 pt frame, centered
  /// in the strip.
  static let urlBarHeight: CGFloat = 24

  public let backButton = ToolbarNavigationButton(frame: .zero)
  public let forwardButton = ToolbarNavigationButton(frame: .zero)
  public let reloadButton = ToolbarNavigationButton(frame: .zero)
  public let urlBar = URLBarView(style: .full)
  public var onBack: (@MainActor () -> Void)?
  public var onForward: (@MainActor () -> Void)?
  public var onReload: (@MainActor () -> Void)?
  /// Cmd-click or middle-click Back: opens the previous history entry in a new background Today tab (#81, GS-025,
  /// BH-165).
  public var onBackInNewTab: (@MainActor () -> Void)?
  /// Cmd-click or middle-click Forward: opens the next history entry in a new background Today tab (#81, GS-025,
  /// BH-165).
  public var onForwardInNewTab: (@MainActor () -> Void)?
  /// Cmd-click Reload: duplicates the current tab with its history (#81, GS-026, BH-027).
  public var onDuplicateTab: (@MainActor () -> Void)?
  /// Supplies the active tab's back and forward entries for the Back and Forward history menus (#81, GS-024, BH-166).
  public var historyProvider: (@MainActor () -> TabHistory?)?
  /// A history menu item was chosen (`offset < 0` from Back, `offset > 0` from Forward; #81, GS-024, BH-166).
  public var onSelectHistory: (@MainActor (Int) -> Void)?

  /// The hairline under the strip.
  let hairline = CALayer()
  private var flavor: ThemeFlavor?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layer?.addSublayer(hairline)
    for (button, _, label, action) in buttons {
      button.isBordered = false
      button.bezelStyle = .regularSquare
      button.imagePosition = .imageOnly
      button.setAccessibilityLabel(label)
      button.toolTip = label
      button.target = self
      button.action = action
      button.autoresizingMask = []
      addSubview(button)
    }
    setHistory(canGoBack: false, canGoForward: false)
    backButton.menuProvider = { [weak self] in self?.backHistoryMenu() }
    forwardButton.menuProvider = { [weak self] in self?.forwardHistoryMenu() }
    backButton.onMiddleClick = { [weak self] in self?.onBackInNewTab?() }
    forwardButton.onMiddleClick = { [weak self] in self?.onForwardInNewTab?() }
    urlBar.autoresizingMask = []
    addSubview(urlBar)
    setAccessibilityElement(true)
    setAccessibilityRole(.toolbar)
    setAccessibilityLabel("Toolbar")
    setAccessibilityIdentifier(AXID.Toolbar.root)
    backButton.setAccessibilityIdentifierWithCell(AXID.Toolbar.back)
    forwardButton.setAccessibilityIdentifierWithCell(AXID.Toolbar.forward)
    reloadButton.setAccessibilityIdentifierWithCell(AXID.Toolbar.reload)
    urlBar.setAccessibilityIdentifier(AXID.Toolbar.urlBar)
    applyFlavor()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var wantsUpdateLayer: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }

  private var buttons: [(ToolbarNavigationButton, String, String, Selector)] {
    [(backButton, "chevron.left", "Back", #selector(back(_:))),
     (forwardButton, "chevron.right", "Forward", #selector(forward(_:))),
     (reloadButton, "arrow.clockwise", "Reload", #selector(reload(_:)))]
  }

  /// Enables Back and Forward from the shown tab's `canGoBack` / `canGoForward`; both off when no tab is shown.
  public func setHistory(canGoBack: Bool, canGoForward: Bool) {
    backButton.isEnabled = canGoBack
    forwardButton.isEnabled = canGoForward
  }

  /// Back history menu (nearest entry first, tags `-1, -2, ...`), or nil when disabled or empty (#81, GS-024, BH-166).
  public func backHistoryMenu() -> NSMenu? {
    guard backButton.isEnabled, let entries = historyProvider?()?.back, !entries.isEmpty else { return nil }
    return makeHistoryMenu(entries: entries, sign: -1)
  }

  /// Forward history menu (nearest entry first, tags `+1, +2, ...`), or nil when disabled or empty (#81, GS-024).
  public func forwardHistoryMenu() -> NSMenu? {
    guard forwardButton.isEnabled, let entries = historyProvider?()?.forward, !entries.isEmpty else { return nil }
    return makeHistoryMenu(entries: entries, sign: 1)
  }

  private func makeHistoryMenu(entries: [HistoryEntry], sign: Int) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for (index, entry) in entries.enumerated() {
      let title = entry.title.isEmpty ? entry.url.absoluteString : entry.title
      let item = NSMenuItem(title: title, action: #selector(historyMenuItemChosen(_:)), keyEquivalent: "")
      item.target = self
      item.tag = sign * (index + 1)
      menu.addItem(item)
    }
    return menu
  }

  @objc private func historyMenuItemChosen(_ sender: NSMenuItem) {
    guard sender.tag != 0 else { return }
    onSelectHistory?(sender.tag)
  }

  @objc private func back(_ sender: Any?) {
    if backButton.clickModifiers.contains(.command) { onBackInNewTab?() } else { onBack?() }
  }
  @objc private func forward(_ sender: Any?) {
    if forwardButton.clickModifiers.contains(.command) { onForwardInNewTab?() } else { onForward?() }
  }
  @objc private func reload(_ sender: Any?) {
    if reloadButton.clickModifiers.contains(.command) { onDuplicateTab?() } else { onReload?() }
  }

  /// The card follows the window's appearance, not the Space theme; so does the Toolbar.
  private func applyFlavor() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    guard flavor != self.flavor else { return }
    self.flavor = flavor
    urlBar.flavor = flavor
    applyButtonImages(flavor)
    needsDisplay = true
  }

  private func applyButtonImages(_ flavor: ThemeFlavor) {
    let color = ShellTokens.secondaryText.resolve(flavor)
    for (button, symbol, _, _) in buttons {
      button.image = SymbolImageCache.shared.symbol(symbol, box: Self.iconSize, color: color,
                                                    scale: shellBackingScale)
    }
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyFlavor()
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    if let flavor { applyButtonImages(flavor) }
  }

  public override func updateLayer() {
    let flavor = flavor ?? .light
    layer?.backgroundColor = ShellTokens.toolbarSurface.resolve(flavor).cgColor
    hairline.backgroundColor = ShellTokens.toolbarHairline.resolve(flavor).cgColor
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let strip = min(Self.stripHeight, bounds.height)
    let size = Self.buttonSize
    let buttonY = ((strip - size.height) / 2).rounded()
    var x = Self.horizontalPadding
    for (button, _, _, _) in buttons {
      button.frame = NSRect(x: x, y: buttonY, width: size.width, height: size.height)
      x += size.width + Self.buttonSpacing
    }
    // Centered in the whole strip: the frame keeps the same inset on both sides, clear of the buttons.
    let inset = x
    let barHeight = Self.urlBarHeight
    urlBar.frame = NSRect(x: inset, y: ((strip - barHeight) / 2).rounded(),
                          width: max(0, bounds.width - 2 * inset), height: barHeight)
    hairline.frame = CGRect(x: 0, y: strip, width: bounds.width, height: max(0, bounds.height - strip))
    CATransaction.commit()
  }
}
