import AppKit

/// What one proxy row reports to accessibility clients. It is read from the model for a row index on every query,
/// never copied from a row view, so a row that was never laid out (or was scrolled away and recycled) still has
/// its real label and value.
struct AXProxyRowContent: Equatable, Sendable {
  var identifier: String
  var label: String
  var value: String?

  init(identifier: String, label: String, value: String? = nil) {
    self.identifier = identifier
    self.label = label
    self.value = value
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
/// moment, so a moved window never leaves a stale frame behind. A proxy is a leaf.
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

  override func isAccessibilityElement() -> Bool { true }

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

  /// Empty on purpose: the inherited element children would walk back to the table that lists this row, and a
  /// hierarchy snapshot would recurse.
  override func accessibilityChildren() -> [Any]? { [] }
}

/// Publishes an `NSTableView`'s rows to accessibility clients through `element`, an `AXProxyTable`. Shared by every
/// AppKit table or outline that has to expose rows out of process: the command bar results here; the Archive table
/// (#292) and the sidebar outline (#283, #269) adopt it next.
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

  // MARK: Answers for the proxies (main actor)

  fileprivate var rowCount: Int { table?.numberOfRows ?? 0 }

  fileprivate func rowContent(_ row: Int) -> AXProxyRowContent? {
    guard let table, row >= 0, row < table.numberOfRows else { return nil }
    return content?(row)
  }

  fileprivate func isRowSelected(_ row: Int) -> Bool {
    table?.selectedRowIndexes.contains(row) ?? false
  }

  fileprivate var selectedRowIndexes: IndexSet { table?.selectedRowIndexes ?? IndexSet() }

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
