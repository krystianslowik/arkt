import AppKit
import QuartzCore

/// The Library button in the sidebar's bottom bar (design/downloads, direction B): the download glyph, with a graphite
/// ring that fills while files download. When everything finished it shows a check, and a small dot (also for a failed
/// or held file) until the Library is opened. Idle it is one quiet glyph, so a browser that never downloads shows
/// nothing extra. A click toggles the popover; resting the pointer on it for 0.4 s lists the recent files.
@MainActor
public final class LibraryButton: NSButton {
  static let symbols = (idle: "arrow.down.to.line", done: "checkmark", attention: "exclamationmark")

  private let ring = ProgressRing()
  private let dot = CALayer()
  private(set) public var ringState: DownloadsRingState = .idle
  private var tracking: NSTrackingArea?
  private(set) var isHovered = false
  /// The pointer entered or left the button.
  var onHoverChanged: (@MainActor (Bool) -> Void)?
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { ring.reduceMotion = reduceMotion }
  }
  /// The clock the ring's tween reads (tests step it by hand).
  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() } {
    didSet { ring.now = now }
  }

  public init() {
    super.init(frame: .zero)
    title = ""
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    setButtonType(.momentaryChange)
    focusRingType = .default
    autoresizingMask = []
    wantsLayer = true
    layer?.addSublayer(ring.layer)
    dot.cornerRadius = DownloadsMetrics.dotSize / 2
    dot.isHidden = true
    layer?.addSublayer(dot)
    setAccessibilityIdentifierWithCell(AXID.Downloads.libraryButton)
    apply(.idle)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override public var mouseDownCanMoveWindow: Bool { false }
  override public var wantsUpdateLayer: Bool { true }
  override public func updateLayer() { restyle() }

  /// The ring's arc position, for tests.
  var ringStrokeEnd: Double { ring.arcStrokeEnd }
  var ringAnimation: CABasicAnimation? { ring.arcAnimation }
  var ringIsShown: Bool { ring.showsRing }
  var dotIsShown: Bool { !dot.isHidden }
  var ringShownFraction: Double { ring.shownFraction }
  var ringLastStep: ProgressStep? { ring.lastStep }
  var glyphName: String {
    switch ringState {
    case .idle, .active: Self.symbols.idle
    case .done: Self.symbols.done
    case .attention: Self.symbols.attention
    }
  }

  /// Shows `next`: the arc eases to the whole's progress; the glyph and the dot follow the state.
  public func apply(_ next: DownloadsRingState) {
    ringState = next
    switch next {
    case .active(let fraction):
      ring.showsRing = true
      ring.setFraction(fraction ?? 0.25, attached: window != nil)
    case .idle, .done, .attention:
      ring.showsRing = false
      ring.setFraction(0, attached: false)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dot.isHidden = !(next == .done || next == .attention)
    CATransaction.commit()
    setAccessibilityLabel(DownloadsFormat.libraryButtonLabel(next))
    toolTip = next == .idle ? "Library" : DownloadsFormat.libraryButtonLabel(next)
    restyle()
  }

  private func restyle() {
    let flavor = archiveFlavor
    let color = (ringState == .idle ? ShellTokens.sidebarForeground : ShellTokens.primaryText).resolve(flavor)
    image = SymbolImageCache.shared.symbol(glyphName, box: DownloadsMetrics.glyphSize, weight: .regular, color: color,
                                           scale: shellBackingScale)
    ring.restyle(flavor: flavor)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dot.backgroundColor = DownloadsTokens.dot.resolve(flavor).cgColor
    CATransaction.commit()
  }

  override public func layout() {
    super.layout()
    let side = DownloadsMetrics.ringSize
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    ring.layer.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(),
                              width: side, height: side)
    ring.layoutRing()
    let size = DownloadsMetrics.dotSize
    dot.frame = NSRect(x: ring.layer.frame.maxX - size - 1, y: ring.layer.frame.maxY - size - 1, width: size, height: size)
    CATransaction.commit()
  }

  override public func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override public func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restyle()
  }

  override public func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override public func mouseEntered(with event: NSEvent) { setHovered(true) }
  override public func mouseExited(with event: NSEvent) { setHovered(false) }

  /// The pointer is over the button (tests set it directly).
  func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    onHoverChanged?(hovered)
  }
}
