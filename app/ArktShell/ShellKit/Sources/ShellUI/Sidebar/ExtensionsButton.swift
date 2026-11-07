import AppKit

/// The Extensions control in the sidebar's bottom bar, shown only for an engine that runs extensions
/// (`EngineExtensions`; week-3 Decision 10). A click opens and closes the Extensions panel
/// (`ExtensionsPanelController`, design/extensions direction C), which also shows the empty state, so the button is
/// always enabled. While the panel is up the button keeps a round `sidebarItemHovered` fill.
@MainActor
public final class ExtensionsButton: NSButton {
  static let symbolName = "puzzlepiece.extension"
  private let fill = CALayer()

  /// The panel is open.
  public var isOpen = false {
    didSet {
      guard isOpen != oldValue else { return }
      restyleFill()
    }
  }

  public init() {
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    autoresizingMask = []
    toolTip = "Extensions"   // [I] product wording
    wantsLayer = true
    layer?.addSublayer(fill)
    setAccessibilityLabel("Extensions")
    setAccessibilityIdentifierWithCell(AXID.Sidebar.extensions)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override func layout() {
    super.layout()
    ArchiveMotion.set {
      fill.frame = bounds
      fill.cornerRadius = bounds.height / 2
      fill.zPosition = -1
    }
  }

  public override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyleFill()
  }

  private func restyleFill() {
    let color = isOpen ? ShellTokens.sidebarItemHovered.resolve(archiveFlavor).cgColor : nil
    ArchiveMotion.set { fill.backgroundColor = color }
  }
}
