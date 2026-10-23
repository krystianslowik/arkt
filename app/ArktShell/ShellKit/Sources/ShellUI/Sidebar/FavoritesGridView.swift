import AppKit

/// One favorite tile: rounded fill (resting / hovered / current) with a centered 20 pt favicon, and the hover close
/// (X) in the top trailing corner while a loaded tile is hovered (#82). Frames set in `layout()`; no constraints.
@MainActor
public final class FavoriteTileView: NSView {
  public let faviconView = NSImageView()
  /// Shown while the tile is hovered and has a close action (its page is loaded). Target and action are set by the
  /// grid; hidden (so neither hit-tested nor in the accessibility tree) otherwise.
  public let closeButton = HoverCloseButton()
  public var flavor: ThemeFlavor = .light {
    didSet {
      guard flavor != oldValue else { return }
      needsDisplay = true
      closeButton.image = SidebarGlyphs.close(flavor: flavor, scale: shellBackingScale)
    }
  }
  public var isCurrent = false { didSet { if isCurrent != oldValue { needsDisplay = true } } }
  /// Also shows or hides the X, fading with the fill.
  public var isHovered = false {
    didSet {
      guard isHovered != oldValue else { return }
      needsDisplay = true
      setCloseButtonShown(isHovered, animated: true)
    }
  }
  /// The Favorite this tile shows; the grid sets it, the X reports it.
  public internal(set) var nodeID: NodeID?
  /// What the X does; nil (no loaded page) never shows it.
  public private(set) var closeAction: RowCloseAction?
  /// Whether the X is shown or fading in (the tile is hovered and there is a close action).
  public private(set) var isCloseButtonShown = false
  private var hoverArea: NSTrackingArea?

  /// The fill currently drawn. Exposed for tests.
  public var displayedFill: RGBA {
    if isCurrent { return ShellTokens.tabCurrent.resolve(flavor) }
    return (isHovered ? ShellTokens.sidebarItemHovered : ShellTokens.sidebarItemBackground).resolve(flavor)
  }

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    faviconView.autoresizingMask = []
    faviconView.setAccessibilityElement(false)
    addSubview(faviconView)
    addSubview(closeButton)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var wantsUpdateLayer: Bool { true }

  public override func updateLayer() {
    guard let layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.cornerRadius = FavoritesLayout.tileCornerRadius
    layer.cornerCurve = .continuous
    layer.backgroundColor = displayedFill.cgColor
    let shadow = ShellTokens.tabCurrentShadow.resolve(flavor)
    layer.shadowColor = shadow.cgColor
    layer.shadowRadius = 2
    layer.shadowOffset = CGSize(width: 0, height: -1)
    layer.shadowOpacity = isCurrent && shadow.alpha > 0 ? 1 : 0
    layer.shadowPath = CGPath(roundedRect: layer.bounds, cornerWidth: FavoritesLayout.tileCornerRadius,
                              cornerHeight: FavoritesLayout.tileCornerRadius, transform: nil)
    CATransaction.commit()
  }

  public override func layout() {
    super.layout()
    needsDisplay = true                                 // shadowPath follows the bounds
    let size = SidebarMetrics.favoriteFaviconSize
    faviconView.frame = NSRect(x: ((bounds.width - size) / 2).rounded(), y: ((bounds.height - size) / 2).rounded(),
                               width: size, height: size)
    let box = SidebarMetrics.favoriteCloseButtonSize
    let inset = SidebarMetrics.favoriteCloseButtonInset
    closeButton.frame = NSRect(x: bounds.width - inset - box, y: bounds.height - inset - box, width: box, height: box)
  }

  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    closeButton.image = SidebarGlyphs.close(flavor: flavor, scale: shellBackingScale)
  }

  /// Sets what the X does (nil: nothing to close) and its tooltip. A tile that gains or loses its action under the
  /// pointer shows or hides the X at once.
  func setCloseAction(_ action: RowCloseAction?) {
    if closeButton.image == nil { closeButton.image = SidebarGlyphs.close(flavor: flavor, scale: shellBackingScale) }
    closeAction = action
    closeButton.toolTip = action?.tooltip
    closeButton.setAccessibilityLabel(action?.tooltip)
    if (isHovered && action != nil) != isCloseButtonShown { setCloseButtonShown(isHovered, animated: false) }
  }

  /// Shows or hides the X (only when there is a close action), fading with the hover state. Only the button's
  /// opacity and hidden flag change; nothing is laid out.
  public func setCloseButtonShown(_ shown: Bool, animated: Bool) {
    let shown = shown && closeAction != nil
    guard shown != isCloseButtonShown || !animated else { return }   // unanimated calls always settle the state
    isCloseButtonShown = shown
    closeButton.setShown(shown, animated: animated)
  }

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    hoverArea = area
    setNeedsHoverResyncInHost()                     // a tile shifted or reused under a still pointer
  }

  /// Sets the hover state from a pointer location in window coordinates (nil: the pointer is not over this window).
  func syncHover(pointerInWindow point: NSPoint?) {
    guard let point else { isHovered = false; return }
    isHovered = bounds.contains(convert(point, from: nil))
  }

  /// Clears what belongs to the Favorite shown before (item reuse).
  public override func prepareForReuse() {
    super.prepareForReuse()
    isHovered = false
    isCurrent = false
    nodeID = nil
    setCloseAction(nil)
    setCloseButtonShown(false, animated: false)        // no fade on a reused tile
    setAccessibilityCustomActions([])
  }

  public override func mouseEntered(with event: NSEvent) { isHovered = true }
  public override func mouseExited(with event: NSEvent) { isHovered = false }
}

@MainActor
public final class FavoriteTileItem: NSCollectionViewItem {
  public static let reuseIdentifier = NSUserInterfaceItemIdentifier("FavoriteTileItem")
  public var tileView: FavoriteTileView { view as! FavoriteTileView }   // set in loadView

  public override func loadView() {
    view = FavoriteTileView(frame: NSRect(x: 0, y: 0, width: 52, height: FavoritesLayout.tileHeight))
  }

  public override func prepareForReuse() {
    super.prepareForReuse()
    tileView.prepareForReuse()
  }
}

/// Favorites grid: an NSCollectionView with a flow layout (3 columns, 9 pt gaps). Not inside a scrolling clip;
/// its height is `FavoritesLayout.height(itemCount:)`. Shared by every Space of the same profile (BH-045).
@MainActor
public final class FavoritesGridView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate, HoverResyncHost {
  public let source: any SidebarSource
  public let profile: String
  public let collectionView = NSCollectionView(frame: .zero)
  public private(set) var nodeIDs: [NodeID]
  public var flavor: ThemeFlavor = .light { didSet { if flavor != oldValue { refreshVisibleTiles() } } }
  public private(set) var resolver: TabRowState.Resolver = .empty

  public var onActivate: (@MainActor (NodeID) -> Void)?
  public var faviconProvider: (@MainActor (NodeID) -> NSImage?)?
  /// A tile's hover close (X) or its VoiceOver close action was used (#82); the window runs the same close as Cmd-W.
  public var onClose: (@MainActor (NodeID) -> Void)?
  /// Whether the Favorite's page is loaded in this window; only a loaded tile shows the X and the close action.
  public var pageLoadedProvider: (@MainActor (NodeID) -> Bool)?

  private let flowLayout = NSCollectionViewFlowLayout()
  private lazy var hoverResync = HoverResyncScheduler(view: self) { [unowned self] pointer in
    for case let item as FavoriteTileItem in collectionView.visibleItems() {
      item.tileView.syncHover(pointerInWindow: pointer)
    }
  }
  /// Where hover resyncs read the pointer; tests replace it.
  var hoverPointerLookup: HoverPointerLookup {
    get { hoverResync.lookup }
    set { hoverResync.lookup = newValue }
  }

  public init(source: any SidebarSource, profile: String) {
    self.source = source
    self.profile = profile
    self.nodeIDs = source.children(of: .favorites(profile: profile))
    super.init(frame: .zero)
    flowLayout.minimumInteritemSpacing = FavoritesLayout.gap
    flowLayout.minimumLineSpacing = FavoritesLayout.gap
    flowLayout.sectionInset = NSEdgeInsetsZero
    flowLayout.itemSize = FavoritesLayout.itemSize(
      contentWidth: FavoritesLayout.contentWidth(sidebarWidth: ShellMetrics.standard.sidebarDefaultWidth))
    collectionView.collectionViewLayout = flowLayout
    collectionView.register(FavoriteTileItem.self, forItemWithIdentifier: FavoriteTileItem.reuseIdentifier)
    collectionView.isSelectable = true
    collectionView.allowsMultipleSelection = false
    collectionView.backgroundColors = [.clear]
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.autoresizingMask = []
    addSubview(collectionView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  /// Height for the current item count.
  public var preferredHeight: CGFloat { FavoritesLayout.height(itemCount: nodeIDs.count) }

  /// Letter tiles are bitmaps per backing scale; re-render the visible tiles when the window's scale changes.
  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    refreshVisibleTiles()
  }

  public override func layout() {
    super.layout()
    var size = FavoritesLayout.itemSize(contentWidth: bounds.width)
    size.width = (size.width * 2).rounded(.down) / 2      // half-point floor so three tiles never wrap
    if flowLayout.itemSize != size {
      flowLayout.itemSize = size
      flowLayout.invalidateLayout()
    }
    collectionView.frame = bounds
  }

  // MARK: Hover

  func setNeedsHoverResync() { hoverResync.setNeeded() }

  /// Reads the pointer once and sets the hover state of every visible tile from it.
  func resyncHoverWithPointer() { hoverResync.resyncNow() }

  // MARK: Data source

  public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
    nodeIDs.count
  }

  public func collectionView(_ collectionView: NSCollectionView,
                             itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
    let item = collectionView.makeItem(withIdentifier: FavoriteTileItem.reuseIdentifier, for: indexPath)
    if let tile = item as? FavoriteTileItem { configure(tile, id: nodeIDs[indexPath.item]) }
    return item
  }

  private func configure(_ item: FavoriteTileItem, id: NodeID) {
    let tile = item.tileView
    tile.flavor = flavor
    tile.isCurrent = resolver.state(for: id) == .current
    var title = "", url: URL?
    if case .tab(_, let tabURL, let tabTitle)? = source.node(id) { title = tabTitle; url = tabURL }
    tile.faviconView.image = faviconProvider?(id)
      ?? SidebarGlyphs.letter(for: title, url: url, flavor: flavor, size: SidebarMetrics.favoriteFaviconSize,
                              scale: collectionView.shellBackingScale)
    tile.toolTip = title
    tile.setAccessibilityLabel(title)
    tile.nodeID = id
    let action = pageLoadedProvider?(id) == true ? RowCloseAction.resolve(id, in: source) : nil
    tile.closeButton.target = self
    tile.closeButton.action = #selector(closeClicked(_:))
    tile.setCloseAction(action)
    tile.setAccessibilityCustomActions(closeAccessibilityActions(for: id, action: action))
  }

  // MARK: Close

  /// The X of a tile; same close as the rows' X (`RowCloseAction.closeFavorite`).
  @objc private func closeClicked(_ sender: NSButton) {
    guard let id = (sender.superview as? FavoriteTileView)?.nodeID else { return }
    onClose?(id)
  }

  /// VoiceOver's "Close" on a loaded tile; none otherwise.
  private func closeAccessibilityActions(for id: NodeID, action: RowCloseAction?) -> [NSAccessibilityCustomAction] {
    guard let action else { return [] }
    return [NSAccessibilityCustomAction(name: action.accessibilityName) { [weak self] in
      guard let self, self.source.node(id) != nil else { return false }
      self.onClose?(id)
      return true
    }]
  }

  // MARK: Delegate

  public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
    collectionView.deselectItems(at: indexPaths)      // `current` is ours, not the collection view's selection
    guard let index = indexPaths.first?.item, nodeIDs.indices.contains(index) else { return }
    onActivate?(nodeIDs[index])
  }

  // MARK: State and changes

  public func setRowStates(_ resolver: TabRowState.Resolver) {
    self.resolver = resolver
    refreshVisibleTiles()
  }

  /// Tile currently showing `id`, if realized.
  public func tile(for id: NodeID) -> FavoriteTileView? {
    guard let index = nodeIDs.firstIndex(of: id) else { return nil }
    return (collectionView.item(at: IndexPath(item: index, section: 0)) as? FavoriteTileItem)?.tileView
  }

  private func refreshVisibleTiles() {
    for indexPath in collectionView.indexPathsForVisibleItems() where nodeIDs.indices.contains(indexPath.item) {
      if let item = collectionView.item(at: indexPath) as? FavoriteTileItem {
        configure(item, id: nodeIDs[indexPath.item])
      }
    }
  }

  /// Refreshes one tile (favicon, title or whether its page is loaded).
  public func reload(node id: NodeID) {
    guard let index = nodeIDs.firstIndex(of: id),
          let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? FavoriteTileItem else { return }
    configure(item, id: id)
  }

  /// Targeted update for a `.favorites` structure change. Returns true when the grid height changed.
  @discardableResult
  public func apply(structure location: SidebarLocation) -> Bool {
    guard location == .favorites(profile: profile) else { return false }
    let old = nodeIDs
    let new = source.children(of: location)
    nodeIDs = new
    let difference = new.difference(from: old)
    if difference.isEmpty { return false }
    collectionView.performBatchUpdates({
      var removed = Set<IndexPath>(), inserted = Set<IndexPath>()
      for change in difference {
        switch change {
        case .remove(let offset, _, _): removed.insert(IndexPath(item: offset, section: 0))
        case .insert(let offset, _, _): inserted.insert(IndexPath(item: offset, section: 0))
        }
      }
      if !removed.isEmpty { collectionView.deleteItems(at: removed) }
      if !inserted.isEmpty { collectionView.insertItems(at: inserted) }
    })
    return FavoritesLayout.height(itemCount: old.count) != FavoritesLayout.height(itemCount: new.count)
  }
}
