import AppKit

/// The selected row's fill and its 3 pt mustard tick, one view behind the rows so it can move between them
/// (design/command-bar/README.md, Selected row and Motion). Both are fills: the tick is mustard, never a stroke, and
/// the fill carries a 0.5 pt inner edge only as a hairline. `CommandBarSelectionMotion` slides it between rows.
@MainActor
final class CommandBarSelectionIndicator: NSView {
  private let fill = CALayer()
  private let tick = CALayer()
  private var flavor: ThemeFlavor = .dark

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.addSublayer(fill)
    layer?.addSublayer(tick)
    fill.cornerRadius = CommandBarGeometry.selectedRowRadius
    fill.cornerCurve = .continuous
    fill.borderWidth = 0.5
    tick.cornerRadius = CommandBarGeometry.tickWidth
    tick.cornerCurve = .continuous
    tick.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]   // a rounded trailing edge only
    isHidden = true
    applyColors()
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Not a hit target: clicks and hover reach the rows.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  var flavorForColors: ThemeFlavor {
    get { flavor }
    set { flavor = newValue; applyColors() }
  }

  private func applyColors() {
    fill.backgroundColor = ShellTokens.commandBarSelectedRow.resolve(flavor).cgColor
    fill.borderColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    tick.backgroundColor = ShellTokens.commandBarTick.resolve(flavor).cgColor
  }

  /// The frames of the two layers inside `rowRect`, in the indicator's own coordinates (origin at the row).
  static func layerFrames(rowSize: NSSize) -> (fill: NSRect, tick: NSRect) {
    let fill = NSRect(origin: .zero, size: rowSize)
    let inset = CommandBarGeometry.tickInset
    let tick = NSRect(x: 0, y: inset, width: CommandBarGeometry.tickWidth, height: max(0, rowSize.height - 2 * inset))
    return (fill, tick)
  }

  override func layout() {
    super.layout()
    let frames = Self.layerFrames(rowSize: bounds.size)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fill.frame = frames.fill
    tick.frame = frames.tick
    CATransaction.commit()
  }

  /// Draws the indicator `offset` points from its frame, vertically: the spring's distance behind the target row. A
  /// transform only, so a frame in flight costs no layout.
  func setOffset(_ offset: CGFloat) {
    let transform = offset == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(0, offset, 0)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.transform = transform
    CATransaction.commit()
  }

  /// Puts the indicator on `rect` (the row's rect in its superview), or hides it for nil. Instant.
  func place(on rect: NSRect?) {
    guard let rect else { isHidden = true; return }
    isHidden = false
    frame = rect
  }
}
