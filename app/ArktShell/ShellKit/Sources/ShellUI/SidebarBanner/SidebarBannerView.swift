import AppKit
import Motion

/// The sidebar banner (design/sidebar-banner, direction B): one 34 pt row shaped like a tab row, above the bottom bar.
/// An update shows its glyph, "Update" and a small Restart pill; an announcement shows its title on one truncated line
/// and a chevron, and a click opens the popover. Hovering shows an 18 pt close button over the row's top leading
/// corner.
///
/// The view's frame is the row's outset by the close button's overhang at the top and leading edges, so the button
/// stays inside the view; only the row (and the close button while shown) take clicks. Nothing here takes focus.
@MainActor
public final class SidebarBannerView: NSView {
  public private(set) var notice: SidebarNotice?
  /// The close button (or VoiceOver's press on it).
  var onDismiss: (@MainActor () -> Void)?
  /// Restart.
  var onAction: (@MainActor () -> Void)?
  /// A click on an announcement row: the popover.
  var onOpen: (@MainActor () -> Void)?
  var flavor: ThemeFlavor = .light { didSet { if flavor != oldValue { restyle() } } }
  /// Reduce Motion for the close button's fade (the container passes the model's).
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  let row = SidebarBannerRowView(frame: .zero)
  let glyph = NSImageView(frame: .zero)
  let label: NSTextField = {
    let label = NSTextField(labelWithString: "")
    label.lineBreakMode = .byTruncatingTail
    label.usesSingleLineMode = true
    label.cell?.isScrollable = false
    label.cell?.truncatesLastVisibleLine = true
    label.maximumNumberOfLines = 1
    label.setAccessibilityElement(false)
    return label
  }()
  let restartButton = ArchivePillButton(style: .primary, title: "Restart", metrics: .sidebarBanner)
  let chevron = NSImageView(frame: .zero)
  let closeButton = SidebarBannerCloseButton(frame: .zero)
  /// Whether the pointer is over the banner (the close button shows).
  private(set) var isHovered = false
  private(set) var rowLayout: SidebarBannerLayout?
  private var tracking: NSTrackingArea?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    isHidden = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.SidebarBanner.root)
    for view in [glyph, chevron] {
      view.imageScaling = .scaleProportionallyDown
      view.setAccessibilityElement(false)
    }
    restartButton.setAccessibilityLabel("Restart to update")
    restartButton.setAccessibilityIdentifierWithCell(AXID.SidebarBanner.restart)
    restartButton.refusesFirstResponder = true
    restartButton.target = self
    restartButton.action = #selector(restartPressed(_:))
    closeButton.setAccessibilityLabel("Dismiss notice")
    closeButton.setAccessibilityIdentifierWithCell(AXID.SidebarBanner.dismiss)
    closeButton.target = self
    closeButton.action = #selector(dismissPressed(_:))
    row.onPress = { [weak self] in self?.rowPressed() }
    row.pill = restartButton
    for view in [glyph, label, restartButton, chevron] as [NSView] { row.addSubview(view) }
    addSubview(row)
    addSubview(closeButton)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }
  public override var acceptsFirstResponder: Bool { false }

  /// The banner's frame for a row at `rowFrame` (both in the superview).
  static func frame(forRow rowFrame: NSRect) -> NSRect {
    let overhang = SidebarBannerMetrics.closeOverhang
    return NSRect(x: rowFrame.minX - overhang, y: rowFrame.minY - overhang,
                  width: rowFrame.width + overhang, height: rowFrame.height + overhang)
  }

  /// Shows `notice`'s content (no motion; the container animates the banner itself).
  func setNotice(_ notice: SidebarNotice?) {
    guard notice != self.notice else { return }
    self.notice = notice
    guard let notice else { return }
    label.stringValue = notice.rowLabel
    label.toolTip = notice.isUpdate ? nil : notice.title
    restartButton.title = notice.actionTitle ?? "Restart"
    restartButton.isHidden = !notice.isUpdate
    chevron.isHidden = notice.isUpdate
    setAccessibilityLabel(notice.title)
    row.isAnnouncement = !notice.isUpdate
    row.setAccessibilityLabel(notice.isUpdate ? nil : notice.title)
    restyle()
    needsLayout = true
  }

  // MARK: Drawing

  private func restyle() {
    let scale = shellBackingScale
    let text = ShellTokens.primaryText.resolve(flavor)
    row.layer?.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
    let isUpdate = notice?.isUpdate ?? true
    label.font = .systemFont(ofSize: SidebarBannerMetrics.labelFontSize, weight: isUpdate ? .semibold : .regular)
    label.textColor = text.nsColor()
    glyph.image = SymbolImageCache.shared.symbol(isUpdate ? "arrow.down.circle" : "sparkle",
                                                 box: SidebarBannerMetrics.glyphSize, color: text, scale: scale)
    chevron.image = SymbolImageCache.shared.symbol(
      "chevron.right", box: SidebarBannerMetrics.chevronHeight, weight: .semibold,
      color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
    closeButton.flavor = flavor
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }

  public override func layout() {
    super.layout()
    let overhang = SidebarBannerMetrics.closeOverhang
    row.frame = NSRect(x: overhang, y: overhang, width: max(0, bounds.width - overhang),
                       height: SidebarBannerMetrics.rowHeight)
    let isUpdate = notice?.isUpdate ?? true
    let labelWidth = label.attributedStringValue.size().width
    let layout = SidebarBannerLayout(rowWidth: row.bounds.width, isUpdate: isUpdate, labelWidth: labelWidth,
                                     pillWidth: restartButton.intrinsicContentSize.width)
    rowLayout = layout
    glyph.frame = layout.glyph
    let labelHeight = ceil(label.intrinsicContentSize.height)
    label.frame = NSRect(x: layout.label.minX, y: ((layout.label.height - labelHeight) / 2).rounded(),
                         width: layout.label.width, height: labelHeight)
    label.isHidden = layout.label.width <= 0
    restartButton.frame = layout.pill
    chevron.frame = layout.chevron ?? .zero
    let size = SidebarBannerMetrics.closeSize
    closeButton.frame = NSRect(x: 0, y: 0, width: size, height: size)
  }

  // MARK: Hit testing and hover

  public override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden, notice != nil, alphaValue > 0 else { return nil }
    let local = convert(point, from: superview)
    if isHovered, closeButton.frame.contains(local) { return closeButton }
    guard row.frame.contains(local) else { return nil }
    // The close button overlaps the row's corner but takes clicks only while shown.
    return row.hitTest(convert(local, to: row.superview)) ?? row
  }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  public override func mouseEntered(with event: NSEvent) { setHovered(true) }
  public override func mouseExited(with event: NSEvent) { setHovered(false) }

  /// Shows or hides the close button; it fades in 0.12 s (at once with Reduce Motion).
  func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    closeButton.setShown(hovered, animated: window != nil && !reduceMotion())
  }

  // MARK: Motion

  /// Bumped by every entrance and exit; an exit hides the view only while it is the latest.
  private var motionGeneration = 0

  /// The row rises `step.offset` points and fades in.
  func animateIn(_ step: SidebarBannerMotion.Step) {
    motionGeneration &+= 1
    isHidden = false
    guard let layer else { return }
    layer.removeAllAnimations()
    alphaValue = 1
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = step.duration
    fade.timingFunction = step.curve.timingFunction
    layer.add(fade, forKey: "bannerFade")
    if step.offset != 0 {
      // Below its place on screen: down is +y in a flipped superlayer.
      let down: CGFloat = layer.superlayer?.contentsAreFlipped() == true ? 1 : -1
      let rise = CABasicAnimation(keyPath: "transform.translation.y")
      rise.fromValue = step.offset * down
      rise.toValue = 0
      rise.duration = step.duration
      rise.timingFunction = step.curve.timingFunction
      layer.add(rise, forKey: "bannerRise")
    }
  }

  /// Fades out, then hides; `completion` runs when the view is hidden (not when a newer entrance took over).
  func animateOut(_ step: SidebarBannerMotion.Step, completion: @escaping @MainActor () -> Void) {
    motionGeneration &+= 1
    let generation = motionGeneration
    setHovered(false)
    guard let layer, window != nil else {
      finishOut(generation, completion)
      return
    }
    let from = layer.presentation()?.opacity ?? Float(alphaValue)
    layer.removeAllAnimations()
    alphaValue = 0
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated { self?.finishOut(generation, completion) }
    }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = 0
    fade.duration = step.duration
    fade.timingFunction = step.curve.timingFunction
    layer.add(fade, forKey: "bannerFade")
    CATransaction.commit()
  }

  /// Hides at once (no window, or a reset).
  func hideNow() {
    motionGeneration &+= 1
    setHovered(false)
    layer?.removeAllAnimations()
    alphaValue = 1
    isHidden = true
    notice = nil
  }

  private func finishOut(_ generation: Int, _ completion: @MainActor () -> Void) {
    guard generation == motionGeneration else { return }
    hideNow()
    completion()
  }

  // MARK: Actions

  @objc private func restartPressed(_ sender: Any?) { onAction?() }
  @objc private func dismissPressed(_ sender: Any?) { onDismiss?() }

  private func rowPressed() {
    guard notice?.isUpdate == false else { return }
    onOpen?()
  }
}

/// The banner's row: the tab-row fill, and for an announcement a button (click or VoiceOver press opens the popover).
/// Clicks on its label and glyph land here; the Restart pill keeps its own.
@MainActor
final class SidebarBannerRowView: NSView {
  var onPress: (@MainActor () -> Void)?
  weak var pill: NSView?
  var isAnnouncement = false {
    didSet {
      setAccessibilityElement(isAnnouncement)
      setAccessibilityRole(isAnnouncement ? .button : nil)
      setAccessibilityIdentifier(isAnnouncement ? AXID.SidebarBanner.open : nil)
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = SidebarBannerMetrics.cornerRadius
    layer?.cornerCurve = .continuous
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let hit = super.hitTest(point) else { return nil }
    if let pill, !pill.isHidden, hit === pill || hit.isDescendant(of: pill) { return hit }
    return self
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if bounds.contains(point) { onPress?() }
  }

  override func accessibilityPerformPress() -> Bool {
    guard isAnnouncement else { return false }
    onPress?()
    return true
  }
}

/// The 18 pt close button over the row's top leading corner: the brand surface with the overlay shadow, an X in
/// `secondaryText`. Invisible and not hit-tested until the banner is hovered, yet always in the accessibility tree,
/// so VoiceOver can dismiss without a pointer.
@MainActor
final class SidebarBannerCloseButton: NSButton {
  /// A full fade's length (the rows' X).
  static let fadeDuration = SidebarMetrics.closeButtonFadeDuration
  var flavor: ThemeFlavor = .light { didSet { restyle() } }
  private(set) var isShown = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    imageScaling = .scaleNone
    refusesFirstResponder = true
    wantsLayer = true
    layer?.masksToBounds = false
    layer?.cornerRadius = SidebarBannerMetrics.closeSize / 2
    alphaValue = 0
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  private func restyle() {
    guard let layer else { return }
    let shadow = ShellTokens.overlayShadow
    layer.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    layer.borderColor = ShellTokens.overlayEdge.resolve(flavor).cgColor
    layer.borderWidth = 0.5
    layer.shadowColor = shadow.contactColor.resolve(flavor).cgColor
    layer.shadowOpacity = 1
    layer.shadowRadius = shadow.contactRadius
    layer.shadowOffset = CGSize(width: 0, height: layer.contentsAreFlipped() ? shadow.contactOffsetY
                                                                             : -shadow.contactOffsetY)
    image = SymbolImageCache.shared.symbol("xmark", box: 8, weight: .bold,
                                           color: ShellTokens.secondaryText.resolve(flavor), scale: shellBackingScale)
  }

  override func layout() {
    super.layout()
    layer?.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
  }

  func setShown(_ shown: Bool, animated: Bool) {
    isShown = shown
    guard let layer else { return }
    let target: Float = shown ? 1 : 0
    let from = layer.presentation()?.opacity ?? Float(alphaValue)
    layer.removeAnimation(forKey: "opacity")
    alphaValue = CGFloat(target)
    guard animated else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = from
    fade.toValue = target
    fade.duration = Self.fadeDuration * Double(abs(target - from))
    fade.timingFunction = MotionCurve.strongEaseOut.timingFunction
    layer.add(fade, forKey: "opacity")
  }
}
