import AppKit

/// Space indicator dots in the bottom bar. The fill follows the pager's continuous position, so the
/// active dot hands over during a swipe (BH-040). Each dot is an accessibility button named after its
/// Space; pressing it (or clicking) selects that Space.
///
/// When the dots do not fit between the archive and new-tab buttons (#193), they sit on a clipped strip that
/// scrolls with the trackpad or scroll wheel (no visible scroller), fades at the edges with hidden dots, and
/// follows the current Space (and the Space nearest the fingers during a swipe). Scrolling moves one layer and
/// re-sets the accessibility frames; it never relayouts or redraws the dock.
@MainActor
public final class SpaceDotsView: NSView {
  /// Space titles, in order; one dot each.
  public var titles: [String] = [] {
    didSet {
      if titles.count != oldValue.count { rebuild() }
      for (element, title) in zip(elements, titles) { element.setAccessibilityLabel(title) }
    }
  }
  /// Icon per Space, parallel to `titles` (BH-034). Nil, or a symbol name AppKit does not know, keeps the dot.
  public var icons: [SpaceIconInfo?] = [] {
    didSet {
      guard icons != oldValue else { return }
      resolveMarks()
      applyColors()
    }
  }
  public var count: Int { titles.count }
  /// The committed Space. Setting it also moves `position` there.
  public var selectedIndex = 0 {
    didSet {
      position = CGFloat(selectedIndex)
      for (i, element) in elements.enumerated() { element.setAccessibilitySelected(i == selectedIndex) }
      if selectedIndex != oldValue { NSAccessibility.post(element: self, notification: .selectedChildrenChanged) }
      reveal(selectedIndex)
    }
  }
  /// Continuous pager position (1.5 = halfway between dots 1 and 2).
  public var position: CGFloat = 0 {
    didSet {
      guard position != oldValue else { return }
      applyColors()
      reveal(Int(position.rounded()))
    }
  }
  public var flavor: ThemeFlavor = .light { didSet { if flavor != oldValue { applyColors(force: true) } } }
  public var onSelect: (@MainActor (Int) -> Void)?
  /// How far the dot strip is scrolled (0 when the dots fit).
  public private(set) var scrollOffset: CGFloat = 0
  private var dots: [CALayer] = []
  private var elements: [SpaceDotElement] = []
  /// Fill weight each dot was last painted with (a swipe repaints only the dots whose weight changes).
  private var paintedWeights: [Double] = []
  /// What each slot shows, resolved once per `icons` change (an unknown symbol is a dot), never per frame.
  private var marks: [DockMark] = []
  /// Mark each layer was last given an image for; nil before the first paint. A swipe frame never re-sets an image.
  private var paintedMarks: [DockMark?] = []
  /// Backing scale the images were made for; a change re-sets them.
  private var paintedScale: CGFloat = 0
  /// Icon bitmaps per (mark, scale). Symbols are alpha masks, so one bitmap serves both flavors.
  private var iconImages: [IconImageKey: CGImage] = [:]
  /// Clips the strip to the dock; its mask fades the edges past which dots are hidden.
  private let clipLayer = CALayer()
  private let fadeMask = CAGradientLayer()
  /// Holds the dots; scrolling moves only this layer.
  private let stripLayer = CALayer()
  /// Layout the strip was last placed for; a change re-reveals the current dot.
  private var placedLayout: SpaceDockLayout?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Spaces")
    setAccessibilityIdentifier(AXID.Sidebar.spaceDots)
    clipLayer.masksToBounds = true
    clipLayer.addSublayer(stripLayer)
    fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
    fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
    clipLayer.mask = fadeMask
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }
  public override var wantsUpdateLayer: Bool { true }
  public override var mouseDownCanMoveWindow: Bool { false }

  private var dockLayout: SpaceDockLayout {
    SpaceDockLayout(count: count, width: bounds.width, scale: shellBackingScale)
  }
  public var contentWidth: CGFloat { dockLayout.contentWidth }

  private func rebuild() {
    dots.forEach { $0.removeFromSuperlayer() }
    dots = (0..<count).map { _ in CALayer() }
    dots.forEach { stripLayer.addSublayer($0) }
    paintedWeights = []
    paintedMarks = []
    resolveMarks()
    elements = (0..<count).map { index in
      let element = SpaceDotElement { [weak self] in self?.onSelect?(index) }
      element.setAccessibilityParent(self)
      element.setAccessibilityRole(.button)
      element.setAccessibilityIdentifier(AXID.Sidebar.spaceDot)
      element.setAccessibilitySelected(index == selectedIndex)
      return element
    }
    needsDisplay = true
  }

  /// Frame of dot `index` in this view (the full pitch, so the hit target is wider than the dot). Dots scrolled
  /// out of the dock have frames outside `bounds`.
  func dotFrame(_ index: Int) -> NSRect {
    NSRect(x: dockLayout.hitMinX(index, offset: scrollOffset), y: 0, width: dockLayout.pitch, height: bounds.height)
  }

  public override func updateLayer() {
    guard let layer else { return }
    if clipLayer.superlayer !== layer { layer.addSublayer(clipLayer) }
    let layout = dockLayout
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    clipLayer.frame = layer.bounds
    fadeMask.frame = clipLayer.bounds
    if layout != placedLayout {
      placedLayout = layout
      scrollOffset = layout.offsetRevealing(Int(position.rounded()), from: scrollOffset)
    }
    placeStrip(layout)
    CATransaction.commit()
    applyColors(force: true)
  }

  /// Scrolls just enough to show dot `index`. Cheap enough for every swipe frame: no layout, no redraw.
  private func reveal(_ index: Int) {
    let layout = dockLayout
    guard layout.width > 0, layout == placedLayout else { return }
    setScrollOffset(layout.offsetRevealing(index, from: scrollOffset))
  }

  private func setScrollOffset(_ offset: CGFloat) {
    let layout = dockLayout
    let clamped = layout.clamp(offset)
    guard clamped != scrollOffset else { return }
    scrollOffset = clamped
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    placeStrip(layout)
    CATransaction.commit()
  }

  /// Moves the strip to `scrollOffset`, updates the fades and clips each dot's accessibility frame to the dock.
  private func placeStrip(_ layout: SpaceDockLayout) {
    scrollOffset = layout.clamp(scrollOffset)
    stripLayer.frame = CGRect(x: layout.stripMinX(offset: scrollOffset), y: 0,
                              width: layout.stripWidth, height: bounds.height)
    let fades = layout.fades(offset: scrollOffset)
    let edge = layout.width > 0 ? Double(min(layout.fadeWidth / layout.width, 0.5)) : 0
    let opaque = CGColor(gray: 0, alpha: 1)
    let clear = CGColor(gray: 0, alpha: 0)
    fadeMask.colors = [fades.leading ? clear : opaque, opaque, opaque, fades.trailing ? clear : opaque]
    fadeMask.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
    for (index, element) in elements.enumerated() {
      element.setAccessibilityFrameInParentSpace(visibleFrame(index))
    }
  }

  /// `dotFrame(index)` clipped to the dock. A dot scrolled out gets a 1 pt sliver at the edge it left by: it stays
  /// in the accessibility tree (pressing it selects its Space, which scrolls it into view), and an empty frame
  /// would be reported as the screen origin.
  private func visibleFrame(_ index: Int) -> NSRect {
    let frame = dotFrame(index)
    let visible = frame.intersection(bounds)
    if !visible.isNull, visible.width >= 1 { return visible }
    let sliver = min(1, bounds.width)
    let x = frame.midX <= bounds.midX ? bounds.minX : bounds.maxX - sliver
    return NSRect(x: x, y: 0, width: sliver, height: bounds.height)
  }

  /// Weight 1 at the dot under `position`, falling to 0 one dot away.
  func fillWeight(_ index: Int) -> Double { Double(max(0, 1 - abs(position - CGFloat(index)))) }

  /// Paints the dots for the current `position`. A swipe frame (not `force`, marks unchanged) only sets each changed
  /// dot's fill or opacity: no frame, no image, no rasterization. `force` (layout, flavor, scale) also re-places
  /// every layer; images are re-set only when a mark or the backing scale changed.
  private func applyColors(force: Bool = false) {
    let scale = shellBackingScale
    if paintedWeights.count != dots.count || paintedScale != scale {
      paintedWeights = Array(repeating: -1, count: dots.count)
      paintedMarks = Array(repeating: nil, count: dots.count)
      paintedScale = scale
    } else if force {
      paintedWeights = Array(repeating: -1, count: dots.count)
    }
    if marks.count != dots.count { resolveMarks() }
    let idle = ShellTokens.sidebarForeground.resolve(flavor)
    let active = ShellTokens.primaryText.resolve(flavor)
    let layout = dockLayout
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (index, dot) in dots.enumerated() {
      let mark = marks[index]
      let markChanged = paintedMarks[index] != mark
      if force || markChanged { place(dot, index: index, mark: mark, layout: layout) }
      if markChanged {
        paint(dot, mark: mark, scale: scale)
        paintedMarks[index] = mark
      }
      let weight = fillWeight(index)
      guard markChanged || weight != paintedWeights[index] else { continue }
      paintedWeights[index] = weight
      repaintCountForTesting += 1
      switch mark {
      case .dot, .symbol:
        // A symbol is the dot's fill seen through the symbol's mask: the same contrast-tuned tokens (#72).
        dot.backgroundColor = RGBA.mix(idle, active, weight).cgColor
      case .emoji:
        dot.opacity = SpaceDockIconPaint.emojiOpacity(weight, flavor: flavor)
      }
    }
    CATransaction.commit()
  }

  /// What slot `index` shows. `NSImage(systemSymbolName:)` runs here, once per `icons` change.
  private func resolveMarks() {
    marks = (0..<count).map { (index: Int) -> DockMark in
      switch index < icons.count ? icons[index] : nil {
      case nil: .dot
      case .symbol(let name)?:
        NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? .dot : .symbol(name)
      case .emoji(let emoji)?: .emoji(emoji)
      }
    }
  }

  /// The dot is `spaceDotSize` round; an icon is a `spaceIconSize` square on the same center, so the pitch holds.
  private func place(_ dot: CALayer, index: Int, mark: DockMark, layout: SpaceDockLayout) {
    let dotSize = SidebarMetrics.spaceDotSize
    let side = mark == .dot ? dotSize : SidebarMetrics.spaceIconSize
    let center = layout.stripDotMinX(index) + dotSize / 2
    let frame = CGRect(x: center - side / 2, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
    if dot.frame != frame { dot.frame = frame }
    dot.mask?.frame = dot.bounds
  }

  /// Gives the layer its image for `mark`, from `iconImages`. Runs only when the mark or the scale changes.
  private func paint(_ dot: CALayer, mark: DockMark, scale: CGFloat) {
    switch mark {
    case .dot:
      dot.contents = nil
      dot.mask = nil
      dot.opacity = 1
      dot.cornerRadius = SidebarMetrics.spaceDotSize / 2
    case .symbol:
      let mask = CALayer()
      mask.frame = dot.bounds
      mask.contents = iconImage(mark, scale: scale)
      mask.contentsScale = scale
      mask.contentsGravity = .resizeAspect
      dot.contents = nil
      dot.mask = mask
      dot.opacity = 1
      dot.cornerRadius = 0
      iconPaintCountForTesting += 1
    case .emoji:
      dot.contents = iconImage(mark, scale: scale)
      dot.contentsScale = scale
      dot.contentsGravity = .resizeAspect
      dot.mask = nil
      dot.backgroundColor = nil
      dot.cornerRadius = 0
      iconPaintCountForTesting += 1
    }
  }

  /// One bitmap per (mark, scale), rasterized on first use and then reused by every paint, swipe and window.
  private func iconImage(_ mark: DockMark, scale: CGFloat) -> CGImage? {
    let key = IconImageKey(mark: mark, scale: scale)
    if let image = iconImages[key] { return image }
    let box = SidebarMetrics.spaceIconSize
    let image: NSImage
    switch mark {
    case .dot: return nil
    case .symbol(let name):
      // Opaque black: only the alpha matters to a mask.
      image = SymbolImageCache.shared.symbol(name, box: box, weight: .medium, color: .black(1), scale: scale)
    case .emoji(let emoji):
      image = SymbolImageCache.shared.bitmap(key: "space-emoji:\(emoji)", size: box, scale: scale) { rect in
        let text = NSAttributedString(
          string: emoji, attributes: [.font: NSFont.systemFont(ofSize: SidebarMetrics.spaceEmojiFontSize)])
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
      }
    }
    var rect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    iconRasterCountForTesting += 1
    iconImages[key] = cgImage
    return cgImage
  }

  enum DockMark: Hashable {
    case dot
    /// Drawn as the layer's mask over the dot's fill.
    case symbol(String)
    /// Drawn as the layer's contents, in its own colors.
    case emoji(String)
  }

  private struct IconImageKey: Hashable {
    var mark: DockMark
    var scale: CGFloat
  }

  struct SpaceDotMark {
    var mark: DockMark
    var width: CGFloat
    var opacity: Float
    /// The bitmap shown: the contents for an emoji, the mask for a symbol.
    var showsImage: Bool
    var fill: CGColor?
  }

  func markForTesting(_ index: Int) -> SpaceDotMark? {
    guard dots.indices.contains(index), marks.indices.contains(index) else { return nil }
    let dot = dots[index]
    return SpaceDotMark(mark: marks[index], width: dot.bounds.width, opacity: dot.opacity,
                        showsImage: dot.contents != nil || dot.mask?.contents != nil, fill: dot.backgroundColor)
  }

  /// Icon images set on a layer so far (for tests: a swipe frame sets none).
  private(set) var iconPaintCountForTesting = 0
  /// Icon bitmaps this view made (cache misses) so far (for tests: a swipe frame makes none).
  private(set) var iconRasterCountForTesting = 0

  /// Number of dot fills set so far (for tests).
  private(set) var repaintCountForTesting = 0

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    needsDisplay = true
  }

  public override func layout() {
    super.layout()
    needsDisplay = true
  }

  public override func accessibilityChildren() -> [Any]? { elements }

  public override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard bounds.contains(point) else { return }
    if let index = (0..<count).first(where: { dotFrame($0).contains(point) }) { onSelect?(index) }
  }

  /// Scrolls the strip when the dots overflow: trackpad deltas as they come, wheel lines one dot each. A vertical
  /// wheel scrolls sideways. When the dots fit, the event goes up the responder chain as before.
  public override func scrollWheel(with event: NSEvent) {
    let layout = dockLayout
    guard layout.maxOffset > 0 else { super.scrollWheel(with: event); return }
    let dx = event.scrollingDeltaX
    let dy = event.scrollingDeltaY
    var delta = abs(dx) >= abs(dy) ? dx : dy
    if !event.hasPreciseScrollingDeltas { delta *= layout.pitch }
    let next = scrollOffset - delta
    let ends = event.phase.contains(.ended) || event.phase.contains(.cancelled)
      || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
      || (event.phase == [] && event.momentumPhase == [])
    setScrollOffset(ends ? layout.align(next) : next)
  }
}

/// How an emoji icon follows the dock's fill weight. An emoji keeps its own colors, so the idle-to-active step is
/// opacity: idle draws at the idle dot's alpha relative to the active dot's (`sidebarForeground` over `primaryText`,
/// the contrast-tuned pair of #72), the same step a dot or a symbol takes. TODO(measure): Arc's idle emoji.
enum SpaceDockIconPaint {
  static func emojiOpacity(_ weight: Double, flavor: ThemeFlavor) -> Float {
    let idle = ShellTokens.sidebarForeground.resolve(flavor).alpha
    let active = ShellTokens.primaryText.resolve(flavor).alpha
    let rest = active > 0 ? min(idle / active, 1) : 1
    return Float(rest + (1 - rest) * min(max(weight, 0), 1))
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

/// The sidebar column (flipped): traffic-light strip, URL bar, favorites grid, one Space page, bottom bar.
/// All frames are set in `layout()`. Empty areas drag the window: a `WindowDragView` fills the back.
@MainActor
public final class SidebarContainerView: NSView {
  private let dragSurface = WindowDragView(frame: .zero)
  /// Reserved for the traffic lights. Back / forward / reload next to the traffic lights when the Toolbar is off could
  /// not be measured in the passive Toolbar-on pass (`docs/plans/2026-10-23-arc-measurements.md`, interaction checklist
  /// item 4) and are recorded as a parity gap (#81).
  public let topBar: NSView = WindowDragView(frame: .zero)
  /// The active tab's host under the traffic lights (BH-031, GS-042); the window controller binds it.
  public let urlBar = URLBarView(style: .host)
  /// False hides the URL bar and moves the favorites up under the traffic-light strip. Arc hides it while the
  /// Toolbar is on (Arc 1.168, see `docs/plans/2026-10-23-arc-measurements.md`); the window controller sets it.
  public var showsURLBar = true {
    didSet {
      guard showsURLBar != oldValue else { return }
      urlBar.isHidden = !showsURLBar
      needsLayout = true
    }
  }
  public let favorites: FavoritesGridView
  /// Every Space page of this profile side by side; swipes and Space switches move it.
  public let pager = SpacePagerView(frame: .zero)
  /// The pager (C3 name).
  public var pagesHost: NSView { pager }
  public let bottomBar: NSView = WindowDragView(frame: .zero)
  public let archiveButton = NSButton(frame: .zero)
  public let newTabButton = NSButton(frame: .zero)
  public let spaceDots = SpaceDotsView(frame: .zero)
  /// The Extensions control, left of New Tab; nil for an engine without extensions (week-3 Decision 10).
  public var extensionsButton: ExtensionsButton? {
    didSet {
      guard extensionsButton !== oldValue else { return }
      oldValue?.removeFromSuperview()
      if let extensionsButton { bottomBar.addSubview(extensionsButton) }
      applyButtonImages()
      needsLayout = true
    }
  }
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
    urlBar.setAccessibilityIdentifier(AXID.Sidebar.urlBar)
    newTabButton.setAccessibilityIdentifierWithCell(AXID.Sidebar.newTab)
    for view in [dragSurface, topBar, urlBar, favorites, pager, bottomBar] {
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
    for (pageIndex, page) in pages.enumerated() {
      page.scrollView.horizontalGestureTarget = pager
      page.setAccessibilitySelected(pageIndex == index)
    }
    pager.setPages(pages, index: index)
  }

  /// Marks the committed Space's page (what `currentOutline` reads).
  public func setCurrent(page: SpacePageView?) {
    currentPage?.setAccessibilitySelected(false)
    currentPage = page
    page?.setAccessibilitySelected(true)
  }

  // MARK: Non-key dimming (BH-025)

  /// The sidebar's content opacity while the window is not key (design 5, OQ8). The traffic lights are the
  /// system's and keep their look; the content card is not part of this view.
  public static let dimmedAlpha: CGFloat = 0.6

  /// Dims the URL bar, Favorites, the Space pages and the bottom bar at once, without animation (design 5 and 8).
  /// Purely visual: hit-testing and accessibility do not change.
  public var isDimmed = false {
    didSet {
      guard isDimmed != oldValue else { return }
      let alpha = isDimmed ? Self.dimmedAlpha : 1
      for view in [urlBar, favorites, pager, bottomBar] as [NSView] { view.alphaValue = alpha }
    }
  }

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
    urlBar.flavor = flavor
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
    extensionsButton?.image = SymbolImageCache.shared.symbol(
      ExtensionsButton.symbolName, box: SidebarMetrics.bottomBarIconSize, color: color, scale: shellBackingScale)
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
    urlBar.frame = NSRect(x: padding, y: topBarHeight + SidebarMetrics.urlBarTopGap,
                          width: max(0, width - 2 * padding), height: SidebarMetrics.urlBarHeight)
    let favoritesHeight = favorites.preferredHeight
    let favoritesY = (showsURLBar ? urlBar.frame.maxY : topBarHeight) + SidebarMetrics.favoritesTopGap
    favorites.frame = NSRect(x: padding, y: favoritesY,
                             width: FavoritesLayout.contentWidth(sidebarWidth: width), height: favoritesHeight)
    let pagesY = favoritesY + favoritesHeight + (favoritesHeight > 0 ? SidebarMetrics.favoritesBottomGap : 0)
    let pagerFrame = NSRect(x: 0, y: pagesY, width: width, height: max(0, bounds.height - pagesY - bottomHeight))
    if pager.frame != pagerFrame { pager.frame = pagerFrame }
    bottomBar.frame = NSRect(x: 0, y: max(pagesY, bounds.height - bottomHeight), width: width, height: bottomHeight)
    let buttonSize = SidebarMetrics.bottomBarButtonSize
    let buttonY = ((bottomHeight - buttonSize) / 2).rounded()
    archiveButton.frame = NSRect(x: padding, y: buttonY, width: buttonSize, height: buttonSize)
    newTabButton.frame = NSRect(x: width - padding - buttonSize, y: buttonY, width: buttonSize, height: buttonSize)
    var trailing = newTabButton.frame.minX
    if let extensionsButton {
      extensionsButton.frame = NSRect(x: trailing - buttonSize, y: buttonY, width: buttonSize, height: buttonSize)
      trailing = extensionsButton.frame.minX
    }
    let dotsX = archiveButton.frame.maxX
    spaceDots.frame = NSRect(x: dotsX, y: 0, width: max(0, trailing - dotsX), height: bottomHeight)
  }

  /// Trackpad swipes starting over the Favorites grid, bottom bar, or other sidebar chrome outside the outline page
  /// the Spaces (#98, M1, GS-001).
  public override func scrollWheel(with event: NSEvent) {
    guard event.phase != [] || event.momentumPhase != [] else {
      super.scrollWheel(with: event)
      return
    }
    pager.scrollWheel(with: event)
  }
}
