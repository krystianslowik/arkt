import AppKit
import Motion

/// The Extensions panel's motion (design/extensions, Motion), as data. Transform and opacity only.
@MainActor
enum ExtensionsPanelMotion {
  /// The design system's `firmFast` `cubic-bezier(0.2, 1, 0.4, 1)` for the panel, `firm` for the drop.
  static let firmFast = CAMediaTimingFunction(controlPoints: 0.2, 1, 0.4, 1)
  static let firm = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
  static let easeOut = MotionCurve.strongEaseOut.timingFunction
  /// The panel appears: opacity 0 to 1, scale 0.97 to 1 and 4 pt down to its place over 0.22 s; Reduce Motion fades
  /// in 0.15 s.
  static let appearDuration: CFTimeInterval = 0.22
  static let appearScale: CGFloat = 0.97
  static let appearOffset: CGFloat = 4
  static let reducedAppearDuration: CFTimeInterval = FadeDuration.standard
  static let exitDuration: CFTimeInterval = FadeDuration.quick
  /// The row lifted by its grip scales to 1.02 (Reduce Motion: no scale) and follows the pointer.
  static let liftScale: CGFloat = 1.02
  /// The dropped row settles into its slot in 0.18 s (Reduce Motion: it jumps).
  static let settleDuration: CFTimeInterval = 0.18
}

/// The row's main button: the icon, name and status area. Clicking it runs the extension's action, anchored to the
/// row. A real `NSButton` that always takes keyboard focus (the panel is a keyboard surface even without Full Keyboard
/// Access), drawing the system focus ring around the row's content.
@MainActor
final class ExtensionsRowButton: NSButton {
  init() {
    super.init(frame: .zero)
    title = ""
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    imagePosition = .noImage
    focusRingType = .default
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override func draw(_ dirtyRect: NSRect) {}
  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: ExtensionsPanelMetrics.rowCorner,
                 yRadius: ExtensionsPanelMetrics.rowCorner).fill()
  }
  override var focusRingMaskBounds: NSRect { bounds }

  /// Right-click on the row's main area: the row's context menu.
  override func menu(for event: NSEvent) -> NSMenu? { superview?.menu(for: event) }

  /// Ctrl-click opens the row's context menu instead of running the action.
  override func mouseDown(with event: NSEvent) {
    if event.modifierFlags.contains(.control), let row = superview as? ExtensionsPanelRow {
      row.showMenu()
      return
    }
    super.mouseDown(with: event)
  }
}

/// The row's pin toggle (design: "Pin <name>", pressed when pinned): a 28 pt circle, filled with the pin in
/// `primaryText` when pinned, a quiet pin otherwise. VoiceOver reads it as a toggle button with its state; the state
/// changes only when the engine reports the new pin, never on the click itself.
@MainActor
final class ExtensionsPinToggle: NSButton {
  static let symbolName = "pin"
  private let body = CALayer()
  private var hovering = false
  private var tracking: NSTrackingArea?

  /// Pinned: the toggle is pressed.
  var isOn = false {
    didSet {
      guard isOn != oldValue else { return }
      setAccessibilityValue(isOn)
      cell?.setAccessibilityValue(isOn)
      restyle()
    }
  }

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: ExtensionsPanelMetrics.buttonSize,
                             height: ExtensionsPanelMetrics.buttonSize))
    title = ""
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    imagePosition = .imageOnly
    focusRingType = .default
    wantsLayer = true
    layer?.addSublayer(body)
    body.cornerCurve = .continuous
    setAccessibilityRole(.checkBox)
    setAccessibilitySubrole(.toggle)
    cell?.setAccessibilityRole(.checkBox)
    cell?.setAccessibilitySubrole(.toggle)
    setAccessibilityValue(false)
    cell?.setAccessibilityValue(false)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyleLayer() }
  override func accessibilityValue() -> Any? { isOn }
  override func menu(for event: NSEvent) -> NSMenu? { superview?.menu(for: event) }

  private func restyle() {
    let flavor = archiveFlavor
    let color = (isOn || hovering ? ShellTokens.primaryText : ShellTokens.secondaryText).resolve(flavor)
    let next = SymbolImageCache.shared.symbol(isOn ? "pin.fill" : Self.symbolName, box: 13, weight: .medium,
                                              color: color, scale: window?.backingScaleFactor ?? 2)
    if image !== next { image = next }
    restyleLayer()
  }

  private func restyleLayer() {
    let flavor = archiveFlavor
    let fill: RGBA? = isOn ? ShellTokens.sidebarItemHovered.resolve(flavor)
      : hovering ? ShellTokens.sidebarItemBackground.resolve(flavor) : nil
    ArchiveMotion.set { body.backgroundColor = fill?.cgColor }
  }

  override func layout() {
    super.layout()
    ArchiveMotion.set {
      body.frame = bounds
      body.cornerRadius = bounds.height / 2
    }
  }

  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle() }
  override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); restyle() }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
  override func mouseExited(with event: NSEvent) { hovering = false; restyle() }
  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " { performClick(nil); return }
    super.keyDown(with: event)
  }
}

/// The 10 pt grip at a pinned row's leading edge (six dots). Pressing it lifts the row; dragging moves it among the
/// pinned rows. The pointer becomes the open hand over it. Hidden from accessibility: Move Up and Move Down are the
/// row's actions there.
@MainActor
final class ExtensionsGripView: NSView {
  var onBegin: (@MainActor (NSPoint) -> Void)?
  var onMove: (@MainActor (NSPoint) -> Void)?
  var onEnd: (@MainActor () -> Void)?
  private let dots = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.addSublayer(dots)
    setAccessibilityElement(false)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func layout() {
    super.layout()
    let path = CGMutablePath()
    let top = (bounds.height - 14) / 2
    for row in 0..<3 {
      for column in 0..<2 {
        let center = CGPoint(x: (bounds.width - 10) / 2 + 3 + CGFloat(column) * 4, y: top + 3 + CGFloat(row) * 4)
        path.addEllipse(in: CGRect(x: center.x - 1.1, y: center.y - 1.1, width: 2.2, height: 2.2))
      }
    }
    ArchiveMotion.set {
      dots.frame = bounds
      dots.path = path
    }
  }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle() }

  private func restyle() {
    var color = ShellTokens.primaryText.resolve(archiveFlavor)
    color.alpha *= 0.55
    ArchiveMotion.set { dots.fillColor = color.cgColor }
  }

  private func listPoint(_ event: NSEvent) -> NSPoint {
    (superview?.superview ?? self).convert(event.locationInWindow, from: nil)
  }

  /// The closed hand is pushed while the row is lifted.
  private(set) var holdsCursor = false

  override func mouseDown(with event: NSEvent) {
    // Ctrl-click is a context click (#596): AppKit shows the row's menu.
    guard !event.modifierFlags.contains(.control) else { super.mouseDown(with: event); return }
    NSCursor.closedHand.push()
    holdsCursor = true
    onBegin?(listPoint(event))
  }

  override func mouseDragged(with event: NSEvent) {
    guard holdsCursor else { return }
    onMove?(listPoint(event))
  }

  override func mouseUp(with event: NSEvent) {
    guard holdsCursor else { return }
    releaseCursor()
    onEnd?()
  }

  /// Pops the closed hand: on the drop, or when the row goes away or the drag is cancelled mid-gesture.
  func releaseCursor() {
    guard holdsCursor else { return }
    holdsCursor = false
    NSCursor.pop()
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { releaseCursor() }
    super.viewWillMove(toWindow: newWindow)
  }
}
