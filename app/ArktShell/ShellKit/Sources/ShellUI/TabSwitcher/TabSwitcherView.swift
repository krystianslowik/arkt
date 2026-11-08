import AppKit
import Motion

/// What one switcher row shows: favicon, title, then a split marker and the Space chip (design "Look"). The
/// recording indicator of the design waits for the engine to report camera and microphone use.
public struct TabSwitcherRow {
  public var node: NodeID
  public var title: String
  public var favicon: NSImage
  public var spaceTitle: String?
  public var spaceColor: RGBA?
  public var isSplitPane: Bool

  public init(node: NodeID, title: String, favicon: NSImage, spaceTitle: String?, spaceColor: RGBA?,
              isSplitPane: Bool) {
    self.node = node; self.title = title; self.favicon = favicon
    self.spaceTitle = spaceTitle; self.spaceColor = spaceColor; self.isSplitPane = isSplitPane
  }
}

/// The Ctrl-Tab panel: a quiet floating list of up to five rows over the window, no scrim, no header (design
/// "Look"). It is built once per window and only filled and unhidden on the key-down, so it is on screen with the
/// next frame. Motion after that first frame is transform and opacity only: the highlight springs between rows
/// (`springyFast`), rows below a closed one slide up (`firmFast`), and the panel fades out on dismiss (0.10 s).
/// Frames are set directly; no Auto Layout.
@MainActor
public final class TabSwitcherView: NSView {
  public static let width: CGFloat = 480
  public static let padding: CGFloat = 6
  public static let rowHeight: CGFloat = 40
  static let cornerRadius = ShellRadius.popover
  static let rowCornerRadius: CGFloat = 8
  static let fadeDuration: CFTimeInterval = FadeDuration.quick
  static let fadeKey = "tabSwitcher.fade"
  /// Strong ease-out (`--ease-out` of the motion guidelines) for the dismiss fade and the Reduce Motion crossfades.
  static let easeOut = MotionCurve.strongEaseOut.timingFunction

  public static func height(rows: Int) -> CGFloat { 2 * padding + CGFloat(rows) * rowHeight }

  /// Reading Reduce Motion; the controller passes its own so tests can switch it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var reduceTransparency: @MainActor () -> Bool = {
    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
  }
  /// Increase Contrast (#640): the highlight's 1 pt edge takes `increasedContrastEdge`. Tests replace it.
  var increaseContrast: @MainActor () -> Bool = { IncreasedContrast.systemSetting }

  /// One row view per possible row, plus `ghost`, which shows a closed row while it fades.
  public private(set) var rowViews: [TabSwitcherRowView] = []
  public private(set) var rowCount = 0
  let ghost = TabSwitcherRowView(frame: .zero)
  /// Bumped on every ghost fade; a fade's completion hides the ghost only if no fade came after it.
  private var ghostGeneration = 0
  /// Clips the rows to the panel, so a row sliding up from below the new bottom edge enters from under it.
  private let rowsClip = FlippedClipView(frame: .zero)
  private let surface = CALayer()
  private var dropLayers: [CALayer] = []
  let highlightLayer = CALayer()
  private(set) var flavor: ThemeFlavor = .light

  private lazy var highlightDriver = SpringDriver(reduceMotion: { [weak self] in self?.reduceMotion() ?? true })
  /// The clock of the row slides; tests freeze it and step the drivers by hand.
  var collapseClock: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  /// One slide per row slot, in points from the slot, so a second W retargets each row from its own presented offset
  /// and velocity.
  private(set) lazy var collapseDrivers: [SpringDriver] = (0..<TabSwitcherSession.maximumRows).map { _ in
    SpringDriver(now: { [weak self] in self?.collapseClock() ?? CACurrentMediaTime() },
                 reduceMotion: { [weak self] in self?.reduceMotion() ?? true })
  }
  /// Where the highlight is heading, in points from the first row.
  public private(set) var highlightOffset: CGFloat = 0
  /// The value the highlight shows now (also mid-flight).
  private var presentedHighlightOffset: CGFloat = 0
  public var isHighlightMoving: Bool { highlightDriver.isRunning }
  public var isCollapsing: Bool { collapseDrivers.contains { $0.isRunning } }
  /// Bumped on every show; a fade's completion hides the panel only if no show came after it.
  private var showGeneration = 0
  public private(set) var isFadingOut = false

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    isHidden = true
    layer?.masksToBounds = false
    for _ in 0..<2 {
      let drop = CALayer()
      drop.masksToBounds = false
      dropLayers.append(drop)
      layer?.addSublayer(drop)
    }
    surface.cornerRadius = Self.cornerRadius
    surface.cornerCurve = .continuous
    surface.borderWidth = 0.5
    layer?.addSublayer(surface)
    rowsClip.wantsLayer = true
    rowsClip.layer?.masksToBounds = true
    addSubview(rowsClip)
    highlightLayer.cornerRadius = Self.rowCornerRadius
    highlightLayer.cornerCurve = .continuous
    rowsClip.layer?.addSublayer(highlightLayer)
    ghost.isHidden = true
    rowsClip.addSubview(ghost)
    for _ in 0..<TabSwitcherSession.maximumRows {
      let row = TabSwitcherRowView(frame: .zero)
      row.isHidden = true
      rowViews.append(row)
      rowsClip.addSubview(row)
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilitySubrole(.dialog)
    setAccessibilityLabel("Recent tabs")
    setAccessibilityIdentifier(AXID.TabSwitcher.panel)
    setAccessibilityModal(true)
    applyColors()
    IncreasedContrast.observe(self, selector: #selector(displayOptionsChanged(_:)))
  }

  @objc private func displayOptionsChanged(_ note: Notification) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    applyColors()
    CATransaction.commit()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var acceptsFirstResponder: Bool { false }
  public override var mouseDownCanMoveWindow: Bool { false }

  public override func accessibilityChildren() -> [Any]? { Array(rowViews.prefix(rowCount)) }

  // MARK: Showing

  /// Fills `rows`, highlights `highlight` and shows the panel at full opacity in this turn: no entrance animation,
  /// so the panel is on screen with the next frame (the one-frame bar). A running fade-out is dropped.
  func show(rows: [TabSwitcherRow], highlight: Int, flavor: ThemeFlavor, frame: NSRect) {
    showGeneration += 1
    isFadingOut = false
    layer?.removeAnimation(forKey: Self.fadeKey)
    highlightDriver.stop()
    stopCollapse()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.opacity = 1
    ghost.isHidden = true                           // a W fade still running from the last session ends here
    self.flavor = flavor
    applyColors()                                   // also picks up a Reduce Transparency change
    self.frame = frame
    fill(rows)
    setHighlight(index: highlight, animated: false)
    layoutChrome()
    CATransaction.commit()
    isHidden = false
  }

  /// Hides the panel: at once when it was never presented (a flick), else with the 0.10 s fade. A `show` during the
  /// fade takes over.
  func dismiss(animated: Bool) {
    highlightDriver.stop()
    stopCollapse()
    guard animated, !isHidden, let layer else {
      layer?.removeAnimation(forKey: Self.fadeKey)
      isFadingOut = false
      isHidden = true
      return
    }
    let generation = showGeneration
    isFadingOut = true
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = layer.presentation()?.opacity ?? 1
    fade.toValue = 0
    fade.duration = Self.fadeDuration
    fade.timingFunction = Self.easeOut
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.showGeneration == generation, self.isFadingOut else { return }
        self.isFadingOut = false
        self.isHidden = true
        self.layer?.removeAnimation(forKey: Self.fadeKey)
        self.layer?.opacity = 1
      }
    }
    layer.opacity = 0
    layer.add(fade, forKey: Self.fadeKey)
    CATransaction.commit()
  }

  // MARK: Highlight

  /// Moves the highlight to row `index`. Animated, it springs (`springyFast`) and a move during a running spring
  /// continues from where the highlight is, with its velocity. Reduce Motion: it jumps.
  func setHighlight(index: Int, animated: Bool) {
    let target = CGFloat(index) * Self.rowHeight
    highlightOffset = target
    for (row, view) in rowViews.prefix(rowCount).enumerated() { view.setAccessibilitySelected(row == index) }
    guard animated, !reduceMotion(), window != nil else {
      highlightDriver.stop()
      applyHighlight(target)
      return
    }
    let running = highlightDriver.stop()
    highlightDriver.animate(in: self, from: Double(running?.value ?? Double(presentedHighlightOffset)),
                            to: Double(target), initialVelocity: running?.velocity ?? 0,
                            parameters: SpringPreset.springyFast.parameters) { [weak self] value in
      self?.applyHighlight(CGFloat(value))
    }
  }

  private func applyHighlight(_ offset: CGFloat) {
    presentedHighlightOffset = offset
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    highlightLayer.transform = CATransform3DMakeTranslation(0, offset, 0)
    CATransaction.commit()
  }

  // MARK: Closing a row

  /// The row at `index` closed and `rows` are the ones left. The panel takes its new height at once (W is a key
  /// press); the closed row fades where it was while the rows below it slide up into place (`firmFast`). A W during a
  /// running slide continues every row from where it is on screen, with its velocity. Reduce Motion: no slide, the
  /// closed row fades out while the rows that moved fade in.
  func collapse(closed: TabSwitcherRow, at index: Int, rows: [TabSwitcherRow], highlight: Int, frame: NSRect) {
    let presented = stopCollapse()                  // offset and velocity per old slot, before `fill` resets them
    let animates = window != nil
    let slides = animates && !reduceMotion()
    // Slot `k` now shows the row that was in slot `k` above the closed one and in slot `k + 1` below it.
    let starts = (0..<rows.count).map { slot -> (offset: CGFloat, velocity: Double) in
      guard slides else { return (0, 0) }
      let old = slot < index ? slot : slot + 1
      let state = presented[old]
      return (CGFloat(old - slot) * Self.rowHeight + CGFloat(state.value), state.velocity)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    self.frame = frame
    fill(rows)
    layoutChrome()
    ghost.configure(closed, flavor: flavor)
    var ghostFrame = rowFrame(index)
    if slides { ghostFrame.origin.y += CGFloat(presented[index].value) }   // where the closed row was on screen
    ghost.frame = ghostFrame
    ghost.isHidden = !animates
    ghost.layer?.opacity = 0
    for (slot, start) in starts.enumerated() where start.offset != 0 {   // where they are, until the first frame
      rowViews[slot].layer?.transform = CATransform3DMakeTranslation(0, start.offset, 0)
    }
    CATransaction.commit()
    setHighlight(index: highlight, animated: animates)
    guard animates else { return }
    fadeOut(ghost)
    guard slides else {
      for row in rowViews[index..<rowCount] { fadeIn(row) }
      return
    }
    for (slot, start) in starts.enumerated() where start.offset != 0 || start.velocity != 0 {
      let row = rowViews[slot]
      collapseDrivers[slot].animate(in: self, from: Double(start.offset), to: 0, initialVelocity: start.velocity,
                                    parameters: SpringPreset.firmFast.parameters) { [weak row] offset in
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        row?.layer?.transform = CATransform3DMakeTranslation(0, CGFloat(offset), 0)
        CATransaction.commit()
      }
    }
  }

  /// Stops every row slide. Returns each slot's presented offset (points below its slot) and velocity; `(0, 0)` for
  /// a slot at rest.
  @discardableResult
  private func stopCollapse() -> [(value: Double, velocity: Double)] {
    collapseDrivers.map { $0.stop() ?? (0, 0) }
  }

  private func fadeOut(_ view: NSView) {
    ghostGeneration += 1
    let generation = ghostGeneration
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 1
    fade.toValue = 0
    fade.duration = SpringPreset.firmFast.parameters.response
    fade.timingFunction = Self.easeOut
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self, weak view] in
      MainActor.assumeIsolated {                    // a fade replaced by a later W's keeps the ghost up
        guard let self, self.ghostGeneration == generation else { return }
        view?.isHidden = true
      }
    }
    view.layer?.add(fade, forKey: "tabSwitcher.closeFade")
    CATransaction.commit()
  }

  private func fadeIn(_ view: NSView) {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = SpringPreset.firmFast.parameters.response
    fade.timingFunction = Self.easeOut
    view.layer?.add(fade, forKey: "tabSwitcher.closeFade")
  }

  // MARK: Layout

  private func fill(_ rows: [TabSwitcherRow]) {
    rowCount = rows.count
    for (index, view) in rowViews.enumerated() {
      guard index < rows.count else {
        view.isHidden = true
        continue
      }
      view.configure(rows[index], flavor: flavor)
      view.position = (index + 1, rows.count)
      view.frame = rowFrame(index)
      view.layer?.transform = CATransform3DIdentity
      view.layer?.removeAnimation(forKey: "tabSwitcher.closeFade")
      view.isHidden = false
    }
  }

  private func rowFrame(_ index: Int) -> NSRect {
    NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: Self.width - 2 * Self.padding, height: Self.rowHeight)
  }

  private func layoutChrome() {
    let shape = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius,
                       transform: nil)
    surface.frame = bounds
    for drop in dropLayers {
      drop.frame = bounds
      drop.shadowPath = shape
    }
    rowsClip.frame = bounds.insetBy(dx: Self.padding, dy: Self.padding)
    // Bounds and position, not `frame`: setting the frame of a transformed layer would cancel its translation.
    let first = rowFrame(0)
    highlightLayer.bounds = CGRect(origin: .zero, size: first.size)
    highlightLayer.position = CGPoint(x: first.midX, y: first.midY)
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layoutChrome()
    CATransaction.commit()
  }

  /// The row under `point` (in this view's coordinates), if any.
  func row(at point: NSPoint) -> Int? {
    let local = convert(point, to: rowsClip)
    guard rowsClip.bounds.contains(local) else { return nil }
    let index = Int(local.y / Self.rowHeight)
    return index < rowCount ? index : nil
  }

  // MARK: Colors

  private func applyColors() {
    let surfaceColor = reduceTransparency() ? ShellTokens.toolbarSurface : ShellTokens.toastSurface
    surface.backgroundColor = surfaceColor.resolve(flavor).cgColor
    surface.borderColor = ShellTokens.overlayEdge.resolve(flavor).cgColor
    for (drop, shadow) in zip(dropLayers, ShellTokens.overlayShadow.drops(flavor)) {
      drop.shadowColor = shadow.color
      drop.shadowOpacity = shadow.opacity
      drop.shadowRadius = shadow.radius
      drop.shadowOffset = CGSize(width: 0, height: shadow.offsetY)        // the layer is flipped: y points down
    }
    highlightLayer.backgroundColor = ShellTokens.sidebarItemHovered.resolve(flavor).cgColor
    IncreasedContrast.setEdge(on: highlightLayer, increased: increaseContrast(), flavor: flavor, otherwiseWidth: 1,
                              color: ShellTokens.sidebarDivider.resolve(flavor))
  }
}

/// One switcher row: favicon, title, split marker and Space chip. Frames set in `layout()`.
@MainActor
public final class TabSwitcherRowView: NSView {
  static let faviconLeading: CGFloat = 12          // 10 inset, then the 16 pt favicon centered in a 20 pt slot
  static let titleLeading: CGFloat = 40            // 10 + 20 + 10
  static let trailingInset: CGFloat = 10
  static let titleGap: CGFloat = 12
  static let markerGap: CGFloat = 8
  static let dotSize: CGFloat = 7
  static let dotGap: CGFloat = 5
  static let spaceMaxWidth: CGFloat = 120
  static let glyphSize: CGFloat = 12

  public let faviconView = NSImageView()
  public let titleField = NSTextField(labelWithString: "")
  public let spaceField = NSTextField(labelWithString: "")
  public let splitView = NSImageView()
  private let dot = CALayer()
  /// 1-based position and row count, for the accessibility label.
  var position = (1, 1) {
    didSet { updateAccessibilityLabel() }
  }
  private var isSplitPane = false
  private var title = ""
  private var spaceTitle: String?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    titleField.font = ShellType.rowTitle.font
    titleField.lineBreakMode = .byTruncatingTail
    titleField.maximumNumberOfLines = 1
    titleField.cell?.truncatesLastVisibleLine = true
    spaceField.font = ShellType.footnote.font
    spaceField.lineBreakMode = .byTruncatingTail
    spaceField.maximumNumberOfLines = 1
    splitView.imageScaling = .scaleProportionallyUpOrDown
    for view in [faviconView, titleField, spaceField, splitView] as [NSView] {
      view.autoresizingMask = []
      view.setAccessibilityElement(false)
      addSubview(view)
    }
    titleField.cell?.setAccessibilityElement(false)
    spaceField.cell?.setAccessibilityElement(false)
    dot.cornerRadius = Self.dotSize / 2
    layer?.addSublayer(dot)
    setAccessibilityElement(true)
    setAccessibilityRole(.row)
    setAccessibilityIdentifier(AXID.TabSwitcher.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  func configure(_ row: TabSwitcherRow, flavor: ThemeFlavor) {
    title = row.title
    spaceTitle = row.spaceTitle
    isSplitPane = row.isSplitPane
    faviconView.image = row.favicon
    titleField.stringValue = row.title
    titleField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    spaceField.stringValue = row.spaceTitle ?? ""
    spaceField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    spaceField.isHidden = row.spaceTitle == nil
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dot.isHidden = row.spaceTitle == nil
    dot.backgroundColor = (row.spaceColor ?? ShellTokens.sidebarForeground.resolve(flavor)).cgColor
    CATransaction.commit()
    splitView.isHidden = !row.isSplitPane
    if row.isSplitPane {
      splitView.image = SymbolImageCache.shared.symbol(
        "rectangle.split.2x1", box: Self.glyphSize, color: ShellTokens.secondaryText.resolve(flavor),
        scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }
    updateAccessibilityLabel()
    needsLayout = true
  }

  /// "title, Space, k of n", with ", split" for a pane (design "VoiceOver").
  private func updateAccessibilityLabel() {
    var parts = [title]
    if let spaceTitle { parts.append(spaceTitle) }
    parts.append("\(position.0) of \(position.1)")
    var label = parts.joined(separator: ", ")
    if isSplitPane { label += ", split" }
    setAccessibilityLabel(label)
  }

  public override func layout() {
    super.layout()
    let midY = bounds.midY
    faviconView.frame = NSRect(x: Self.faviconLeading, y: midY - 8, width: 16, height: 16)
    var trailing = bounds.width - Self.trailingInset
    if !spaceField.isHidden {
      let size = spaceField.cell?.cellSize ?? spaceField.intrinsicContentSize
      let width = min(ceil(size.width), Self.spaceMaxWidth)
      let height = ceil(size.height)
      spaceField.frame = NSRect(x: trailing - width, y: midY - height / 2, width: width, height: height)
      trailing -= width + Self.dotGap
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      dot.frame = NSRect(x: trailing - Self.dotSize, y: midY - Self.dotSize / 2, width: Self.dotSize,
                         height: Self.dotSize)
      CATransaction.commit()
      trailing -= Self.dotSize
    }
    if !splitView.isHidden {
      trailing -= Self.markerGap
      splitView.frame = NSRect(x: trailing - Self.glyphSize, y: midY - Self.glyphSize / 2, width: Self.glyphSize,
                               height: Self.glyphSize)
      trailing -= Self.glyphSize
    }
    let titleHeight = ceil(titleField.intrinsicContentSize.height)
    let titleWidth = max(0, trailing - Self.titleGap - Self.titleLeading)
    titleField.frame = NSRect(x: Self.titleLeading, y: midY - titleHeight / 2, width: titleWidth, height: titleHeight)
  }
}

/// A flipped, clipping container: rows and the highlight are placed top down.
@MainActor
private final class FlippedClipView: NSView {
  override var isFlipped: Bool { true }
}

extension ShadowToken {
  /// The two drops, outer first, as Core Animation shadow settings for `flavor`: an opaque color, the opacity, the
  /// radius and the downward offset.
  func drops(_ flavor: ThemeFlavor) -> [(color: CGColor, opacity: Float, radius: CGFloat, offsetY: CGFloat)] {
    [(color, radius, offsetY), (contactColor, contactRadius, contactOffsetY)].map { pair, radius, offsetY in
      let value = pair.resolve(flavor)
      let opaque = RGBA(red: value.red, green: value.green, blue: value.blue, alpha: 1, space: value.space)
      return (opaque.cgColor, Float(value.alpha), radius, offsetY)
    }
  }
}
