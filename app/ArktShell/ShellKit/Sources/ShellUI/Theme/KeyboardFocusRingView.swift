import AppKit

/// The keyboard focus ring of the chrome and Settings (#642, design/drag-hint-focus-ring/README.md): a
/// `ShellTokens.focusRingWidth` stroke in `ShellTokens.focusRing`, following a rounded shape, in place of the system
/// ring.
/// The color resolves from the view's appearance: the Space's text tone in the sidebar (the sidebar sets its
/// appearance from it), the window's on the page card and in Settings.
///
/// Sidebar rows and Favorite tiles draw it inside their own fill (`frame` is the fill, so the clip view never cuts
/// it). Controls draw it outside themselves with `attach(outside:radius:)`, toggled by their first responder state:
/// AppKit's ring shows only for keyboard focus, and so does this one. It appears at once, as the system ring does.
/// Not hit-testable and not an accessibility element.
@MainActor
final class KeyboardFocusRingView: NSView {
  static let lineWidth = ShellTokens.focusRingWidth
  var cornerRadius = SidebarMetrics.rowCornerRadius { didSet { needsDisplay = true } }
  let ring = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    isHidden = true
    ring.fillColor = nil
    ring.lineWidth = Self.lineWidth
    layer?.addSublayer(ring)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// A ring drawn just outside `host`, whose shape has corner `radius`; it follows the host's size. The host must not
  /// clip its subviews (the default) and calls `setFocused(_:)` from its responder methods.
  static func attach(outside host: NSView, radius: CGFloat) -> KeyboardFocusRingView {
    let ring = KeyboardFocusRingView(frame: host.bounds.insetBy(dx: -lineWidth, dy: -lineWidth))
    ring.cornerRadius = radius + lineWidth
    ring.autoresizingMask = [.width, .height]
    host.addSubview(ring, positioned: .above, relativeTo: nil)
    return ring
  }

  /// Shows the ring for keyboard focus, hides it otherwise.
  func setFocused(_ focused: Bool) {
    isHidden = !focused
    needsDisplay = true
  }

  override var wantsUpdateLayer: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  var strokeColor: CGColor {
    ShellTokens.focusRing.resolve(ThemeFlavor(appearance: effectiveAppearance)).cgColor
  }

  override func updateLayer() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let inset = Self.lineWidth / 2
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let radius = min(max(cornerRadius - inset, 0), max(min(rect.width, rect.height), 0) / 2)
    ring.frame = bounds
    ring.path = rect.width > 0 && rect.height > 0
      ? CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil) : nil
    ring.strokeColor = strokeColor
    CATransaction.commit()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsDisplay = true
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    needsDisplay = true
  }
}
