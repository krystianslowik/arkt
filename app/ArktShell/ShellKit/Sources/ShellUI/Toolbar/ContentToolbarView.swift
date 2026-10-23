import AppKit

/// The Toolbar at the top of the content card (Toggle Toolbar, Cmd-Shift-D; KB-018, BH-032): Back, Forward,
/// Reload and the full URL. Shown and laid out by `ContentCardView`; actions are wired by the window controller.
/// Back and Forward are always enabled for now; a press with no history does nothing (engine contract rule 7).
@MainActor
public final class ContentToolbarView: NSView {
  public static let height: CGFloat = 40                 // TODO(measure)
  static let buttonSize: CGFloat = 28                    // TODO(measure)
  static let iconSize: CGFloat = 14                      // TODO(measure)
  static let horizontalPadding: CGFloat = 8              // TODO(measure)
  static let urlBarHeight: CGFloat = 28                  // TODO(measure)

  public let backButton = NSButton(frame: .zero)
  public let forwardButton = NSButton(frame: .zero)
  public let reloadButton = NSButton(frame: .zero)
  public let urlBar = URLBarView(style: .full)
  public var onBack: (@MainActor () -> Void)?
  public var onForward: (@MainActor () -> Void)?
  public var onReload: (@MainActor () -> Void)?

  private let divider = CALayer()
  private var flavor: ThemeFlavor?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    layer?.addSublayer(divider)
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
    divider.backgroundColor = ShellTokens.cardBorder.resolve(flavor).cgColor
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let size = Self.buttonSize
    let buttonY = ((bounds.height - size) / 2).rounded()
    var x = Self.horizontalPadding
    for (button, _, _, _) in buttons {
      button.frame = NSRect(x: x, y: buttonY, width: size, height: size)
      x += size
    }
    x += Self.horizontalPadding
    let barHeight = Self.urlBarHeight
    urlBar.frame = NSRect(x: x, y: ((bounds.height - barHeight) / 2).rounded(),
                          width: max(0, bounds.width - x - Self.horizontalPadding), height: barHeight)
    let hairline = 1 / (window?.backingScaleFactor ?? 2)
    divider.frame = CGRect(x: 0, y: bounds.height - hairline, width: bounds.width, height: hairline)
    CATransaction.commit()
  }
}
