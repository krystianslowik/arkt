import AppKit

/// The zoom pill (#579, design/extensions `surf-zoom`): minus, the percent, plus and Reset in a 36 pt pill at the top
/// trailing corner of the page card, like the find bar. A sibling above the card's clip view; `ZoomPillPresenter` holds
/// the state and this view draws `display` and reports the user. Hot path rules: frames set directly, transform and
/// opacity only. The entrance is the find bar's (a short fade and a 6 pt rise; Reduce Motion: the fade only); closing
/// is instant.
@MainActor
public final class ZoomPillView: NSView {
  /// Layer animation keys of the entrance.
  static let fadeKey = "zoomPillFade"
  static let riseKey = "zoomPillRise"

  weak var presenter: ZoomPillPresenter?
  let zoomOutButton = FindBarButton(symbol: "minus", pointSize: 11, label: "Zoom out", identifier: AXID.Zoom.zoomOut)
  let zoomInButton = FindBarButton(symbol: "plus", pointSize: 11, label: "Zoom in", identifier: AXID.Zoom.zoomIn)
  let percentLabel = NSTextField(labelWithString: "")
  let resetButton = ArchivePillButton(style: .neutral, title: "Reset", metrics: .infobar)
  /// The pill: the surface fill, the 0.5 pt edge and the radius. Two shadow layers sit under it.
  let surfaceLayer = CALayer()
  private var dropLayers: [CALayer] = []
  private var hoverArea: NSTrackingArea?
  /// Reduce Motion, read when the pill comes. Tests set it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { for button in [zoomOutButton, zoomInButton] { button.reduceMotion = reduceMotion } }
  }
  /// Where the pointer is in the window, for a pill that appears under it; nil: unknown. Tests set it, so the real
  /// pointer never decides a test.
  var pointerInWindow: @MainActor (NSView) -> NSPoint? = { $0.window?.mouseLocationOutsideOfEventStream }
  /// Speaks the percent instead of VoiceOver. Tests set it.
  var postAnnouncement: (@MainActor (String) -> Void)?

  public init(presenter: ZoomPillPresenter) {
    self.presenter = presenter
    super.init(frame: .zero)
    wantsLayer = true
    isHidden = true
    layer?.masksToBounds = false
    for _ in 0..<2 {
      let drop = CALayer()
      drop.masksToBounds = false
      dropLayers.append(drop)
      layer?.addSublayer(drop)
    }
    surfaceLayer.cornerRadius = ZoomPillLayout.cornerRadius
    surfaceLayer.cornerCurve = .continuous
    surfaceLayer.borderWidth = 0.5
    layer?.addSublayer(surfaceLayer)

    percentLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    percentLabel.alignment = .center
    percentLabel.isSelectable = false
    percentLabel.lineBreakMode = .byClipping
    percentLabel.setAccessibilityElement(true)
    percentLabel.setAccessibilityRole(.staticText)
    percentLabel.setAccessibilityLabel("Zoom level")
    percentLabel.setAccessibilityIdentifierWithCell(AXID.Zoom.percent)

    zoomOutButton.target = self
    zoomOutButton.action = #selector(zoomOutPressed(_:))
    zoomInButton.target = self
    zoomInButton.action = #selector(zoomInPressed(_:))
    resetButton.target = self
    resetButton.action = #selector(resetPressed(_:))
    resetButton.setArchiveAccessibilityLabel("Reset zoom")
    resetButton.setAccessibilityIdentifierWithCell(AXID.Zoom.reset)
    // A click never takes the keyboard from the page, as the toast's action (the zoom keys keep working).
    for button in [zoomOutButton, zoomInButton, resetButton] as [NSButton] { button.refusesFirstResponder = true }
    for view in [zoomOutButton, percentLabel, zoomInButton, resetButton] as [NSView] { addSubview(view) }

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Zoom")
    setAccessibilityIdentifier(AXID.Zoom.root)
    applyColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }

  /// The Reset pill's width; the pill's width follows it.
  var resetWidth: CGFloat { ceil(resetButton.intrinsicContentSize.width) }

  // MARK: Showing

  /// Draws the presenter's display: the pill for the tab on screen, or hidden.
  func refresh() {
    guard let display = presenter?.display else {
      isHidden = true
      return
    }
    let wasHidden = isHidden
    isHidden = false
    percentLabel.stringValue = display.percentText
    percentLabel.setAccessibilityValue(display.percentText)
    (superview as? ContentCardView)?.layoutZoomPill()
    needsLayout = true
    layoutSubtreeIfNeeded()
    if wasHidden { seedHover() }
    if wasHidden, presenter?.isOpening == true { animateEntrance() }
  }

  /// A pill that appears under a pointer that is not moving gets no `mouseEntered`; it starts out held open.
  private func seedHover() {
    guard let point = pointerInWindow(self) else { return }
    if bounds.contains(convert(point, from: nil)) { presenter?.setHovering(true) }
  }

  /// The percent after a change the user made, polite: it does not interrupt what VoiceOver is saying. Posted on the
  /// app, so it is heard when the pill closed at the default zoom too.
  func announce(_ text: String) {
    if let postAnnouncement {
      postAnnouncement(text)
      return
    }
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
      .announcement: text,
      .priority: NSAccessibilityPriorityLevel.medium.rawValue,
    ])
  }

  private func animateEntrance() {
    guard window != nil, let layer else { return }
    let entrance = FindBarMotion.entrance(reduceMotion: reduceMotion())
    layer.add(FindBarMotion.fadeAnimation(entrance), forKey: Self.fadeKey)
    if let rise = FindBarMotion.riseAnimation(entrance) { layer.add(rise, forKey: Self.riseKey) }
  }

  // MARK: Layout

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let parts = ZoomPillLayout.parts(resetWidth: resetWidth)
    let placed: [(NSView, CGRect)] = [(zoomOutButton, parts.zoomOut), (percentLabel, parts.percent),
                                      (zoomInButton, parts.zoomIn), (resetButton, parts.reset)]
    for (view, frame) in placed {
      view.frame = frame
      view.isHidden = !ZoomPillLayout.fits(frame, inWidth: bounds.width)     // a narrow pane drops Reset first
    }
    let shape = CGPath(roundedRect: bounds, cornerWidth: ZoomPillLayout.cornerRadius,
                       cornerHeight: ZoomPillLayout.cornerRadius, transform: nil)
    surfaceLayer.frame = bounds
    for drop in dropLayers {
      drop.frame = bounds
      drop.shadowPath = shape
    }
    CATransaction.commit()
  }

  // MARK: Pointer

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    guard hoverArea == nil else { return }       // `.inVisibleRect` follows the frame; added once
    // Always active: leaving while the window is not key still releases the hold, so the pill cannot stay forever.
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
  }

  public override func mouseEntered(with event: NSEvent) { presenter?.setHovering(true) }
  public override func mouseExited(with event: NSEvent) { presenter?.setHovering(false) }

  // MARK: Colors

  private func applyColors() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    surfaceLayer.backgroundColor = BrandTokens.surfaceBrand.resolve(flavor).cgColor
    surfaceLayer.borderColor = ShellTokens.overlayEdge.resolve(flavor).cgColor
    for (drop, shadow) in zip(dropLayers, ShellTokens.overlayShadow.drops(flavor)) {
      drop.shadowColor = shadow.color
      drop.shadowOpacity = shadow.opacity
      drop.shadowRadius = shadow.radius
      drop.shadowOffset = CGSize(width: 0, height: -shadow.offsetY)         // y points up: the drop falls below
    }
    percentLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    for button in [zoomOutButton, zoomInButton] { button.refreshColors() }
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  @objc private func zoomOutPressed(_ sender: Any?) { presenter?.zoomOut() }
  @objc private func zoomInPressed(_ sender: Any?) { presenter?.zoomIn() }
  @objc private func resetPressed(_ sender: Any?) { presenter?.reset() }
}
