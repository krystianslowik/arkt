import AppKit

/// One sidebar row's background: a rounded fill at Arc's token levels, inset to a 34 pt pill on the 41 pt
/// pitch. Selection is the `current` state, never AppKit's highlight.
@MainActor
public final class SidebarRowView: NSTableRowView {
  public static let reuseIdentifier = NSUserInterfaceItemIdentifier("SidebarRowView")

  public let backgroundLayer = CALayer()

  public var state: TabRowState = .normal {
    didSet { if state != oldValue { needsDisplay = true } }
  }
  public var flavor: ThemeFlavor = .light {
    didSet { if flavor != oldValue { needsDisplay = true } }
  }
  /// Also shows or hides the cell's hover close (X) button (GS-043), fading with the fill.
  public var isHovered = false {
    didSet {
      guard isHovered != oldValue else { return }
      needsDisplay = true
      tabCell?.setCloseButtonShown(isHovered, animated: true)
    }
  }
  public var isPressed = false {
    didSet { if isPressed != oldValue { needsDisplay = true } }
  }
  /// Divider rows never draw a fill or react to the pointer.
  public var isInteractive = true {
    didSet { if isInteractive != oldValue { needsDisplay = true } }
  }

  /// The fill currently drawn (nil = none). Exposed for tests.
  public var displayedFill: RGBA? {
    guard isInteractive else { return nil }
    let shown = state.displayed(hovered: isHovered, pressed: isPressed)
    if shown == .normal && isHovered { return ShellTokens.sidebarItemHovered.resolve(flavor) }
    return shown.background(flavor)
  }

  private var hoverArea: NSTrackingArea?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    identifier = Self.reuseIdentifier
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    backgroundLayer.cornerRadius = SidebarMetrics.rowCornerRadius
    backgroundLayer.cornerCurve = .continuous
    backgroundLayer.shadowRadius = 2
    backgroundLayer.shadowOffset = CGSize(width: 0, height: -1)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var wantsUpdateLayer: Bool { true }

  public override func updateLayer() {
    if backgroundLayer.superlayer !== layer { layer?.insertSublayer(backgroundLayer, at: 0) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    backgroundLayer.frame = bounds.insetBy(dx: 0, dy: SidebarMetrics.rowBackgroundInsetY)
    backgroundLayer.backgroundColor = displayedFill?.cgColor
    let shadow = ShellTokens.tabCurrentShadow.resolve(flavor)
    let showsShadow = isInteractive && state == .current && shadow.alpha > 0
    backgroundLayer.shadowColor = shadow.cgColor
    backgroundLayer.shadowOpacity = showsShadow ? 1 : 0
    updateShadowPath()
    CATransaction.commit()
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    backgroundLayer.frame = bounds.insetBy(dx: 0, dy: SidebarMetrics.rowBackgroundInsetY)
    updateShadowPath()
    CATransaction.commit()
  }

  /// Explicit path so Core Animation never derives the shadow from layer contents offscreen.
  private func updateShadowPath() {
    let radius = SidebarMetrics.rowCornerRadius
    backgroundLayer.shadowPath = CGPath(roundedRect: backgroundLayer.bounds, cornerWidth: radius,
                                        cornerHeight: radius, transform: nil)
  }

  public override func drawSelection(in dirtyRect: NSRect) {}
  public override func drawBackground(in dirtyRect: NSRect) {}

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
    resyncHoverWithPointer { syncHover(pointerInWindow: $0) }   // a row scrolled or reused under a still pointer
  }

  /// Sets the hover state from a pointer location in window coordinates (nil: the pointer is not over this
  /// window).
  func syncHover(pointerInWindow point: NSPoint?) {
    guard let point else { isHovered = false; isPressed = false; return }
    let inside = bounds.contains(convert(point, from: nil))
    isHovered = inside
    if !inside { isPressed = false }
  }

  /// The tab cell this row hosts (nil for divider rows).
  private var tabCell: SidebarTabCellView? {
    numberOfColumns > 0 ? view(atColumn: 0) as? SidebarTabCellView : nil
  }

  /// A cell added to a hovered row (a reload under the pointer) shows its X at once.
  public override func didAddSubview(_ subview: NSView) {
    super.didAddSubview(subview)
    (subview as? SidebarTabCellView)?.setCloseButtonShown(isHovered, animated: false)
  }

  public override func mouseEntered(with event: NSEvent) { isHovered = true }
  public override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }

  public override func prepareForReuse() {
    super.prepareForReuse()
    isHovered = false
    isPressed = false
    state = .normal
    isInteractive = true
  }
}
