import AppKit

/// One Space page: the Space title (12 pt secondary at x 16) above the scrolling pinned + Today outline.
@MainActor
public final class SpacePageView: NSView {
  public let spaceID: SpaceID
  public let titleLabel = NSTextField(labelWithString: "")
  public let scrollView = SidebarScrollView(frame: .zero)
  public let outlineController: SidebarOutlineController

  public init(source: any SidebarSource, spaceID: SpaceID) {
    self.spaceID = spaceID
    self.outlineController = SidebarOutlineController(source: source, spaceID: spaceID)
    super.init(frame: .zero)
    let info = source.space(spaceID)
    titleLabel.stringValue = info?.title ?? ""
    titleLabel.font = .systemFont(ofSize: SidebarMetrics.spaceTitleFontSize, weight: .medium)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.autoresizingMask = []
    titleLabel.setAccessibilityIdentifierWithCell(AXID.Sidebar.spaceTitle)
    scrollView.autoresizingMask = []
    scrollView.documentView = outlineController.outlineView
    addSubview(titleLabel)
    addSubview(scrollView)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Sidebar.page)
    setAccessibilityLabel(titleLabel.stringValue)
    setFlavor(info?.theme.flavor ?? .light)
  }

  /// Applies the Space's current title and flavor after a Space change; unchanged fields cost nothing.
  public func refresh(from info: SidebarSpaceInfo?) {
    let title = info?.title ?? ""
    if titleLabel.stringValue != title {
      titleLabel.stringValue = title
      setAccessibilityLabel(title)
      needsLayout = true
    }
    let flavor = info?.theme.flavor ?? .light
    if flavor != self.flavor { setFlavor(flavor) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  public var outlineView: SidebarOutlineView { outlineController.outlineView }

  public private(set) var flavor: ThemeFlavor = .light

  /// Pages keep their own Space's flavor (and appearance, for the scroller) while they slide past.
  public func setFlavor(_ flavor: ThemeFlavor) {
    self.flavor = flavor
    appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    titleLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    outlineController.setFlavor(flavor)
  }

  /// Glyph bitmaps are per backing scale; re-render the realized rows when the window's scale changes.
  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    outlineController.refreshRealizedCells()
  }

  public override func layout() {
    super.layout()
    let padding = SidebarMetrics.horizontalPadding
    let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
    let titleX = SidebarMetrics.spaceTitleLeading
    titleLabel.frame = NSRect(x: titleX, y: ((SidebarMetrics.spaceTitleHeight - titleHeight) / 2).rounded(),
                              width: max(0, bounds.width - titleX - padding), height: titleHeight)
    let scrollFrame = NSRect(x: padding, y: SidebarMetrics.spaceTitleHeight,
                             width: max(0, bounds.width - 2 * padding),
                             height: max(0, bounds.height - SidebarMetrics.spaceTitleHeight))
    if scrollView.frame != scrollFrame {
      scrollView.frame = scrollFrame
      outlineView.sizeLastColumnToFit()
    }
  }
}
