import AppKit

/// One favorite tile: rounded fill (resting / hovered / current) with a centered 20 pt favicon, and the hover close
/// (X) in the top trailing corner while a loaded tile is hovered (#82). Frames set in `layout()`; no constraints.
@MainActor
public final class FavoriteTileView: NSView {
  public let faviconView = NSImageView()
  /// Shown while the tile is hovered and has a close action (its page is loaded). Target and action are set by the
  /// grid; hidden (so neither hit-tested nor in the accessibility tree) otherwise.
  public let closeButton = HoverCloseButton()
  /// The Ctrl-Space cursor, in the same system color as outline-row focus (#343).
  let keyboardFocusRing = KeyboardFocusRingView(frame: .zero)
  var isKeyboardFocused = false {
    didSet {
      guard isKeyboardFocused != oldValue else { return }
      keyboardFocusRing.isHidden = !isKeyboardFocused
      keyboardFocusRing.needsDisplay = true
    }
  }
  public var flavor: ThemeFlavor = .light {
    didSet {
      guard flavor != oldValue else { return }
      needsDisplay = true
      closeButton.image = SidebarGlyphs.close(flavor: flavor, scale: shellBackingScale)
    }
  }
  public var isCurrent = false {
    didSet {
      guard isCurrent != oldValue else { return }
      needsDisplay = true
      applyFillOpacity()
    }
  }
  /// The selection fill's layer opacity (#465): Little Arkt's arrival fades it on the flight's room spring. Only
  /// the fill fades; the favicon stays, and the title is this view's accessibility label.
  public var selectionAlpha: CGFloat = 1 {
    didSet {
      guard selectionAlpha != oldValue else { return }
      applyFillOpacity()
    }
  }
  /// The rounded fill. Its opacity is the only thing the arrival fade changes.
  public let fillLayer = CALayer()
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
    fillLayer.cornerRadius = FavoritesLayout.tileCornerRadius
    fillLayer.cornerCurve = .continuous
    fillLayer.shadowRadius = 2
    fillLayer.shadowOffset = CGSize(width: 0, height: -1)
    faviconView.imageScaling = .scaleProportionallyUpOrDown
    faviconView.autoresizingMask = []
    faviconView.setAccessibilityElement(false)
    addSubview(faviconView)
    addSubview(closeButton)
    keyboardFocusRing.cornerRadius = FavoritesLayout.tileCornerRadius
    addSubview(keyboardFocusRing)
    closeButton.setAccessibilityIdentifierWithCell(AXID.Favorites.tileClose)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityIdentifier(AXID.Favorites.tile)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var wantsUpdateLayer: Bool { true }

  public override func updateLayer() {
    guard let layer else { return }
    if fillLayer.superlayer !== layer { layer.insertSublayer(fillLayer, at: 0) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.backgroundColor = nil
    layer.shadowOpacity = 0
    layer.shadowPath = nil
    fillLayer.frame = bounds
    fillLayer.cornerRadius = FavoritesLayout.tileCornerRadius
    fillLayer.cornerCurve = .continuous
    fillLayer.backgroundColor = displayedFill.cgColor
    let shadow = ShellTokens.tabCurrentShadow.resolve(flavor)
    fillLayer.shadowColor = shadow.cgColor
    fillLayer.shadowRadius = 2
    fillLayer.shadowOffset = CGSize(width: 0, height: -1)
    fillLayer.shadowOpacity = isCurrent && shadow.alpha > 0 ? 1 : 0
    updateFillShadowPath()
    fillLayer.opacity = Float(isCurrent ? selectionAlpha : 1)
    CATransaction.commit()
  }

  /// Only the fill fades. The favicon is a subview of this view, so it keeps the view's opacity.
  private func applyFillOpacity() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fillLayer.opacity = Float(isCurrent ? selectionAlpha : 1)
    CATransaction.commit()
  }

  /// Explicit path so Core Animation never derives the shadow from layer contents offscreen.
  private func updateFillShadowPath() {
    let radius = FavoritesLayout.tileCornerRadius
    fillLayer.shadowPath = CGPath(roundedRect: fillLayer.bounds, cornerWidth: radius, cornerHeight: radius,
                                  transform: nil)
  }

  public override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fillLayer.frame = bounds
    updateFillShadowPath()
    CATransaction.commit()
    let size = SidebarMetrics.favoriteFaviconSize
    faviconView.frame = NSRect(x: ((bounds.width - size) / 2).rounded(), y: ((bounds.height - size) / 2).rounded(),
                               width: size, height: size)
    let box = SidebarMetrics.favoriteCloseButtonSize
    let inset = SidebarMetrics.favoriteCloseButtonInset
    closeButton.frame = NSRect(x: bounds.width - inset - box, y: bounds.height - inset - box, width: box, height: box)
    keyboardFocusRing.frame = bounds
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
    selectionAlpha = 1
    isKeyboardFocused = false
    nodeID = nil
    setCloseAction(nil)
    setCloseButtonShown(false, animated: false)        // no fade on a reused tile
    setAccessibilityValue(nil)
    setAccessibilityCustomActions([])
  }

  public override func accessibilityParent() -> Any? {
    superview.flatMap(NSAccessibility.unignoredAncestor(of:))
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

@MainActor
final class FavoritesCollectionView: NSCollectionView {
  var onMouseDownBegan: (@MainActor () -> Void)?
  var onMouseDownEnded: (@MainActor (IndexPath?, NSPoint) -> Void)?
  var onMoveCommand: (@MainActor (_ deltaColumns: Int, _ deltaRows: Int) -> Void)?
  var onKeyboardReturn: (@MainActor () -> Void)?
  var onKeyboardEscape: (@MainActor () -> Void)?
  var onKeyboardFocusResigned: (@MainActor () -> Void)?
  /// The context menu of the tile at an index path (design 3.3); nil: none.
  var menuProvider: (@MainActor (IndexPath) -> NSMenu?)?

  /// A right-click or Ctrl-click on a tile opens that Favorite's menu; elsewhere in the grid there is none.
  override func menu(for event: NSEvent) -> NSMenu? {
    guard let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) else { return nil }
    return menuProvider?(indexPath)
  }

  override var acceptsFirstResponder: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) {
    let downIndexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil))
    onMouseDownBegan?()
    super.mouseDown(with: event)
    let endEvent = NSApp.currentEvent ?? event
    onMouseDownEnded?(downIndexPath, convert(endEvent.locationInWindow, from: nil))
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 123: moveLeft(self)
    case 124: moveRight(self)
    case 125: moveDown(self)
    case 126: moveUp(self)
    case 36, 76: onKeyboardReturn?()
    case 53: onKeyboardEscape?()
    default: super.keyDown(with: event)
    }
  }

  override func moveRight(_ sender: Any?) { onMoveCommand?(1, 0) }
  override func moveLeft(_ sender: Any?) { onMoveCommand?(-1, 0) }
  override func moveDown(_ sender: Any?) { onMoveCommand?(0, 1) }
  override func moveUp(_ sender: Any?) { onMoveCommand?(0, -1) }

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { onKeyboardFocusResigned?() }
    return resigned
  }

  /// Not an accessibility element: `NSCollectionView`, like `NSTableView`, answers its children out of process from
  /// its own internals rather than from overridden children, so `FavoritesGridView` (a plain view, whose overridden
  /// children AppKit does publish) lists the tiles itself and the tiles report the grid as their parent.
  override func isAccessibilityElement() -> Bool { false }

  /// The tile views of the items that exist, in item order. Reads only: never creates an item, reloads or lays out
  /// (doing so from an out-of-process client's accessibility callback re-enters layout while the client waits, and
  /// it times out). The grid keeps every Favorite realized once it has a size (`FavoritesGridView.layout`).
  func tileViews() -> [NSView] {
    guard numberOfSections > 0 else { return [] }
    return (0..<numberOfItems(inSection: 0)).compactMap { item(at: IndexPath(item: $0, section: 0))?.view }
  }
}

/// Places each Favorite at the frame the grid answers (`FavoritesLayout`, or the column spring's frame while it runs).
/// Every item is answered for any rect, so the grid keeps every Favorite realized (see `tileViews()`).
@MainActor
final class FavoritesCollectionLayout: NSCollectionViewLayout {
  /// The frame of an item for a content width.
  var frameProvider: (@MainActor (_ item: Int, _ contentWidth: CGFloat) -> CGRect)?
  private var attributes: [NSCollectionViewLayoutAttributes] = []
  private var contentSize: NSSize = .zero
  private var preparedWidth: CGFloat = 0

  override func prepare() {
    super.prepare()
    guard let collectionView, collectionView.numberOfSections > 0 else {
      attributes = []
      contentSize = .zero
      return
    }
    let width = collectionView.bounds.width
    preparedWidth = width
    attributes = (0..<collectionView.numberOfItems(inSection: 0)).map { item in
      let attribute = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: item, section: 0))
      attribute.frame = frameProvider?(item, width) ?? .zero
      return attribute
    }
    contentSize = NSSize(width: width, height: attributes.map(\.frame.maxY).max() ?? 0)
  }

  override var collectionViewContentSize: NSSize { contentSize }

  override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] { attributes }

  override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
    attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
  }

  override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
    newBounds.width != preparedWidth
  }
}

/// Favorites grid: an NSCollectionView placing 1 to 4 columns of tiles by width, rows filled evenly, 9 pt gaps
/// (#337). Not inside a scrolling clip; its height is `preferredHeight(contentWidth:)`. A sidebar resize that changes
/// the column count moves the tiles on a spring (`FavoritesColumnMotion`). Shared by every Space of the same profile
/// (BH-045).
@MainActor
public final class FavoritesGridView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate, HoverResyncHost {
  public let source: any SidebarSource
  public let profile: String
  public let collectionView: NSCollectionView = FavoritesCollectionView(frame: .zero)
  public private(set) var nodeIDs: [NodeID]
  public var flavor: ThemeFlavor = .light { didSet { if flavor != oldValue { refreshVisibleTiles() } } }
  public private(set) var resolver: TabRowState.Resolver = .empty
  /// The tile cursor after Ctrl-Space; moving it never activates a tab (#343).
  public internal(set) var keyboardFocusID: NodeID? {
    didSet {
      guard keyboardFocusID != oldValue else { return }
      if let keyboardFocusID { lastKeyboardFocusID = keyboardFocusID }
      updateKeyboardFocusRing()
    }
  }
  private var lastKeyboardFocusID: NodeID?

  public var onActivate: (@MainActor (NodeID) -> Void)?
  /// Return or Esc leaves keyboard navigation; Down below the last tile enters the outline.
  var onKeyboardFocusExit: (@MainActor () -> Void)?
  var onKeyboardFocusBelow: (@MainActor () -> Void)?
  /// Left / Right / vertical grid movement changed the destination VoiceOver should read (#343).
  var onKeyboardFocusMoved: (@MainActor (NodeID) -> Void)?
  public var faviconProvider: (@MainActor (NodeID) -> NSImage?)?
  /// A tile's hover close (X) or its VoiceOver close action was used (#82); the window runs the same close as Cmd-W.
  public var onClose: (@MainActor (NodeID) -> Void)?
  /// Whether the Favorite's page is loaded in this window; only a loaded tile shows the X and the close action.
  public var pageLoadedProvider: (@MainActor (NodeID) -> Bool)?
  /// A Favorite tile's context menu action (design 3.3); the window runs it.
  public var onMenuAction: (@MainActor (SidebarMenuAction) -> Void)?
  /// A Favorite tab tile started or ended a drag (#214, S7); the window shows and hides its drop overlay.
  public var onNodeDragBegan: (@MainActor (NodeID) -> Void)?
  public var onNodeDragEnded: (@MainActor () -> Void)?

  private var isTrackingMouse = false
  private var didDragInMouseDown = false
  private var isDragging = false

  private static var defaultContentWidth: CGFloat {
    FavoritesLayout.contentWidth(sidebarWidth: ShellMetrics.standard.sidebarDefaultWidth)
  }
  private let gridLayout = FavoritesCollectionLayout()
  /// The columns the tiles are in, or heading to while the column spring runs; the keyboard cursor follows it.
  public private(set) var columns: Int
  /// The content width `columns` was chosen for; nil until the grid first learns its width.
  private var columnsWidth: CGFloat?
  /// The spring of a width-driven column change; tests drive its clock.
  let columnMotion = FavoritesColumnMotion()
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
    let nodeIDs = source.children(of: .favorites(profile: profile))
    self.nodeIDs = nodeIDs
    self.columns = FavoritesLayout.columns(itemCount: nodeIDs.count, contentWidth: Self.defaultContentWidth)
    super.init(frame: .zero)
    gridLayout.frameProvider = { [weak self] item, contentWidth in
      self?.tileFrame(item, contentWidth: contentWidth) ?? .zero
    }
    collectionView.collectionViewLayout = gridLayout
    columnMotion.onFrame = { [weak self] in self?.columnMotionPresentedFrame() }
    collectionView.register(FavoriteTileItem.self, forItemWithIdentifier: FavoriteTileItem.reuseIdentifier)
    collectionView.isSelectable = true
    collectionView.allowsMultipleSelection = false
    collectionView.backgroundColors = [.clear]
    collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
    collectionView.setDraggingSourceOperationMask([], forLocal: false)
    if let favoritesCollectionView = collectionView as? FavoritesCollectionView {
      favoritesCollectionView.onMouseDownBegan = { [weak self] in
        self?.keyboardFocusID = nil
        self?.isTrackingMouse = true
        self?.didDragInMouseDown = false
      }
      favoritesCollectionView.onMouseDownEnded = { [weak self] downIndexPath, point in
        self?.mouseDownEnded(downIndexPath: downIndexPath, at: point)
      }
      favoritesCollectionView.menuProvider = { [weak self] indexPath in
        guard let self, let id = self.nodeID(at: indexPath) else { return nil }
        return self.contextMenu(for: id)
      }
      favoritesCollectionView.onMoveCommand = { [weak self] deltaColumns, deltaRows in
        self?.moveKeyboardFocus(deltaColumns: deltaColumns, deltaRows: deltaRows)
      }
      favoritesCollectionView.onKeyboardReturn = { [weak self] in self?.activateKeyboardFocus() }
      favoritesCollectionView.onKeyboardEscape = { [weak self] in
        guard let self else { return }
        keyboardFocusID = nil
        onKeyboardFocusExit?()
      }
      favoritesCollectionView.onKeyboardFocusResigned = { [weak self] in self?.keyboardFocusID = nil }
    }
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.autoresizingMask = []
    addSubview(collectionView)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Favorites.grid)
  }

  /// The Favorite tiles, in order, as this group's children (the tiles report the group as their parent, since the
  /// collection view between them is not an accessibility element). Read from the items that exist; see
  /// `FavoritesCollectionView.tileViews()`.
  public override func accessibilityChildren() -> [Any]? {
    guard let favoritesCollectionView = collectionView as? FavoritesCollectionView else {
      return super.accessibilityChildren()
    }
    return NSAccessibility.unignoredChildren(from: favoritesCollectionView.tileViews())
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  /// Height for the current item count and columns, or for the rows the tiles span while the column spring moves
  /// them. The sidebar calls `updateColumns(contentWidth:)` for its width before reading it.
  public var preferredHeight: CGFloat {
    guard !nodeIDs.isEmpty else { return 0 }
    if columnMotion.isRunning {
      let lastRow = nodeIDs.indices.map { columnMotion.slot(ofItem: $0)?.row ?? 0 }.max() ?? 0
      return FavoritesLayout.height(rows: CGFloat(lastRow) + 1).rounded()
    }
    return FavoritesLayout.height(rows: CGFloat(FavoritesLayout.rows(itemCount: nodeIDs.count, columns: columns)))
  }

  /// Picks the columns for `contentWidth` (the sidebar's layout calls it before it reads `preferredHeight`). A change
  /// at a new width of a grid on screen runs the column spring; the first width, Reduce Motion and an off-screen grid
  /// switch at once.
  public func updateColumns(contentWidth: CGFloat) {
    defer { columnsWidth = contentWidth }
    let target = FavoritesLayout.columns(itemCount: nodeIDs.count, contentWidth: contentWidth)
    guard target != columns else { return }
    let old = columns
    columns = target
    if columnsWidth != nil, columnsWidth != contentWidth, !nodeIDs.isEmpty, columnMotion.canAnimate(in: self) {
      columnMotion.run(itemCount: nodeIDs.count, from: old, to: target, in: self)
    } else {
      columnMotion.settleNow()
    }
    gridLayout.invalidateLayout()
  }

  /// The frame of tile `item`: its slot in the current columns, or where the column spring has it now.
  private func tileFrame(_ item: Int, contentWidth: CGFloat) -> CGRect {
    let slot = columnMotion.slot(ofItem: item) ?? FavoritesLayout.slot(ofItem: item, columns: columns)
    return FavoritesLayout.frame(of: slot, contentWidth: contentWidth)
  }

  /// A column spring frame: the tiles move, and the sidebar lays out again for the height they span.
  private func columnMotionPresentedFrame() {
    gridLayout.invalidateLayout()
    needsLayout = true
    superview?.needsLayout = true
  }

  /// Letter tiles are bitmaps per backing scale; re-render the visible tiles when the window's scale changes.
  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    refreshVisibleTiles()
  }

  public override func layout() {
    super.layout()
    updateColumns(contentWidth: bounds.width)
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
    tile.selectionAlpha = selectionFade?.node == id ? (selectionFade?.alpha ?? 1) : 1
    tile.isKeyboardFocused = keyboardFocusID == id
    var title = "", url: URL?
    if case .tab(_, let tabURL, let tabTitle)? = source.node(id) { title = tabTitle; url = tabURL }
    tile.faviconView.image = faviconProvider?(id)
      ?? SidebarGlyphs.letter(for: title, url: url, flavor: flavor, size: SidebarMetrics.favoriteFaviconSize,
                              scale: collectionView.shellBackingScale)
    tile.toolTip = title
    tile.setAccessibilityLabel(title)
    tile.nodeID = id
    let isLoaded = pageLoadedProvider?(id) == true
    tile.setAccessibilityValue(isLoaded ? AXID.Favorites.loaded : AXID.Favorites.unloaded)
    let action = isLoaded ? RowCloseAction.resolve(id, in: source) : nil
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

  // MARK: Drag source (#214)

  /// Only tab tiles (not folders) write their node id under the private `.sidebarNode` type.
  public func collectionView(_ collectionView: NSCollectionView,
                             pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
    guard let id = nodeID(at: indexPath), isTab(id) else { return nil }
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(id.uuidString, forType: .sidebarNode)
    return pasteboardItem
  }

  public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                             willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
    draggingSessionWillBegin(indexPaths: indexPaths)
  }

  public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                             endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
    draggingSessionEnded()
  }

  func draggingSessionWillBegin(indexPaths: Set<IndexPath>) {
    didDragInMouseDown = true
    isDragging = true
    collectionView.deselectItems(at: collectionView.selectionIndexPaths)
    guard let id = indexPaths.sorted().compactMap({ nodeID(at: $0) }).first(where: isTab) else { return }
    onNodeDragBegan?(id)
  }

  func draggingSessionEnded() {
    isDragging = false
    collectionView.deselectItems(at: collectionView.selectionIndexPaths)
    onNodeDragEnded?()
  }

  private func nodeID(at indexPath: IndexPath) -> NodeID? {
    nodeIDs.indices.contains(indexPath.item) ? nodeIDs[indexPath.item] : nil
  }

  private func isTab(_ id: NodeID) -> Bool {
    if case .tab? = source.node(id) { true } else { false }
  }

  // MARK: Delegate

  public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
    // During mouseDown tracking, keep the selection until mouseUp or drag start so NSCollectionView can initiate a
    // drag, and so starting a drag does not activate the tile on mouseDown.
    guard !isTrackingMouse, !isDragging else { return }
    collectionView.deselectItems(at: indexPaths)      // `current` is ours, not the collection view's selection
    if let indexPath = indexPaths.first, let id = nodeID(at: indexPath) { onActivate?(id) }
  }

  private func mouseDownEnded(downIndexPath: IndexPath?, at point: NSPoint) {
    isTrackingMouse = false
    collectionView.deselectItems(at: collectionView.selectionIndexPaths)
    guard !didDragInMouseDown, !isDragging,
          let indexPath = downIndexPath,
          collectionView.indexPathForItem(at: point) == indexPath,
          let id = nodeID(at: indexPath) else { return }
    onActivate?(id)
  }

  /// Gives a tile the keyboard cursor. With no explicit id (Up from the outline), returns to the last focused tile.
  func focusKeyboard(on id: NodeID? = nil) {
    guard let id = id ?? lastKeyboardFocusID ?? nodeIDs.last, nodeIDs.contains(id) else { return }
    keyboardFocusID = id
  }

  /// In the Ctrl-Space focus mode arrows move only the cursor (RT-13 assumed); Down at the bottom enters the outline.
  /// Outside that mode the original direct navigation (#94) still activates the destination.
  private func moveKeyboardFocus(deltaColumns: Int, deltaRows: Int) {
    guard !nodeIDs.isEmpty else { return }
    let step = deltaColumns + deltaRows * columns
    func neighbor(of index: Int) -> Int? {
      FavoritesLayout.neighbor(of: index, deltaColumns: deltaColumns, deltaRows: deltaRows, itemCount: nodeIDs.count,
                               columns: columns)
    }
    if let focused = keyboardFocusID, let currentIndex = nodeIDs.firstIndex(of: focused) {
      if let proposed = neighbor(of: currentIndex) {
        keyboardFocusID = nodeIDs[proposed]
        onKeyboardFocusMoved?(nodeIDs[proposed])
      } else if deltaRows > 0 {
        onKeyboardFocusBelow?()
      }
      return
    }
    let targetIndex: Int
    if let current = resolver.current, let currentIndex = nodeIDs.firstIndex(of: current) {
      guard let proposed = neighbor(of: currentIndex) else { return }
      targetIndex = proposed
    } else {
      targetIndex = step >= 0 ? 0 : nodeIDs.count - 1
    }
    onActivate?(nodeIDs[targetIndex])
  }

  private func activateKeyboardFocus() {
    guard let id = keyboardFocusID else { return }
    keyboardFocusID = nil
    onActivate?(id)
    onKeyboardFocusExit?()
  }

  private func updateKeyboardFocusRing() {
    for case let item as FavoriteTileItem in collectionView.visibleItems() {
      item.tileView.isKeyboardFocused = item.tileView.nodeID == keyboardFocusID
    }
  }

  // MARK: State and changes

  public func setRowStates(_ resolver: TabRowState.Resolver) {
    self.resolver = resolver
    refreshVisibleTiles()
  }

  /// The Favorite whose selection fill is fading, and how far it has faded (1 full, 0 gone). Nil at rest.
  private var selectionFade: (node: NodeID, alpha: CGFloat)?

  /// Sets one tile's selection-fill opacity (#465). Only that layer's opacity changes: no reload and no layout.
  /// Nil `node` ends the fade and restores the tile that was fading.
  func setSelectionFade(_ alpha: CGFloat, for node: NodeID?) {
    let previous = selectionFade?.node
    selectionFade = node.map { ($0, alpha) }
    if let previous, previous != node {
      tile(for: previous)?.selectionAlpha = 1
    }
    if let node {
      tile(for: node)?.selectionAlpha = alpha
    }
  }

  /// Tile currently showing `id`, if realized.
  /// The Favorite menu of `id` (design 3.3), nil for an unknown tile.
  public func contextMenu(for id: NodeID) -> NSMenu? {
    guard source.node(id) != nil else { return nil }
    let entries = SidebarContextMenu.entries(for: .favorite(id), in: source, context: SidebarMenuContext())
    return SidebarContextMenu.menu(entries, target: self, action: #selector(menuActionChosen(_:)))
  }

  @objc private func menuActionChosen(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? SidebarMenuAction else { return }
    onMenuAction?(action)
  }

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

  /// Targeted update for a `.favorites` structure change. Returns true when the grid height changed. The columns
  /// follow the new count at once (only a resize runs the column spring).
  @discardableResult
  public func apply(structure location: SidebarLocation) -> Bool {
    guard location == .favorites(profile: profile) else { return false }
    let old = nodeIDs
    let new = source.children(of: location)
    let oldHeight = preferredHeight
    columnMotion.settleNow()
    nodeIDs = new
    columns = FavoritesLayout.columns(itemCount: new.count, contentWidth: columnsWidth ?? Self.defaultContentWidth)
    let heightChanged = preferredHeight != oldHeight
    if let keyboardFocusID, !new.contains(keyboardFocusID) { self.keyboardFocusID = nil }
    if let lastKeyboardFocusID, !new.contains(lastKeyboardFocusID) { self.lastKeyboardFocusID = nil }
    let difference = new.difference(from: old)
    if difference.isEmpty { return false }
    // Without a size (an empty grid is 0 pt tall, so the first Favorites of an Arc import arrive that way) a batch
    // update leaves the collection view's layout prepared for the old items: its content size stays empty and no
    // item is realized once the grid is sized. Reload instead, here in the model change and not from `layout()`
    // (a reload issued during the layout pass did not re-prepare the layout either); the collection view prepares
    // its layout for every Favorite in its next layout pass, when the grid has its new height.
    if collectionView.bounds.isEmpty {
      collectionView.reloadData()
      return heightChanged
    }
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
    return heightChanged
  }
}
