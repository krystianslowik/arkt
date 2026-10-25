import AppKit

/// What one proxy row reports to accessibility clients. It is read from the model for a row index on every query,
/// never copied from a row view, so a row that was never laid out (or was scrolled away and recycled) still has
/// its real label and value.
struct AXProxyRowContent: Equatable, Sendable {
  /// What the element is. A table or outline row is `.row`; a row that only separates groups (the sidebar's
  /// divider between Pinned and Today) is `.separator`, reported as a splitter so clients do not count it as a row.
  enum Role: Equatable, Sendable {
    case row
    case separator
  }

  var identifier: String
  var label: String
  var value: String?
  var role: Role
  /// Outline rows only: the row's depth (0 = top level). Nil for a table row.
  var disclosureLevel: Int?
  /// Outline rows only: whether the row's children are shown. Nil for a row that cannot expand.
  var isExpanded: Bool?

  init(identifier: String, label: String, value: String? = nil, role: Role = .row, disclosureLevel: Int? = nil,
       isExpanded: Bool? = nil) {
    self.identifier = identifier
    self.label = label
    self.value = value
    self.role = role
    self.disclosureLevel = disclosureLevel
    self.isExpanded = isExpanded
  }
}

/// Runs `body` on the main actor when the caller is on the main thread, and returns `fallback` otherwise, without
/// blocking. For the accessibility getters of `AXProxyTable` and `AXProxyRow`: they override `NSAccessibilityElement`
/// methods, which the SDK does not isolate to the main actor, so they are nonisolated. AppKit calls them on the main
/// thread (it services accessibility requests from the main run loop), where this asserts the isolation the call
/// already has. Only `Sendable` values cross: `AXProxyRows` is a main-actor class, and every result is a value.
private func onMainThread<T: Sendable>(
  _ source: AXProxyRows?, default fallback: T, _ body: @MainActor @Sendable (AXProxyRows) -> T
) -> T {
  guard Thread.isMainThread, let source else { return fallback }
  return MainActor.assumeIsolated { body(source) }
}

/// A table (or outline) as one accessibility element whose children are `AXProxyRow`s. `NSTableView` and
/// `NSOutlineView` answer `AXChildren` / `AXRows` out of process from their own internals, without the row views or
/// overridden children (#269), so the container view lists this element in place of the scroll view that holds the
/// real table. It keeps its rows, because accessibility clients hold elements by identity between queries, and
/// rebuilds them when `AXProxyRows.invalidate()` marked them stale or the row count changed.
///
/// The row getters keep the `[Any]?` signatures `NSAccessibilityElement` inherits from the `NSAccessibility`
/// protocol; the element's role comes from `setAccessibilityRole`, not from a role protocol conformance.
final class AXProxyTable: NSAccessibilityElement {
  fileprivate weak var source: AXProxyRows?
  fileprivate weak var parentView: NSView?
  private var cache: [AXProxyRow] = []
  private var isStale = true

  fileprivate init(role: NSAccessibility.Role, identifier: String) {
    super.init()
    setAccessibilityRole(role)
    setAccessibilityIdentifier(identifier)
  }

  fileprivate func markStale() { isStale = true }

  /// One element per table row, in row order, with stable identity until the next reload.
  fileprivate func currentRows() -> [AXProxyRow] {
    let count = onMainThread(source, default: cache.count) { $0.rowCount }
    if isStale || cache.count != count {
      cache = (0..<count).map { AXProxyRow(table: self, row: $0) }
      isStale = false
    }
    return cache
  }

  override func isAccessibilityElement() -> Bool { true }

  override func accessibilityParent() -> Any? { parentView }

  override func accessibilityFrame() -> NSRect {
    onMainThread(source, default: NSRect.zero) { $0.tableScreenFrame }
  }

  override func accessibilityChildren() -> [Any]? { currentRows() }

  override func accessibilityRows() -> [Any]? { currentRows() }

  override func accessibilityRowCount() -> Int { currentRows().count }

  /// The rows that intersect the table's visible rectangle (geometry only; no row view is built).
  override func accessibilityVisibleRows() -> [Any]? {
    let rows = currentRows()
    let visible = onMainThread(source, default: 0..<0) { $0.visibleRowRange }
    let lower = min(max(visible.lowerBound, 0), rows.count)
    let upper = min(max(visible.upperBound, lower), rows.count)
    return Array(rows[lower..<upper])
  }

  override func accessibilitySelectedRows() -> [Any]? {
    let selected = onMainThread(source, default: IndexSet()) { $0.selectedRowIndexes }
    return currentRows().filter { selected.contains($0.accessibilityIndex()) }
  }
}

/// One table row as an accessibility element. Every attribute is computed when asked: identifier, label and value
/// from the model, selection from the table, the frame from the row's rectangle in screen coordinates at that
/// moment, so a moved window never leaves a stale frame behind. A proxy is a leaf unless the owner supplies
/// `children`. In a proxy table of role `.outline` a row reports the `AXOutlineRow` subrole, its disclosure level and
/// whether it is expanded.
final class AXProxyRow: NSAccessibilityElement, NSAccessibilityRow {
  private weak var table: AXProxyTable?
  private let row: Int

  fileprivate init(table: AXProxyTable, row: Int) {
    self.table = table
    self.row = row
    super.init()
    setAccessibilityRole(.row)
  }

  private var source: AXProxyRows? { table?.source }

  private var content: AXProxyRowContent? {
    let index = self.row
    return onMainThread(source, default: nil) { $0.rowContent(index) }
  }

  /// A separator row (the sidebar's divider) is not an element: VoiceOver skips it instead of announcing a
  /// control that does nothing (#297).
  override func isAccessibilityElement() -> Bool { content?.role != .separator }

  override func accessibilityRole() -> NSAccessibility.Role? {
    // The divider is a plain group, not a splitter: it resizes nothing (#297).
    content?.role == .separator ? .group : .row
  }

  override func accessibilitySubrole() -> NSAccessibility.Subrole? {
    guard content?.role != .separator, table?.accessibilityRole() == .outline else { return nil }
    return .outlineRow
  }

  override func accessibilityDisclosureLevel() -> Int { content?.disclosureLevel ?? 0 }

  override func isAccessibilityDisclosed() -> Bool { content?.isExpanded ?? false }

  /// The element protocol requires a non-optional identifier; the inherited getter is optional, so the row
  /// conformance needs this override as its witness.
  override func accessibilityIdentifier() -> String { content?.identifier ?? "" }

  override func accessibilityLabel() -> String? { content?.label }

  override func accessibilityValue() -> Any? { content?.value }

  override func accessibilityIndex() -> Int { row }

  override func isAccessibilitySelected() -> Bool {
    let index = self.row
    return onMainThread(source, default: false) { $0.isRowSelected(index) }
  }

  override func accessibilityFrame() -> NSRect {
    let index = self.row
    return onMainThread(source, default: NSRect.zero) { $0.screenFrame(ofRow: index) }
  }

  override func accessibilityParent() -> Any? { table }

  /// Empty unless the owner supplies `children`. The inherited element children would walk back to the table that
  /// lists this row, and a hierarchy snapshot would recurse.
  override func accessibilityChildren() -> [Any]? {
    let index = self.row
    return onMainThread(source, default: [NSView]()) { $0.rowChildren(index) }
  }

  /// Built from the owner's action names; performing one goes back to the owner by name, so no action object (or
  /// its handler) crosses from the main actor.
  override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
    let index = self.row
    let names = onMainThread(source, default: [String]()) { $0.rowActionNames(index) }
    guard !names.isEmpty else { return nil }
    return names.map { NSAccessibilityCustomAction(name: $0, target: self, selector: #selector(performAction(_:))) }
  }

  @objc private func performAction(_ action: NSAccessibilityCustomAction) -> Bool {
    let index = self.row
    let name = action.name
    return onMainThread(source, default: false) { $0.performRowAction(index, name) }
  }
}

/// Publishes an `NSTableView`'s rows to accessibility clients through `element`, an `AXProxyTable`. Shared by every
/// AppKit table or outline that has to expose rows out of process: the command bar results and the sidebar outline
/// (#269); the Archive table (#292) adopts it next.
///
/// Wiring:
/// - the table subclass creates it before `super.init` and calls `attach(to: self)` after; it calls `invalidate()`
///   from `reloadData()` and `selectionDidChange()` after a selection change;
/// - the owner of the model sets `content`;
/// - the container view calls `setParent(_:)` and lists `element` in its `accessibilityChildren()` in place of the
///   scroll view that holds the table.
///
/// No legacy `accessibilityAttributeValue` override is needed: the container is a plain `NSView` and `element` an
/// `NSAccessibilityElement`, and AppKit answers both out of process from their overridden protocol getters. Nothing
/// here creates a row view or asks the table to lay out; answers come from the model, the selection index set and
/// `rect(ofRow:)`. Building a row from an accessibility callback re-enters layout while the client waits on the
/// snapshot, and the client times out.
@MainActor
final class AXProxyRows {
  private(set) weak var table: NSTableView?

  /// The model's answer for a row index; nil for an index the model no longer has.
  var content: (@MainActor (Int) -> AXProxyRowContent?)?

  /// Whether a row reports itself selected; nil reads the table's `selectedRowIndexes`. For a table whose rows are
  /// never selected in AppKit's sense but show a model state instead (the sidebar's current tab).
  var isSelected: (@MainActor (Int) -> Bool)?

  /// The accessibility children of a row; nil (or empty) makes the proxy a leaf. Must return views of a row view
  /// that already exists (`rowView(atRow:makeIfNecessary: false)`), never build one; the views should name the row's
  /// proxy (`rowElement(forRow:)`) as their accessibility parent.
  var children: (@MainActor (Int) -> [NSView])?

  /// The names of a row's VoiceOver actions, and what performing one does (true: handled).
  var customActionNames: (@MainActor (Int) -> [String])?
  var performCustomAction: (@MainActor (Int, String) -> Bool)?

  /// The table as clients see it: role `role`, identifier `identifier`, one `AXProxyRow` child per row.
  let element: AXProxyTable

  init(role: NSAccessibility.Role = .table, identifier: String) {
    element = AXProxyTable(role: role, identifier: identifier)
    element.source = self
  }

  func attach(to table: NSTableView) {
    self.table = table
    element.markStale()
  }

  /// The accessibility parent of `element`: the view that lists it among its children.
  func setParent(_ view: NSView) {
    element.parentView = view
  }

  /// Marks the proxies stale; the next query builds a fresh set for the table's current rows. After a reload the row
  /// at an index may be a different item, so it gets a new element rather than a recycled one.
  func invalidate() {
    element.markStale()
  }

  /// Tells clients the selected rows changed. Selection itself is read from the table on every query.
  func selectionDidChange() {
    NSAccessibility.post(element: element, notification: .selectedRowsChanged)
  }

  /// Testing seam: when a test sets this to an array, every notification posted through `post(_:forRow:)` is
  /// recorded as a (name, row) pair in order; a nil row names the table element. Nil (the default) records nothing,
  /// so a long session does not accumulate a log of every title change.
  var postedNotificationsForTesting: [(NSAccessibility.Notification, Int?)]?

  /// Posts `notification` for the proxy of `row`, or for the table element when `row` is nil (#297): clients
  /// that cached the tree are told to refresh.
  func post(_ notification: NSAccessibility.Notification, forRow row: Int? = nil) {
    let target: NSAccessibilityElement = row.flatMap { rowElement(forRow: $0) } ?? element
    NSAccessibility.post(element: target, notification: notification)
    postedNotificationsForTesting?.append((notification, row))
  }

  /// The proxy of one table row (nil for an index the table does not have), for a view that the proxy lists as a
  /// child and that names the proxy as its parent.
  func rowElement(forRow row: Int) -> AXProxyRow? {
    let rows = element.currentRows()
    return rows.indices.contains(row) ? rows[row] : nil
  }

  // MARK: Answers for the proxies (main actor)

  fileprivate var rowCount: Int { table?.numberOfRows ?? 0 }

  fileprivate func rowContent(_ row: Int) -> AXProxyRowContent? {
    guard let table, row >= 0, row < table.numberOfRows else { return nil }
    return content?(row)
  }

  fileprivate func isRowSelected(_ row: Int) -> Bool {
    guard let table, row >= 0, row < table.numberOfRows else { return false }
    if let isSelected { return isSelected(row) }
    return table.selectedRowIndexes.contains(row)
  }

  fileprivate var selectedRowIndexes: IndexSet {
    guard let table else { return IndexSet() }
    guard let isSelected else { return table.selectedRowIndexes }
    return IndexSet((0..<table.numberOfRows).filter { isSelected($0) })
  }

  fileprivate func rowChildren(_ row: Int) -> [NSView] {
    guard let table, row >= 0, row < table.numberOfRows else { return [] }
    return children?(row) ?? []
  }

  fileprivate func rowActionNames(_ row: Int) -> [String] {
    guard let table, row >= 0, row < table.numberOfRows else { return [] }
    return customActionNames?(row) ?? []
  }

  fileprivate func performRowAction(_ row: Int, _ name: String) -> Bool {
    guard let table, row >= 0, row < table.numberOfRows else { return false }
    return performCustomAction?(row, name) ?? false
  }

  fileprivate var visibleRowRange: Range<Int> {
    guard let table else { return 0..<0 }
    let range = table.rows(in: table.visibleRect)
    guard range.location != NSNotFound, range.length > 0 else { return 0..<0 }
    return range.location..<(range.location + range.length)
  }

  /// The row's rectangle converted through the table and its window to screen coordinates, at the time of the
  /// query. A row the table has not laid out yet still has a rectangle: `rect(ofRow:)` is row-height arithmetic.
  fileprivate func screenFrame(ofRow row: Int) -> NSRect {
    guard let table, let window = table.window, row >= 0, row < table.numberOfRows else { return .zero }
    var rect = table.rect(ofRow: row)
    if rect.width < 1 { rect.size.width = max(table.bounds.width, 1) }
    if rect.height < 1 { rect.size.height = max(table.rowHeight, 1) }
    return window.convertToScreen(table.convert(rect, to: nil))
  }

  /// The visible part of the table: its scroll view's bounds in screen coordinates.
  fileprivate var tableScreenFrame: NSRect {
    guard let table, let window = table.window else { return .zero }
    let container: NSView = table.enclosingScrollView ?? table
    return window.convertToScreen(container.convert(container.bounds, to: nil))
  }
}
