import AppKit

extension NSPasteboard.PasteboardType {
  /// A sidebar node dragged inside the app: the node's UUID string. Only tab rows write it (S7).
  static let sidebarNode = NSPasteboard.PasteboardType("dev.arkt.sidebar-node")
}

/// NSOutlineView compares items by identity, so every node is represented by one cached instance.
@MainActor
public final class OutlineItem: NSObject {
  public enum Kind: Equatable { case node(NodeID), divider }
  public let kind: Kind
  init(_ kind: Kind) { self.kind = kind }

  public var nodeID: NodeID? {
    if case .node(let id) = kind { return id }
    return nil
  }
}

/// Outline view with Arc's flat geometry: no disclosure triangle, children indented by a fixed step, and a
/// pressed state shown on the row under the pointer while the button is down.
///
/// Accessibility: `NSOutlineView` answers `AXChildren` / `AXRows` out of process from its own internals, without the
/// row views or overridden children (#269), so its rows reach VoiceOver and XCUITest's `outlineRows` through
/// `axProxyRows`: a proxy outline element (`sidebar.outline`) with one `AXProxyRow` per displayed row, in display
/// order, which `SpacePageView` lists in place of the scroll view. The controller supplies each row's identifier,
/// label, state and disclosure from its model. A structural change (expand, collapse, insert, remove, move,
/// reloadData) marks the proxies stale so the next query builds them afresh; a row reload does not, so the element
/// a client holds survives title, favicon and Closing changes (#297).
@MainActor
public final class SidebarOutlineView: NSOutlineView, HoverResyncHost {
  let axProxyRows: AXProxyRows

  public override init(frame frameRect: NSRect) {
    axProxyRows = AXProxyRows(role: .outline, identifier: AXID.Sidebar.outline)
    super.init(frame: frameRect)
    axProxyRows.attach(to: self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private lazy var hoverResync = HoverResyncScheduler(view: self) { [unowned self] pointer in
    enumerateAvailableRowViews { rowView, _ in (rowView as? SidebarRowView)?.syncHover(pointerInWindow: pointer) }
  }
  /// Where hover resyncs read the pointer; tests replace it.
  var hoverPointerLookup: HoverPointerLookup {
    get { hoverResync.lookup }
    set { hoverResync.lookup = newValue }
  }

  /// Rows ask on every tracking-area update (a scroll updates all of them); one lookup serves them all.
  func setNeedsHoverResync() { hoverResync.setNeeded() }

  /// Reads the pointer once and sets the hover state of every realized row from it.
  func resyncHoverWithPointer() { hoverResync.resyncNow() }

  public override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

  public override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
    let full = super.frameOfCell(atColumn: column, row: row)
    let indent = CGFloat(max(0, level(forRow: row))) * indentationPerLevel
    let rowRect = rect(ofRow: row)
    return NSRect(x: rowRect.minX + indent, y: full.minY, width: max(0, rowRect.width - indent), height: full.height)
  }

  /// Modifier flags of the mouse-down that is being handled; the click action reads them (Opt-click, GS-032 and
  /// GS-033) instead of `NSApp.currentEvent`, which is not always the click.
  private(set) var clickModifiers: NSEvent.ModifierFlags = []

  /// The mouse-down's point in this outline's coordinates; the click action hit-tests the pinned rows' favicons
  /// with it (GS-005). Kept until the next mouse-down.
  var lastClickPoint: NSPoint?

  /// Number of `reloadData()` calls so far; exists for tests (checks that split edits never reload the whole outline).
  private(set) var reloadDataCount = 0

  public override func reloadData() {
    reloadDataCount += 1
    super.reloadData()
    axProxyRows.invalidate()
  }

  // A structural change to the displayed rows (insert, remove, move, expand, collapse, reloadData): the proxy at
  // an index may now stand for another item, so the proxies are rebuilt, and clients are told. A plain
  // `reloadItem` is NOT here (#297): it changes no row's item, and the proxies read the new title and value when
  // asked, so the element a VoiceOver user is on survives it. The title/value notification comes from
  // `SidebarOutlineController.reload(node:)`, which knows the row.

  public override func expandItem(_ item: Any?) {
    super.expandItem(item)
    axProxyRows.invalidate()
    axProxyRows.post(.rowExpanded, forRow: row(forItem: item))
  }

  public override func collapseItem(_ item: Any?) {
    super.collapseItem(item)
    axProxyRows.invalidate()
    axProxyRows.post(.rowCollapsed, forRow: row(forItem: item))
  }

  public override func expandItem(_ item: Any?, expandChildren: Bool) {
    super.expandItem(item, expandChildren: expandChildren)
    axProxyRows.invalidate()
    axProxyRows.post(.rowExpanded, forRow: row(forItem: item))
  }

  public override func collapseItem(_ item: Any?, collapseChildren: Bool) {
    super.collapseItem(item, collapseChildren: collapseChildren)
    axProxyRows.invalidate()
    axProxyRows.post(.rowCollapsed, forRow: row(forItem: item))
  }

  public override func insertItems(at indexes: IndexSet, inParent parent: Any?,
                                   withAnimation animationOptions: NSTableView.AnimationOptions = []) {
    super.insertItems(at: indexes, inParent: parent, withAnimation: animationOptions)
    axProxyRows.invalidate()
    axProxyRows.post(.rowCountChanged)
  }

  public override func removeItems(at indexes: IndexSet, inParent parent: Any?,
                                   withAnimation animationOptions: NSTableView.AnimationOptions = []) {
    super.removeItems(at: indexes, inParent: parent, withAnimation: animationOptions)
    axProxyRows.invalidate()
    axProxyRows.post(.rowCountChanged)
  }

  public override func moveItem(at fromIndex: Int, inParent oldParent: Any?, to toIndex: Int,
                                inParent newParent: Any?) {
    super.moveItem(at: fromIndex, inParent: oldParent, to: toIndex, inParent: newParent)
    axProxyRows.invalidate()
  }

  /// Shows the context menu of a Ctrl-click, when `menu(for:)` gave one; tests replace it to record the request
  /// instead of tracking the menu.
  var presentContextMenu: @MainActor (NSMenu?, NSEvent, NSView) -> Void = { menu, event, view in
    if let menu { NSMenu.popUpContextMenu(menu, with: event, for: view) }
  }

  public override func mouseDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    // A Ctrl-click is a secondary click: the row's context menu, as a right-click shows, never the click action.
    // Left to the table, it sends the row action with Control set, which activates the row (#277).
    if modifiers.contains(.control) {
      presentContextMenu(menu(for: event), event, self)
      return
    }
    clickModifiers = modifiers
    defer { clickModifiers = [] }
    let point = convert(event.locationInWindow, from: nil)
    lastClickPoint = point
    let row = self.row(at: point)
    let rowView = row >= 0 ? self.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView : nil
    rowView?.isPressed = true
    super.mouseDown(with: event)
    rowView?.isPressed = false
  }

  /// Clicks activate rows; the window drags from empty sidebar space only.
  public override var mouseDownCanMoveWindow: Bool { false }
  public override var needsPanelToBecomeKey: Bool { false }

  // MARK: Accessibility

  /// The proxy of the row hosting `view` (a cell), so the cell names it as its parent.
  func axProxyRow(hosting view: NSView) -> AXProxyRow? {
    let row = self.row(for: view)
    return row >= 0 ? axProxyRows.rowElement(forRow: row) : nil
  }
}

/// Data source and delegate for one Space: pinned nodes, a divider, then Today nodes; folders and splits expand.
/// Changes are applied as targeted diffs (`insertItems` / `removeItems` / `reloadItem`), never `reloadData()`
/// after setup (design section 4).
@MainActor
public final class SidebarOutlineController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate,
  NSMenuDelegate {
  public let source: any SidebarSource
  public let spaceID: SpaceID
  public let outlineView: SidebarOutlineView
  public var flavor: ThemeFlavor = .light
  public private(set) var resolver: TabRowState.Resolver = .empty

  /// A tab or split row was clicked (folders toggle in place).
  public var onActivate: (@MainActor (NodeID) -> Void)?
  /// A row's hover close (X) button or its VoiceOver close action was used (GS-043); the window runs the same
  /// close as Cmd-W. A pane row's X goes to `onRemovePane` instead (BH-121).
  public var onClose: (@MainActor (NodeID) -> Void)?
  /// Separate All Tabs on a split row: its context menu, or an Opt-click on it (BH-121, GS-033).
  public var onSeparateSplit: (@MainActor (NodeID) -> Void)?
  /// Remove Tab from Split View: a pane row's X, its context menu or its VoiceOver action (BH-121).
  public var onRemovePane: (@MainActor (NodeID) -> Void)?
  /// Convert to Vertical / Horizontal Split View on a split row's context menu (BH-120).
  public var onConvertSplit: (@MainActor (NodeID) -> Void)?
  /// Duplicate Split View on a split row's context menu (BH-126).
  public var onDuplicateSplit: (@MainActor (NodeID) -> Void)?
  /// Opt-click on the current plain tab: duplicate it into a split (GS-032).
  public var onDuplicateIntoSplit: (@MainActor (NodeID) -> Void)?
  /// Move To > Favorites on a tab row's context menu (BH-047); the window moves the node.
  public var onMoveToFavorites: (@MainActor (NodeID) -> Void)?
  /// Pin / Unpin Tab on a row's context menu (BH-055); the window moves the node.
  public var onPinToggle: (@MainActor (NodeID) -> Void)?
  /// Back to Pinned URL on a pinned row's context menu (BH-057); the window navigates the live tab.
  public var onResetPinned: (@MainActor (NodeID) -> Void)?
  /// Replace Pin with Current Page on a pinned row's context menu (BH-060).
  public var onReplacePin: (@MainActor (NodeID) -> Void)?
  /// Separate From Pinned Tab on a pinned row's context menu (BH-061).
  public var onSeparateFromPinned: (@MainActor (NodeID) -> Void)?
  /// A pinned tab row's favicon was clicked (GS-005), with the click's modifiers (Cmd: BH-058); the window resets
  /// or activates.
  public var onPinnedFaviconClick: (@MainActor (NodeID, NSEvent.ModifierFlags) -> Void)?
  /// Whether a pinned tab sits away from its pinned URL; drives the reset-family items' enabled state (the window
  /// knows the live page's URL).
  public var pinnedNavigatedProvider: (@MainActor (NodeID) -> Bool)?
  /// A tab row started a drag (S7, GS-011); the window shows its drop overlay above the page.
  public var onNodeDragBegan: (@MainActor (NodeID) -> Void)?
  /// The drag that `onNodeDragBegan` reported ended, dropped or not.
  public var onNodeDragEnded: (@MainActor () -> Void)?
  /// Favicon for a tab, nil = letter placeholder.
  public var faviconProvider: (@MainActor (NodeID) -> NSImage?)?
  /// True while the row's page close is held behind a leave-site prompt (week-3 Decision 11).
  public var closingProvider: (@MainActor (NodeID) -> Bool)?

  private let divider = OutlineItem(.divider)
  private var items: [NodeID: OutlineItem] = [:]
  private var pinnedIDs: [NodeID] = []
  private var todayIDs: [NodeID] = []
  /// BH-065: the Pinned section of this page is collapsed (per window). Pinned rows leave the outline; the divider
  /// stays [I], so the boundary the pinned tabs sit above keeps drawing (PARITY: Arc's collapsed look is
  /// unmeasured).
  public var isPinnedCollapsed = false {
    didSet {
      guard isPinnedCollapsed != oldValue else { return }
      let old = rootItems
      rebuildRootItems()
      applyDiff(old: old, new: rootItems, parent: nil)
    }
  }
  /// Pinned items (unless collapsed), the divider, then Today items. Rebuilt only when the pinned or Today ids
  /// change, or the collapse toggles.
  private var rootItems: [OutlineItem] = []
  private var containerChildren: [NodeID: [NodeID]] = [:]
  /// Folders the user collapsed in this outline; preserved across moves and sibling removals (#94).
  private var collapsedFolders: Set<NodeID> = []

  /// The outline is `scrollView`'s document view before its first reload and expansion, so the load realizes only
  /// the rows the clip view shows (#297). An offscreen page is hidden and a hidden table realizes nothing; the
  /// pager's `preparePageForDisplay` builds a hidden page's rows before a switch shows it, off the showing frame.
  public init(source: any SidebarSource, spaceID: SpaceID, hostedIn scrollView: NSScrollView) {
    self.source = source
    self.spaceID = spaceID
    self.outlineView = SidebarOutlineView(frame: NSRect(x: 0, y: 0, width: 174, height: 400))
    super.init()
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
    column.resizingMask = .autoresizingMask
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column
    outlineView.headerView = nil
    outlineView.style = .plain
    outlineView.rowHeight = SidebarMetrics.rowPitch
    outlineView.intercellSpacing = .zero
    outlineView.selectionHighlightStyle = .none
    outlineView.backgroundColor = .clear
    outlineView.indentationPerLevel = SidebarMetrics.indentationPerLevel
    outlineView.indentationMarkerFollowsCell = false
    outlineView.floatsGroupRows = false
    outlineView.usesAutomaticRowHeights = false
    outlineView.focusRingType = .none
    outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    outlineView.autoresizesOutlineColumn = false
    outlineView.target = self
    outlineView.action = #selector(rowClicked(_:))
    outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
    outlineView.setDraggingSourceOperationMask([], forLocal: false)   // tabs stay inside the app
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    outlineView.menu = menu
    pinnedIDs = source.children(of: .pinned(spaceID))
    todayIDs = source.children(of: .today(spaceID))
    rebuildRootItems()
    outlineView.dataSource = self
    outlineView.delegate = self
    wireAccessibility()
    scrollView.documentView = outlineView
    outlineView.reloadData()
    for id in pinnedIDs + todayIDs {
      expandContainer(id)
    }
  }

  // MARK: Items

  func item(for id: NodeID) -> OutlineItem {
    if let existing = items[id] { return existing }
    let made = OutlineItem(.node(id))
    items[id] = made
    return made
  }

  private func rebuildRootItems() {
    let pinned = isPinnedCollapsed ? [] : pinnedIDs.map(item(for:))
    rootItems = pinned + [divider] + todayIDs.map(item(for:))
  }

  /// Row index of the divider (equals the pinned count).
  public var dividerRow: Int { outlineView.row(forItem: divider) }

  public func row(for id: NodeID) -> Int {
    guard let existing = items[id] else { return -1 }
    return outlineView.row(forItem: existing)
  }

  private func children(of id: NodeID) -> [NodeID] {
    if let cached = containerChildren[id] { return cached }
    guard let location = source.node(id)?.childLocation else { return [] }
    let fresh = source.children(of: location)
    containerChildren[id] = fresh
    return fresh
  }

  // MARK: Data source

  public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    guard let item = item as? OutlineItem else { return rootItems.count }
    guard let id = item.nodeID else { return 0 }
    return children(of: id).count
  }

  public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    guard let item = item as? OutlineItem, let id = item.nodeID else { return rootItems[index] }
    return self.item(for: children(of: id)[index])
  }

  public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    guard let id = (item as? OutlineItem)?.nodeID else { return false }
    return source.node(id)?.childLocation != nil
  }

  // MARK: Drag source (S7)

  /// Tab rows (plain tabs, tabs in folders, panes) write their node id under the private `.sidebarNode` type; folders,
  /// splits and the divider are not dragged.
  public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any)
    -> (any NSPasteboardWriting)? {
    guard let id = (item as? OutlineItem)?.nodeID, isTab(id) else { return nil }
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(id.uuidString, forType: .sidebarNode)
    return pasteboardItem
  }

  public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                          willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
    draggingSessionWillBegin(items: draggedItems)
  }

  public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                          endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    draggingSessionEnded()
  }

  /// Rows cannot be selected, so a drag carries one row: the first tab among `items`.
  func draggingSessionWillBegin(items: [Any]) {
    let ids = items.compactMap { ($0 as? OutlineItem)?.nodeID }
    guard let id = ids.first(where: isTab) else { return }
    onNodeDragBegan?(id)
  }

  func draggingSessionEnded() { onNodeDragEnded?() }

  // MARK: Delegate

  public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    (item as? OutlineItem)?.kind == .divider ? SidebarMetrics.dividerHeight : SidebarMetrics.rowPitch
  }

  public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    let row = outlineView.makeView(withIdentifier: SidebarRowView.reuseIdentifier, owner: self) as? SidebarRowView
      ?? SidebarRowView(frame: .zero)
    let item = item as? OutlineItem
    configure(row, for: item)
    return row
  }

  public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let item = item as? OutlineItem else { return nil }
    guard let id = item.nodeID else {
      let view = outlineView.makeView(withIdentifier: SidebarDividerView.reuseIdentifier, owner: self)
        as? SidebarDividerView ?? SidebarDividerView(frame: .zero)
      view.flavor = flavor
      return view
    }
    let cell = outlineView.makeView(withIdentifier: SidebarTabCellView.reuseIdentifier, owner: self)
      as? SidebarTabCellView ?? SidebarTabCellView(frame: .zero)
    configure(cell, for: id)
    cell.closeButton.target = self
    cell.closeButton.action = #selector(closeClicked(_:))
    return cell
  }

  /// A row held closing has no X: a second close would do nothing (Decision 11).
  private func configure(_ cell: SidebarTabCellView, for id: NodeID) {
    let (title, image) = presentation(of: id)
    let closing = closingProvider?(id) ?? false
    cell.configure(title: title, image: image, flavor: flavor,
                   closeAction: closing ? nil : RowCloseAction.resolve(id, in: source), isClosing: closing)
  }

  public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { false }

  private func presentation(of id: NodeID) -> (String, NSImage) {
    let scale = outlineView.shellBackingScale
    switch source.node(id) {
    case .tab(_, let url, let title)?:
      let image = faviconProvider?(id)
        ?? SidebarGlyphs.letter(for: title, url: url, flavor: flavor, size: SidebarMetrics.faviconSize, scale: scale)
      return (title, image)
    case .folder?:
      let symbol = collapsedFolders.contains(id) ? "folder" : "folder.fill"
      return (title(of: id), SidebarGlyphs.symbol(symbol, flavor: flavor, scale: scale))
    case .split?:
      return (title(of: id), SidebarGlyphs.symbol("rectangle.split.2x1", flavor: flavor, scale: scale))
    case nil:
      return ("", SidebarGlyphs.symbol("questionmark.square", flavor: flavor, scale: scale))
    }
  }

  /// A row's title: the tab or folder title, or a split's pane titles joined. No image is made, so accessibility
  /// queries can read it cheaply.
  private func title(of id: NodeID) -> String {
    switch source.node(id) {
    case .tab(_, _, let title)?, .folder(_, let title)?:
      return title
    case .split?:
      let titles = children(of: id).compactMap { child -> String? in
        if case .tab(_, _, let title)? = source.node(child) { return title }
        return nil
      }
      return titles.joined(separator: " | ")
    case nil:
      return ""
    }
  }

  // MARK: Accessibility (#269)

  /// Feeds the outline's proxy rows from the model: identifier and label as the rows have them, "Closing" while a
  /// close is held, the depth and expansion of containers, selection as the `current` row state (outline selection
  /// stays off), the realized cell (its title and hover close button) as the row's child, and the row's VoiceOver
  /// actions. Every answer is read when asked; none builds a row view.
  private func wireAccessibility() {
    let proxies = outlineView.axProxyRows
    proxies.content = { [weak self] row in self?.accessibilityContent(ofRow: row) }
    proxies.isSelected = { [weak self] row in
      guard let self, let id = self.nodeID(atRow: row) else { return false }
      return self.state(for: id) == .current
    }
    proxies.children = { [weak self] row in
      // The divider row's proxy is the splitter itself, so it lists nothing.
      guard let self, self.nodeID(atRow: row) != nil,
            let cell = self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarTabCellView
      else { return [] }
      return [cell]
    }
    proxies.customActionNames = { [weak self] row in
      guard let self, let id = self.nodeID(atRow: row) else { return [] }
      return self.accessibilityActions(for: id).map(\.name)
    }
    proxies.performCustomAction = { [weak self] row, name in
      guard let self, let id = self.nodeID(atRow: row) else { return false }
      return self.performAccessibilityAction(named: name, on: id)
    }
  }

  private func nodeID(atRow row: Int) -> NodeID? {
    (outlineView.item(atRow: row) as? OutlineItem)?.nodeID
  }

  private func accessibilityContent(ofRow row: Int) -> AXProxyRowContent? {
    guard let item = outlineView.item(atRow: row) as? OutlineItem else { return nil }
    guard let id = item.nodeID else {
      return AXProxyRowContent(identifier: AXID.Sidebar.divider, label: "", role: .separator)
    }
    let expandable = source.node(id)?.childLocation != nil
    return AXProxyRowContent(
      identifier: rowIdentifier(for: id), label: title(of: id),
      value: (closingProvider?(id) ?? false) ? "Closing" : nil,
      disclosureLevel: max(0, outlineView.level(forRow: row)),
      isExpanded: expandable ? outlineView.isItemExpanded(item) : nil)
  }

  // MARK: Row state

  /// Row state for a node; a split shows the strongest state among its panes.
  public func state(for id: NodeID) -> TabRowState {
    guard case .split? = source.node(id) else { return resolver.state(for: id) }
    let states = children(of: id).map { resolver.state(for: $0) }
    for candidate in [TabRowState.current, .contentVisible, .previous] where states.contains(candidate) {
      return candidate
    }
    return .normal
  }

  /// Row configurations so far (tests check that state pushes touch only changed rows).
  private(set) var rowConfigureCount = 0

  private func configure(_ row: SidebarRowView, for item: OutlineItem?) {
    rowConfigureCount += 1
    row.flavor = flavor
    if let id = item?.nodeID {
      row.isInteractive = true
      row.state = state(for: id)
    } else {
      row.isInteractive = false
      row.state = .normal
    }
  }

  private func rowIdentifier(for id: NodeID) -> String {
    switch source.node(id) {
    case .folder?: return AXID.Sidebar.rowFolder
    case .split?: return AXID.Sidebar.rowSplit
    case .tab?, nil:
      if case .pinned? = source.section(containing: id) { return AXID.Sidebar.rowPinned }
      return AXID.Sidebar.rowToday
    }
  }

  /// Pushes new row states to the realized row views only.
  /// Only rows whose state changed are touched (a split row when any of its panes changed); a page whose
  /// rows are all unaffected is left alone.
  public func setRowStates(_ resolver: TabRowState.Resolver) {
    let changed = resolver.changedNodes(from: self.resolver)
    self.resolver = resolver
    guard !changed.isEmpty else { return }
    // The proxies read selection from the resolver; tell clients that cached it.
    outlineView.axProxyRows.selectionDidChange()
    outlineView.enumerateAvailableRowViews { rowView, row in
      guard let rowView = rowView as? SidebarRowView,
            let item = self.outlineView.item(atRow: row) as? OutlineItem, let id = item.nodeID else { return }
      let affected: Bool
      if case .split? = self.source.node(id) {
        affected = self.children(of: id).contains(where: changed.contains)
      } else {
        affected = changed.contains(id)
      }
      if affected { self.configure(rowView, for: item) }
    }
  }

  public func setFlavor(_ flavor: ThemeFlavor) {
    guard flavor != self.flavor else { return }
    self.flavor = flavor
    refreshRealizedCells()
  }

  /// Reconfigures every realized row and its cell for the current flavor and backing scale (glyph bitmaps
  /// are per scale, so a window moving between a 1x and a 2x display needs them re-rendered).
  public func refreshRealizedCells() {
    outlineView.enumerateAvailableRowViews { rowView, row in
      guard let rowView = rowView as? SidebarRowView else { return }
      self.configure(rowView, for: self.outlineView.item(atRow: row) as? OutlineItem)
      if let id = (self.outlineView.item(atRow: row) as? OutlineItem)?.nodeID,
         let cell = self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarTabCellView {
        self.configure(cell, for: id)
      } else if let divider = self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                  as? SidebarDividerView {
        divider.flavor = self.flavor
      }
    }
  }

  /// Refreshes one row's cell (title or favicon) without touching any other row.
  public func reload(node id: NodeID) {
    guard let existing = items[id] else { return }
    let row = outlineView.row(forItem: existing)
    guard row >= 0 else { return }
    outlineView.reloadItem(existing, reloadChildren: false)
    // The proxy keeps its element and reads the new fields when asked; tell clients that cached them (#297).
    // A favicon-only reload over-posts, which costs the client one attribute read.
    outlineView.axProxyRows.post(.titleChanged, forRow: row)
    outlineView.axProxyRows.post(.valueChanged, forRow: row)
    if let container = source.parent(of: id)?.containerNode, case .split? = source.node(container),
       let splitItem = items[container] {
      outlineView.reloadItem(splitItem, reloadChildren: false)   // split titles derive from their panes
      outlineView.axProxyRows.post(.titleChanged, forRow: outlineView.row(forItem: splitItem))
    }
  }

  // MARK: Changes

  /// A location's child list changed: insert / remove exactly the rows that differ, reload nothing else.
  /// Ignores locations outside this Space. (Node-level changes go to `reload(node:)`.)
  public func apply(structure location: SidebarLocation) {
    // The row mutations below drop the proxies too; this also covers a change that moves no row.
    defer { outlineView.axProxyRows.invalidate() }
    switch location {
    case .pinned(let space) where space == spaceID:
      let new = source.children(of: location)
      guard new != pinnedIDs else { return }
      let old = rootItems
      pinnedIDs = new
      rebuildRootItems()
      applyDiff(old: old, new: rootItems, parent: nil)
    case .today(let space) where space == spaceID:
      let new = source.children(of: location)
      guard new != todayIDs else { return }
      let old = rootItems
      todayIDs = new
      rebuildRootItems()
      applyDiff(old: old, new: rootItems, parent: nil)
    case .folder(let id), .split(let id):
      // Never asked for: the outline holds no rows for it yet and the next query reads the source fresh.
      guard let parent = items[id], let old = containerChildren[id] else { return }
      let new = source.children(of: location)
      containerChildren[id] = new
      applyDiff(old: old.map { item(for: $0) }, new: new.map { item(for: $0) }, parent: parent)
      if case .split = location { outlineView.reloadItem(parent, reloadChildren: false) }  // title from panes
    default:
      return
    }
  }

  private func applyDiff(old: [OutlineItem], new: [OutlineItem], parent: OutlineItem?) {
    let difference = new.map(ObjectIdentifier.init).difference(from: old.map(ObjectIdentifier.init))
    guard !difference.isEmpty else { return }
    outlineView.beginUpdates()
    for change in difference.removals.reversed() {
      if case .remove(let offset, _, _) = change {
        outlineView.removeItems(at: IndexSet(integer: offset), inParent: parent, withAnimation: [])
      }
    }
    for change in difference.insertions {
      if case .insert(let offset, _, _) = change {
        outlineView.insertItems(at: IndexSet(integer: offset), inParent: parent, withAnimation: [])
      }
    }
    outlineView.endUpdates()
    // Forget removed nodes the source no longer has, so a node restored later with the same id is read fresh.
    for change in difference.removals {
      if case .remove(let offset, _, _) = change, let id = old[offset].nodeID, source.node(id) == nil {
        forget(id)
      }
    }
    for change in difference.insertions {
      if case .insert(let offset, _, _) = change, let id = new[offset].nodeID {
        expandContainer(id)
      }
    }
  }

  /// Expands `id` (unless it is a folder the user collapsed) and any non-collapsed containers inside it (#94).
  private func expandContainer(_ id: NodeID) {
    guard source.node(id)?.childLocation != nil, !collapsedFolders.contains(id) else { return }
    outlineView.expandItem(item(for: id))
    for child in children(of: id) where source.node(child)?.childLocation != nil {
      expandContainer(child)
    }
  }

  /// Drops the cached item and child list of `id` and of its cached descendants that left the source.
  private func forget(_ id: NodeID) {
    items[id] = nil
    collapsedFolders.remove(id)
    for child in containerChildren.removeValue(forKey: id) ?? [] where source.node(child) == nil {
      forget(child)
    }
  }

  // MARK: Clicks

  @objc private func rowClicked(_ sender: Any?) {
    handleClick(row: outlineView.clickedRow, modifiers: outlineView.clickModifiers)
  }

  /// A click on `row`. Folders toggle. Opt-click on a split row separates it (GS-033); Opt-click on the current tab
  /// duplicates it into a split (GS-032). Arc gates both behind `newSplitSeparationMechanismsEnabled` and
  /// `dragToCombineTabsIntoSplitEnabled` [S]; here they are always on [I]. An Opt-click on any other tab, or on a
  /// pane, activates it like a plain click [I]. A click on a pinned tab's favicon goes to the window's reset path
  /// (GS-005, BH-057, BH-058); anywhere else on the row activates it.
  func handleClick(row: Int, modifiers: NSEvent.ModifierFlags) {
    guard row >= 0, let item = outlineView.item(atRow: row) as? OutlineItem, let id = item.nodeID else { return }
    let option = modifiers.intersection([.command, .option, .control, .shift]) == .option
    switch source.node(id) {
    case .folder?:
      if outlineView.isItemExpanded(item) {
        collapsedFolders.insert(id)
        outlineView.collapseItem(item)
      } else {
        collapsedFolders.remove(id)
        expandContainer(id)
      }
      reload(node: id)
    case .split? where option:
      onSeparateSplit?(id)
    case .tab? where option && resolver.current == id && !isPane(id):
      onDuplicateIntoSplit?(id)
    case .tab? where isPinnedFaviconClick(row: row, id: id):
      onPinnedFaviconClick?(id, modifiers)
    case .tab?, .split?:
      onActivate?(id)
    case nil:
      return
    }
  }

  /// GS-005: true when the recorded click point lands in the favicon of a pinned tab's row (foldered tabs
  /// included; panes have no favicon path of their own — they sit in a split).
  private func isPinnedFaviconClick(row: Int, id: NodeID) -> Bool {
    guard !isPane(id), case .pinned? = source.section(containing: id),
          let point = outlineView.lastClickPoint,
          let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarTabCellView
    else { return false }
    return cell.faviconView.frame.contains(cell.convert(point, from: outlineView))
  }

  private func isTab(_ id: NodeID) -> Bool {
    if case .tab? = source.node(id) { true } else { false }
  }

  private func isPane(_ id: NodeID) -> Bool {
    if case .split? = source.parent(of: id) { true } else { false }
  }

  // MARK: Context menu

  public func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    for item in self.menu(forRow: outlineView.clickedRow)?.items ?? [] {
      item.menu?.removeItem(item)
      menu.addItem(item)
    }
  }

  /// The context menu of `row`, nil for rows without one (folders, the divider). A split row: Separate
  /// All Tabs, Convert to Vertical / Horizontal Split View and Duplicate Split View (BH-120, BH-121, BH-126); a pane
  /// row: Remove Tab from Split View (BH-121, [S] string); any other tab row: Move To > Favorites (BH-047), then the
  /// pin items (BH-055) and, for pinned tabs, the reset family (BH-057, BH-060, BH-061; [S] strings).
  /// Mute, Share and Archive Below are deferred (BH-126); the full menu set is #105.
  func menu(forRow row: Int) -> NSMenu? {
    guard row >= 0, let id = (outlineView.item(atRow: row) as? OutlineItem)?.nodeID else { return nil }
    let menu = NSMenu()
    menu.autoenablesItems = false
    switch source.node(id) {
    case .split(_, let layout)?:
      menu.addItem(menuItem("Separate All Tabs", #selector(separateSplitChosen(_:)), id))
      menu.addItem(menuItem(SplitMenu.convertTitle(for: layout.orientation), #selector(convertSplitChosen(_:)), id))
      menu.addItem(menuItem("Duplicate Split View", #selector(duplicateSplitChosen(_:)), id))   // [I] title
    case .tab? where isPane(id):
      menu.addItem(menuItem("Remove Tab from Split View", #selector(removePaneChosen(_:)), id))
    case .tab?:
      menu.addItem(moveToItem(id))
      switch source.parent(of: id) {
      case .today?:
        menu.addItem(menuItem("Pin Tab", #selector(pinToggleChosen(_:)), id))
      case .pinned?:
        menu.addItem(menuItem("Unpin Tab", #selector(pinToggleChosen(_:)), id))
        addResetItems(to: menu, for: id)
      case .folder?:
        addResetItems(to: menu, for: id)          // foldered tabs are pinned through their folder
      default:
        break
      }
    default:
      return nil
    }
    return menu
  }

  /// Back to Pinned URL, Replace Pin with Current Page and Separate From Pinned Tab (BH-057, BH-060, BH-061);
  /// enabled only while the tab sits away from its pinned URL.
  private func addResetItems(to menu: NSMenu, for id: NodeID) {
    let navigated = pinnedNavigatedProvider?(id) ?? false
    menu.addItem(.separator())
    for (title, action) in [("Back to Pinned URL", #selector(resetPinnedChosen(_:))),
                            ("Replace Pin with Current Page", #selector(replacePinChosen(_:))),
                            ("Separate From Pinned Tab", #selector(separateFromPinnedChosen(_:)))] {
      let item = menuItem(title, action, id)
      item.isEnabled = navigated
      menu.addItem(item)
    }
  }

  /// "Move To" with its submenu (BH-047): Favorites; the Spaces join it with #105 (BH-042).
  private func moveToItem(_ id: NodeID) -> NSMenuItem {
    let item = NSMenuItem(title: "Move To", action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    submenu.addItem(menuItem("Favorites", #selector(moveToFavoritesChosen(_:)), id))
    item.submenu = submenu
    return item
  }

  private func menuItem(_ title: String, _ action: Selector, _ id: NodeID) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.representedObject = id
    return item
  }

  @objc private func separateSplitChosen(_ sender: NSMenuItem) { chosen(sender, onSeparateSplit) }
  @objc private func convertSplitChosen(_ sender: NSMenuItem) { chosen(sender, onConvertSplit) }
  @objc private func duplicateSplitChosen(_ sender: NSMenuItem) { chosen(sender, onDuplicateSplit) }
  @objc private func removePaneChosen(_ sender: NSMenuItem) { chosen(sender, onRemovePane) }
  @objc private func moveToFavoritesChosen(_ sender: NSMenuItem) { chosen(sender, onMoveToFavorites) }
  @objc private func pinToggleChosen(_ sender: NSMenuItem) { chosen(sender, onPinToggle) }
  @objc private func resetPinnedChosen(_ sender: NSMenuItem) { chosen(sender, onResetPinned) }
  @objc private func replacePinChosen(_ sender: NSMenuItem) { chosen(sender, onReplacePin) }
  @objc private func separateFromPinnedChosen(_ sender: NSMenuItem) { chosen(sender, onSeparateFromPinned) }

  private func chosen(_ item: NSMenuItem, _ handler: (@MainActor (NodeID) -> Void)?) {
    guard let id = item.representedObject as? NodeID, source.node(id) != nil else { return }
    handler?(id)
  }

  // MARK: Close

  /// The X of a row's cell: on a pane row it removes the pane from its split (BH-121); on any other row it runs the
  /// window's close, as Cmd-W does. Opt-click unsplitting a split (BH-127) is gated behind an Arc flag and
  /// NEEDS-RUNTIME-CHECK (RT-22), so it is not implemented: an Opt-click acts like a plain click.
  @objc private func closeClicked(_ sender: NSButton) {
    let row = outlineView.row(for: sender)
    guard row >= 0, let id = (outlineView.item(atRow: row) as? OutlineItem)?.nodeID else { return }
    closeAction(for: id)?(id)
  }

  /// Where a row's X (and its VoiceOver equivalent) goes: `onRemovePane` on a pane row, else `onClose`.
  private func closeAction(for id: NodeID) -> (@MainActor (NodeID) -> Void)? {
    RowCloseAction.resolve(id, in: source) == .removeFromSplit ? onRemovePane : onClose
  }

  /// VoiceOver actions of a row: the X's action ("Close", "Archive", or "Remove Tab from Split View" on a pane row),
  /// plus "Separate All Tabs" on a split row; none for folders and the divider. The row's proxy lists their names and
  /// performs one through `performAccessibilityAction(named:on:)`.
  func accessibilityActions(for id: NodeID?) -> [NSAccessibilityCustomAction] {
    guard let id else { return [] }
    var actions: [NSAccessibilityCustomAction] = []
    if let action = RowCloseAction.resolve(id, in: source) {
      actions.append(customAction(action.accessibilityName, id) { $0.closeAction(for: id) })
    }
    if case .split? = source.node(id) {
      actions.append(customAction("Separate All Tabs", id) { $0.onSeparateSplit })
    }
    return actions
  }

  /// Runs the row action called `name` on `id`; false when the node is gone or has no such action.
  func performAccessibilityAction(named name: String, on id: NodeID) -> Bool {
    accessibilityActions(for: id).first { $0.name == name }?.handler?() ?? false
  }

  private func customAction(
    _ name: String, _ id: NodeID,
    _ handler: @escaping @MainActor (SidebarOutlineController) -> (@MainActor (NodeID) -> Void)?
  ) -> NSAccessibilityCustomAction {
    NSAccessibilityCustomAction(name: name) { [weak self] in
      guard let self, self.source.node(id) != nil else { return false }
      handler(self)?(id)
      return true
    }
  }
}
