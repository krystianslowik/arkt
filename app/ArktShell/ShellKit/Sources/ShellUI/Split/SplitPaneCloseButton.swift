import AppKit

/// The close (X) at the top trailing corner of a split pane (#388, BH-121 "the X above a pane"): closes that pane the
/// way Cmd-W closes the focused one. Shown while the pointer is over the pane or the button has keyboard focus.
///
/// Never `isHidden` while its pane has a page, so VoiceOver and Full Keyboard Access always reach it; while not shown
/// it is transparent and takes no clicks (`hitTest` passes them to the page). The surface follows the Peek controls:
/// `toastSurface` fill, `cardBorder` hairline, `secondaryText` glyph that turns `primaryText` on hover. The focus ring
/// is the system ring, drawn around the circle. PARITY(NEEDS-RUNTIME-CHECK RT-37): Arc's exact chrome is unmeasured.
@MainActor
public final class SplitPaneCloseButton: NSButton {
  /// Circle diameter: the Toolbar's button height, so it sits centered in the Toolbar strip when that shows.
  static let size: CGFloat = 24
  /// Distance from the card's top and trailing edges while the Toolbar is off (inside the 10 pt corner radius).
  static let inset: CGFloat = 8
  /// Full fade, 0 to 1 or back; an interrupted fade covers only what is left (`HoverCloseFade`).
  static let fadeDuration = 0.15

  /// Shown: visible and clickable. Hover and keyboard focus show it; the pane card decides.
  public private(set) var isRevealed = false
  /// Read on every show or hide; tests replace it.
  var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Keyboard focus came or went; the card combines it with the hover.
  var onFocusChange: (@MainActor (Bool) -> Void)?
  private var hovering = false { didSet { if hovering != oldValue { refreshColors() } } }
  private var hoverArea: NSTrackingArea?
  private var generation = 0

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    imageScaling = .scaleNone
    title = ""
    let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
    image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    focusRingType = .default
    autoresizingMask = []
    wantsLayer = true
    layer?.cornerRadius = Self.size / 2
    alphaValue = 0
    toolTip = "Close Pane"
    // Explicit: AppKit reports a borderless button at alpha 0 as an unknown element.
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel("Close Pane")
    setAccessibilityIdentifier(AXID.Split.close)
    refreshColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }

  /// Clicks go to the page below while the button is not shown.
  public override func hitTest(_ point: NSPoint) -> NSView? {
    isRevealed ? super.hitTest(point) : nil
  }

  /// VoiceOver presses it whether or not the pointer has shown it.
  public override func accessibilityPerformPress() -> Bool {
    guard isEnabled, !isHidden else { return false }
    performClick(nil)
    return true
  }

  // MARK: Showing

  /// Fades to shown or hidden. With Reduce Motion, outside a window or `animated: false`, the change is immediate.
  func setRevealed(_ revealed: Bool, animated: Bool = true) {
    guard revealed != isRevealed else { return }
    isRevealed = revealed
    generation &+= 1
    let target: CGFloat = revealed ? 1 : 0
    guard animated, window != nil, !reducesMotion() else {
      layer?.removeAnimation(forKey: "opacity")
      alphaValue = target
      return
    }
    let start = layer?.presentation().map { CGFloat($0.opacity) } ?? alphaValue
    NSAnimationContext.runAnimationGroup { context in
      context.duration = HoverCloseFade.duration(from: start, to: target, full: Self.fadeDuration)
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)   // strong ease-out
      context.allowsImplicitAnimation = true
      animator().alphaValue = target
    }
  }

  // MARK: Keyboard focus

  public override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { onFocusChange?(true) }
    return became
  }

  public override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { onFocusChange?(false) }
    return resigned
  }

  /// The system focus ring follows the circle, not the glyph.
  public override func drawFocusRingMask() {
    NSBezierPath(ovalIn: bounds).fill()
  }

  public override var focusRingMaskBounds: NSRect { bounds }

  // MARK: Hover and colors

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    guard hoverArea == nil else { return }       // `.inVisibleRect` follows the frame; added once
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  public override func mouseEntered(with event: NSEvent) { hovering = true }
  public override func mouseExited(with event: NSEvent) { hovering = false }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshColors()
  }

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refreshColors()
  }

  private func refreshColors() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    layer?.backgroundColor = ShellTokens.toastSurface.resolve(flavor).cgColor
    layer?.borderColor = ShellTokens.cardBorder.resolve(flavor).cgColor
    layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
    let glyph = hovering ? ShellTokens.primaryText : ShellTokens.secondaryText
    contentTintColor = glyph.resolve(flavor).nsColor()
  }
}
