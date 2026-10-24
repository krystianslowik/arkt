import AppKit

/// Runs `body` on the main actor from a nonisolated AppKit callback. `MainActor.assumeIsolated` can only return a
/// `Sendable` value, and an accessibility element array is not one. The result stays on this thread:
/// `assumeIsolated` traps unless the caller is already on the main thread.
private enum MainThreadAX {
  static func sync<T>(_ body: @MainActor () -> T) -> T {
    nonisolated(unsafe) var result: T?
    MainActor.assumeIsolated {
      result = body()
    }
    return result!
  }
}

/// One command-bar result as an accessibility element. `NSTableRowView` is dropped from the out-of-process tree, so
/// XCUITest's `tableRows` query on `commandBar.results` sees no children unless the table publishes these.
@MainActor
private final class CommandBarAXRow: NSAccessibilityElement, NSAccessibilityRow {
  /// The formal element protocol requires a non-optional identifier. The inherited getter is optional, so the
  /// witness has to be this override or the row conformance does not type-check.
  override func accessibilityIdentifier() -> String { AXID.CommandBar.row }

  /// Empty on purpose. A failure snapshot walks children, and the inherited element children walk back to the
  /// table that lists this row.
  override func accessibilityChildren() -> [Any]? { [] }
}

@MainActor
final class CommandBarTableView: NSTableView {
  private var axRows: [CommandBarAXRow] = []
  private var publishingAX = false

  override func accessibilityChildren() -> [Any]? { axRows }

  /// Not an overridable Swift method on `NSTableView`, but the ObjC selector is what out-of-process clients call
  /// for `AXChildrenInNavigationOrder` when they do not go through `accessibilityAttributeValue`.
  @objc func accessibilityChildrenInNavigationOrder() -> [NSAccessibilityElement]? { axRows }

  override func accessibilityRows() -> [any NSAccessibilityRow]? { axRows }

  override func accessibilityVisibleRows() -> [any NSAccessibilityRow]? { axRows }

  override func accessibilitySelectedRows() -> [any NSAccessibilityRow]? {
    axRows.filter { $0.isAccessibilitySelected() }
  }

  override func accessibilityRowCount() -> Int { axRows.count }

  override func layout() {
    super.layout()
    publishRows()
  }

  override func tile() {
    super.tile()
    publishRows()
  }

  override func reloadData() {
    super.reloadData()
    publishRows()
  }

  override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
    super.selectRowIndexes(indexes, byExtendingSelection: extend)
    for (index, element) in axRows.enumerated() {
      element.setAccessibilitySelected(index == selectedRow)
    }
  }

  /// XCUITest reads `AXChildren` and `AXRows` through these legacy methods. `NSTableView` does not forward them to
  /// the overrides above. The methods are nonisolated AppKit entry points; the table is main-actor, and these calls
  /// are already on the main thread. They only read `axRows` — creating row views here re-enters layout and stalls
  /// the snapshot.
  override nonisolated func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
    MainThreadAX.sync {
      if attribute == .rowCount { return NSNumber(value: self.axRows.count) }
      if let rows = self.rows(for: attribute) { return rows }
      return super.accessibilityAttributeValue(attribute)
    }
  }

  override nonisolated func accessibilityArrayAttributeCount(_ attribute: NSAccessibility.Attribute) -> Int {
    MainThreadAX.sync {
      if let rows = self.rows(for: attribute) { return rows.count }
      return super.accessibilityArrayAttributeCount(attribute)
    }
  }

  override nonisolated func accessibilityArrayAttributeValues(
    _ attribute: NSAccessibility.Attribute, index: Int, maxCount: Int
  ) -> [Any] {
    MainThreadAX.sync {
      guard let rows = self.rows(for: attribute) else {
        return super.accessibilityArrayAttributeValues(attribute, index: index, maxCount: maxCount)
      }
      guard index >= 0, index < rows.count, maxCount > 0 else { return [] }
      return Array(rows[index..<min(rows.count, index + maxCount)])
    }
  }

  /// Copies label, caption, selection and screen frame off row views that already exist. Never asks the table to
  /// build a row: that runs from accessibility callbacks and deadlocks the hierarchy snapshot.
  private func publishRows() {
    guard !publishingAX else { return }
    publishingAX = true
    defer { publishingAX = false }
    let count = numberOfRows
    if axRows.count != count {
      axRows = (0..<count).map { index in
        let element = CommandBarAXRow()
        element.setAccessibilityElement(true)
        element.setAccessibilityRole(.row)
        element.setAccessibilityIdentifier(AXID.CommandBar.row)
        element.setAccessibilityParent(self)
        element.setAccessibilityIndex(index)
        return element
      }
    }
    for index in axRows.indices {
      let element = axRows[index]
      element.setAccessibilityIndex(index)
      if let view = rowView(atRow: index, makeIfNecessary: false) {
        element.setAccessibilityLabel(view.accessibilityLabel())
        if let value = view.accessibilityValue() { element.setAccessibilityValue(value) }
      }
      element.setAccessibilitySelected(index == selectedRow)
      guard let window else { continue }
      var rowRect = rect(ofRow: index)
      if rowRect.width < 1 { rowRect.size.width = bounds.width > 1 ? bounds.width : 1 }
      if rowRect.height < 1 { rowRect.size.height = rowHeight }
      element.setAccessibilityFrame(window.convertToScreen(convert(rowRect, to: nil)))
    }
  }

  private func rows(for attribute: NSAccessibility.Attribute) -> [Any]? {
    switch attribute {
    case .children, .visibleChildren, .rows, .visibleRows,
         NSAccessibility.Attribute(rawValue: "AXChildrenInNavigationOrder"):
      return axRows
    case .selectedRows:
      return axRows.filter { $0.isAccessibilitySelected() }
    default:
      return nil
    }
  }
}

/// Root view of the command bar: input row, divider, results table. Frames are set in `layout()`.
@MainActor
final class CommandBarView: NSView {
  let field = NSTextField()
  let divider = NSView()
  let scrollView = NSScrollView()
  let table: NSTableView = CommandBarTableView()

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.CommandBar.root)
    setAccessibilityValue(AXID.CommandBar.closed)
    layer?.cornerRadius = CommandBarGeometry.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.backgroundColor = ShellTokens.commandBarSurface.cgColor
    layer?.borderWidth = 1
    layer?.borderColor = ShellTokens.commandBarBorder.cgColor

    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 18)
    field.textColor = ShellTokens.commandBarText.nsColor()
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.placeholderAttributedString = NSAttributedString(string: "Search or Enter URL...", attributes: [
      .font: NSFont.systemFont(ofSize: 18),
      .foregroundColor: ShellTokens.commandBarSecondaryText.nsColor(),
    ])
    field.setAccessibilityIdentifierWithCell(AXID.CommandBar.field)
    addSubview(field)

    divider.wantsLayer = true
    divider.layer?.backgroundColor = ShellTokens.commandBarDivider.cgColor
    addSubview(divider)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
    table.addTableColumn(column)
    table.headerView = nil
    table.style = .plain
    table.rowHeight = CommandBarGeometry.rowHeight
    table.intercellSpacing = .zero
    table.selectionHighlightStyle = .none
    table.backgroundColor = .clear
    table.refusesFirstResponder = true            // the field keeps focus; arrows are routed by the controller
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.setAccessibilityIdentifier(AXID.CommandBar.results)

    // One tracking area for the life of the view (never per show): pointer moves select the row under them.
    table.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                         owner: self, userInfo: nil))

    scrollView.documentView = table
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.automaticallyAdjustsContentInsets = false
    addSubview(scrollView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Called with the result row under the pointer when it moves over one [I]. Only moves select, so a pointer
  /// that already rests where the bar appears does not change the selection.
  var onHoverRow: ((Int) -> Void)?

  override func mouseMoved(with event: NSEvent) {
    let point = table.convert(event.locationInWindow, from: nil)
    guard table.visibleRect.contains(point) else { return }   // a row scrolled out of view is not under the pointer
    let row = table.row(at: point)
    if row >= 0 { onHoverRow?(row) }
  }

  override func layout() {
    super.layout()
    let g = CommandBarGeometry.self
    let fieldHeight = ceil(field.intrinsicContentSize.height)
    field.frame = NSRect(x: g.inputLeading, y: (g.inputHeight - fieldHeight) / 2,
                         width: bounds.width - 2 * g.inputLeading, height: fieldHeight)
    let hasResults = bounds.height > g.inputHeight
    divider.isHidden = !hasResults
    scrollView.isHidden = !hasResults
    divider.frame = NSRect(x: 0, y: g.inputHeight, width: bounds.width, height: 1)
    let listTop = g.inputHeight + 1 + g.listPadding
    scrollView.frame = NSRect(x: 0, y: listTop, width: bounds.width,
                              height: max(0, bounds.height - listTop - g.listPadding))
    table.tableColumns.first?.width = scrollView.contentSize.width
  }
}

/// Row background: the selected row gets a lighter rounded fill, inset from the panel edges.
@MainActor
final class CommandBarRowView: NSTableRowView {
  static let identifier = NSUserInterfaceItemIdentifier("commandBar.row")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.row)
    setAccessibilityIdentifier(AXID.CommandBar.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isSelected: Bool {
    didSet {
      if isSelected != oldValue { needsDisplay = true }
      setAccessibilitySelected(isSelected)
    }
  }

  override func isAccessibilitySelected() -> Bool { isSelected }

  override func accessibilityParent() -> Any? {
    superview.flatMap(NSAccessibility.unignoredAncestor(of:))
  }

  override func accessibilityChildren() -> [Any]? {
    NSAccessibility.unignoredChildren(from: subviews)
  }

  private var resultCell: CommandBarCellView? {
    numberOfColumns > 0 ? view(atColumn: 0) as? CommandBarCellView : nil
  }

  override func accessibilityLabel() -> String? {
    resultCell?.title.stringValue ?? super.accessibilityLabel()
  }

  override func accessibilityValue() -> Any? {
    resultCell?.accessibilityValue() ?? super.accessibilityValue()
  }

  override func drawBackground(in dirtyRect: NSRect) {
    guard isSelected else { return }
    let r = CommandBarGeometry.selectedRowRadius
    let rect = bounds.insetBy(dx: CommandBarGeometry.listPadding, dy: 0)
    ShellTokens.commandBarSelectedRow.nsColor().setFill()
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
  }

  override func drawSelection(in dirtyRect: NSRect) {}
}

/// One result: 16 pt icon, title, subtitle on the same baseline, trailing hint ("Switch to Tab ->").
@MainActor
final class CommandBarCellView: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("commandBar.cell")
  static let iconSize: CGFloat = 16

  let icon = NSImageView()
  let title = CommandBarCellView.label(size: 14, color: ShellTokens.commandBarText)
  let subtitle = CommandBarCellView.label(size: 12, color: ShellTokens.commandBarSecondaryText)
  let hint = CommandBarCellView.label(size: 12, color: ShellTokens.commandBarSecondaryText)

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    icon.imageScaling = .scaleProportionallyUpOrDown
    [icon, title, subtitle, hint].forEach(addSubview)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private static func label(size: CGFloat, color: RGBA) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: size)
    label.textColor = color.nsColor()
    label.lineBreakMode = .byTruncatingTail
    label.cell?.usesSingleLineMode = true
    return label
  }

  /// `scale`: pixels per point for the icon bitmap (the bar's backing scale, which the cell's own window may
  /// not report yet while the panel is still on the previous display).
  func configure(_ result: CommandBarResults.Result, scale: CGFloat) {
    let symbol = switch result.kind {
    case .open: "globe"
    case .switchTo: "square.on.square"
    case .search: "magnifyingglass"
    }
    icon.image = SymbolImageCache.shared.symbol(symbol, box: Self.iconSize, color: ShellTokens.commandBarText,
                                                scale: scale)
    title.stringValue = result.title
    subtitle.stringValue = result.subtitle
    hint.stringValue = result.trailingHint.map { $0 + " \u{2192}" } ?? ""
    hint.isHidden = result.trailingHint == nil
    setAccessibilityLabel(result.title)
    setAccessibilityValue(result.accessibilityCaption)
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let leading = CommandBarGeometry.listPadding + 16       // matches the 8 pt inset of the selected fill
    let trailing = bounds.width - leading
    let iconSize = Self.iconSize
    icon.frame = NSRect(x: leading, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
    let hintWidth = hint.isHidden ? 0 : ceil(hint.fittingSize.width)
    hint.frame = centered(x: trailing - hintWidth, width: hintWidth, field: hint)
    let textX = icon.frame.maxX + 12
    let textLimit = (hint.isHidden ? trailing : hint.frame.minX - 12)
    let titleWidth = min(ceil(title.fittingSize.width), max(0, textLimit - textX))
    title.frame = centered(x: textX, width: titleWidth, field: title)
    let subtitleX = title.frame.maxX + 8
    subtitle.frame = centered(x: subtitleX, width: max(0, textLimit - subtitleX), field: subtitle)
  }

  private func centered(x: CGFloat, width: CGFloat, field: NSTextField) -> NSRect {
    let h = ceil(field.intrinsicContentSize.height)
    return NSRect(x: x, y: (bounds.height - h) / 2, width: width, height: h)
  }
}
