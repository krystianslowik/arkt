import AppKit

/// A file's tile: its extension in white on a fixed mid-tone fill (the same in light and dark), or, for a blocked file, a
/// neutral fill with a warning glyph. Decoration: VoiceOver reads the row.
@MainActor
final class DownloadTileView: NSView {
  private(set) var kind = DownloadsFormat.kind(of: "")
  private(set) var isBlocked = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  func configure(filename: String, blocked: Bool) {
    let next = DownloadsFormat.kind(of: filename)
    guard next != kind || blocked != isBlocked else { return }
    kind = next
    isBlocked = blocked
    needsDisplay = true
  }

  /// The fill drawn now, for tests.
  var displayedFill: RGBA {
    isBlocked ? DownloadsTokens.warnTileFill.resolve(archiveFlavor) : .srgb(hex: UInt32(kind.fillHex))
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let radius = bounds.width * 0.25
    displayedFill.nsColor().setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    if isBlocked {
      let color = ShellTokens.primaryText.resolve(archiveFlavor)
      let glyph = SymbolImageCache.shared.symbol("exclamationmark.circle", box: bounds.width * 0.5, color: color,
                                                 scale: shellBackingScale)
      let side = bounds.width * 0.5
      glyph.draw(in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side))
      return
    }
    let font = NSFont.systemFont(ofSize: max(7, (bounds.width * 0.29).rounded()), weight: .bold)
    let text = NSAttributedString(string: kind.label, attributes: [
      .font: font, .foregroundColor: DownloadsTokens.tileText.nsColor(), .kern: 0.2,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
  }
}

/// A 24 pt icon button (Cancel x, Show in Finder, Remove from list): a quiet symbol that fills on hover and presses to
/// 0.94 in 0.12 s (nothing under Reduce Motion). A real `NSButton`, so Space, VoiceOver's press and the key view loop
/// work.
@MainActor
final class DownloadIconButton: NSButton {
  let symbolName: String
  private var hovering = false
  private var tracking: NSTrackingArea?
  private let body = CALayer()
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  private(set) var pressing = false

  init(symbol: String, label: String) {
    symbolName = symbol
    super.init(frame: NSRect(x: 0, y: 0, width: DownloadsMetrics.iconButton, height: DownloadsMetrics.iconButton))
    title = ""
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    imagePosition = .imageOnly
    focusRingType = .default
    wantsLayer = true
    layer?.addSublayer(body)
    body.cornerCurve = .continuous
    setArchiveAccessibilityLabel(label)
    toolTip = label
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }
  override var intrinsicContentSize: NSSize {
    NSSize(width: DownloadsMetrics.iconButton, height: DownloadsMetrics.iconButton)
  }

  /// The fill drawn now (nil: none), for tests.
  var displayedFill: RGBA? { hovering ? DownloadsTokens.rowFill.resolve(archiveFlavor) : nil }

  private func restyle() {
    let flavor = archiveFlavor
    let color = (hovering ? ShellTokens.primaryText : ShellTokens.sidebarForeground).resolve(flavor)
    image = SymbolImageCache.shared.symbol(symbolName, box: 12, weight: .semibold, color: color,
                                           scale: window?.backingScaleFactor ?? 2)
    ArchiveMotion.set { body.backgroundColor = displayedFill?.cgColor }
  }

  override func layout() {
    super.layout()
    ArchiveMotion.set {
      body.bounds = bounds
      body.position = CGPoint(x: bounds.midX, y: bounds.midY)
      body.cornerRadius = bounds.height / 2
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) { hovering = true; restyle() }
  override func mouseExited(with event: NSEvent) { hovering = false; restyle() }

  /// The press: scale 0.94 over 0.12 s ease-out; Reduce Motion changes nothing.
  func setPressed(_ pressed: Bool) {
    guard isEnabled, pressed != pressing else { return }
    pressing = pressed
    guard !reduceMotion() else { return }
    let scale = pressed ? DownloadsMotion.iconPressScale : 1
    ArchiveMotion.animate(body, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1)),
                          duration: DownloadsMotion.pressDuration)
  }

  override func mouseDown(with event: NSEvent) {
    setPressed(true)
    super.mouseDown(with: event)                       // tracks until the button goes up
    setPressed(false)
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " { performClick(nil); return }
    super.keyDown(with: event)
  }
}
