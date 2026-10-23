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
@MainActor
public final class SidebarOutlineView: NSOutlineView, HoverResyncHost {
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

  /// `reloadData()` calls so far (tests check that split edits never reload the whole outline).
  private(set) var reloadDataCount = 0

  public override func reloadData() {
    reloadDataCount += 1
    super.reloadData()
  }

  public override func mouseDown(with event: NSEvent) {
    clickModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    defer { clickModifiers = [] }
    let row = self.row(at: convert(event.locationInWindow, from: nil))
    let rowView = row >= 0 ? self.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView : nil
    rowView?.isPressed = true
    super.mouseDown(with: event)
    rowView?.isPressed = false
  }

  /// Clicks activate rows; the window drags from empty sidebar space only.
  public override var mouseDownCanMoveWindow: Bool { false }
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
  /// A tab row started a drag (S7, GS-011); the window shows its drop overlay above the page.
  public var onNodeDragBegan: (@MainActor (NodeID) -> Void)?
  /// The drag that `onNodeDragBegan` reported ended, dropped or not.
  public var onNodeDragEnded: (@MainActor () -> Void)?
  /// Favicon for a tab, nil = letter placeholder.
  public var faviconProvider: (@MainActor (NodeID) -> NSImage?)?

  private let divider = OutlineItem(.divider)
  private var items: [NodeID: OutlineItem] = [:]
  private var pinnedIDs: [NodeID] = []
  private var todayIDs: [NodeID] = []
  /// Pinned items, the divider, then Today items. Rebuilt only when the pinned or Today ids change.
  private var rootItems: [OutlineItem] = []
  private var containerChildren: [NodeID: [NodeID]] = [:]

  public init(source: any SidebarSource, spaceID: SpaceID) {
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
    outlineView.reloadData()
    for id in pinnedIDs + todayIDs where source.node(id)?.childLocation != nil {
      outlineView.expandItem(item(for: id))
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
    rootItems = pinnedIDs.map(item(for:)) + [divider] + todayIDs.map(item(for:))
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
    row.setAccessibilityCustomActions(accessibilityActions(for: item?.nodeID))
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
    let (title, image) = presentation(of: id)
    cell.configure(title: title, image: image, flavor: flavor, closeAction: RowCloseAction.resolve(id, in: source))
    cell.closeButton.target = self
    cell.closeButton.action = #selector(closeClicked(_:))
    return cell
  }

  public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { false }

  private func presentation(of id: NodeID) -> (String, NSImage) {
    switch source.node(id) {
    case .tab(_, let url, let title)?:
      let image = faviconProvider?(id)
        ?? SidebarGlyphs.letter(for: title, url: url, flavor: flavor, size: SidebarMetrics.faviconSize,
                                scale: outlineView.shellBackingScale)
      return (title, image)
    case .folder(_, let title)?:
      return (title, SidebarGlyphs.symbol("folder", flavor: flavor, scale: outlineView.shellBackingScale))
    case .split?:
      let titles = children(of: id).compactMap { child -> String? in
        if case .tab(_, _, let title)? = source.node(child) { return title }
        return nil
      }
      return (titles.joined(separator: " | "), SidebarGlyphs.symbol("rectangle.split.2x1", flavor: flavor,
                                                                 scale: outlineView.shellBackingScale))
    case nil:
      return ("", SidebarGlyphs.symbol("questionmark.square", flavor: flavor, scale: outlineView.shellBackingScale))
    }
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

  /// Pushes new row states to the realized row views only.
  /// Only rows whose state changed are touched (a split row when any of its panes changed); a page whose
  /// rows are all unaffected is left alone.
  public func setRowStates(_ resolver: TabRowState.Resolver) {
    let changed = resolver.changedNodes(from: self.resolver)
    self.resolver = resolver
    guard !changed.isEmpty else { return }
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
        let (title, image) = self.presentation(of: id)
        cell.configure(title: title, image: image, flavor: self.flavor,
                       closeAction: RowCloseAction.resolve(id, in: self.source))
      } else if let divider = self.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
                  as? SidebarDividerView {
        divider.flavor = self.flavor
      }
    }
  }

  /// Refreshes one row's cell (title or favicon) without touching any other row.
  public func reload(node id: NodeID) {
    guard let existing = items[id], outlineView.row(forItem: existing) >= 0 else { return }
    outlineView.reloadItem(existing, reloadChildren: false)
    if let container = source.parent(of: id)?.containerNode, case .split? = source.node(container),
       let splitItem = items[container] {
      outlineView.reloadItem(splitItem, reloadChildren: false)   // split titles derive from their panes
    }
  }

  // MARK: Changes

  /// A location's child list changed: insert / remove exactly the rows that differ, reload nothing else.
  /// Ignores locations outside this Space. (Node-level changes go to `reload(node:)`.)
  public func apply(structure location: SidebarLocation) {
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
      if case .insert(let offset, _, _) = change, let id = new[offset].nodeID,
         source.node(id)?.childLocation != nil {
        outlineView.expandItem(new[offset])
      }
    }
  }

  /// Drops the cached item and child list of `id` and of its cached descendants that left the source.
  private func forget(_ id: NodeID) {
    items[id] = nil
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
  /// pane, activates it like a plain click [I].
  func handleClick(row: Int, modifiers: NSEvent.ModifierFlags) {
    guard row >= 0, let item = outlineView.item(atRow: row) as? OutlineItem, let id = item.nodeID else { return }
    let option = modifiers.intersection([.command, .option, .control, .shift]) == .option
    switch source.node(id) {
    case .folder?:
      if outlineView.isItemExpanded(item) { outlineView.collapseItem(item) } else { outlineView.expandItem(item) }
    case .split? where option:
      onSeparateSplit?(id)
    case .tab? where option && resolver.current == id && !isPane(id):
      onDuplicateIntoSplit?(id)
    case .tab?, .split?:
      onActivate?(id)
    case nil:
      return
    }
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

  /// The context menu of `row`, nil for rows without one (plain tabs, folders, the divider). A split row: Separate
  /// All Tabs, Convert to Vertical / Horizontal Split View and Duplicate Split View (BH-120, BH-121, BH-126); a pane
  /// row: Remove Tab from Split View (BH-121, [S] string). Mute, Share and Archive Below are deferred (BH-126).
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
    default:
      return nil
    }
    return menu
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
  /// plus "Separate All Tabs" on a split row; none for folders and the divider.
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

  private func customAction(_ name: String, _ id: NodeID,
                            _ handler: @escaping @MainActor (SidebarOutlineController) -> (@MainActor (NodeID) -> Void)?)
    -> NSAccessibilityCustomAction {
    NSAccessibilityCustomAction(name: name) { [weak self] in
      guard let self, self.source.node(id) != nil else { return false }
      handler(self)?(id)
      return true
    }
  }
}
