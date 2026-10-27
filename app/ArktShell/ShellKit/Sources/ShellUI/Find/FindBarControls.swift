import AppKit

/// The field editor of the find field. It remembers the modifiers of the last key it saw, because the `insertNewline:`
/// that Return and Shift-Return both become does not say whether Shift was down.
@MainActor
final class FindBarEditor: NSTextView {
  private(set) var lastModifiers: NSEvent.ModifierFlags = []

  override func keyDown(with event: NSEvent) {
    lastModifiers = event.modifierFlags
    super.keyDown(with: event)
  }
}

@MainActor
final class FindBarFieldCell: NSTextFieldCell {
  private let editor: FindBarEditor = {
    let editor = FindBarEditor(frame: .zero)
    editor.isFieldEditor = true
    return editor
  }()

  override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

/// The bare text field of the find bar: no bezel, no background, no focus ring (the pill is the field), one line that
/// scrolls inside its frame, never wraps and never grows the bar.
@MainActor
final class FindBarField: NSTextField {
  override class var cellClass: AnyClass? {
    get { FindBarFieldCell.self }
    set {}
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    isBezeled = false
    drawsBackground = false
    focusRingType = .none
    font = .systemFont(ofSize: 13)
    usesSingleLineMode = true
    cell?.isScrollable = true
    cell?.wraps = false
    cell?.lineBreakMode = .byClipping
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }
}

/// A round 24 pt glyph button of the find bar (design `.ib`): `secondaryText` glyph that turns `primaryText` on hover
/// over a `sidebarItemHovered` disc, a 0.94 press, 35 % when it cannot act. The focus ring is the system ring around the
/// disc.
@MainActor
final class FindBarButton: NSButton {
  private var hovering = false { didSet { if hovering != oldValue { refreshColors() } } }
  private var hoverArea: NSTrackingArea?
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  init(symbol: String, pointSize: CGFloat, label: String, identifier: String) {
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    imageScaling = .scaleNone
    title = ""
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    focusRingType = .default
    wantsLayer = true
    layer?.cornerRadius = FindBarLayout.buttonSize / 2
    toolTip = label
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(label)
    setAccessibilityIdentifierWithCell(identifier)
    cell?.setAccessibilityLabel(label)
    refreshColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }

  override var isEnabled: Bool {
    didSet { if isEnabled != oldValue { alphaValue = isEnabled ? 1 : 0.35 } }
  }

  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    performClick(nil)
    return true
  }

  // MARK: Press

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return super.mouseDown(with: event) }
    setPressed(true)
    super.mouseDown(with: event)          // tracks the button until the mouse goes up
    setPressed(false)
  }

  private func setPressed(_ pressed: Bool) {
    guard let layer, let press = FindBarMotion.press(reduceMotion: reduceMotion()) else { return }
    let target = pressed ? press.scale : 1
    let transform = ToastMotion.transform(offset: 0, scale: target, bounds: bounds, anchor: layer.anchorPoint)
    let animation = CABasicAnimation(keyPath: "transform")
    animation.fromValue = layer.presentation()?.transform ?? layer.transform
    animation.toValue = transform
    animation.duration = press.duration
    animation.timingFunction = FindBarMotion.strongEaseOut.timingFunction
    layer.transform = transform
    layer.add(animation, forKey: "press")
  }

  // MARK: Focus ring

  override func drawFocusRingMask() {
    NSBezierPath(ovalIn: bounds).fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }

  // MARK: Hover and colors

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    guard hoverArea == nil else { return }       // `.inVisibleRect` follows the frame; added once
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) { hovering = true }
  override func mouseExited(with event: NSEvent) { hovering = false }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshColors()
  }

  func refreshColors() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    layer?.backgroundColor = hovering ? ShellTokens.sidebarItemHovered.resolve(flavor).cgColor : nil
    contentTintColor = (hovering ? ShellTokens.primaryText : ShellTokens.secondaryText).resolve(flavor).nsColor()
  }
}
