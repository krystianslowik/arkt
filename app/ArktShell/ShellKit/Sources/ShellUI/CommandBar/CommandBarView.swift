import AppKit

/// The results table. Its rows reach accessibility clients through `axProxyRows`: `NSTableView` publishes neither
/// its row views nor overridden children out of process, so XCUITest's `tableRows` query on `commandBar.results` and
/// VoiceOver row navigation would see no rows otherwise. `CommandBarView` lists the proxy table element in place of
/// the scroll view; the controller supplies each row's label and value from its results.
@MainActor
final class CommandBarTableView: NSTableView {
  let axProxyRows: AXProxyRows

  override init(frame frameRect: NSRect) {
    axProxyRows = AXProxyRows(identifier: AXID.CommandBar.results)
    super.init(frame: frameRect)
    axProxyRows.attach(to: self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func reloadData() {
    super.reloadData()
    axProxyRows.invalidate()
  }

  override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
    super.selectRowIndexes(indexes, byExtendingSelection: extend)
    axProxyRows.selectionDidChange()
  }
}

/// Root view of the command bar: input row (scope chip + field), notice strip, divider, results table.
/// Frames are set in `layout()`.
@MainActor
final class CommandBarView: NSView {
  let field = NSTextField()
  /// The scope chip left of the field (BH-106 "Actions", BH-107 the engine name); hidden in the normal scope.
  let scopeChip = NSTextField(labelWithString: "")
  /// BH-113: the search-suggestion privacy notice, shown until dismissed.
  let noticeView = NSView()
  let noticeLabel = NSTextField(labelWithString: "")
  let noticeDismissButton = NSButton()
  let divider = NSView()
  let scrollView = NSScrollView()
  let table = CommandBarTableView(frame: .zero)

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

    scopeChip.isHidden = true
    scopeChip.font = .systemFont(ofSize: 13, weight: .medium)
    scopeChip.textColor = ShellTokens.commandBarText.nsColor()
    scopeChip.wantsLayer = true
    scopeChip.layer?.cornerRadius = 6
    scopeChip.layer?.cornerCurve = .continuous
    scopeChip.layer?.backgroundColor = ShellTokens.commandBarSelectedRow.cgColor
    scopeChip.setAccessibilityIdentifier(AXID.CommandBar.scope)
    addSubview(scopeChip)

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

    noticeView.isHidden = true
    noticeLabel.stringValue = CommandBarView.noticeText
    noticeLabel.font = .systemFont(ofSize: 12)
    noticeLabel.textColor = ShellTokens.commandBarSecondaryText.nsColor()
    noticeLabel.lineBreakMode = .byTruncatingTail
    noticeLabel.cell?.usesSingleLineMode = true
    noticeLabel.setAccessibilityIdentifier(AXID.CommandBar.notice)
    noticeView.addSubview(noticeLabel)
    noticeDismissButton.isBordered = false
    noticeDismissButton.imagePosition = .imageOnly
    noticeDismissButton.toolTip = "Dismiss"
    noticeDismissButton.setAccessibilityLabel("Dismiss")
    noticeDismissButton.setAccessibilityIdentifier(AXID.CommandBar.noticeDismiss)
    noticeDismissButton.target = self
    noticeDismissButton.action = #selector(dismissNoticeClicked(_:))
    noticeView.addSubview(noticeDismissButton)
    addSubview(noticeView)

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
    table.axProxyRows.setParent(self)        // the results reach accessibility as `commandBar.results` (proxy)

    // One tracking area for the life of the view (never per show): pointer moves select the row under them
    // and show its remove button (BH-109); leaving the list hides it again.
    table.addTrackingArea(NSTrackingArea(rect: .zero,
                                         options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
                                                   .inVisibleRect],
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

  /// BH-113, [S] string.
  static let noticeText = "We talk to your search engine to help us suggest results."

  /// Called with the result row under the pointer when it moves over one [I]. Only moves select, so a pointer
  /// that already rests where the bar appears does not change the selection.
  var onHoverRow: ((Int) -> Void)?
  /// The notice's X.
  var onDismissNotice: (() -> Void)?

  @objc private func dismissNoticeClicked(_ sender: Any?) { onDismissNotice?() }

  func setScope(title: String?) {
    scopeChip.stringValue = title ?? ""
    scopeChip.isHidden = title == nil
    needsLayout = true
  }

  func setNoticeVisible(_ visible: Bool) {
    guard visible != !noticeView.isHidden else { return }
    noticeView.isHidden = !visible
    if visible { applyNoticeDismissImage() }
    needsLayout = true
  }

  /// The notice's X glyph at the bar's backing scale; without it the borderless image-only button draws nothing.
  private func applyNoticeDismissImage() {
    noticeDismissButton.image = SymbolImageCache.shared.symbol("xmark", box: 10,
                                                               color: ShellTokens.commandBarSecondaryText,
                                                               scale: shellBackingScale)
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    if !noticeView.isHidden { applyNoticeDismissImage() }
  }

  /// The row under the pointer, if any; its remove button shows (BH-109). Cleared when the results reload.
  private(set) var hoveredRow: Int?

  func setHoveredRow(_ row: Int?) {
    guard row != hoveredRow else { return }
    let old = hoveredRow
    hoveredRow = row
    for r in [old, row].compactMap({ $0 }) {
      (table.view(atColumn: 0, row: r, makeIfNecessary: false) as? CommandBarCellView)?.setCloseHovered(r == row)
    }
  }

  /// The input field and, while results show, the proxy results table in place of the scroll view that holds the
  /// real table (`AXProxyRows`).
  override func accessibilityChildren() -> [Any]? {
    let children = (super.accessibilityChildren() ?? []).filter { child in
      let view = (child as? NSView) ?? (child as? NSCell)?.controlView
      return !(view?.isDescendant(of: scrollView) ?? false)
    }
    return scrollView.isHidden ? children : children + [table.axProxyRows.element]
  }

  override func mouseMoved(with event: NSEvent) {
    let point = table.convert(event.locationInWindow, from: nil)
    guard table.visibleRect.contains(point) else { return }   // a row scrolled out of view is not under the pointer
    let row = table.row(at: point)
    let target = row >= 0 && row < table.numberOfRows ? row : nil
    setHoveredRow(target)
    if let target { onHoverRow?(target) }
  }

  override func mouseExited(with event: NSEvent) { setHoveredRow(nil) }

  override func layout() {
    super.layout()
    let g = CommandBarGeometry.self
    let fieldHeight = ceil(field.intrinsicContentSize.height)
    var fieldX = g.inputLeading
    if !scopeChip.isHidden {
      let chipWidth = ceil(scopeChip.fittingSize.width) + 16     // 8 pt padding on each side
      let chipHeight = ceil(scopeChip.fittingSize.height) + 6
      scopeChip.frame = NSRect(x: fieldX, y: (g.inputHeight - chipHeight) / 2,
                               width: chipWidth, height: chipHeight)
      fieldX = scopeChip.frame.maxX + 10
    }
    field.frame = NSRect(x: fieldX, y: (g.inputHeight - fieldHeight) / 2,
                         width: bounds.width - fieldX - g.inputLeading, height: fieldHeight)
    let dividerY = noticeView.isHidden ? g.inputHeight : g.inputHeight + g.noticeHeight
    if !noticeView.isHidden {
      noticeView.frame = NSRect(x: 0, y: g.inputHeight, width: bounds.width, height: g.noticeHeight)
      let dismissSize: CGFloat = 20
      noticeDismissButton.frame = NSRect(x: bounds.width - dismissSize - 14,
                                         y: (g.noticeHeight - dismissSize) / 2,
                                         width: dismissSize, height: dismissSize)
      let labelHeight = ceil(noticeLabel.intrinsicContentSize.height)
      noticeLabel.frame = NSRect(x: g.inputLeading, y: (g.noticeHeight - labelHeight) / 2,
                                 width: noticeDismissButton.frame.minX - g.inputLeading - 8, height: labelHeight)
    }
    let hasResults = bounds.height > dividerY
    divider.isHidden = !hasResults
    scrollView.isHidden = !hasResults
    divider.frame = NSRect(x: 0, y: dividerY, width: bounds.width, height: 1)
    let listTop = dividerY + 1 + g.listPadding
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
  /// The hovered row's remove button (BH-109); hidden unless the row is removable and hovered.
  let closeButton = NSButton()

  override init(frame: NSRect) {
    super.init(frame: frame)
    identifier = Self.identifier
    icon.imageScaling = .scaleProportionallyUpOrDown
    [icon, title, subtitle, hint].forEach(addSubview)
    closeButton.isBordered = false
    closeButton.imagePosition = .imageOnly
    closeButton.toolTip = "Remove Suggestion"
    closeButton.setAccessibilityLabel("Remove Suggestion")
    closeButton.setAccessibilityIdentifier(AXID.CommandBar.rowRemove)
    closeButton.isHidden = true
    closeButton.target = self
    closeButton.action = #selector(closeClicked(_:))
    addSubview(closeButton)
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

  /// Removal (BH-109): nil for a row that is not removable; the X shows only while the row is hovered.
  var onRemove: (() -> Void)?

  @objc private func closeClicked(_ sender: Any?) { onRemove?() }

  func setCloseHovered(_ hovered: Bool) {
    closeButton.isHidden = !(hovered && onRemove != nil)
    needsLayout = true
  }

  /// `scale`: pixels per point for the icon bitmap (the bar's backing scale, which the cell's own window may
  /// not report yet while the panel is still on the previous display).
  func configure(_ result: CommandBarResults.Result, scale: CGFloat) {
    let symbol = switch result.kind {
    case .open, .pasteAndGo: "globe"
    case .switchTo: "square.on.square"
    case .search, .siteSearch: "magnifyingglass"
    case .restore: "archivebox"
    case .action: "bolt"
    case .switchSpace: "square.grid.2x2"
    }
    icon.image = SymbolImageCache.shared.symbol(symbol, box: Self.iconSize, color: ShellTokens.commandBarText,
                                                scale: scale)
    closeButton.image = SymbolImageCache.shared.symbol("xmark", box: 10,
                                                       color: ShellTokens.commandBarSecondaryText, scale: scale)
    closeButton.isHidden = true
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
    var trailing = bounds.width - leading
    let iconSize = Self.iconSize
    icon.frame = NSRect(x: leading, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
    if !closeButton.isHidden {
      let closeSize: CGFloat = 20
      closeButton.frame = NSRect(x: trailing - closeSize, y: (bounds.height - closeSize) / 2,
                                 width: closeSize, height: closeSize)
      trailing = closeButton.frame.minX - 8
    }
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
