import AppKit
import Motion

// MARK: - Pane item

/// A pane item in the bar (section 4): 84 x 44, radius 9, a 16 pt SF Symbol in `sidebarForeground` 3 above an 11
/// medium `secondaryText` label; hover `sidebarItemBackground`. Selected, the item lifts in `tabCurrent` with
/// `tabCurrentShadow`, glyph and label `primaryText`, exactly as the current tab does in the sidebar. VoiceOver reads it
/// as a radio button in the "Settings" tab group; with Full Keyboard Access, Tab reaches it and Space selects.
@MainActor
public final class SettingsPaneItemView: NSView {
  let pane: SettingsPane
  var onSelect: (@MainActor (SettingsPane) -> Void)?
  public private(set) var isSelected = false
  private let plate = CALayer()
  private let hoverFill = CALayer()
  private let content = CALayer()
  private let glyph = CALayer()
  private let label = CATextLayer()
  private var hovering = false
  private var tracking: NSTrackingArea?

  init(pane: SettingsPane) {
    self.pane = pane
    super.init(frame: NSRect(origin: .zero, size: SettingsMetrics.paneItemSize))
    wantsLayer = true
    layer?.masksToBounds = false
    for fill in [hoverFill, plate] {
      fill.cornerRadius = SettingsMetrics.paneItemRadius
      fill.cornerCurve = .continuous
    }
    plate.shadowOffset = CGSize(width: 0, height: -1)
    plate.shadowRadius = 1.5
    plate.opacity = 0
    label.alignmentMode = .center
    content.addSublayer(glyph)
    content.addSublayer(label)
    layer?.addSublayer(hoverFill)
    layer?.addSublayer(plate)
    layer?.addSublayer(content)
    focusRingType = .default
    setAccessibilityElement(true)
    setAccessibilityRole(.radioButton)
    setAccessibilityLabel(pane.label)
    setAccessibilityIdentifier(AXID.Settings.tab(pane.rawValue))
    if let number = SettingsPane.allCases.firstIndex(of: pane).map({ $0 + 1 }) {
      toolTip = "\(pane.label) (\u{2318}\(number))"
    }
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override public var isFlipped: Bool { true }
  override public var mouseDownCanMoveWindow: Bool { false }

  /// The plate's model opacity: 1 selected, 0 not.
  var plateOpacity: Float { plate.opacity }

  /// Selects or clears the item; `animated` fades the plate in over 0.12 s (a click), otherwise it is instant (Cmd-1
  /// to Cmd-7). There is no sliding highlight.
  func setSelected(_ selected: Bool, animated: Bool) {
    isSelected = selected
    let target: Float = selected ? 1 : 0
    plate.removeAnimation(forKey: "opacity")
    if animated, selected, !SettingsMotion.reduceMotion() {
      SettingsMotion.fade(plate, to: target, duration: SettingsMotion.plateFade)
    } else {
      ArchiveMotion.set { plate.opacity = target }
    }
    restyle()
  }

  override public func accessibilityValue() -> Any? { NSNumber(value: isSelected ? 1 : 0) }

  override public func accessibilityPerformPress() -> Bool {
    onSelect?(pane)
    return true
  }

  // MARK: Keyboard (Full Keyboard Access)

  /// Tab reaches the items with Full Keyboard Access; a click selects without taking focus (no ring on click).
  override public var acceptsFirstResponder: Bool {
    NSApp.isFullKeyboardAccessEnabled && NSApp.currentEvent?.type != .leftMouseDown
  }
  override public var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }

  override public func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " {
      onSelect?(pane)
      return
    }
    super.keyDown(with: event)
  }

  override public func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: SettingsMetrics.paneItemRadius,
                 yRadius: SettingsMetrics.paneItemRadius).fill()
  }

  override public var focusRingMaskBounds: NSRect { bounds }

  // MARK: Pointer

  override public func mouseDown(with event: NSEvent) {
    press(true)
    var inside = true
    while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      inside = bounds.contains(convert(next.locationInWindow, from: nil))
      if next.type == .leftMouseUp { break }
    }
    press(false)
    if inside { onSelect?(pane) }
  }

  /// Scale 0.96 while the pointer is down, back on `springyExtraFast` (feedback; Reduce Motion: none).
  private func press(_ down: Bool) {
    guard !SettingsMotion.reduceMotion() else { return }
    ArchiveMotion.set {
      content.position = CGPoint(x: bounds.midX, y: bounds.midY)
      plate.position = content.position
    }
    for target in [content, plate] {
      SettingsMotion.spring(target, "transform.scale", to: down ? SettingsMotion.paneItemPressScale : 1,
                            preset: .springyExtraFast, reduceMotion: false)
    }
  }

  override public func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override public func mouseEntered(with event: NSEvent) {
    hovering = true
    restyle()
  }

  override public func mouseExited(with event: NSEvent) {
    hovering = false
    restyle()
  }

  // MARK: Drawing

  private func restyle() {
    let flavor = archiveFlavor
    let scale = window?.backingScaleFactor ?? 2
    let ink = (isSelected ? ShellTokens.primaryText : ShellTokens.sidebarForeground).resolve(flavor)
    let text = (isSelected ? ShellTokens.primaryText : ShellTokens.secondaryText).resolve(flavor)
    let increase = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    ArchiveMotion.set {
      let box = CGRect(origin: .zero, size: SettingsMetrics.paneItemSize)
      for fill in [hoverFill, plate, content] {
        fill.bounds = box
        fill.position = CGPoint(x: box.midX, y: box.midY)
      }
      hoverFill.backgroundColor = hovering && !isSelected
        ? ShellTokens.sidebarItemBackground.resolve(flavor).cgColor : nil
      plate.backgroundColor = ShellTokens.tabCurrent.resolve(flavor).cgColor
      plate.shadowOpacity = flavor == .light ? Float(ShellTokens.tabCurrentShadow.light.alpha) * 0.5 : 0
      plate.borderWidth = increase && flavor == .dark ? 1 : 0
      plate.borderColor = SettingsTokens.separatorIncreasedContrast.resolve(flavor).cgColor
      let font = NSFont.systemFont(ofSize: 11, weight: .medium)
      let line = ceil(font.ascender - font.descender)
      let glyphSize = SettingsMetrics.paneGlyph
      let top = ((box.height - glyphSize - SettingsMetrics.paneGlyphToLabel - line) / 2).rounded()
      // The view is flipped, and so are its layers: y grows downwards.
      glyph.frame = CGRect(x: ((box.width - glyphSize) / 2).rounded(), y: top, width: glyphSize, height: glyphSize)
      let image = SymbolImageCache.shared.symbol(pane.symbolName, box: glyphSize, color: ink, scale: scale)
      glyph.contents = image.layerContents(forContentsScale: scale)
      glyph.contentsScale = scale
      label.frame = CGRect(x: 0, y: top + glyphSize + SettingsMetrics.paneGlyphToLabel, width: box.width,
                           height: line)
      label.string = NSAttributedString(string: pane.label, attributes: [.font: font, .foregroundColor: text.nsColor()])
      label.contentsScale = scale
    }
  }

  override public func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override public func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }
}

// MARK: - Chrome

/// The unified chrome (section 4): 84 high on the window surface, no hairline. Over scrolled content it shows the
/// `.titlebar` vibrancy behind `toolbarMaterial`; with Reduce Transparency it is opaque `surfaceBrand`.
@MainActor
final class SettingsChromeView: NSView {
  let titleLabel = NSTextField(labelWithString: "")
  let items: [SettingsPaneItemView]
  private let material = NSVisualEffectView()
  private let tint = CALayer()
  private let bar = NSView()
  /// Content is scrolled under the chrome: the material shows. Otherwise the chrome is the plain surface.
  private(set) var isOverContent = false

  init(items: [SettingsPaneItemView]) {
    self.items = items
    super.init(frame: .zero)
    wantsLayer = true
    material.material = .titlebar
    material.blendingMode = .withinWindow
    material.state = .followsWindowActiveState
    addSubview(material)
    layer?.addSublayer(tint)
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.alignment = .center
    titleLabel.setAccessibilityElement(false)        // the window title says it
    addSubview(titleLabel)
    bar.setAccessibilityElement(true)
    bar.setAccessibilityRole(.tabGroup)
    bar.setAccessibilityLabel("Settings")
    items.forEach(bar.addSubview)
    addSubview(bar)
    restyle()
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(displayOptionsChanged(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { true }

  @objc private func displayOptionsChanged(_ note: Notification) { restyle() }

  override func layout() {
    super.layout()
    material.frame = bounds
    ArchiveMotion.set { tint.frame = bounds }
    let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
    titleLabel.frame = NSRect(x: 80, y: (SettingsMetrics.titleCenterY - titleHeight / 2).rounded(),
                              width: bounds.width - 160, height: titleHeight)
    let size = SettingsMetrics.paneItemSize
    let total = CGFloat(items.count) * size.width + CGFloat(items.count - 1) * SettingsMetrics.paneItemGap
    bar.frame = NSRect(x: ((bounds.width - total) / 2).rounded(), y: SettingsMetrics.paneBarTop, width: total,
                       height: size.height)
    for (index, item) in items.enumerated() {
      item.frame = NSRect(x: CGFloat(index) * (size.width + SettingsMetrics.paneItemGap), y: 0, width: size.width,
                          height: size.height)
    }
  }

  /// Shows the material while content sits under the chrome (section 4); a 0.15 s fade between the two.
  func setOverContent(_ over: Bool) {
    guard over != isOverContent else { return }
    isOverContent = over
    restyle()
  }

  func restyle() {
    let flavor = archiveFlavor
    let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || !isOverContent
    material.isHidden = opaque
    ArchiveMotion.set {
      tint.backgroundColor = (opaque ? BrandTokens.surfaceBrand : SettingsTokens.toolbarMaterial)
        .resolve(flavor).cgColor
    }
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }
}

/// The window's content view: the surface, the scrolling pane under the chrome, the chrome on top.
@MainActor
final class SettingsRootView: NSView {
  override var isFlipped: Bool { true }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(archiveFlavor).cgColor
  }
}

/// The Settings window: one window (not a sheet, not per browser window), titled "Settings" for the Window menu and
/// read by VoiceOver as "Settings, <pane>". Cmd-W and Cmd-1 to Cmd-7 are taken here, before the main menu, whose
/// Archive Tab and Go to Sidebar Item items would otherwise claim them.
@MainActor
final class SettingsWindow: NSWindow {
  var onCommandNumber: (@MainActor (Int) -> Bool)?
  var paneTitle = "General"

  override func accessibilityTitle() -> String? { "Settings, \(paneTitle)" }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    if flags == .command, event.type == .keyDown, let characters = event.charactersIgnoringModifiers {
      if characters == "w" {
        performClose(nil)
        return true
      }
      if let number = Int(characters), let handle = onCommandNumber, handle(number) { return true }
    }
    return super.performKeyEquivalent(with: event)
  }

  /// Escape that no view took (the Shortcuts search field handles its own first): the controller clears the search or
  /// closes the window. AppKit's default ends in a beep here, never reaching the window controller.
  override func keyDown(with event: NSEvent) {
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    if event.keyCode == Self.escapeKeyCode, flags.isEmpty {
      cancelOperation(self)
      return
    }
    super.keyDown(with: event)
  }

  override func cancelOperation(_ sender: Any?) {
    if let controller = windowController { controller.cancelOperation(sender) } else { super.cancelOperation(sender) }
  }

  private static let escapeKeyCode: UInt16 = 53

  /// Close, minimize and zoom at x 20, 40 and 60, centered 20 pt from the top, level with the title.
  func layoutTrafficLights() {
    guard !styleMask.contains(.fullScreen), let close = standardWindowButton(.closeButton),
          let titlebar = close.superview, let container = titlebar.superview else { return }
    let height = SettingsMetrics.titleCenterY * 2
    let width = SettingsMetrics.trafficLightX * 2 + SettingsMetrics.trafficLightSpacing * 2 + close.frame.width
    let containerFrame = NSRect(x: 0, y: frame.height - height, width: width, height: height)
    if container.frame != containerFrame { container.frame = containerFrame }
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for (index, kind) in kinds.enumerated() {
      guard let button = standardWindowButton(kind) else { continue }
      let origin = NSPoint(x: SettingsMetrics.trafficLightX + CGFloat(index) * SettingsMetrics.trafficLightSpacing,
                           y: ((titlebar.bounds.height - button.frame.height) / 2).rounded())
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
  }
}
