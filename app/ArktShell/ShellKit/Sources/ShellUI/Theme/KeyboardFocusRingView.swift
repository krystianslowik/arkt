import AppKit

/// The keyboard focus ring of the chrome and Settings (#642, design/drag-hint-focus-ring/README.md): a
/// `ShellTokens.focusRingWidth` stroke in `ShellTokens.focusRing`, following a rounded shape, in place of the system
/// ring.
/// The color resolves from the view's appearance: the Space's text tone in the sidebar (the sidebar sets its
/// appearance from it), the window's on the page card and in Settings.
///
/// Sidebar rows and Favorite tiles draw it inside their own fill (`frame` is the fill, so the clip view never cuts
/// it), as do controls a clipping parent would cut (`attach(inside:radius:)`, the Little Arkt split button). Controls
/// draw it outside themselves with `attach(outside:radius:)`, or around a part of themselves (`place(around:radius:)`,
/// the theme creator's knob, swatch and colour dot), toggled by their first responder state:
/// AppKit's ring shows only for keyboard focus, and so does this one. Like the system ring it shows only while its
/// window is key, and it appears and goes at once. Not hit-testable and not an accessibility element.
@MainActor
final class KeyboardFocusRingView: NSView {
  static let lineWidth = ShellTokens.focusRingWidth
  var cornerRadius = SidebarMetrics.rowCornerRadius { didSet { needsDisplay = true } }
  /// The tone to draw in, for hosts whose colors come from a model rather than their appearance (the theme creator,
  /// the Peek controls, the import checkbox) or from the fill under the ring (the mustard split); nil follows
  /// `effectiveAppearance`.
  var flavor: ThemeFlavor? { didSet { if flavor != oldValue { needsDisplay = true } } }
  let ring = CAShapeLayer()
  /// The owner has keyboard focus. The ring shows while this is true and the window is key.
  private(set) var isFocused = false
  /// Raises the host above its siblings while shown (`attach(outside:radius:raisesHost:)`), for hosts whose neighbor
  /// sits closer than the ring's width (Settings' pane items, 2 pt apart). Off by default: a raised host would draw
  /// over overlays it does not own (the split close button under the find bar and the zoom pill).
  private var raisesHost = false
  private weak var observedWindow: NSWindow?

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
  static func attach(outside host: NSView, radius: CGFloat, raisesHost: Bool = false) -> KeyboardFocusRingView {
    let ring = KeyboardFocusRingView(frame: host.bounds.insetBy(dx: -lineWidth, dy: -lineWidth))
    ring.cornerRadius = radius + lineWidth
    ring.raisesHost = raisesHost
    ring.autoresizingMask = [.width, .height]
    host.addSubview(ring, positioned: .above, relativeTo: nil)
    return ring
  }

  /// A ring drawn inside `host`, on its edge, with corner `radius`: for a host whose parent clips its subviews.
  static func attach(inside host: NSView, radius: CGFloat) -> KeyboardFocusRingView {
    let ring = KeyboardFocusRingView(frame: host.bounds)
    ring.cornerRadius = radius
    ring.autoresizingMask = [.width, .height]
    host.addSubview(ring, positioned: .above, relativeTo: nil)
    return ring
  }

  /// Draws the ring just outside `rect` (the superview's coordinates), whose shape has corner `radius`; for a ring
  /// around a part of its host. The host calls it again whenever that part moves.
  func place(around rect: NSRect, radius: CGFloat) {
    let lineWidth = Self.lineWidth
    frame = rect.insetBy(dx: -lineWidth, dy: -lineWidth)
    cornerRadius = radius + lineWidth
    refreshVisibility()
  }

  /// Keyboard focus came or went.
  func setFocused(_ focused: Bool) {
    isFocused = focused
    refreshVisibility()
  }

  private func refreshVisibility() {
    let shown = isFocused && window?.isKeyWindow == true
    if raisesHost { superview?.layer?.zPosition = shown ? 1 : 0 }
    // A host whose layer has a corner radius clips its subviews (AppKit turns `clipsToBounds` on with it), which would
    // cut a ring drawn outside it down to nothing: a ring that reaches past its host unclips it.
    if shown, let host = superview, host.clipsToBounds, !host.bounds.contains(frame) { host.clipsToBounds = false }
    guard isHidden == shown else { return }
    isHidden = !shown
    needsDisplay = true
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    super.viewWillMove(toWindow: newWindow)
    guard let observedWindow, observedWindow !== newWindow else { return }
    let center = NotificationCenter.default
    center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: observedWindow)
    center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: observedWindow)
    self.observedWindow = nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window, window !== observedWindow {
      let center = NotificationCenter.default
      center.addObserver(self, selector: #selector(windowKeyChanged(_:)), name: NSWindow.didBecomeKeyNotification,
                         object: window)
      center.addObserver(self, selector: #selector(windowKeyChanged(_:)), name: NSWindow.didResignKeyNotification,
                         object: window)
      observedWindow = window
    }
    refreshVisibility()
  }

  @objc private func windowKeyChanged(_ notification: Notification) { refreshVisibility() }

  override var wantsUpdateLayer: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  var strokeColor: CGColor {
    ShellTokens.focusRing.resolve(flavor ?? ThemeFlavor(appearance: effectiveAppearance)).cgColor
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
