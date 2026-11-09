import AppKit

/// One favorite tile: rounded fill (resting / hovered / current) with a centered 20 pt favicon, and the hover close
/// (X) in the top trailing corner while a loaded tile is hovered (#82). Frames set in `layout()`; no constraints.
@MainActor
public final class FavoriteTileView: NSView {
  public let faviconView = NSImageView()
  /// Shown while the tile is hovered and has a close action (its page is loaded). Target and action are set by the
  /// grid; hidden (so neither hit-tested nor in the accessibility tree) otherwise.
  public let closeButton = HoverCloseButton()
  /// The Ctrl-Space cursor (#343): the same `ShellTokens.focusRing` ring as outline-row focus (#642).
  let keyboardFocusRing = KeyboardFocusRingView(frame: .zero)
  var isKeyboardFocused = false {
    didSet {
      guard isKeyboardFocused != oldValue else { return }
      keyboardFocusRing.setFocused(isKeyboardFocused)
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
      postAccessibility(.valueChanged)             // the spoken value says "current" (#607)
    }
  }
  /// Whether the Favorite's page is loaded in this window; the grid sets it with the `loaded` / `unloaded` value.
  var isLoaded = false
  /// Testing seam: receives every accessibility notification this tile posts. Nil (the default) records nothing.
  var postedNotificationsForTesting: (@MainActor (NSAccessibility.Notification) -> Void)?

  private func postAccessibility(_ notification: NSAccessibility.Notification) {
    NSAccessibility.post(element: self, notification: notification)
    postedNotificationsForTesting?(notification)
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
  /// What VoiceOver's press (VO-Space) and show menu (VO-Shift-M) do on this tile (#607); the grid sets them for the
  /// Favorite shown and reuse clears them. Nil: the tile offers that action to no one.
  var onAccessibilityPress: (@MainActor () -> Void)?
  var onAccessibilityShowMenu: (@MainActor () -> Void)?
  /// Whether the X is shown or fading in (the tile is hovered and there is a close action).
  public private(set) var isCloseButtonShown = false
  private var hoverArea: NSTrackingArea?

  /// The fill currently drawn. Exposed for tests.
  public var displayedFill: RGBA {
    if isCurrent { return ShellTokens.tabCurrent.resolve(flavor) }
    return (isHovered ? ShellTokens.sidebarItemHovered : ShellTokens.sidebarItemBackground).resolve(flavor)
  }

  /// Increase Contrast (#640): every tile is filled, so every tile draws the 1 pt edge. Tests replace it.
  var increaseContrast: @MainActor () -> Bool = { IncreasedContrast.systemSetting }
  /// Read when a Favorite split's front layer changes and when its X plate fades; tests replace it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  // MARK: Split stack (#788)

  /// What a Favorite split's tile shows: its panes in order, and the stack's panes front first with their images.
  struct SplitStack {
    var panes: [NodeID]
    var order: [NodeID]
    var images: [NSImage]
  }

  /// A Favorite split's stack of pane favicons (`FavoriteSplitStack`), above the fill and below the X. Nil contents
  /// on a plain Favorite, which shows `faviconView`.
  let stackLayer = CALayer()
  /// The stack's mask: everything but the X's round plate, and the plate itself at `plateLayer`'s opacity (1 while the
  /// X is hidden, 0 while it shows), so the hovered fill covers the favicons under the X. A cut-out, never a paint.
  private let stackMask = CALayer()
  private let stackMaskOutside = CAShapeLayer()
  let plateLayer = CAShapeLayer()
  /// The panes and the front pane the stack shows now; nil on a plain Favorite.
  private(set) var splitStack: SplitStack?

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    IncreasedContrast.observe(self, selector: #selector(displayOptionsChanged(_:)))
    fillLayer.cornerRadius = FavoritesLayout.tileCornerRadius
    fillLayer.cornerCurve = .continuous
    fillLayer.shadowRadius = ShellTokens.rowLiftShadow.radius
    fillLayer.shadowOffset = ShellTokens.rowLiftShadow.unflippedOffset
    stackLayer.contentsGravity = .resize
    stackLayer.isHidden = true
    stackMaskOutside.fillRule = .evenOdd
    stackMask.addSublayer(stackMaskOutside)
    stackMask.addSublayer(plateLayer)
    stackLayer.mask = stackMask
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
    if stackLayer.superlayer !== layer { layer.insertSublayer(stackLayer, above: fillLayer) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.backgroundColor = nil
    layer.shadowOpacity = 0
    layer.shadowPath = nil
    fillLayer.frame = bounds
    fillLayer.cornerRadius = FavoritesLayout.tileCornerRadius
    fillLayer.cornerCurve = .continuous
    fillLayer.backgroundColor = displayedFill.cgColor
    IncreasedContrast.setEdge(on: fillLayer, increased: increaseContrast(), flavor: flavor)
    let shadow = ShellTokens.rowLiftShadow.color.resolve(flavor)
    fillLayer.shadowColor = shadow.cgColor
    fillLayer.shadowOpacity = isCurrent && shadow.alpha > 0 ? 1 : 0
    updateFillShadowPath()
    fillLayer.opacity = Float(isCurrent ? selectionAlpha : 1)
    CATransaction.commit()
  }

  @objc private func displayOptionsChanged(_ note: Notification) { needsDisplay = true }

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
    layoutStack()
  }

  /// The stack's box, centered on whole points (`FavoriteSplitStack.boxOrigin`), and the X's plate in it.
  private func layoutStack() {
    let size = FavoriteSplitStack.boxSize
    let origin = FavoriteSplitStack.boxOrigin(in: bounds.size)
    let frame = NSRect(x: origin.x, y: bounds.height - origin.y - size.height, width: size.width, height: size.height)
    let plate = closeButton.frame.offsetBy(dx: -frame.minX, dy: -frame.minY)
    let platePath = CGPath(ellipseIn: plate, transform: nil)
    let outside = CGMutablePath()
    outside.addRect(CGRect(origin: .zero, size: size).insetBy(dx: -size.width, dy: -size.height))
    outside.addPath(platePath)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    stackLayer.frame = frame
    stackMask.frame = stackLayer.bounds
    stackMaskOutside.frame = stackLayer.bounds
    stackMaskOutside.path = outside
    plateLayer.frame = stackLayer.bounds
    plateLayer.path = platePath
    CATransaction.commit()
  }

  /// Shows a Favorite split's stack (nil: a plain Favorite, which shows `faviconView`). A change of the front pane
  /// among the same panes cross-fades in `FavoritesLayout.focusCrossFadeDuration`, ease-out, while the tile is in a
  /// window; Reduce Motion, a first stack, new panes or a new favicon switch at once.
  func setSplitStack(_ stack: SplitStack?) {
    let previous = splitStack
    splitStack = stack
    faviconView.isHidden = stack != nil
    guard let stack else {
      stackLayer.removeAnimation(forKey: kCATransition)
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      stackLayer.contents = nil
      stackLayer.isHidden = true
      CATransaction.commit()
      return
    }
    let scale = shellBackingScale
    let focusMoved = previous.map { $0.panes == stack.panes && $0.order.first != stack.order.first } ?? false
    if focusMoved, window != nil, !reduceMotion() {
      let fade = CATransition()
      fade.type = .fade
      fade.duration = FavoritesLayout.focusCrossFadeDuration
      fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
      stackLayer.add(fade, forKey: kCATransition)
    } else if focusMoved {
      stackLayer.removeAnimation(forKey: kCATransition)
    }
    // Row states refresh every tile on each tab switch: draw again only when what the stack shows changed.
    let unchanged = previous.map { $0.order == stack.order && $0.images.count == stack.images.count
      && zip($0.images, stack.images).allSatisfy { $0 === $1 } } ?? false
    guard !unchanged || stackLayer.contentsScale != scale || stackLayer.contents == nil else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    stackLayer.contentsScale = scale
    stackLayer.contents = FavoriteSplitStack.render(stack.images, scale: scale)
    stackLayer.isHidden = false
    CATransaction.commit()
  }

  /// The X's plate follows the X: the hole in the stack's mask opens as the X fades in and closes as it fades out.
  private func setPlateShown(_ shown: Bool, animated: Bool) {
    let target: Float = shown ? 0 : 1
    let start = plateLayer.presentation()?.opacity ?? plateLayer.opacity
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    plateLayer.removeAnimation(forKey: "opacity")
    if animated, splitStack != nil, window != nil, !reduceMotion(), start != target {
      let animation = CABasicAnimation(keyPath: "opacity")
      animation.fromValue = NSNumber(value: start)
      animation.toValue = NSNumber(value: target)
      animation.duration = HoverCloseFade.duration(from: CGFloat(1 - start), to: shown ? 1 : 0,
                                                   full: SidebarMetrics.closeButtonFadeDuration)
      plateLayer.add(animation, forKey: "opacity")
    }
    plateLayer.opacity = target
    CATransaction.commit()
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
    setPlateShown(shown, animated: animated)
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
    isLoaded = false
    setSplitStack(nil)                                 // a reused tile never cross-fades from another Favorite
    setCloseAction(nil)
    setCloseButtonShown(false, animated: false)        // no fade on a reused tile
    setAccessibilityValue(nil)
    setAccessibilityCustomActions([])
    onAccessibilityPress = nil
    onAccessibilityShowMenu = nil
  }

  /// The current Favorite reports itself selected, as the current sidebar row does (#607).
  public override func isAccessibilitySelected() -> Bool { isCurrent }

  /// What VoiceOver speaks for the value (#607): the value itself is the `loaded` / `unloaded` token clients and UI
  /// tests read, and VoiceOver does not speak "selected" on a button. "Favorites, current"; "Favorites, loaded";
  /// "Favorites" for a Favorite with no page open.
  public override func accessibilityValueDescription() -> String? {
    if isCurrent { return "Favorites, current" }
    return isLoaded ? "Favorites, loaded" : "Favorites"
  }

  public override func accessibilityPerformPress() -> Bool {
    guard let onAccessibilityPress else { return false }
    onAccessibilityPress()
    return true
  }

  public override func accessibilityPerformShowMenu() -> Bool {
    guard let onAccessibilityShowMenu else { return false }
    onAccessibilityShowMenu()
    return true
  }

  public override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
    if selector == #selector(NSAccessibilityProtocol.accessibilityPerformPress) { return onAccessibilityPress != nil }
    if selector == #selector(NSAccessibilityProtocol.accessibilityPerformShowMenu) {
      return onAccessibilityShowMenu != nil
    }
    return super.isAccessibilitySelectorAllowed(selector)
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
  var onMouseDownEnded: (@MainActor (IndexPath?, NSPoint, NSEvent.ModifierFlags) -> Void)?
  var onMoveCommand: (@MainActor (_ deltaColumns: Int, _ deltaRows: Int) -> Void)?
  var onKeyboardReturn: (@MainActor () -> Void)?
  var onKeyboardEscape: (@MainActor () -> Void)?
  var onKeyboardFocusResigned: (@MainActor () -> Void)?
  /// The tile holding the keyboard cursor, and putting it back on a tile (false when the tile is gone), for a popover
  /// that gives the keyboard back when it closes (#696).
  var keyboardCursor: (@MainActor () -> NodeID?)?
  var restoreKeyboardCursor: (@MainActor (NodeID) -> Bool)?
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
    // The tracking loop ends on this window's mouse-up. When no loop ran, the current event is an unrelated earlier
    // one, so only a mouse-up of this window counts; otherwise the press itself decides.
    let endEvent = NSApp.currentEvent.flatMap {
      $0.type == .leftMouseUp && $0.windowNumber == event.windowNumber ? $0 : nil
    } ?? event
    onMouseDownEnded?(downIndexPath, convert(endEvent.locationInWindow, from: nil),
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask))
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
  /// Opt-Cmd-click on a tile (#356): true when the window opened the page in Little Arkt.
  public var onOpenInLittleArkt: (@MainActor (NodeID) -> Bool)?
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
  /// Shows the menu of a VoiceOver show-menu on a tile (#607); nil pops it up under the tile. Tests replace it to
  /// record the menu instead of tracking it.
  var presentAccessibilityMenu: (@MainActor (NSMenu, FavoriteTileView) -> Void)?
  /// Handed to every tile: a Favorite split's focus cross-fade and X plate (#788). Tests replace it.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
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
  public override func viewWillMove(toWindow newWindow: NSWindow?) {
    if window !== newWindow { hoverResync.cancel() }
    super.viewWillMove(toWindow: newWindow)
  }

  /// Where hover resyncs read the pointer; tests replace it.
  var hoverPointerLookup: HoverPointerLookup {
    get { hoverResync.lookup }
    set { hoverResync.lookup = newValue }
  }
  /// How a coalesced hover resync waits for the next main-queue turn; tests run it by hand.
  var hoverResyncEnqueue: @MainActor (@escaping @MainActor () -> Void) -> Void {
    get { hoverResync.enqueue }
    set { hoverResync.enqueue = newValue }
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
      favoritesCollectionView.onMouseDownEnded = { [weak self] downIndexPath, point, modifiers in
        self?.mouseDownEnded(downIndexPath: downIndexPath, at: point, modifiers: modifiers)
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
      favoritesCollectionView.keyboardCursor = { [weak self] in self?.keyboardFocusID }
      favoritesCollectionView.restoreKeyboardCursor = { [weak self] id in
        guard let self, nodeIDs.contains(id) else { return false }
        keyboardFocusID = id
        return true
      }
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
    tile.isCurrent = state(for: id) == .current
    tile.selectionAlpha = selectionFade?.node == id ? (selectionFade?.alpha ?? 1) : 1
    tile.isKeyboardFocused = keyboardFocusID == id
    tile.reduceMotion = reduceMotion
    if case .split? = source.node(id) {
      tile.faviconView.image = nil
      tile.setSplitStack(splitStack(of: id))
    } else {
      tile.setSplitStack(nil)
      tile.faviconView.image = favicon(of: id, size: SidebarMetrics.favoriteFaviconSize)
    }
    let shown = label(of: id)
    tile.toolTip = shown
    tile.setAccessibilityLabel(shown)
    tile.nodeID = id
    let isLoaded = hasLoadedPage(id)
    tile.isLoaded = isLoaded
    tile.setAccessibilityValue(isLoaded ? AXID.Favorites.loaded : AXID.Favorites.unloaded)
    let action = isLoaded ? RowCloseAction.resolve(id, in: source) : nil
    tile.closeButton.target = self
    tile.closeButton.action = #selector(closeClicked(_:))
    tile.setCloseAction(action)
    tile.setAccessibilityCustomActions(closeAccessibilityActions(for: id, action: action)
                                         + splitAccessibilityActions(for: id))
    tile.onAccessibilityPress = { [weak self] in self?.accessibilityPress(id) }
    tile.onAccessibilityShowMenu = { [weak self, weak tile] in
      guard let self, let tile else { return }
      self.accessibilityShowMenu(id, on: tile)
    }
  }

  /// A tab's favicon, else its letter tile (the host's first letter) at `size`: a page loading or without a favicon.
  private func favicon(of id: NodeID, size: CGFloat) -> NSImage {
    var title = "", url: URL?
    if case .tab(_, let tabURL, let tabTitle)? = source.node(id) { title = tabTitle; url = tabURL }
    return faviconProvider?(id)
      ?? SidebarGlyphs.letter(for: title, url: url, flavor: flavor, size: size, scale: collectionView.shellBackingScale)
  }

  /// A Favorite split's stack (#788): the focused pane in front while the split is shown, else the first pane, and
  /// each layer's favicon or letter tile at that layer's size.
  private func splitStack(of id: NodeID) -> FavoriteTileView.SplitStack {
    let panes = source.children(of: .split(id))
    let order = FavoriteSplitStack.order(panes: panes, focused: resolver.current)
    let images = zip(order, FavoriteSplitStack.layerSizes).map { favicon(of: $0, size: $1) }
    return FavoriteTileView.SplitStack(panes: panes, order: order, images: images)
  }

  /// A tile's tooltip and VoiceOver label: the tab's title, or a split's pane titles joined as its outline row has
  /// them (#801).
  private func label(of id: NodeID) -> String {
    switch source.node(id) {
    case .tab(_, let url, let title)?:
      return HostDisplay.title(title, for: url)
    case .split?:
      return source.children(of: .split(id)).compactMap { pane -> String? in
        if case .tab(_, let url, let title)? = source.node(pane) { return HostDisplay.title(title, for: url) }
        return nil
      }.joined(separator: " | ")
    case .folder?, nil:
      return ""
    }
  }

  /// Whether the tile has a page to close: a split while one of its panes has one, as the outline's pinned split row
  /// (#601, #801).
  private func hasLoadedPage(_ id: NodeID) -> Bool {
    guard let pageLoadedProvider else { return false }
    if case .split? = source.node(id) { return source.children(of: .split(id)).contains { pageLoadedProvider($0) } }
    return pageLoadedProvider(id)
  }

  /// A tile's row state: a split takes the strongest state among its panes, as its outline row does (#801).
  private func state(for id: NodeID) -> TabRowState {
    guard case .split? = source.node(id) else { return resolver.state(for: id) }
    let states = source.children(of: .split(id)).map { resolver.state(for: $0) }
    return [TabRowState.current, .contentVisible, .previous].first(where: states.contains) ?? .normal
  }

  /// VoiceOver's press on a tile: the Favorite activates, as a click on it does (#607).
  private func accessibilityPress(_ id: NodeID) {
    guard nodeIDs.contains(id) else { return }
    keyboardFocusID = nil
    onActivate?(id)
  }

  /// VoiceOver's show menu on a tile: the Favorite's right-click menu, under the tile (#607).
  private func accessibilityShowMenu(_ id: NodeID, on tile: FavoriteTileView) {
    guard let menu = contextMenu(for: id) else { return }
    if let presentAccessibilityMenu {
      presentAccessibilityMenu(menu, tile)
    } else {
      let below = NSPoint(x: 0, y: tile.isFlipped ? tile.bounds.maxY : tile.bounds.minY)
      menu.popUp(positioning: nil, at: below, in: tile)
    }
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

  /// VoiceOver's Separate All Tabs on a Favorite split's tile (#788), next to the X's close, so it is reached
  /// without the menu. None on a plain Favorite.
  private func splitAccessibilityActions(for id: NodeID) -> [NSAccessibilityCustomAction] {
    guard case .split? = source.node(id) else { return [] }
    return [NSAccessibilityCustomAction(name: SidebarContextMenu.separateAllTabsTitle) { [weak self] in
      guard let self, case .split? = self.source.node(id) else { return false }
      self.onMenuAction?(.separateSplit(id))
      return true
    }]
  }

  // MARK: Drag source (#214)

  /// Tab and split tiles (not folders) write their node id under the private `.sidebarNode` type; a split is dragged
  /// whole, as its outline row is (#801).
  public func collectionView(_ collectionView: NSCollectionView,
                             pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
    guard let id = nodeID(at: indexPath), isDraggable(id) else { return nil }
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
    guard let id = indexPaths.sorted().compactMap({ nodeID(at: $0) }).first(where: isDraggable) else { return }
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

  private func isDraggable(_ id: NodeID) -> Bool {
    switch source.node(id) {
    case .tab?, .split?: true
    case .folder?, nil: false
    }
  }

  // MARK: Delegate

  public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
    // During mouseDown tracking, keep the selection until mouseUp or drag start so NSCollectionView can initiate a
    // drag, and so starting a drag does not activate the tile on mouseDown.
    guard !isTrackingMouse, !isDragging else { return }
    collectionView.deselectItems(at: indexPaths)      // `current` is ours, not the collection view's selection
    if let indexPath = indexPaths.first, let id = nodeID(at: indexPath) { onActivate?(id) }
  }

  private func mouseDownEnded(downIndexPath: IndexPath?, at point: NSPoint, modifiers: NSEvent.ModifierFlags) {
    isTrackingMouse = false
    collectionView.deselectItems(at: collectionView.selectionIndexPaths)
    guard !didDragInMouseDown, !isDragging,
          let indexPath = downIndexPath,
          collectionView.indexPathForItem(at: point) == indexPath,
          let id = nodeID(at: indexPath) else { return }
    handleTileClick(id, modifiers: modifiers)
  }

  /// A click on a tile: Opt-Cmd-click opens the Favorite's page in a new Little Arkt window and leaves the Favorite
  /// as it is (#356, BH-132) while the window takes it; any other click activates it.
  func handleTileClick(_ id: NodeID, modifiers: NSEvent.ModifierFlags) {
    if LittleArktRouting.isLittleArktClick(modifiers), isTab(id), onOpenInLittleArkt?(id) == true { return }
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

  /// Refreshes one tile (favicon, title or whether its page is loaded). A pane of a Favorite split refreshes its
  /// split's tile, which shows the X while a pane has a page (#801).
  public func reload(node id: NodeID) {
    let tileID = if case .split(let split)? = source.parent(of: id), nodeIDs.contains(split) { split } else { id }
    guard let index = nodeIDs.firstIndex(of: tileID),
          let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? FavoriteTileItem else { return }
    configure(item, id: tileID)
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
