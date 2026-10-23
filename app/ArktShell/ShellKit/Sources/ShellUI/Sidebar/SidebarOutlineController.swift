import AppKit

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
public final class SidebarOutlineView: NSOutlineView {
  public override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

  public override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
    let full = super.frameOfCell(atColumn: column, row: row)
    let indent = CGFloat(max(0, level(forRow: row))) * indentationPerLevel
    let rowRect = rect(ofRow: row)
    return NSRect(x: rowRect.minX + indent, y: full.minY, width: max(0, rowRect.width - indent), height: full.height)
  }

  public override func mouseDown(with event: NSEvent) {
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
public final class SidebarOutlineController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
  public let source: any SidebarSource
  public let spaceID: SpaceID
  public let outlineView: SidebarOutlineView
  public var flavor: ThemeFlavor = .light
  public private(set) var resolver: TabRowState.Resolver = .empty

  /// A tab or split row was clicked (folders toggle in place).
  public var onActivate: (@MainActor (NodeID) -> Void)?
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

  // MARK: Delegate

  public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    (item as? OutlineItem)?.kind == .divider ? SidebarMetrics.dividerHeight : SidebarMetrics.rowPitch
  }

  public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    let row = outlineView.makeView(withIdentifier: SidebarRowView.reuseIdentifier, owner: self) as? SidebarRowView
      ?? SidebarRowView(frame: .zero)
    configure(row, for: item as? OutlineItem)
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
    cell.configure(title: title, image: image, flavor: flavor)
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
        cell.configure(title: title, image: image, flavor: self.flavor)
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
    for change in difference.insertions {
      if case .insert(let offset, _, _) = change, let id = new[offset].nodeID,
         source.node(id)?.childLocation != nil {
        outlineView.expandItem(new[offset])
      }
    }
  }

  // MARK: Clicks

  @objc private func rowClicked(_ sender: Any?) {
    let row = outlineView.clickedRow
    guard row >= 0, let item = outlineView.item(atRow: row) as? OutlineItem, let id = item.nodeID else { return }
    if case .folder? = source.node(id) {
      if outlineView.isItemExpanded(item) { outlineView.collapseItem(item) } else { outlineView.expandItem(item) }
      return
    }
    onActivate?(id)
  }
}
