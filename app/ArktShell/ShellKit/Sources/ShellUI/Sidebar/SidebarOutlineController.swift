import AppKit
import Carbon.HIToolbox

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
  /// Takes this outline's drags and drops (#104); the controller's `drop`.
  weak var dropHandler: SidebarOutlineDrop?

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

  /// A row's hover state changed (the pointer entered or left it); the controller turns it into Folder Preview's
  /// hover (BH-093).
  var onRowHover: (@MainActor (_ row: Int, _ hovered: Bool) -> Void)?

  func rowHoverChanged(_ rowView: NSTableRowView, hovered: Bool) {
    let row = self.row(for: rowView)
    guard row >= 0 else { return }
    onRowHover?(row, hovered)
  }

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
    keyboardFocusRow = nil                       // the next pointer click removes the keyboard focus ring
    commitRenameInProgress()                     // any click, a Ctrl-click too, ends a rename first
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
    guard row >= 0 else {
      emptyAreaMouseDown(event)
      return
    }
    let rowView = row >= 0 ? self.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView : nil
    rowView?.isPressed = true
    super.mouseDown(with: event)
    rowView?.isPressed = false
  }

  // MARK: Empty area (BH-021, BH-023)

  /// A double-click on the outline below or between rows (BH-021): the window opens the command bar for a new tab.
  var onEmptyAreaDoubleClick: (@MainActor () -> Void)?
  /// A plain press on empty outline space; the controller ends the multi-selection.
  var onEmptyAreaClick: (@MainActor () -> Void)?
  /// Drags the window from empty outline space (BH-023); tests replace it, since a drag runs a tracking loop.
  var performWindowDrag: @MainActor (NSEvent, NSWindow?) -> Void = { event, window in window?.performDrag(with: event) }

  /// The same empty area moves the window and opens a new tab (design 4.3): the gesture decides. A press that moves
  /// drags; a second click without motion is a double-click.
  private func emptyAreaMouseDown(_ event: NSEvent) {
    if clickModifiers.intersection([.command, .shift]).isEmpty { onEmptyAreaClick?() }
    if event.clickCount == 2 {
      onEmptyAreaDoubleClick?()
    } else {
      performWindowDrag(event, window)
    }
  }

  /// A right-click ends a rename in progress first too, as a left click does.
  public override func rightMouseDown(with event: NSEvent) {
    commitRenameInProgress()
    super.rightMouseDown(with: event)
  }

  /// A click anywhere in the outline ends a rename in progress first, keeping the typed name (design 4.1): the
  /// outline itself never takes first responder from the field, so the field would stay open otherwise.
  private func commitRenameInProgress() {
    guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor,
          let field = editor.delegate as? NSView, field.isDescendant(of: self) else { return }
    window?.makeFirstResponder(nil)
  }

  // MARK: Keyboard focus (BH-019, BH-020)

  /// The row that holds keyboard focus after Ctrl-Space, drawn with the focus ring; nil otherwise. Selection stays off
  /// (`shouldSelectItem`), so this is the outline's only keyboard cursor.
  public internal(set) var keyboardFocusRow: Int? {
    didSet {
      guard keyboardFocusRow != oldValue else { return }
      updateKeyboardFocusRing()
    }
  }
  /// The ring on the focused row: the system focus ring's color (`NSColor.keyboardFocusIndicatorColor`, which follows
  /// the user's accent color) and width, never mustard. Drawn here because a table view ignores a row-sized focus
  /// ring mask (it rings the whole table or nothing). Inset into the row fill so the clip view never cuts it.
  let keyboardFocusRing = KeyboardFocusRingView(frame: .zero)
  /// Whether Up and Down may stop on a row (the divider may not).
  var isKeyboardFocusable: @MainActor (Int) -> Bool = { _ in true }
  /// Return on the focused row.
  var onKeyboardReturn: (@MainActor (Int) -> Void)?
  /// Esc: focus goes back to the page.
  var onKeyboardEscape: (@MainActor () -> Void)?
  /// Up or Down moved the focus row; the window scrolls it into view the way every keyboard reveal does.
  var onKeyboardFocusMoved: (@MainActor (Int) -> Void)?
  /// Up passed the first focusable row; the window hands focus to the Favorites grid above (#343).
  var onKeyboardFocusAbove: (@MainActor () -> Void)?

  /// The focused row's fill, where the ring is drawn.
  func keyboardFocusRect(_ row: Int) -> NSRect {
    rect(ofRow: row).insetBy(dx: 0, dy: SidebarMetrics.rowBackgroundInsetY)
  }

  /// Places the ring on the focused row (or hides it), above the rows.
  func updateKeyboardFocusRing() {
    guard let row = keyboardFocusRow, row < numberOfRows else {
      keyboardFocusRing.isHidden = true
      return
    }
    if keyboardFocusRing.superview !== self { addSubview(keyboardFocusRing, positioned: .above, relativeTo: nil) }
    keyboardFocusRing.frame = keyboardFocusRect(row)
    keyboardFocusRing.isHidden = false
    keyboardFocusRing.needsDisplay = true
  }

  public override func layout() {
    super.layout()
    if keyboardFocusRow != nil { updateKeyboardFocusRing() }
  }

  /// Up / Down move the focus row, Return opens it, Esc gives focus back to the page. Without keyboard focus the
  /// outline handles keys as before.
  public override func keyDown(with event: NSEvent) {
    guard let row = keyboardFocusRow else {
      super.keyDown(with: event)
      return
    }
    switch Int(event.keyCode) {
    case kVK_DownArrow: moveKeyboardFocus(from: row, by: 1)
    case kVK_UpArrow: moveKeyboardFocus(from: row, by: -1)
    case kVK_Return, kVK_ANSI_KeypadEnter: onKeyboardReturn?(row)
    case kVK_Escape: onKeyboardEscape?()
    case kVK_LeftArrow, kVK_RightArrow: break                         // horizontal movement belongs to the grid
    default: super.keyDown(with: event)
    }
  }

  private func moveKeyboardFocus(from row: Int, by step: Int) {
    var next = row + step
    while next >= 0, next < numberOfRows, !isKeyboardFocusable(next) { next += step }
    guard next >= 0, next < numberOfRows else {
      if step < 0 { onKeyboardFocusAbove?() }
      return
    }
    keyboardFocusRow = next
    onKeyboardFocusMoved?(next)
  }

  /// Only Ctrl-Space makes the outline the key view (a click never did: selection is off), so it accepts first
  /// responder only while it holds a keyboard focus row.
  public override var acceptsFirstResponder: Bool { keyboardFocusRow != nil }

  public override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { keyboardFocusRow = nil }
    return resigned
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
  /// Every context menu action the outline does not run through the callbacks above (#105); the window runs it.
  public var onMenuAction: (@MainActor (SidebarMenuAction) -> Void)?
  /// Double-click on empty outline space (BH-021); the window opens the command bar for a new tab.
  public var onEmptyAreaDoubleClick: (@MainActor () -> Void)? {
    get { outlineView.onEmptyAreaDoubleClick }
    set { outlineView.onEmptyAreaDoubleClick = newValue }
  }
  /// The URL on the clipboard, if any (Paste URL as New Tab, KB-016); tests replace it.
  var clipboardURL: @MainActor () -> URL? = {
    NSPasteboard.general.string(forType: .string).flatMap {
      URLInputParser.url(from: $0.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }
  /// This outline as a drag source and drop target (#104).
  public private(set) lazy var drop = SidebarOutlineDrop(controller: self)
  /// A row started a drag (S7, GS-011); the window shows its drop overlays.
  public var onNodeDragBegan: (@MainActor (NodeID) -> Void)?
  /// The drag that `onNodeDragBegan` reported ended, dropped or not.
  public var onNodeDragEnded: (@MainActor () -> Void)?
  /// Favicon for a tab, nil = letter placeholder.
  public var faviconProvider: (@MainActor (NodeID) -> NSImage?)?
  /// True while the row's page close is held behind a leave-site prompt (week-3 Decision 11).
  public var closingProvider: (@MainActor (NodeID) -> Bool)?
  /// The sound of the row's page (#364); nil means silent.
  public var audioProvider: (@MainActor (NodeID) -> TabAudio)?
  /// True while the row's tab has a page open; the menu's Mute needs one (#364).
  public var loadedProvider: (@MainActor (NodeID) -> Bool)?

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
  /// Each container's children as the source last reported them (split titles and states, BH-092 move-ins).
  private var containerChildren: [NodeID: [NodeID]] = [:]
  /// Each container's children as this outline lists them (`display`): what the data source answers.
  private var shownChildren: [NodeID: [NodeID]] = [:]
  /// Open, closed, closing and peeking folders of this outline (per window, BH-098); collapsed folders are preserved
  /// across moves and sibling removals (#94).
  private var display = FolderDisplay()
  /// The open and close springs of this outline's folders (#109).
  let folderMotion = FolderMotion()
  /// The style each row draws in the current folder motion frame; rows realized mid-motion take theirs from here.
  /// Keyed by outline item, so the Pinned / Today divider row moves with the rows around it.
  private var rowStyles: [ObjectIdentifier: FolderMotionLayout.RowStyle] = [:]
  /// Rows a Reduce Motion open shows that had no row view yet; they fade in when it is added.
  private var pendingFades: Set<NodeID> = []
  /// Folder rows drawn above the rows sliding under them.
  private var raisedRows: Set<NodeID> = []
  /// The current tab this outline last saw, so a change ends the previous peek.
  private var peekedCurrent: NodeID?

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
    outlineView.doubleAction = #selector(rowDoubleClicked(_:))
    outlineView.onEmptyAreaClick = { [weak self] in self?.clearSelection() }   // a plain click ends it (design 6)
    outlineView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)   // Option copies (GS-014)
    outlineView.setDraggingSourceOperationMask([], forLocal: false)   // rows stay inside the app
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
    outlineView.isKeyboardFocusable = { [weak self] row in self?.isKeyboardFocusable(row: row) ?? false }
    outlineView.onKeyboardReturn = { [weak self] row in self?.keyboardReturn(on: row) }
    outlineView.onKeyboardEscape = { [weak self] in
      self?.outlineView.keyboardFocusRow = nil
      self?.onKeyboardFocusExit?()
    }
    scrollView.documentView = outlineView
    outlineView.dropHandler = drop
    outlineView.reloadData()
    syncAllFolders()
    folderMotion.onFrame = { [weak self] progress in self?.presentFolderMotion(progress) }
    folderMotion.onSettle = { [weak self] folder, open in self?.folderMotionSettled(folder, open: open) }
    outlineView.onRowHover = { [weak self] row, hovered in
      guard let self, let id = self.nodeID(atRow: row), case .folder? = self.source.node(id) else { return }
      self.onFolderHover?(id, hovered)
    }
  }

  /// The pointer entered or left a folder row (Folder Preview, BH-093).
  public var onFolderHover: (@MainActor (NodeID, Bool) -> Void)?
  /// A folder of this outline opened or closed.
  public var onFoldersChanged: (@MainActor () -> Void)?

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

  /// Folders the user collapsed in this outline; the keyboard skips their tabs (`SidebarTabOrder`).
  public var collapsedFolderIDs: Set<NodeID> { display.collapsed }

  /// Opens every collapsed folder that holds `id` (BH-019) and returns its row, or nil when this outline does not
  /// show it. A keyboard reveal: no motion.
  @discardableResult
  public func expandAncestors(of id: NodeID) -> Int? {
    var folders: Set<NodeID> = []
    var location = source.parent(of: id)
    for _ in 0..<64 {                                 // depth guard against a malformed source
      guard let container = location?.containerNode else { break }
      if case .folder? = source.node(container) { folders.insert(container) }
      location = source.parent(of: container)
    }
    let next = display.collapsed.subtracting(folders)
    if next != display.collapsed { setCollapsed(next, animated: false) }
    let found = row(for: id)
    return found >= 0 ? found : nil
  }

  /// Whether keyboard focus may sit on `row` (tabs, folders and splits; not the divider).
  public func isKeyboardFocusable(row: Int) -> Bool { nodeID(atRow: row) != nil }

  /// Keyboard focus left the outline through Return or Esc; the window gives focus back to the page.
  public var onKeyboardFocusExit: (@MainActor () -> Void)?

  /// Ctrl-Space: keyboard focus on `row` with the system focus ring (BH-019). The window makes the outline first
  /// responder.
  public func focusKeyboard(on row: Int) {
    outlineView.keyboardFocusRow = row
  }

  /// Return on the focused row (RT-13 assumed): a folder opens or closes in place and keeps the focus; a tab or split
  /// opens and focus goes back to the page.
  private func keyboardReturn(on row: Int) {
    guard let id = nodeID(atRow: row) else { return }
    if case .folder? = source.node(id) {
      clearSelection()
      toggleFolder(id, animated: false)               // a keyboard action never animates
      return
    }
    outlineView.keyboardFocusRow = nil
    onActivate?(id)
    onKeyboardFocusExit?()
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
    return shown(id).count
  }

  public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    guard let item = item as? OutlineItem, let id = item.nodeID else { return rootItems[index] }
    return self.item(for: shown(id)[index])
  }

  /// The children the outline lists under `id`: answered from `shownChildren`, filled from `display` on first ask.
  private func shown(_ id: NodeID) -> [NodeID] {
    if let listed = shownChildren[id] { return listed }
    _ = children(of: id)                              // remembers the source's list for later diffs
    let fresh = display.children(of: id, in: source)
    shownChildren[id] = fresh
    return fresh
  }

  public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    guard let id = (item as? OutlineItem)?.nodeID else { return false }
    return source.node(id)?.childLocation != nil
  }

  // MARK: Drag source (S7, #104)

  /// Every node row is dragged (#104; the divider is not). It writes its id under `.sidebarNode`, which the page and
  /// Favorites overlays read, and the whole drag under `.sidebarNodes`: the multi-selection when the row is part of
  /// one (#105), else the row alone.
  public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any)
    -> (any NSPasteboardWriting)? {
    guard let id = (item as? OutlineItem)?.nodeID, source.node(id) != nil else { return nil }
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(id.uuidString, forType: .sidebarNode)
    pasteboardItem.setString(dragPayload(startingAt: id).pasteboardString, forType: .sidebarNodes)
    return pasteboardItem
  }

  public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                          willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
    draggingSessionWillBegin(items: draggedItems, session: session)
  }

  public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                          endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    drop.sourceEnded(at: screenPoint, operation: operation)
    draggingSessionEnded()
  }

  /// Rows cannot be selected in the table's sense, so a drag starts on one row: the first node among `items`. It
  /// carries the multi-selection when that row is part of it.
  func draggingSessionWillBegin(items: [Any], session: NSDraggingSession? = nil) {
    let ids = items.compactMap { ($0 as? OutlineItem)?.nodeID }
    guard let id = ids.first(where: { source.node($0) != nil }) else { return }
    drop.sourceBegan(dragPayload(startingAt: id), session: session)
    onNodeDragBegan?(id)
  }

  func draggingSessionEnded() { onNodeDragEnded?() }

  /// The selection in display order when `id` is one of two or more selected rows, else `id`.
  private func dragPayload(startingAt id: NodeID) -> SidebarDragPayload {
    let nodes = selection.count >= 2 && selection.contains(id) ? selectedNodes : [id]
    return SidebarDragPayload(nodes: nodes, isSingleTab: nodes.count == 1 && isTab(nodes[0]))
  }

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
    cell.audioButton.target = self
    cell.audioButton.action = #selector(audioClicked(_:))
    return cell
  }

  /// A row held closing has no X: a second close would do nothing (Decision 11).
  private func configure(_ cell: SidebarTabCellView, for id: NodeID) {
    let (title, image) = presentation(of: id)
    let closing = closingProvider?(id) ?? false
    cell.configure(title: title, image: image, flavor: flavor,
                   closeAction: closing ? nil : RowCloseAction.resolve(id, in: source), isClosing: closing,
                   audio: audio(of: id))
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
      let symbol = display.collapsed.contains(id) ? "folder" : "folder.fill"
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

  func nodeID(atRow row: Int) -> NodeID? {
    (outlineView.item(atRow: row) as? OutlineItem)?.nodeID
  }

  private func accessibilityContent(ofRow row: Int) -> AXProxyRowContent? {
    guard let item = outlineView.item(atRow: row) as? OutlineItem else { return nil }
    guard let id = item.nodeID else {
      return AXProxyRowContent(identifier: AXID.Sidebar.divider, label: "", role: .separator)
    }
    // A closed folder with a row peeking out is expanded in the outline but closed to the user.
    let isExpanded: Bool? = switch source.node(id) {
    case .folder?: isFolderOpen(id)
    case .split?: outlineView.isItemExpanded(item)
    case .tab?, nil: nil
    }
    return AXProxyRowContent(
      identifier: rowIdentifier(for: id), label: title(of: id),
      value: (closingProvider?(id) ?? false) ? "Closing" : nil,
      disclosureLevel: max(0, outlineView.level(forRow: row)),
      isExpanded: isExpanded)
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

  /// The state a row draws: a selected row takes the `contentVisible` fill (design 6, OQ9) unless it is current,
  /// which wins.
  func displayedState(for id: NodeID) -> TabRowState {
    let base = state(for: id)
    return selection.contains(id) && base != .current ? .contentVisible : base
  }

  /// Row configurations so far (tests check that state pushes touch only changed rows).
  private(set) var rowConfigureCount = 0

  private func configure(_ row: SidebarRowView, for item: OutlineItem?) {
    rowConfigureCount += 1
    row.flavor = flavor
    if let id = item?.nodeID {
      row.isInteractive = true
      row.state = displayedState(for: id)
    } else {
      row.isInteractive = false
      row.state = .normal
    }
    let id = item?.nodeID
    applyStyle(item.flatMap { rowStyles[ObjectIdentifier($0)] } ?? .rest, raised: id.map(raisedRows.contains) ?? false,
               to: row)
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
    if resolver.current != peekedCurrent { currentChanged() }
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

  /// A live change of a row's sound (#364): a realized cell fades its audio button in place, without a reload; a row
  /// not on screen picks the state up from `audioProvider` when its cell is made.
  public func audioChanged(node id: NodeID) {
    guard let item = items[id] else { return }
    let row = outlineView.row(forItem: item)
    guard row >= 0, let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
            as? SidebarTabCellView else { return }
    cell.setAudio(audio(of: id), animated: true)
  }

  /// Refreshes one row's cell (title or favicon) without touching any other row.
  public func reload(node id: NodeID) {
    if id == renamingNode {
      renameReloadPending = true             // a reload would replace the cell and close the field
      return
    }
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
    // The row mutations below drop the proxies too; this also covers a change that moves no row. A folder in motion
    // may have left with the change, so the motion frame is presented again for the rows that remain.
    defer {
      outlineView.axProxyRows.invalidate()
      presentFolderMotion(folderMotion.progress())
    }
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
      // BH-092: a tab (or split) moved into a closed folder peeks out under it; the folder stays closed (BH-091). A
      // moved folder does not peek itself; the current tab inside it does.
      if case .folder = location, !display.settled.isEffectivelyOpen(id, in: source) {
        for added in new where !old.contains(added) {
          switch source.node(added) {
          case .tab?, .split?: display.peeks.insert(added)
          case .folder?, nil: break
          }
        }
        peekCurrent(in: &display)
        syncAllFolders()                              // the folders above it list the new path too
      } else {
        syncDisplay(id)
      }
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
        syncDisplay(id)
      }
    }
    pruneSelection()
  }

  /// Drops the cached item and child lists of `id` and of its cached descendants that left the source.
  private func forget(_ id: NodeID) {
    if let item = items[id] { rowStyles[ObjectIdentifier(item)] = nil }
    items[id] = nil
    display.collapsed.remove(id)
    display.closing.remove(id)
    display.peeks.remove(id)
    pendingFades.remove(id)
    raisedRows.remove(id)
    if folderMotion.isMoving(id) { folderMotion.cancel(id) }
    shownChildren[id] = nil
    for child in containerChildren.removeValue(forKey: id) ?? [] where source.node(child) == nil {
      forget(child)
    }
  }

  // MARK: Folders (#109)

  /// The key of the Reduce Motion fade on rows a folder shows.
  public static let folderFadeKey = "arkt.folder.fade"

  /// Whether the user has `folder` open in this outline. A closed folder may still list a row peeking out of it.
  public func isFolderOpen(_ folder: NodeID) -> Bool { !display.collapsed.contains(folder) }

  /// Opens a closed folder or closes an open one. `animated`: a pointer toggle, on the folder spring (or, with
  /// Reduce Motion, a fade of the rows it shows); a keyboard toggle passes false and applies at once.
  public func toggleFolder(_ folder: NodeID, animated: Bool) {
    guard case .folder? = source.node(folder) else { return }
    var next = display.collapsed
    if next.remove(folder) == nil { next.insert(folder) }
    setCollapsed(next, animated: animated)
  }

  /// Collapse All Folders / Expand All Folders (BH-097) for this Space.
  public func setAllFolders(open: Bool, animated: Bool) {
    let folders = Set(folders(under: [.pinned(spaceID), .today(spaceID)]))
    setCollapsed(open ? display.collapsed.subtracting(folders) : display.collapsed.union(folders), animated: animated)
  }

  /// Whether this Space has a folder anywhere in Pinned or Today.
  public var hasFolders: Bool { !folders(under: [.pinned(spaceID), .today(spaceID)]).isEmpty }

  /// The style `node`'s row draws in the current folder motion frame.
  func rowStyle(for node: NodeID) -> FolderMotionLayout.RowStyle {
    items[node].flatMap { rowStyles[ObjectIdentifier($0)] } ?? .rest
  }

  /// The style of the row at `row` (the divider too).
  func rowStyle(atRow row: Int) -> FolderMotionLayout.RowStyle {
    styleKey(atRow: row).flatMap { rowStyles[$0] } ?? .rest
  }

  private func styleKey(atRow row: Int) -> ObjectIdentifier? {
    (outlineView.item(atRow: row) as? OutlineItem).map(ObjectIdentifier.init)
  }

  /// Whether `node` sits under any of `folders`.
  private func isInside(_ node: NodeID, anyOf folders: Set<NodeID>) -> Bool {
    var location = source.parent(of: node)
    for _ in 0..<64 {                                 // depth guard against a malformed source
      guard let container = location?.containerNode else { return false }
      if folders.contains(container) { return true }
      location = source.parent(of: container)
    }
    return false
  }

  /// Every folder in `locations`, depth first.
  private func folders(under locations: [SidebarLocation]) -> [NodeID] {
    var found: [NodeID] = []
    var queue = locations.flatMap { source.children(of: $0) }
    var guardCount = 0
    while let id = queue.first, guardCount < 10_000 {
      queue.removeFirst()
      guardCount += 1
      guard case .folder? = source.node(id) else { continue }
      found.append(id)
      queue.insert(contentsOf: source.children(of: .folder(id)), at: 0)
    }
    return found
  }

  /// Moves this outline to `collapsed`. Each folder whose rows appear or disappear and that sits outside every other
  /// such folder gets one spring for its whole block (nested folders closed by Collapse All ride their outer folder's
  /// spring). A closing folder keeps its rows until its spring settles (`display.closing`), so a reversal finds them in
  /// place; an opening one inserts them at once and springs them out from under the folder row.
  private func setCollapsed(_ collapsed: Set<NodeID>, animated: Bool) {
    pendingFades = []
    let before = display
    var target = display
    target.collapsed = collapsed
    target.closing = []
    // A folder that opens takes its peeking rows back; closing it again leaves only the current tab out [I].
    let opened = before.collapsed.subtracting(collapsed)
    if !opened.isEmpty { target.peeks = target.peeks.filter { !isInside($0, anyOf: opened) } }
    peekCurrent(in: &target)
    let tops = changedTops(before: before, after: target)
    let moving = animated && folderMotion.canAnimate(in: outlineView)
    let fades = animated && !moving && outlineView.window?.isVisible == true
    var rowsBefore: [NodeID: [NodeID]] = [:]
    for top in tops { rowsBefore[top] = shownDescendants(of: top) }

    var next = target
    next.closing = before.closing.intersection(collapsed)
    for top in tops {
      let subtree = Set([top] + folders(under: [.folder(top)]))
      if target.isEffectivelyOpen(top, in: source) {
        next.closing.subtract(subtree)                         // an opening folder ends its own close
      } else if moving {
        next.closing.formUnion(subtree.filter { before.isOpen($0) && collapsed.contains($0) })
      }
      if !moving {                                             // applied at once: no spring may follow
        next.closing.subtract(subtree)
        for folder in subtree where folderMotion.isMoving(folder) { folderMotion.cancel(folder) }
      }
    }
    display = next
    syncAllFolders()

    for top in tops {
      let shownBefore = Set(rowsBefore[top] ?? [])
      if target.isEffectivelyOpen(top, in: source) {
        let shownAfter = Set(shownDescendants(of: top))
        let appeared = shownAfter.subtracting(shownBefore)
        if moving {
          let carried = folderMotion.changing[top].map { $0.union(appeared) } ?? appeared
          folderMotion.run(top, open: true, changing: carried.intersection(shownAfter), in: outlineView)
        } else if fades {
          fadeIn(appeared)
        }
      } else if moving {
        var settled = display
        settled.closing.subtract([top] + folders(under: [.folder(top)]))
        let staying = Set(settled.descendants(of: top, in: source))
        folderMotion.run(top, open: false, changing: shownBefore.subtracting(staying), in: outlineView)
      }
    }
    for folder in before.collapsed.symmetricDifference(collapsed) { reload(node: folder) }   // the folder glyph
    presentFolderMotion(folderMotion.progress())
    if before.collapsed != collapsed { onFoldersChanged?() }
  }

  /// The folders whose shown rows change between `before` and `after` (or whose close is reversed while it still
  /// runs), outermost only, in this Space.
  private func changedTops(before: FolderDisplay, after: FolderDisplay) -> [NodeID] {
    var tops: [NodeID] = []
    func visit(_ ids: [NodeID]) {
      for id in ids {
        guard let location = source.node(id)?.childLocation else { continue }
        guard case .folder = location else {
          visit(source.children(of: location))
          continue
        }
        let changed = before.children(of: id, in: source) != after.children(of: id, in: source)
          || before.isEffectivelyOpen(id, in: source) != after.isEffectivelyOpen(id, in: source)
          || (before.closing.contains(id) && after.isOpen(id))
        if changed { tops.append(id) } else { visit(source.children(of: location)) }
      }
    }
    visit(pinnedIDs + todayIDs)
    return tops
  }

  /// The current tab peeks out of the closed folders around it (BH-105, BH-093), in `display` or a target state.
  private func peekCurrent(in state: inout FolderDisplay) {
    guard let current = resolver.current, source.spaceID(containing: current) == spaceID else { return }
    let root = FolderDisplay.peekRoot(of: current, in: source)
    if state.settled.isHidden(root, in: source) { state.peeks.insert(root) }
  }

  /// A new current tab: the previous peeks go back into their folders, and the new tab peeks out if a closed folder
  /// hides it.
  private func currentChanged() {
    peekedCurrent = resolver.current
    var next = display
    next.peeks = []
    peekCurrent(in: &next)
    guard next != display else { return }
    display = next
    syncAllFolders()
    presentFolderMotion(folderMotion.progress())
  }

  /// Brings the outline's rows under every shown container in line with `display`.
  private func syncAllFolders() {
    for item in rootItems {
      if let id = item.nodeID { syncDisplay(id) }
    }
  }

  /// Brings the rows under `id` (and its containers) in line with `display`: inserts and removes exactly the rows
  /// that differ, and expands the item when it lists any row or is open.
  private func syncDisplay(_ id: NodeID) {
    guard source.node(id)?.childLocation != nil else { return }
    let item = item(for: id)
    _ = children(of: id)
    let new = display.children(of: id, in: source)
    let wantsExpanded = !new.isEmpty || display.isEffectivelyOpen(id, in: source)
    if outlineView.isItemExpanded(item) {
      let old = shownChildren[id] ?? []
      if old != new {
        shownChildren[id] = new
        applyDiff(old: old.map { self.item(for: $0) }, new: new.map { self.item(for: $0) }, parent: item)
      }
      if !wantsExpanded { outlineView.collapseItem(item) }
    } else {
      shownChildren[id] = new
      if wantsExpanded { outlineView.expandItem(item) }
    }
    for child in new where source.node(child)?.childLocation != nil { syncDisplay(child) }
  }

  /// The node rows under `folder`'s row, in order; empty when it has no row.
  private func shownDescendants(of folder: NodeID) -> [NodeID] {
    let row = row(for: folder)
    guard row >= 0 else { return [] }
    let level = outlineView.level(forRow: row)
    var rows: [NodeID] = []
    var next = row + 1
    while next < outlineView.numberOfRows, outlineView.level(forRow: next) > level {
      if let id = nodeID(atRow: next) { rows.append(id) }
      next += 1
    }
    return rows
  }

  /// A folder's spring came to rest: a closed one lets its rows go.
  private func folderMotionSettled(_ folder: NodeID, open: Bool) {
    guard !open else { return }
    display.closing.subtract([folder] + folders(under: [.folder(folder)]))
    syncAllFolders()
  }

  // MARK: Arrival (#352)

  /// A row arriving from Little Arkt's Open in flight: the rows below make room (`room`, 0 to 1) and the row fades
  /// in (`appear`, 0 to 1), on the flight's clock. Nil when no row is arriving.
  private var arrival: (node: NodeID, room: Double, appear: Double)?

  /// One frame of `node`'s arrival at the top of Today, applied with the folder motion frame.
  public func presentArrival(of node: NodeID, room: Double, appear: Double) {
    arrival = (node, room, appear)
    presentFolderMotion(folderMotion.progress())
  }

  /// The arrival ended: every row draws at rest (with any folder motion still running).
  public func endArrival() {
    guard arrival != nil else { return }
    arrival = nil
    presentFolderMotion(folderMotion.progress())
  }

  /// One frame of the folder springs: each realized row gets its offset and opacity as layer properties (never a
  /// frame change, which would rebuild tracking areas and layout every frame).
  private func presentFolderMotion(_ progress: [NodeID: Double]) {
    var transitions: [FolderMotionLayout.Transition] = []
    var raised: Set<NodeID> = []
    for (folder, value) in progress {
      guard let changing = folderMotion.changing[folder], row(for: folder) >= 0 else { continue }
      let rows = Set(changing.map { row(for: $0) }.filter { $0 >= 0 })
      transitions.append(FolderMotionLayout.Transition(changingRows: rows, progress: value))
      raised.insert(folder)
    }
    var styles: [ObjectIdentifier: FolderMotionLayout.RowStyle] = [:]
    let arrivalRow = arrival.map { row(for: $0.node) } ?? -1
    if !transitions.isEmpty || arrivalRow >= 0 {
      let heights = (0..<outlineView.numberOfRows).map { outlineView.rect(ofRow: $0).height }
      var frame = FolderMotionLayout.styles(rowHeights: heights, transitions: transitions)
      if let arrival, arrivalRow >= 0 {
        SidebarArrivalLayout.apply(to: &frame, rowHeights: heights, arrivalRow: arrivalRow, room: arrival.room,
                                   appear: arrival.appear)
      }
      for (row, style) in frame.enumerated() where style != .rest {
        if let key = styleKey(atRow: row) { styles[key] = style }
      }
    }
    guard styles != rowStyles || raised != raisedRows else { return }
    rowStyles = styles
    raisedRows = raised
    outlineView.enumerateAvailableRowViews { rowView, row in
      let id = self.nodeID(atRow: row)
      self.applyStyle(self.styleKey(atRow: row).flatMap { styles[$0] } ?? .rest,
                      raised: id.map(raised.contains) ?? false, to: rowView)
    }
  }

  private func applyStyle(_ style: FolderMotionLayout.RowStyle, raised: Bool, to rowView: NSTableRowView) {
    guard let layer = rowView.layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    var transform = style.offsetY == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(0, style.offsetY, 0)
    if style.scale != 1 {
      // About the row's center; a row view's layer keeps its anchor at the origin.
      let center = CGPoint(x: rowView.bounds.midX, y: rowView.bounds.midY)
      transform = CATransform3DTranslate(transform, center.x, center.y, 0)
      transform = CATransform3DScale(transform, style.scale, style.scale, 1)
      transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
    }
    layer.transform = transform
    layer.opacity = Float(style.alpha)
    layer.zPosition = raised ? 1 : 0
    CATransaction.commit()
  }

  /// Reduce Motion: rows a folder shows fade in where they stand, with no movement.
  /// A row without a row view yet fades when the outline adds one (`didAdd`).
  private func fadeIn(_ nodes: Set<NodeID>) {
    for node in nodes {
      let row = row(for: node)
      guard row >= 0 else { continue }
      if let rowView = outlineView.rowView(atRow: row, makeIfNecessary: false) {
        Self.addFade(to: rowView)
      } else {
        pendingFades.insert(node)
      }
    }
  }

  private static func addFade(to rowView: NSTableRowView) {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = Float(0)
    fade.toValue = Float(1)
    fade.duration = 0.15
    fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    rowView.layer?.add(fade, forKey: folderFadeKey)
  }

  public func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
    let id = nodeID(atRow: row)
    applyStyle(styleKey(atRow: row).flatMap { rowStyles[$0] } ?? .rest, raised: id.map(raisedRows.contains) ?? false,
               to: rowView)
    if let id, pendingFades.remove(id) != nil { Self.addFade(to: rowView) }
  }

  // MARK: Clicks

  @objc private func rowClicked(_ sender: Any?) {
    handleClick(row: outlineView.clickedRow, modifiers: outlineView.clickModifiers)
  }

  /// A click on `row`. Folders toggle. Opt-click on a split row separates it (GS-033); Opt-click on the current tab
  /// duplicates it into a split (GS-032). Arc gates both behind `newSplitSeparationMechanismsEnabled` and
  /// `dragToCombineTabsIntoSplitEnabled` [S]; here they are always on [I]. An Opt-click on any other tab, or on a
  /// pane, activates it like a plain click [I]. A click on a pinned tab's favicon goes to the window's reset path
  /// (GS-005, BH-057, BH-058); anywhere else on the row activates it. The recorded click point serves this click
  /// only, so an activation without a mouse-down (an AX press) is never hit-tested against a stale point.
  func handleClick(row: Int, modifiers: NSEvent.ModifierFlags) {
    defer { outlineView.lastClickPoint = nil }
    guard row >= 0, let item = outlineView.item(atRow: row) as? OutlineItem, let id = item.nodeID else { return }
    let flags = modifiers.intersection([.command, .option, .control, .shift])
    let option = flags == .option
    if flags == .command || flags == .shift, isSelectable(id), !isPinnedFaviconClick(row: row, id: id) {
      var next = selection
      if flags == .command {
        next.toggle(id, seed: selectionSeed)
      } else {
        next.extend(to: id, seed: selectionSeed, order: selectableOrder)
      }
      setSelection(next)
      return
    }
    clearSelection()                                  // a plain click collapses the selection (design 6)
    switch source.node(id) {
    case .folder?:
      toggleFolder(id, animated: true)
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

  // MARK: Multi-selection (BH-028, GS-031)

  /// The rows selected with Cmd-click and Shift-click in this outline.
  public private(set) var selection = SidebarSelection()

  /// The selected nodes in display order.
  public var selectedNodes: [NodeID] { selection.ordered(by: displayedNodes) }

  /// Ends the selection (a plain click, a Space switch); only rows that change are redrawn.
  public func clearSelection() {
    guard !selection.isEmpty else { return }
    setSelection(SidebarSelection())
  }

  private func setSelection(_ next: SidebarSelection) {
    let changed = Set(selection.nodes).symmetricDifference(next.nodes)
    selection = next
    guard !changed.isEmpty else { return }
    outlineView.enumerateAvailableRowViews { rowView, row in
      guard let rowView = rowView as? SidebarRowView, let item = self.outlineView.item(atRow: row) as? OutlineItem,
            let id = item.nodeID, changed.contains(id) else { return }
      self.configure(rowView, for: item)
    }
    outlineView.axProxyRows.selectionDidChange()
  }

  /// Selected rows that left the outline (archived, moved, pinned out, collapsed away) leave the selection.
  private func pruneSelection() {
    guard !selection.isEmpty else { return }
    var next = selection
    next.retain { row(for: $0) >= 0 }
    if next != selection { setSelection(next) }
  }

  /// Tabs and splits may be selected; a pane stays with its split and a folder only opens and closes, so no bulk
  /// action ever receives a pane or a folder from a click.
  private func isSelectable(_ id: NodeID) -> Bool {
    switch source.node(id) {
    case .tab?: !isPane(id)
    case .split?: true
    case .folder?, nil: false
    }
  }

  /// Every node row in display order.
  private var displayedNodes: [NodeID] { (0..<outlineView.numberOfRows).compactMap(nodeID(atRow:)) }

  private var selectableOrder: [NodeID] { displayedNodes.filter(isSelectable) }

  /// The current row (a pane: its split), when this outline shows it: the row an empty selection starts from.
  private var selectionSeed: NodeID? {
    guard let current = resolver.current else { return nil }
    let seed = if case .split(let split)? = source.parent(of: current) { split } else { current }
    return row(for: seed) >= 0 && isSelectable(seed) ? seed : nil
  }

  // MARK: Rename (BH-026)

  /// The node whose rename field is open in this outline.
  public private(set) var renamingNode: NodeID?
  private var renameReloadPending = false
  /// The title the row showed when the field opened. Committing it unchanged stores nothing, so an accidental
  /// double-click never freezes the page title as a custom title.
  private var renameOriginalTitle: String?

  /// Double-click on a tab row opens its rename field (BH-026, GS-004). Folders open and close on the first click
  /// and are renamed from their menu; splits have no stored title.
  @objc private func rowDoubleClicked(_ sender: Any?) {
    handleDoubleClick(row: outlineView.clickedRow, modifiers: outlineView.clickModifiers)
  }

  func handleDoubleClick(row: Int, modifiers: NSEvent.ModifierFlags) {
    guard row >= 0, modifiers.intersection([.command, .option, .control, .shift]).isEmpty,
          let id = nodeID(atRow: row), case .tab? = source.node(id) else { return }
    beginRename(id)
  }

  /// Opens the inline rename field on `id`'s row (tabs and folders). The typed name goes to the source on Return or
  /// a click elsewhere; Escape keeps the title. False when the row is not shown or the field could not open.
  @discardableResult
  public func beginRename(_ id: NodeID) -> Bool {
    guard renamingNode == nil else { return false }
    switch source.node(id) {
    case .tab?, .folder?: break
    case .split?, nil: return false
    }
    let row = row(for: id)
    guard row >= 0 else { return false }
    outlineView.scrollRowToVisible(row)
    guard let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarTabCellView
    else { return false }
    renamingNode = id
    renameReloadPending = false
    renameOriginalTitle = Self.shownTitle(of: source.node(id))
    let opened = cell.beginRename(flavor: flavor) { [weak self] typed in self?.finishRename(id, typed: typed) }
    if !opened { renamingNode = nil }
    return opened
  }

  private func finishRename(_ id: NodeID, typed: String?) {
    renamingNode = nil
    let pending = renameReloadPending
    renameReloadPending = false
    let original = renameOriginalTitle
    renameOriginalTitle = nil
    let changed = typed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) != original } ?? false
    if changed { source.renameNode(id, to: typed) }     // persisted by the source (autosave); emits `.node`
    if pending || !changed { reload(node: id) }
  }

  private static func shownTitle(of node: SidebarNodeInfo?) -> String? {
    switch node {
    case .tab(_, _, let title)?, .folder(_, let title)?: title
    default: nil
    }
  }

  // MARK: Context menu (design/tab-context-menus)

  public func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    for item in self.menu(forRow: outlineView.clickedRow)?.items ?? [] {
      item.menu?.removeItem(item)
      menu.addItem(item)
    }
  }

  /// The context menu for a right-click on `row` (-1 and the divider: the empty area). A right-click on a selected
  /// row of a multi-selection gets the multi-selection menu; on any other row the selection ends first and the
  /// row's own menu shows (OQ10, the standard macOS rule).
  func menu(forRow row: Int) -> NSMenu? {
    let target: SidebarMenuTarget
    if row >= 0, let id = nodeID(atRow: row) {
      if selection.count >= 2, selection.contains(id) {
        target = .rows(selectedNodes)
      } else {
        clearSelection()
        target = .rows([id])
      }
    } else {
      target = .empty(spaceID)
    }
    let entries = SidebarContextMenu.entries(for: target, in: source, context: menuContext(for: target))
    return entries.isEmpty ? nil
      : SidebarContextMenu.menu(entries, target: self, action: #selector(menuActionChosen(_:)))
  }

  private func menuContext(for target: SidebarMenuTarget) -> SidebarMenuContext {
    let profile = source.space(spaceID)?.profile
    let spaces = source.spaceOrder.compactMap { id -> (id: SpaceID, title: String)? in
      guard let info = source.space(id), info.profile == profile else { return nil }
      return (id, info.title)
    }
    var navigated: Set<NodeID> = []
    var loaded: Set<NodeID> = []
    var sound: [NodeID: TabAudio] = [:]
    if case .rows(let ids) = target, ids.count == 1, let id = ids.first {
      if pinnedNavigatedProvider?(id) == true { navigated.insert(id) }
      if loadedProvider?(id) == true { loaded.insert(id) }
      sound[id] = audio(of: id)
    }
    return SidebarMenuContext(spaces: spaces, navigatedPins: navigated, clipboardHasURL: clipboardURL() != nil,
                              loadedTabs: loaded, audio: sound)
  }

  @objc private func menuActionChosen(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? SidebarMenuAction else { return }
    perform(action)
  }

  /// Runs a menu action: the row actions that already have callbacks go through them, rename opens here, and every
  /// other action goes to the window.
  func perform(_ action: SidebarMenuAction) {
    switch action {
    case .rename(let id): beginRename(id)
    case .separateSplit(let id): run(onSeparateSplit, on: id)
    case .convertSplit(let id): run(onConvertSplit, on: id)
    case .duplicateSplit(let id): run(onDuplicateSplit, on: id)
    case .removePane(let id): run(onRemovePane, on: id)
    case .resetPinned(let id): run(onResetPinned, on: id)
    case .replacePin(let id): run(onReplacePin, on: id)
    case .separateFromPinned(let id): run(onSeparateFromPinned, on: id)
    case .moveToFavorites(let ids) where ids.count == 1: run(onMoveToFavorites, on: ids[0])
    case .pinToggle(let ids) where ids.count == 1: run(onPinToggle, on: ids[0])
    default: onMenuAction?(action)
    }
  }

  private func run(_ handler: (@MainActor (NodeID) -> Void)?, on id: NodeID) {
    guard source.node(id) != nil else { return }
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

  /// A row's audio button mutes or unmutes its page through the window (#364), like the menu's Mute.
  @objc private func audioClicked(_ sender: NSButton) {
    let row = outlineView.row(for: sender)
    guard row >= 0, let id = (outlineView.item(atRow: row) as? OutlineItem)?.nodeID, source.node(id) != nil else {
      return
    }
    onMenuAction?(.toggleMute(id))
  }

  /// The window's Mute / Unmute, as the row's VoiceOver action runs it.
  private var muteToggle: (@MainActor (NodeID) -> Void)? {
    guard let onMenuAction else { return nil }
    return { onMenuAction(.toggleMute($0)) }
  }

  /// The sound a row shows: only a tab has one.
  private func audio(of id: NodeID) -> TabAudio {
    guard case .tab? = source.node(id) else { return .silent }
    return audioProvider?(id) ?? .silent
  }

  /// Where a row's X (and its VoiceOver equivalent) goes: `onRemovePane` on a pane row, else `onClose`.
  private func closeAction(for id: NodeID) -> (@MainActor (NodeID) -> Void)? {
    RowCloseAction.resolve(id, in: source) == .removeFromSplit ? onRemovePane : onClose
  }

  /// VoiceOver actions of a row: the X's action ("Close", "Archive", or "Remove Tab from Split View" on a pane row),
  /// "Mute" or "Unmute" while the audio button shows (#364), plus "Separate All Tabs" on a split row; none for
  /// folders and the divider. The row's proxy lists their names and
  /// performs one through `performAccessibilityAction(named:on:)`.
  func accessibilityActions(for id: NodeID?) -> [NSAccessibilityCustomAction] {
    guard let id else { return [] }
    var actions: [NSAccessibilityCustomAction] = []
    if let action = RowCloseAction.resolve(id, in: source) {
      actions.append(customAction(action.accessibilityName, id) { $0.closeAction(for: id) })
    }
    let sound = audio(of: id)
    if sound != .silent {
      actions.append(customAction(sound.toggleTitle, id) { $0.muteToggle })
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

/// The keyboard focus ring on a sidebar row (BH-019): a 3 pt stroke in the system focus ring color, following the
/// row fill's rounded shape. Not hit-testable and not an accessibility element.
@MainActor
final class KeyboardFocusRingView: NSView {
  static let lineWidth: CGFloat = 3
  var cornerRadius = SidebarMetrics.rowCornerRadius { didSet { needsDisplay = true } }
  let ring = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    isHidden = true
    ring.fillColor = nil
    ring.lineWidth = Self.lineWidth
    layer?.addSublayer(ring)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var wantsUpdateLayer: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Resolved here so it follows the accent color and the appearance.
  var strokeColor: CGColor {
    var color = NSColor.keyboardFocusIndicatorColor.cgColor
    effectiveAppearance.performAsCurrentDrawingAppearance {
      color = NSColor.keyboardFocusIndicatorColor.withAlphaComponent(1).cgColor
    }
    return color
  }

  override func updateLayer() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let inset = Self.lineWidth / 2
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let radius = max(cornerRadius - inset, 0)
    ring.frame = bounds
    ring.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ring.strokeColor = strokeColor
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    needsDisplay = true
  }
}
