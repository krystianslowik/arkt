import AppKit
import EngineAPI

/// Covers the page of a tab whose page process went away (#578, design/extensions `surf-crashed`): a 52 pt tile with a
/// face, "This page quit unexpectedly", one line naming the page, Reload (the one primary) and a quiet Close Tab. It
/// sits over the page area of the card that shows the tab, below the card's Toolbar, so the Toolbar's own Reload still
/// works. Frames are set in `layout()`.
@MainActor
final class CrashedTabView: NSView {
  static let title = "This page quit unexpectedly"
  static let reloadTitle = "Reload"
  static let closeTitle = "Close Tab"
  /// The page's own background (the prototype's `--page`): the dead page draws nothing, so the view does.
  static let background = TokenPair(light: .white(1), dark: .srgb(hex: 0x1E1F22))
  static let tileSide: CGFloat = 52
  static let tileRadius: CGFloat = 14
  static let glyphSide: CGFloat = 22
  static let bodyMaxWidth: CGFloat = 340

  /// The body line for a page on `host`; a page with no host (a file, a data URL) is "this page".
  static func message(host: String?) -> String {
    let page = host.flatMap { $0.isEmpty ? nil : $0 } ?? "this page"
    return "Something went wrong while showing \(page). Your other tabs are not affected."
  }

  /// The tab whose page this covers.
  let tab: TabID
  let tile = CrashedTabTileView(frame: .zero)
  let titleLabel = NSTextField(labelWithString: CrashedTabView.title)
  let bodyLabel = NSTextField(wrappingLabelWithString: "")
  let reloadButton = ArchivePillButton(style: .primary, title: CrashedTabView.reloadTitle, metrics: .dialog)
  let closeButton = ArchiveLinkButton(style: .secondary, title: CrashedTabView.closeTitle, fontSize: 13)
  /// Holds everything but the background; the entrance moves it.
  let content = CrashedTabContentView(frame: .zero)

  var onReload: (@MainActor () -> Void)?
  var onClose: (@MainActor () -> Void)?

  /// Return (or Enter) presses Reload while this view covers the current tab, unless text elsewhere in the window is
  /// being edited (its Return is its own). Not a key equivalent on the button, which would take Return from a field.
  var isDefault = false

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
    guard isDefault, event.type == .keyDown, modifiers.isEmpty,
          event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\u{3}",
          !(window?.firstResponder is NSText) else { return super.performKeyEquivalent(with: event) }
    reloadButton.performClick(nil)
    return true
  }

  /// The entrance played last (tests): nil before any, or when the view came with a tab switch (no motion).
  private(set) var entrance: DialogMotion.Step?

  init(tab: TabID, host: String?) {
    self.tab = tab
    super.init(frame: .zero)
    wantsLayer = true
    content.wantsLayer = true
    addSubview(content)
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.alignment = .center
    bodyLabel.font = .systemFont(ofSize: 13)
    bodyLabel.alignment = .center
    bodyLabel.stringValue = Self.message(host: host)
    reloadButton.target = self
    reloadButton.action = #selector(reloadPressed(_:))
    closeButton.target = self
    closeButton.action = #selector(closePressed(_:))
    for view in [tile, titleLabel, bodyLabel, reloadButton, closeButton] as [NSView] { content.addSubview(view) }
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(Self.title)
    setAccessibilityHelp(bodyLabel.stringValue)
    setAccessibilityIdentifier(AXID.CrashedTab.root)
    reloadButton.setAccessibilityIdentifierWithCell(AXID.CrashedTab.reload)
    closeButton.setAccessibilityIdentifierWithCell(AXID.CrashedTab.closeTab)
    tile.setAccessibilityElement(false)
    applyTextColors()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// The page's host changed while crashed (a tab handed over with a new snapshot): the body follows.
  func update(host: String?) {
    let message = Self.message(host: host)
    guard bodyLabel.stringValue != message else { return }
    bodyLabel.stringValue = message
    setAccessibilityHelp(message)
    needsLayout = true
  }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func updateLayer() {
    layer?.backgroundColor = Self.background.resolve(ThemeFlavor(appearance: effectiveAppearance)).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyTextColors()
    needsDisplay = true
    tile.needsDisplay = true
  }

  private func applyTextColors() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    bodyLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }

  override func layout() {
    super.layout()
    let bodyWidth = min(Self.bodyMaxWidth, max(bounds.width - 32, 0))
    let title = titleLabel.intrinsicContentSize
    let body = bodyLabel.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: bodyWidth, height: .greatestFiniteMagnitude))
      ?? .zero
    let reload = reloadButton.intrinsicContentSize
    let close = closeButton.intrinsicContentSize
    let rowWidth = ceil(reload.width) + 12 + ceil(close.width)
    let width = max(bodyWidth, ceil(title.width), rowWidth, Self.tileSide)
    let heights = [Self.tileSide, 12, ceil(title.height), 4, ceil(body.height), 18, reload.height]
    let height = heights.reduce(0, +)
    let frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded(),
                       width: width, height: height)
    if content.frame != frame { content.frame = frame }
    var y: CGFloat = 0
    tile.frame = NSRect(x: ((width - Self.tileSide) / 2).rounded(), y: y, width: Self.tileSide, height: Self.tileSide)
    y += Self.tileSide + 12
    titleLabel.frame = NSRect(x: 0, y: y, width: width, height: ceil(title.height))
    y += ceil(title.height) + 4
    bodyLabel.frame = NSRect(x: ((width - bodyWidth) / 2).rounded(), y: y, width: bodyWidth, height: ceil(body.height))
    y += ceil(body.height) + 18
    let x = ((width - rowWidth) / 2).rounded()
    reloadButton.frame = NSRect(x: x, y: y, width: ceil(reload.width), height: reload.height)
    closeButton.frame = NSRect(x: x + ceil(reload.width) + 12, y: y + ((reload.height - close.height) / 2).rounded(),
                               width: ceil(close.width), height: close.height)
  }

  /// The crash happened on screen: the content fades in and grows from 0.97 about its center (the design's panel
  /// motion, without the drop, since the view is centered); Reduce Motion fades only. The background is there at once:
  /// it covers a page that is gone.
  func playEntrance(reduceMotion: Bool) {
    layoutSubtreeIfNeeded()
    let step = DialogMotion.panelIn(reduceMotion: reduceMotion)
    entrance = step
    guard let layer = content.layer else { return }
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = step.fadeDuration
    fade.timingFunction = DialogMotion.easeOut
    layer.add(fade, forKey: "crashedFade")
    guard let spring = step.spring else { return }
    let bounds = content.bounds
    let start = DialogMotion.transform(scale: step.scale, offsetY: 0, about: CGPoint(x: bounds.midX, y: bounds.midY),
                                       bounds: bounds, layerAnchor: layer.anchorPoint)
    layer.add(DialogAlert.spring(spring, from: start), forKey: "crashedTransform")
  }

  @objc private func reloadPressed(_ sender: Any?) { onReload?() }
  @objc private func closePressed(_ sender: Any?) { onClose?() }
}

/// Top-down frames for the content stack.
@MainActor
final class CrashedTabContentView: NSView {
  override var isFlipped: Bool { true }
}

/// The 52 pt tile with the face (the prototype's `G.face`: a 16-unit circle with two eyes and a frown, stroke 1.4,
/// drawn at 22 pt).
@MainActor
final class CrashedTabTileView: NSView {
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    let tile = NSBezierPath(roundedRect: bounds, xRadius: CrashedTabView.tileRadius, yRadius: CrashedTabView.tileRadius)
    ShellTokens.sidebarItemBackground.resolve(flavor).nsColor().setFill()
    tile.fill()
    let side = CrashedTabView.glyphSide
    let unit = side / 16
    let origin = CGPoint(x: bounds.midX - side / 2, y: bounds.midY - side / 2)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * unit, y: origin.y + y * unit) }
    let face = NSBezierPath()
    face.appendOval(in: NSRect(origin: p(8 - 6.2, 8 - 6.2), size: CGSize(width: 12.4 * unit, height: 12.4 * unit)))
    face.move(to: p(5.6, 6.3)); face.line(to: p(5.6, 7.1))
    face.move(to: p(10.4, 6.3)); face.line(to: p(10.4, 7.1))
    face.move(to: p(5.6, 10.8))
    face.curve(to: p(8, 9.6), controlPoint1: p(6.2, 10.0), controlPoint2: p(7.0, 9.6))
    face.curve(to: p(10.4, 10.8), controlPoint1: p(9.0, 9.6), controlPoint2: p(9.8, 10.0))
    face.lineWidth = 1.4 * unit
    face.lineCapStyle = .round
    face.lineJoinStyle = .round
    ShellTokens.primaryText.resolve(flavor).nsColor().setStroke()
    face.stroke()
  }
}
