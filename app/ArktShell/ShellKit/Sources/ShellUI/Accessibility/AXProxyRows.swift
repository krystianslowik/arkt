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

/// One table row as an accessibility element. `NSTableRowView` is dropped from the out-of-process accessibility
/// tree, so a table that must expose its rows (XCUITest `tableRows` / `outlineRows`, VoiceOver row navigation)
/// publishes these instead. Every attribute is computed when asked: label, value and identifier from the model,
/// selection from the table, the frame from the row's rectangle in screen coordinates at that moment, so a moved
/// window never leaves a stale frame behind.
@MainActor
final class AXProxyRow: NSAccessibilityElement, NSAccessibilityRow {
  private weak var owner: AXProxyRows?
  private let row: Int

  fileprivate init(owner: AXProxyRows, row: Int) {
    self.owner = owner
    self.row = row
    super.init()
    setAccessibilityRole(.row)
  }

  private var content: AXProxyRowContent? { owner?.rowContent(row) }

  override func isAccessibilityElement() -> Bool { true }

  /// The element protocol requires a non-optional identifier; the inherited getter is optional, so the row
  /// conformance needs this override as its witness.
  override func accessibilityIdentifier() -> String { content?.identifier ?? "" }

  override func accessibilityLabel() -> String? { content?.label }

  override func accessibilityValue() -> Any? { content?.value }

  override func accessibilityIndex() -> Int { row }

  override func isAccessibilitySelected() -> Bool { owner?.isRowSelected(row) ?? false }

  override func accessibilityFrame() -> NSRect { owner?.screenFrame(ofRow: row) ?? .zero }

  override func accessibilityParent() -> Any? { owner?.table }

  /// Empty on purpose: a proxy is a leaf. The inherited element children would walk back to the table that lists
  /// this row, and a hierarchy snapshot would recurse.
  override func accessibilityChildren() -> [Any]? { [] }
}

/// Publishes a table's rows as `AXProxyRow`s. Shared by every AppKit table or outline that has to expose rows out of
/// process (the command bar results here; the Archive table and the sidebar outline use the same helper).
///
/// Wiring, in the `NSTableView` / `NSOutlineView` subclass:
/// - hold it as `nonisolated let axProxyRows: AXProxyRows`, created before `super.init` and `attach(to: self)` after;
/// - set `content` to read the model for a row index;
/// - call `invalidate()` from `reloadData()` (and from any other override that replaces the rows wholesale);
/// - return `rows`, `visibleRows` and `selectedRows` from the modern `accessibilityChildren()`, `accessibilityRows()`,
///   `accessibilityVisibleRows()` and `accessibilitySelectedRows()` overrides;
/// - forward the three legacy entry points (`accessibilityAttributeValue(_:)`,
///   `accessibilityArrayAttributeCount(_:)`, `accessibilityArrayAttributeValues(_:index:maxCount:)`) to
///   `attributeValue`, `arrayAttributeCount` and `arrayAttributeValues`, falling back to `super` on nil.
///   Out-of-process clients reach a table through those legacy methods, and `NSTableView`'s own implementation
///   answers rows and children from its row views without consulting the modern overrides.
///
/// Nothing here creates a row view or asks the table to lay out: the answers come from the model, the selection
/// index set and `rect(ofRow:)`. Building a row from an accessibility callback re-enters layout while the client
/// waits on the snapshot, and the client times out.
@MainActor
final class AXProxyRows {
  private(set) weak var table: NSTableView?

  /// The model's answer for a row index; nil for an index the model no longer has.
  var content: (@MainActor (Int) -> AXProxyRowContent?)?

  private var cache: [AXProxyRow]?

  init() {}

  func attach(to table: NSTableView) {
    self.table = table
    cache = nil
  }

  /// Drops the proxies; the next query builds a fresh set for the table's current rows. A reload means the row at
  /// an index may be a different item, so it gets a new element rather than a recycled one.
  func invalidate() {
    cache = nil
  }

  /// One proxy per table row, in row order. Rebuilt when invalidated or when the row count changed without a reload
  /// (`noteNumberOfRowsChanged`, inserts and removals).
  var rows: [AXProxyRow] {
    let count = table?.numberOfRows ?? 0
    if let cache, cache.count == count { return cache }
    let fresh = (0..<count).map { AXProxyRow(owner: self, row: $0) }
    cache = fresh
    return fresh
  }

  /// The proxies whose rows intersect the table's visible rectangle (geometry only; no row is built).
  var visibleRows: [AXProxyRow] {
    let all = rows
    guard let table, !all.isEmpty else { return [] }
    let range = table.rows(in: table.visibleRect)
    let lower = max(0, range.location)
    let upper = min(all.count, range.location + range.length)
    return lower < upper ? Array(all[lower..<upper]) : []
  }

  var selectedRows: [AXProxyRow] {
    guard let table else { return [] }
    let selected = table.selectedRowIndexes
    return rows.filter { selected.contains($0.accessibilityIndex()) }
  }

  fileprivate func rowContent(_ row: Int) -> AXProxyRowContent? {
    guard let table, row >= 0, row < table.numberOfRows else { return nil }
    return content?(row)
  }

  fileprivate func isRowSelected(_ row: Int) -> Bool {
    table?.selectedRowIndexes.contains(row) ?? false
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

  // MARK: Legacy entry points

  /// The proxy answer to one legacy attribute. Its payloads are `Sendable` (`AXProxyRow` is main-actor isolated),
  /// so it can be returned out of `MainActor.assumeIsolated`.
  private enum Answer: Sendable {
    case rows([AXProxyRow])
    case count(Int)
  }

  /// `AXChildrenInNavigationOrder` (macOS 10.13), compared by raw value so it does not depend on an SDK constant
  /// name. Clients that order children (VoiceOver, XCUITest) ask for it alongside `AXChildren`.
  private nonisolated static func isChildrenInNavigationOrder(_ attribute: NSAccessibility.Attribute) -> Bool {
    attribute.rawValue == "AXChildrenInNavigationOrder"
  }

  /// The attributes this helper answers. Checked before any isolation work, so every other attribute goes straight
  /// to the table's own implementation.
  private nonisolated static func answers(_ attribute: NSAccessibility.Attribute) -> Bool {
    switch attribute {
    case .children, .visibleChildren, .rows, .visibleRows, .selectedRows, .rowCount:
      return true
    default:
      return isChildrenInNavigationOrder(attribute)
    }
  }

  /// The legacy accessibility methods are declared on `NSObject` (the informal `NSAccessibility` protocol), which is
  /// not main-actor isolated, so the overrides must be `nonisolated`. AppKit services accessibility requests on the
  /// main thread (the accessibility server's port is a main run-loop source), so on the main thread this asserts
  /// the isolation it already has. Off the main thread it does not answer and does not block: the caller falls back
  /// to `super`, which is exactly what an unmodified table would have done.
  private nonisolated func answer(_ attribute: NSAccessibility.Attribute) -> Answer? {
    guard Self.answers(attribute), Thread.isMainThread else { return nil }
    return MainActor.assumeIsolated { self.isolatedAnswer(attribute) }
  }

  private func isolatedAnswer(_ attribute: NSAccessibility.Attribute) -> Answer? {
    switch attribute {
    case .children, .rows: return .rows(rows)
    case .visibleChildren, .visibleRows: return .rows(visibleRows)
    case .selectedRows: return .rows(selectedRows)
    case .rowCount: return .count(rows.count)
    default: return Self.isChildrenInNavigationOrder(attribute) ? .rows(rows) : nil
    }
  }

  /// For `accessibilityAttributeValue(_:)`. Nil: not a proxy attribute, ask `super`.
  nonisolated func attributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
    switch answer(attribute) {
    case .rows(let rows)?: return rows
    case .count(let count)?: return NSNumber(value: count)
    case nil: return nil
    }
  }

  /// For `accessibilityArrayAttributeCount(_:)`. Nil: not a proxy array attribute, ask `super`.
  nonisolated func arrayAttributeCount(_ attribute: NSAccessibility.Attribute) -> Int? {
    guard case .rows(let rows)? = answer(attribute) else { return nil }
    return rows.count
  }

  /// For `accessibilityArrayAttributeValues(_:index:maxCount:)`. Nil: not a proxy array attribute, ask `super`.
  nonisolated func arrayAttributeValues(_ attribute: NSAccessibility.Attribute, index: Int, maxCount: Int) -> [Any]? {
    guard case .rows(let rows)? = answer(attribute) else { return nil }
    guard index >= 0, index < rows.count, maxCount > 0 else { return [] }
    let end = index + min(maxCount, rows.count - index)
    return Array(rows[index..<end])
  }
}
