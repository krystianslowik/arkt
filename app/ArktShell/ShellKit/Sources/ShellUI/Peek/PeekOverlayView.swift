import AppKit
import QuartzCore

/// The Peek over the content area (docs/design/peek.md): the scrim over the source, the lifted card with the page,
/// the grabber and the three controls in the right gutter. Frames come from `PeekGeometry` and change only on layout
/// (a window resize) and once at the start of an expand; every motion frame (`apply(_:)`) sets layer transforms,
/// opacities and the card mask, never a view frame.
///
/// Hit testing passes through everything outside the Peek's coverage, so the sidebar and the other panes of a split
/// stay live.
@MainActor
public final class PeekOverlayView: NSView {
  public let scrim = PeekScrimView(frame: .zero)
  public let card = PeekCardView(frame: .zero)
  let grabber = NSView(frame: .zero)
  let dragHandle = PeekDragHandleView(frame: .zero)
  let controlsView = PeekFlippedView(frame: .zero)
  public let closeButton = PeekControlButton(symbol: "xmark", label: "Close Peek", help: "Esc",
                                             toolTip: "Close (Esc)", identifier: AXID.Peek.close)
  public let expandButton = PeekControlButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Open as Tab",
                                              help: "Command-O", toolTip: "Open as Tab (\u{2318}O)",
                                              identifier: AXID.Peek.expand)
  public let splitButton = PeekControlButton(symbol: "rectangle.split.2x1", label: "Add to Split View",
                                             help: "Adds this page next to the current tab",
                                             toolTip: "Add to Split View", identifier: AXID.Peek.split)
  public var controls: [PeekControlButton] { [closeButton, expandButton, splitButton] }

  /// Called on layout with the overlay's bounds; answers the geometry for them (the controller knows the panes).
  var geometryProvider: (@MainActor (CGRect) -> PeekGeometry)?
  public private(set) var geometry: PeekGeometry?
  /// The last scene applied.
  public private(set) var scene = PeekScene.rest
  /// Where the card expands to (Open as Tab, Add to Split View), in overlay coordinates; nil when it does not.
  public private(set) var expandTarget: CGRect?
  private var expandSource: CGRect = .zero

  public var flavor: ThemeFlavor = .light { didSet { if flavor != oldValue { refreshColors() } } }
  /// Reduce Transparency: opaque controls.
  public var reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
    didSet { refreshColors() }
  }

  public var onScrimClick: (@MainActor () -> Void)? {
    get { scrim.onClick }
    set { scrim.onClick = newValue }
  }
  /// Cmd-O while the Peek has focus.
  var onOpenAsTab: (@MainActor () -> Void)?
  /// An Esc the page passed on, through the responder chain (engines whose views forward unhandled keys).
  var onEscape: (@MainActor () -> Void)?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    for view in [scrim, card, grabber, dragHandle, controlsView] {
      view.autoresizingMask = []
      addSubview(view)
    }
    grabber.wantsLayer = true
    grabber.layer?.cornerRadius = 3
    grabber.setAccessibilityElement(false)
    controlsView.wantsLayer = true
    for button in controls { controlsView.addSubview(button) }
    card.onEscape = { [weak self] in self?.onEscape?() }
    refreshColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var wantsUpdateLayer: Bool { true }

  // MARK: Layout

  public override func layout() {
    super.layout()
    guard let geometry = geometryProvider?(bounds) else { return }
    setGeometry(geometry)
  }

  /// Places every part at rest positions for `geometry` and re-applies the current scene. A window resize lands here
  /// directly, without animation.
  func setGeometry(_ geometry: PeekGeometry) {
    self.geometry = geometry
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    scrim.frame = geometry.coverage
    if expandTarget == nil { card.setFrameKeepingPage(geometry.card) }
    grabber.frame = geometry.grabber
    let band = PeekLayout.grabberOffset * 2
    dragHandle.frame = CGRect(x: geometry.card.minX, y: geometry.card.minY - band, width: geometry.card.width,
                              height: band)
    let union = geometry.controls.reduce(CGRect.null) { $0.union($1) }
    controlsView.frame = union
    for (button, frame) in zip(controls, geometry.controls) {
      button.frame = frame.offsetBy(dx: -union.minX, dy: -union.minY)
    }
    CATransaction.commit()
    apply(scene)
  }

  /// Starts an expand into `target` (overlay coordinates): the card takes the target frame once, now, and its mask
  /// starts at the old frame; the page keeps its size and place until `finishExpand`.
  func beginExpand(to target: CGRect) {
    guard let geometry else { return }
    expandSource = geometry.card
    expandTarget = target
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    card.beginExpand(from: geometry.card, to: target)
    CATransaction.commit()
    apply(scene)
  }

  // MARK: Frames

  /// One motion frame: layer properties only.
  public func apply(_ scene: PeekScene) {
    self.scene = scene
    guard geometry != nil else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let tx = CGFloat(scene[.cardX]), ty = CGFloat(scene[.cardY]), s = CGFloat(scene[.cardScale])
    card.layer.map { setTransform($0, translation: CGPoint(x: tx, y: ty), scale: s) }
    card.alphaValue = CGFloat(scene[.cardOpacity])
    if expandTarget != nil { card.setExpandProgress(CGFloat(scene[.expand])) }
    scrim.alphaValue = CGFloat(scene[.scrim])
    let chrome = CGFloat(scene[.controls])
    controlsView.alphaValue = chrome
    let slide = CGFloat(PeekMotion.controlSlide) * (1 - chrome)
    controlsView.layer.map { setTransform($0, translation: CGPoint(x: tx - slide, y: ty), scale: 1) }
    grabber.alphaValue = CGFloat(scene[.grabber])
    grabber.layer.map { setTransform($0, translation: CGPoint(x: tx, y: ty), scale: 1) }
    CATransaction.commit()
  }

  /// A translation (overlay points, y down) and a scale about the layer's center, whatever its anchor point.
  private func setTransform(_ layer: CALayer, translation: CGPoint, scale: CGFloat) {
    let size = layer.bounds.size
    let anchor = CGPoint(x: layer.anchorPoint.x * size.width, y: layer.anchorPoint.y * size.height)
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    // The overlay is flipped; a sublayer of an unflipped layer tree measures y upwards.
    let ySign: CGFloat = layer.superlayer?.contentsAreFlipped() == true ? 1 : -1
    var t = CATransform3DMakeTranslation(translation.x, ySign * translation.y, 0)
    t = CATransform3DTranslate(t, center.x - anchor.x, center.y - anchor.y, 0)
    t = CATransform3DScale(t, scale, scale, 1)
    t = CATransform3DTranslate(t, anchor.x - center.x, anchor.y - center.y, 0)
    layer.transform = t
  }

  // MARK: Colors

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshColors()
  }

  private func refreshColors() {
    scrim.color = ShellTokens.peekScrim.resolve(flavor)
    grabber.layer?.backgroundColor = ShellTokens.peekGrabber.resolve(flavor).cgColor
    card.flavor = flavor
    for button in controls {
      button.flavor = flavor
      button.opaqueFill = reducesTransparency
    }
  }

  // MARK: Events

  /// Passes clicks outside the Peek through to the views below (the sidebar, other split panes).
  public override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, let superview else { return nil }
    let local = convert(point, from: superview)
    guard let geometry else { return nil }
    let controlsFrame = controlsView.frame.applying(controlsTransform)
    let inside = geometry.coverage.contains(local) || card.frame.contains(local) || controlsFrame.contains(local)
      || dragHandle.frame.contains(local)
    return inside ? super.hitTest(point) : nil
  }

  private var controlsTransform: CGAffineTransform {
    CGAffineTransform(translationX: CGFloat(scene[.cardX]), y: CGFloat(scene[.cardY]))
  }

  /// Cmd-O goes to the Peek before the page and the main menu.
  public override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "o", let onOpenAsTab {
      onOpenAsTab()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// A plain container measured from the top, like the overlay.
@MainActor
final class PeekFlippedView: NSView {
  override var isFlipped: Bool { true }
}

// MARK: - Scrim

/// The scrim over the source, clipped to the source card's corners. A click on it closes the Peek.
@MainActor
public final class PeekScrimView: NSView {
  var onClick: (@MainActor () -> Void)?
  var color = RGBA.black(0.18) { didSet { layer?.backgroundColor = color.cgColor } }

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = ShellMetrics.standard.cardCornerRadius
    layer?.cornerCurve = .continuous
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }
  public override func mouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - Card

/// The lifted card: two shadows, the plate (the page's stand-in background) and the page, clipped to 10 pt
/// continuous corners with the `cardBorder` hairline. An expand grows `surface`'s mask; the page keeps its size until
/// it leaves the card.
@MainActor
public final class PeekCardView: NSView {
  let contact = NSView(frame: .zero)
  let surface = NSView(frame: .zero)
  public private(set) var page: NSView?
  private let mask = CALayer()
  private var expandFrom: CGRect?
  var flavor: ThemeFlavor = .light { didSet { refreshColors() } }
  var onEscape: (@MainActor () -> Void)?
  var onCancel: (@MainActor () -> Bool)?
  private let radius = ShellMetrics.standard.cardCornerRadius

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    contact.wantsLayer = true
    surface.wantsLayer = true
    for view in [contact, surface] {
      view.autoresizingMask = [.width, .height]
      addSubview(view)
    }
    if let layer = surface.layer {
      layer.cornerRadius = radius
      layer.cornerCurve = .continuous
      layer.masksToBounds = true
    }
    mask.backgroundColor = NSColor.black.cgColor
    mask.cornerRadius = radius
    mask.cornerCurve = .continuous
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilitySubrole(.dialog)
    setAccessibilityLabel("Peek")
    setAccessibilityIdentifier(AXID.Peek.card)
    refreshColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  /// Mounts the page, filling the card.
  func mount(_ view: NSView) {
    if page === view { return }
    page?.removeFromSuperview()
    page = view
    view.translatesAutoresizingMaskIntoConstraints = true
    view.autoresizingMask = [.width, .height]
    view.frame = surface.bounds
    surface.addSubview(view)
  }

  /// Lets go of the page (it moves into a content card or a pane) and returns it.
  @discardableResult
  func unmount() -> NSView? {
    let view = page
    view?.removeFromSuperview()
    page = nil
    return view
  }

  /// A layout frame (a resize, the first placement): the page follows.
  func setFrameKeepingPage(_ frame: CGRect) {
    self.frame = frame
    contact.frame = bounds
    surface.frame = bounds
    page?.frame = surface.bounds
    updateShadowPaths(CGRect(origin: .zero, size: frame.size))
  }

  func beginExpand(from source: CGRect, to target: CGRect) {
    let old = CGRect(x: source.minX - target.minX, y: source.minY - target.minY, width: source.width,
                     height: source.height)
    // The page keeps its size, anchored where it was; the surface grows under it (the plate fills the rest).
    page?.autoresizingMask = []
    frame = target
    contact.frame = bounds
    surface.frame = bounds
    page?.frame = old
    expandFrom = old
    surface.layer?.mask = mask
    setExpandProgress(0)
  }

  /// The mask between the old card frame (0) and the full card (1); the shadows follow it.
  func setExpandProgress(_ progress: CGFloat) {
    guard let from = expandFrom else { return }
    let to = bounds
    func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
    let rect = CGRect(x: lerp(from.minX, to.minX), y: lerp(from.minY, to.minY), width: lerp(from.width, to.width),
                      height: lerp(from.height, to.height))
    // The surface layer is flipped like the view; mask frames are in its coordinates.
    let flipped = surface.layer?.contentsAreFlipped() == true
    mask.frame = flipped ? rect : CGRect(x: rect.minX, y: to.height - rect.maxY, width: rect.width,
                                         height: rect.height)
    updateShadowPaths(rect)
  }

  private func updateShadowPaths(_ rect: CGRect) {
    let flipped = layer?.contentsAreFlipped() == true
    let r = flipped ? rect : CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    layer?.shadowPath = path
    contact.layer?.shadowPath = path
  }

  private func refreshColors() {
    let shadow = ShellTokens.peekShadow
    if let layer {
      layer.shadowColor = shadow.color.resolve(flavor).cgColor
      layer.shadowOpacity = 1
      layer.shadowRadius = shadow.radius / 2   // CALayer radius is a blur radius; the token is CSS-like
      layer.shadowOffset = CGSize(width: 0, height: layer.contentsAreFlipped() ? shadow.offsetY : -shadow.offsetY)
    }
    if let layer = contact.layer {
      layer.shadowColor = shadow.contactColor.resolve(flavor).cgColor
      layer.shadowOpacity = 1
      layer.shadowRadius = shadow.contactRadius / 2
      layer.shadowOffset = CGSize(width: 0, height: layer.contentsAreFlipped() ? shadow.contactOffsetY
                                    : -shadow.contactOffsetY)
    }
    surface.layer?.backgroundColor = ShellTokens.toolbarSurface.resolve(flavor).cgColor
    surface.layer?.borderColor = ShellTokens.cardBorder.resolve(flavor).cgColor
    surface.layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
  }

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refreshColors()
  }

  /// An Esc a page passed up the responder chain.
  public override func keyDown(with event: NSEvent) {
    if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, let onEscape {
      PeekController.logger.notice("peek Esc from the responder chain")
      onEscape()
      return
    }
    super.keyDown(with: event)
  }

  /// VoiceOver's escape gesture and AXCancel close the Peek.
  public override func accessibilityPerformCancel() -> Bool { onCancel?() ?? false }
}

// MARK: - Drag handle

/// The grabber and the band above the card: dragging moves the card (GS-022).
@MainActor
final class PeekDragHandleView: NSView {
  var onBegan: (@MainActor () -> Void)?
  /// Offset in points (down positive) since the drag began.
  var onChanged: (@MainActor (Double) -> Void)?
  /// Offset and release velocity (points per second, down positive).
  var onEnded: (@MainActor (Double, Double) -> Void)?
  private var start: CGPoint?
  private var samples: [(time: TimeInterval, y: Double)] = []

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

  override func mouseDown(with event: NSEvent) {
    start = event.locationInWindow
    samples = [(event.timestamp, 0)]
    onBegan?()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start else { return }
    // Window coordinates measure y upwards; the drag is down positive.
    let offset = Double(start.y - event.locationInWindow.y)
    samples.append((event.timestamp, offset))
    if samples.count > 6 { samples.removeFirst(samples.count - 6) }
    onChanged?(offset)
  }

  override func mouseUp(with event: NSEvent) {
    guard let start else { return }
    let offset = Double(start.y - event.locationInWindow.y)
    samples.append((event.timestamp, offset))
    self.start = nil
    onEnded?(offset, Self.velocity(of: samples))
  }

  /// Points per second over the last samples within 100 ms of the release.
  static func velocity(of samples: [(time: TimeInterval, y: Double)]) -> Double {
    guard let last = samples.last else { return 0 }
    let recent = samples.filter { last.time - $0.time <= 0.1 }
    guard let first = recent.first, last.time > first.time else { return 0 }
    return (last.y - first.y) / (last.time - first.time)
  }
}

// MARK: - Controls

/// One of the three 28 pt circles beside the card. Focus ring only from the keyboard; hover brightens the glyph.
@MainActor
public final class PeekControlButton: NSButton {
  var flavor: ThemeFlavor = .light { didSet { refreshColors() } }
  var opaqueFill = false { didSet { refreshColors() } }
  private var hovering = false { didSet { refreshColors() } }
  private var hoverArea: NSTrackingArea?

  init(symbol: String, label: String, help: String, toolTip: String, identifier: String) {
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(configuration)
    title = ""
    wantsLayer = true
    layer?.cornerRadius = PeekLayout.controlSize / 2
    self.toolTip = toolTip
    setAccessibilityLabel(label)
    setAccessibilityHelp(help)
    setAccessibilityIdentifier(identifier)
    refreshColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }

  public override var isEnabled: Bool { didSet { refreshColors() } }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  public override func mouseEntered(with event: NSEvent) { hovering = true }
  public override func mouseExited(with event: NSEvent) { hovering = false }

  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refreshColors()
  }

  private func refreshColors() {
    let fill = opaqueFill ? ShellTokens.toolbarSurface : ShellTokens.toastSurface
    layer?.backgroundColor = fill.resolve(flavor).cgColor
    layer?.borderColor = ShellTokens.cardBorder.resolve(flavor).cgColor
    layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
    let glyph = hovering && isEnabled ? ShellTokens.primaryText : ShellTokens.secondaryText
    var color = glyph.resolve(flavor)
    if !isEnabled { color.alpha *= 0.45 }
    contentTintColor = color.nsColor()
  }
}
