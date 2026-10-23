import AppKit

/// Space indicator dots in the bottom bar. The fill follows the pager's continuous position, so the
/// active dot hands over during a swipe (BH-040). Each dot is an accessibility button named after its
/// Space; pressing it (or clicking) selects that Space.
@MainActor
public final class SpaceDotsView: NSView {
  /// Space titles, in order; one dot each.
  public var titles: [String] = [] {
    didSet {
      if titles.count != oldValue.count { rebuild() }
      for (element, title) in zip(elements, titles) { element.setAccessibilityLabel(title) }
    }
  }
  public var count: Int { titles.count }
  /// The committed Space. Setting it also moves `position` there.
  public var selectedIndex = 0 {
    didSet {
      position = CGFloat(selectedIndex)
      for (i, element) in elements.enumerated() { element.setAccessibilitySelected(i == selectedIndex) }
      if selectedIndex != oldValue { NSAccessibility.post(element: self, notification: .selectedChildrenChanged) }
    }
  }
  /// Continuous pager position (1.5 = halfway between dots 1 and 2).
  public var position: CGFloat = 0 { didSet { if position != oldValue { applyColors() } } }
  public var flavor: ThemeFlavor = .light { didSet { if flavor != oldValue { applyColors(force: true) } } }
  public var onSelect: (@MainActor (Int) -> Void)?
  private var dots: [CALayer] = []
  private var elements: [SpaceDotElement] = []
  /// Fill weight each dot was last painted with (a swipe repaints only the dots whose weight changes).
  private var paintedWeights: [Double] = []

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Spaces")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var wantsUpdateLayer: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }

  private var pitch: CGFloat { SidebarMetrics.spaceDotSize + SidebarMetrics.spaceDotSpacing }
  public var contentWidth: CGFloat { count == 0 ? 0 : CGFloat(count) * pitch - SidebarMetrics.spaceDotSpacing }
  private var originX: CGFloat { ((bounds.width - contentWidth) / 2).rounded() }

  private func rebuild() {
    dots.forEach { $0.removeFromSuperlayer() }
    dots = (0..<count).map { _ in CALayer() }
    dots.forEach { layer?.addSublayer($0) }
    paintedWeights = []
    elements = (0..<count).map { index in
      let element = SpaceDotElement { [weak self] in self?.onSelect?(index) }
      element.setAccessibilityParent(self)
      element.setAccessibilityRole(.button)
      element.setAccessibilitySelected(index == selectedIndex)
      return element
    }
    needsDisplay = true
  }

  /// Frame of dot `index` in this view (the full pitch, so the hit target is wider than the dot).
  func dotFrame(_ index: Int) -> NSRect {
    NSRect(x: originX + CGFloat(index) * pitch - SidebarMetrics.spaceDotSpacing / 2, y: 0,
           width: pitch, height: bounds.height)
  }

  public override func updateLayer() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let size = SidebarMetrics.spaceDotSize
    for (index, dot) in dots.enumerated() {
      dot.frame = CGRect(x: originX + CGFloat(index) * pitch, y: ((bounds.height - size) / 2).rounded(),
                         width: size, height: size)
      dot.cornerRadius = size / 2
    }
    for (index, element) in elements.enumerated() { element.setAccessibilityFrameInParentSpace(dotFrame(index)) }
    CATransaction.commit()
    applyColors(force: true)
  }

  /// Weight 1 at the dot under `position`, falling to 0 one dot away.
  func fillWeight(_ index: Int) -> Double { Double(max(0, 1 - abs(position - CGFloat(index)))) }

  private func applyColors(force: Bool = false) {
    if force || paintedWeights.count != dots.count { paintedWeights = Array(repeating: -1, count: dots.count) }
    let idle = ShellTokens.sidebarForeground.resolve(flavor)
    let active = ShellTokens.primaryText.resolve(flavor)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, dot) in dots.enumerated() {
      let weight = fillWeight(index)
      guard weight != paintedWeights[index] else { continue }
      paintedWeights[index] = weight
      repaintCountForTesting += 1
      dot.backgroundColor = RGBA.mix(idle, active, weight).cgColor
    }
    CATransaction.commit()
  }

  /// Number of dot fills set so far (for tests).
  private(set) var repaintCountForTesting = 0

  public override func layout() {
    super.layout()
    needsDisplay = true
  }

  public override func accessibilityChildren() -> [Any]? { elements }

  public override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let index = (0..<count).first(where: { dotFrame($0).contains(point) }) { onSelect?(index) }
  }
}

/// One dot as an accessibility button.
final class SpaceDotElement: NSAccessibilityElement {
  /// Immutable and `Sendable`, so a press arriving off the main thread can read it safely.
  private let onPress: @MainActor @Sendable () -> Void

  init(onPress: @escaping @MainActor @Sendable () -> Void) {
    self.onPress = onPress
    super.init()
  }

  /// Runs the press on the main queue (accessibility clients may call from elsewhere).
  override func accessibilityPerformPress() -> Bool {
    let press = onPress
    DispatchQueue.main.async { press() }
    return true
  }
}

/// The sidebar column (flipped): traffic-light strip, favorites grid, one Space page, bottom bar.
/// All frames are set in `layout()`. Empty areas drag the window: a `WindowDragView` fills the back.
@MainActor
public final class SidebarContainerView: NSView {
  private let dragSurface = WindowDragView(frame: .zero)
  /// Reserved for the traffic lights (and later back / forward / reload).
  public let topBar: NSView = WindowDragView(frame: .zero)
  public let favorites: FavoritesGridView
  /// Every Space page of this profile side by side; swipes and Space switches move it.
  public let pager = SpacePagerView(frame: .zero)
  /// The pager (C3 name).
  public var pagesHost: NSView { pager }
  public let bottomBar: NSView = WindowDragView(frame: .zero)
  public let archiveButton = NSButton(frame: .zero)
  public let newTabButton = NSButton(frame: .zero)
  public let spaceDots = SpaceDotsView(frame: .zero)
  public let topBarHeight: CGFloat

  public private(set) var currentPage: SpacePageView?
  public var currentOutline: SidebarOutlineView? { currentPage?.outlineView }

  public init(source: any SidebarSource, profile: String = "default",
              topBarHeight: CGFloat = ShellMetrics.standard.sidebarTopBarHeight) {
    self.favorites = FavoritesGridView(source: source, profile: profile)
    self.topBarHeight = topBarHeight
    super.init(frame: NSRect(x: 0, y: 0, width: ShellMetrics.standard.sidebarDefaultWidth, height: 800))
    for (button, symbol, label) in Self.bottomButtons(archiveButton, newTabButton) {
      button.image = SymbolImageCache.shared.symbol(
        symbol, box: SidebarMetrics.bottomBarIconSize, color: ShellTokens.sidebarForeground.resolve(flavor),
        scale: shellBackingScale)
      button.isBordered = false
      button.bezelStyle = .regularSquare
      button.imagePosition = .imageOnly
      button.setAccessibilityLabel(label)
      button.autoresizingMask = []
      bottomBar.addSubview(button)
    }
    spaceDots.autoresizingMask = []
    bottomBar.addSubview(spaceDots)
    for view in [dragSurface, topBar, favorites, pager, bottomBar] {
      view.autoresizingMask = []
      addSubview(view)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { true }

  /// Puts `pages` into the pager (showing `index` without animating) and routes their horizontal swipes to it.
  public func setPages(_ pages: [SpacePageView], index: Int) {
    for page in pages { page.scrollView.horizontalGestureTarget = pager }
    pager.setPages(pages, index: index)
  }

  /// Marks the committed Space's page (what `currentOutline` reads).
  public func setCurrent(page: SpacePageView?) { currentPage = page }

  /// Flavor of the chrome around the pages (favorites, dots, buttons). Each page keeps its own Space's flavor.
  public private(set) var flavor: ThemeFlavor = .light

  private var appliedFlavor: ThemeFlavor?

  /// No-op when `flavor` is already applied: a new appearance invalidates every descendant's drawing.
  public func setFlavor(_ flavor: ThemeFlavor) {
    guard flavor != appliedFlavor else { return }
    appliedFlavor = flavor
    self.flavor = flavor
    appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    favorites.flavor = flavor
    spaceDots.flavor = flavor
    applyButtonImages()
  }

  private static func bottomButtons(_ archive: NSButton, _ newTab: NSButton) -> [(NSButton, String, String)] {
    [(archive, "archivebox", "Archive"), (newTab, "plus", "New Tab")]
  }

  /// Bottom-bar symbols as cached bitmaps in the chrome flavor's foreground (no template tinting).
  private func applyButtonImages() {
    let color = ShellTokens.sidebarForeground.resolve(flavor)
    for (button, symbol, _) in Self.bottomButtons(archiveButton, newTabButton) {
      button.image = SymbolImageCache.shared.symbol(symbol, box: SidebarMetrics.bottomBarIconSize, color: color,
                                                    scale: shellBackingScale)
    }
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    applyButtonImages()
  }

  public override func layout() {
    super.layout()
    let width = bounds.width
    let padding = SidebarMetrics.horizontalPadding
    let bottomHeight = SidebarMetrics.bottomBarHeight
    dragSurface.frame = bounds
    topBar.frame = NSRect(x: 0, y: 0, width: width, height: topBarHeight)
    let favoritesHeight = favorites.preferredHeight
    let favoritesY = topBarHeight + SidebarMetrics.favoritesTopGap
    favorites.frame = NSRect(x: padding, y: favoritesY,
                             width: FavoritesLayout.contentWidth(sidebarWidth: width), height: favoritesHeight)
    let pagesY = favoritesY + favoritesHeight + (favoritesHeight > 0 ? SidebarMetrics.favoritesBottomGap : 0)
    let pagerFrame = NSRect(x: 0, y: pagesY, width: width, height: max(0, bounds.height - pagesY - bottomHeight))
    if pager.frame != pagerFrame { pager.frame = pagerFrame }
    bottomBar.frame = NSRect(x: 0, y: max(pagesY, bounds.height - bottomHeight), width: width, height: bottomHeight)
    let buttonSize: CGFloat = 28                                   // TODO(measure)
    let buttonY = ((bottomHeight - buttonSize) / 2).rounded()
    archiveButton.frame = NSRect(x: padding, y: buttonY, width: buttonSize, height: buttonSize)
    newTabButton.frame = NSRect(x: width - padding - buttonSize, y: buttonY, width: buttonSize, height: buttonSize)
    let dotsX = archiveButton.frame.maxX
    spaceDots.frame = NSRect(x: dotsX, y: 0, width: max(0, newTabButton.frame.minX - dotsX), height: bottomHeight)
  }
}
