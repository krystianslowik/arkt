import AppKit

/// The Toolbar at the top of the content card (Toggle Toolbar, Cmd-Shift-D; KB-018, BH-032): Back, Forward,
/// Reload and the full URL as plain text centered in the strip. Shown and laid out by `ContentCardView`; actions are
/// wired by the window controller. Geometry is Arc 1.168 (`docs/plans/2026-10-23-arc-measurements.md`).
/// Back and Forward are enabled only while the shown tab can move that way (`setHistory`, engine contract rule 8); a
/// disabled button sends no action and VoiceOver reads it as dimmed.
@MainActor
public final class ContentToolbarView: NSView {
  static let stripHeight: CGFloat = 32                   // Arc 1.168: card top to the hairline
  static let hairlineHeight: CGFloat = 1                 // Arc 1.168; color `ShellTokens.toolbarHairline`
  /// The strip and its hairline.
  public static let height: CGFloat = stripHeight + hairlineHeight
  static let buttonSize = CGSize(width: 32, height: 24)  // Arc 1.168: centered in the strip, 4 pt from the top
  static let buttonSpacing: CGFloat = 5                  // Arc 1.168: 37 pt pitch
  static let iconSize: CGFloat = 14                      // Arc 1.168, inferred from the glyph boxes
  static let horizontalPadding: CGFloat = 5              // Arc 1.168: card edge to the first and last button
  /// The URL's press target, as tall as the buttons. Arc 1.168 draws no pill: plain text in a 16 pt frame, centered
  /// in the strip.
  static let urlBarHeight: CGFloat = 24

  public let backButton = NSButton(frame: .zero)
  public let forwardButton = NSButton(frame: .zero)
  public let reloadButton = NSButton(frame: .zero)
  public let urlBar = URLBarView(style: .full)
  public var onBack: (@MainActor () -> Void)?
  public var onForward: (@MainActor () -> Void)?
  public var onReload: (@MainActor () -> Void)?

  /// The hairline under the strip.
  let hairline = CALayer()
  private var flavor: ThemeFlavor?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layer?.addSublayer(hairline)
    for (button, _, label, action) in buttons {
      button.isBordered = false
      button.bezelStyle = .regularSquare
      button.imagePosition = .imageOnly
      button.setAccessibilityLabel(label)
      button.toolTip = label
      button.target = self
      button.action = action
      button.autoresizingMask = []
      addSubview(button)
    }
    setHistory(canGoBack: false, canGoForward: false)
    urlBar.autoresizingMask = []
    addSubview(urlBar)
    setAccessibilityElement(true)
    setAccessibilityRole(.toolbar)
    setAccessibilityLabel("Toolbar")
    applyFlavor()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var wantsUpdateLayer: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }

  private var buttons: [(NSButton, String, String, Selector)] {
    [(backButton, "chevron.left", "Back", #selector(back(_:))),
     (forwardButton, "chevron.right", "Forward", #selector(forward(_:))),
     (reloadButton, "arrow.clockwise", "Reload", #selector(reload(_:)))]
  }

  /// Enables Back and Forward from the shown tab's `canGoBack` / `canGoForward`; both off when no tab is shown.
  public func setHistory(canGoBack: Bool, canGoForward: Bool) {
    backButton.isEnabled = canGoBack
    forwardButton.isEnabled = canGoForward
  }

  @objc private func back(_ sender: Any?) { onBack?() }
  @objc private func forward(_ sender: Any?) { onForward?() }
  @objc private func reload(_ sender: Any?) { onReload?() }

  /// The card follows the window's appearance, not the Space theme; so does the Toolbar.
  private func applyFlavor() {
    let flavor = ThemeFlavor(appearance: effectiveAppearance)
    guard flavor != self.flavor else { return }
    self.flavor = flavor
    urlBar.flavor = flavor
    applyButtonImages(flavor)
    needsDisplay = true
  }

  private func applyButtonImages(_ flavor: ThemeFlavor) {
    let color = ShellTokens.secondaryText.resolve(flavor)
    for (button, symbol, _, _) in buttons {
      button.image = SymbolImageCache.shared.symbol(symbol, box: Self.iconSize, color: color,
                                                    scale: shellBackingScale)
    }
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyFlavor()
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    if let flavor { applyButtonImages(flavor) }
  }

  public override func updateLayer() {
    let flavor = flavor ?? .light
    layer?.backgroundColor = ShellTokens.toolbarSurface.resolve(flavor).cgColor
    hairline.backgroundColor = ShellTokens.toolbarHairline.resolve(flavor).cgColor
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let strip = min(Self.stripHeight, bounds.height)
    let size = Self.buttonSize
    let buttonY = ((strip - size.height) / 2).rounded()
    var x = Self.horizontalPadding
    for (button, _, _, _) in buttons {
      button.frame = NSRect(x: x, y: buttonY, width: size.width, height: size.height)
      x += size.width + Self.buttonSpacing
    }
    // Centered in the whole strip: the frame keeps the same inset on both sides, clear of the buttons.
    let inset = x
    let barHeight = Self.urlBarHeight
    urlBar.frame = NSRect(x: inset, y: ((strip - barHeight) / 2).rounded(),
                          width: max(0, bounds.width - 2 * inset), height: barHeight)
    hairline.frame = CGRect(x: 0, y: strip, width: bounds.width, height: max(0, bounds.height - strip))
    CATransaction.commit()
  }
}
