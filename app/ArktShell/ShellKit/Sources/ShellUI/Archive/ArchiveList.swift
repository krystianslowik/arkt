import AppKit

/// One line of the Archive table: an archived item, a tab shown under an item that matched through it, or the
/// auto-load row at the end.
enum ArchiveListEntry: Equatable {
  case item(Int)
  case child(item: Int, child: Int)
  case loading

  var itemIndex: Int? {
    if case .item(let index) = self { return index }
    return nil
  }
}

// MARK: - Table

/// The Archive list. Its rows reach accessibility clients through `axProxyRows` (one `AXProxyRow` per table row):
/// `NSTableView` publishes neither its row views nor overridden children out of process, so XCUITest's `tableRows`
/// query on `archive.table` and VoiceOver row navigation would see no rows otherwise. `ArchiveContentView` lists the
/// proxy table element in place of the scroll view; the controller supplies each row's label and value from its rows,
/// so no row view is created for accessibility.
///
/// Up and Down move between archived items only (tabs shown under an opened folder and the auto-load row are not
/// selectable); Return restores the selected item.
@MainActor
final class ArchiveTableView: NSTableView {
  let axProxyRows: AXProxyRows
  /// Whether a table row can be selected (an archived item).
  var isSelectableRow: (Int) -> Bool = { _ in true }
  /// Return or keypad Enter on the table.
  var onReturn: (@MainActor () -> Void)?
  /// The row under the pointer, for the hover fill; -1 when none.
  private(set) var hoveredRow = -1
  private var hoverArea: NSTrackingArea?

  override init(frame frameRect: NSRect) {
    axProxyRows = AXProxyRows(identifier: AXID.Archive.table)
    super.init(frame: frameRect)
    axProxyRows.attach(to: self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func reloadData() {
    super.reloadData()
    axProxyRows.invalidate()
    setHoveredRow(-1)
  }

  override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
    super.selectRowIndexes(indexes, byExtendingSelection: extend)
    axProxyRows.selectionDidChange()
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76:                                    // Return, keypad Enter
      onReturn?()
    case 125: moveSelection(by: 1)                  // Down
    case 126: moveSelection(by: -1)                 // Up
    default: super.keyDown(with: event)
    }
  }

  /// Selects the next (or previous) selectable row and scrolls it into view; at the ends nothing changes.
  func moveSelection(by step: Int) {
    var row = selectedRow < 0 ? (step > 0 ? -1 : numberOfRows) : selectedRow
    repeat { row += step } while row >= 0 && row < numberOfRows && !isSelectableRow(row)
    guard row >= 0, row < numberOfRows else { return }
    selectRowIndexes([row], byExtendingSelection: false)
    scrollRowToVisible(row)
  }

  // MARK: Hover

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow,
                                                     .inVisibleRect], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    let row = self.row(at: convert(event.locationInWindow, from: nil))
    setHoveredRow(row >= 0 && isSelectableRow(row) ? row : -1)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    setHoveredRow(-1)
  }

  private func setHoveredRow(_ row: Int) {
    guard row != hoveredRow else { return }
    if hoveredRow >= 0, hoveredRow < numberOfRows {
      (rowView(atRow: hoveredRow, makeIfNecessary: false) as? ArchiveRowView)?.isHovered = false
    }
    hoveredRow = row
    if row >= 0 { (rowView(atRow: row, makeIfNecessary: false) as? ArchiveRowView)?.isHovered = true }
  }
}

/// The Archive window's content. For accessibility it lists the proxy table (`AXProxyRows.element`, identifier
/// `archive.table`) in place of the scroll view that holds the real table. Flipped: the layout runs top down.
@MainActor
final class ArchiveContentView: NSView {
  let table: ArchiveTableView
  private let scrollView: NSScrollView
  /// Lays out the subviews; the controller sets it.
  var onLayout: (@MainActor () -> Void)?
  /// Restyles after an appearance change; the controller sets it.
  var onAppearanceChange: (@MainActor () -> Void)?

  init(frame: NSRect, table: ArchiveTableView, scrollView: NSScrollView) {
    self.table = table
    self.scrollView = scrollView
    super.init(frame: frame)
    wantsLayer = true
    // A group of its own, so the listed children are this view's answer rather than an ignored view's expansion.
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    table.axProxyRows.setParent(self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = BrandTokens.surfaceBrand.resolve(archiveFlavor).cgColor
  }

  override func layout() {
    super.layout()
    onLayout?()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
    onAppearanceChange?()
  }

  override func accessibilityChildren() -> [Any]? {
    let children = (super.accessibilityChildren() ?? []).filter { child in
      let view = (child as? NSView) ?? (child as? NSCell)?.controlView
      return !(view.map { $0 === scrollView || $0.isDescendant(of: scrollView) } ?? false)
    }
    return children + [table.axProxyRows.element]
  }
}

/// The empty area of the title bar and the window's margins drag the window, like a title bar.
@MainActor
final class ArchiveDragView: WindowDragView {}

/// The recessed field behind the list (`ArchiveTokens.listField`, radius 10).
@MainActor
final class ArchiveListFieldView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = ArchiveMetrics.listRadius
    layer?.cornerCurve = .continuous
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    let flavor = archiveFlavor
    layer?.backgroundColor = ArchiveTokens.listField.resolve(flavor).cgColor
    let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    layer?.borderWidth = increased ? 1 : 0
    layer?.borderColor = ArchiveTokens.increasedContrastEdge.resolve(flavor).cgColor
  }
}

// MARK: - Rows

/// A row's fill: `tabCurrent` with `tabCurrentShadow` when selected, `sidebarItemBackground` on hover, nothing
/// otherwise; 34 pt high, radius 9. No hairlines between rows.
@MainActor
final class ArchiveRowView: NSTableRowView {
  static let identifier = NSUserInterfaceItemIdentifier("ArchiveRow")

  var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
  /// Child and loading rows never draw a fill.
  var isInteractive = true { didSet { if isInteractive != oldValue { needsDisplay = true } } }
  private let fillLayer = CALayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    identifier = Self.identifier
    wantsLayer = true
    fillLayer.cornerRadius = SidebarMetrics.rowCornerRadius
    fillLayer.cornerCurve = .continuous
    fillLayer.shadowRadius = 2
    fillLayer.shadowOffset = CGSize(width: 0, height: -1)
    setAccessibilityElement(true)
    setAccessibilityRole(.row)
    setAccessibilityIdentifier(AXID.Archive.row)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isSelected: Bool {
    didSet {
      setAccessibilitySelected(isSelected)
      if isSelected != oldValue { needsDisplay = true }
    }
  }

  override var wantsUpdateLayer: Bool { true }

  /// The fill drawn now (nil = none), for tests.
  var displayedFill: RGBA? {
    guard isInteractive else { return nil }
    let flavor = archiveFlavor
    if isSelected { return ShellTokens.tabCurrent.resolve(flavor) }
    return isHovered ? ShellTokens.sidebarItemBackground.resolve(flavor) : nil
  }

  override func updateLayer() {
    if fillLayer.superlayer !== layer { layer?.insertSublayer(fillLayer, at: 0) }
    let flavor = archiveFlavor
    ArchiveMotion.set {
      fillLayer.frame = fillRect
      fillLayer.backgroundColor = displayedFill?.cgColor
      let shadow = ShellTokens.tabCurrentShadow.resolve(flavor)
      fillLayer.shadowColor = shadow.cgColor
      fillLayer.shadowOpacity = isInteractive && isSelected && shadow.alpha > 0 ? 1 : 0
      // Increase Contrast: the selected row gets the 1 pt edge (in dark it has no shadow to lift it).
      let edged = isInteractive && isSelected && NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
      fillLayer.borderWidth = edged ? 1 : 0
      fillLayer.borderColor = ArchiveTokens.increasedContrastEdge.resolve(flavor).cgColor
      fillLayer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: fillRect.size),
                                    cornerWidth: SidebarMetrics.rowCornerRadius,
                                    cornerHeight: SidebarMetrics.rowCornerRadius, transform: nil)
    }
  }

  /// A row is one 37 pt pitch; the fill is the 34 pt row centered in it, so 3 pt separate two fills.
  private var fillRect: CGRect {
    bounds.insetBy(dx: 0, dy: max(0, (bounds.height - ArchiveMetrics.rowHeight) / 2))
  }

  override func layout() {
    super.layout()
    needsDisplay = true
  }

  override func drawSelection(in dirtyRect: NSRect) {}
  override func drawBackground(in dirtyRect: NSRect) {}

  override func isAccessibilitySelected() -> Bool { isSelected }

  override func accessibilityParent() -> Any? {
    superview.flatMap(NSAccessibility.unignoredAncestor(of:))
  }

  override func accessibilityChildren() -> [Any]? {
    NSAccessibility.unignoredChildren(from: subviews)
  }
}

/// The title with the search match highlighted: `ArchiveTokens.matchHighlight` behind each match, 3 pt radius, 1 pt
/// padding. A fill, never colored text. One line, tail truncation.
@MainActor
final class ArchiveTitleView: NSView {
  private(set) var text = ""
  private(set) var highlights: [Range<String.Index>] = []
  private var font = NSFont.systemFont(ofSize: 13, weight: .medium)
  private var color = RGBA.black(1)
  private var highlight = RGBA.black(0)

  override var isFlipped: Bool { true }

  /// The matches of `query` in `text`, folded like the store's search (case, diacritics, width).
  static func matches(of query: String, in text: String) -> [Range<String.Index>] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return [] }
    var found: [Range<String.Index>] = []
    var start = text.startIndex
    while start < text.endIndex,
          let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                 range: start..<text.endIndex) {
      found.append(range)
      start = range.upperBound
    }
    return found
  }

  func show(_ text: String, query: String, font: NSFont, color: RGBA, highlight: RGBA) {
    self.text = text
    self.font = font
    self.color = color
    self.highlight = highlight
    highlights = Self.matches(of: query, in: text)
    needsDisplay = true
  }

  var naturalWidth: CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }

  override func draw(_ dirtyRect: NSRect) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.nsColor()]
    let lineHeight = ceil(font.ascender - font.descender)
    let y = ((bounds.height - lineHeight) / 2).rounded()
    if !highlights.isEmpty {
      highlight.nsColor().setFill()
      for range in highlights {
        let x = (String(text[..<range.lowerBound]) as NSString).size(withAttributes: attributes).width
        let width = (String(text[range]) as NSString).size(withAttributes: attributes).width
        guard x < bounds.width else { continue }
        let rect = NSRect(x: x - 1, y: y - 1, width: min(width + 2, bounds.width - x + 1), height: lineHeight + 2)
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
      }
    }
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    var drawn = attributes
    drawn[.paragraphStyle] = style
    (text as NSString).draw(with: NSRect(x: 0, y: y, width: bounds.width, height: lineHeight),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: drawn)
  }
}

/// One archived item, or a tab shown under an opened folder (design section 9): favicon (or folder / split glyph),
/// title with the match highlighted, a folder's tab count, then the Space dot and the compact time. Accessibility
/// reads the row as one element: the title, then the details the row no longer prints.
@MainActor
final class ArchiveRowCellView: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("ArchiveRowCell")

  let chevron = NSImageView()
  let icon = NSImageView()
  let titleView = ArchiveTitleView()
  let countField = NSTextField(labelWithString: "")
  let placeView = NSImageView()
  let timeField = NSTextField(labelWithString: "")
  private var indent: CGFloat = 0
  private var opened = false

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 400, height: ArchiveMetrics.rowHeight))
    identifier = Self.identifier
    for view in [chevron, icon, placeView] { view.imageScaling = .scaleNone }
    icon.imageScaling = .scaleProportionallyUpOrDown
    countField.font = .systemFont(ofSize: 13)
    timeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    timeField.lineBreakMode = .byClipping
    [chevron, icon, titleView, countField, placeView, timeField].forEach(addSubview)
    for view in [chevron, icon, countField, placeView, timeField] as [NSView] {
      view.setAccessibilityElement(false)
      (view as? NSControl)?.cell?.setAccessibilityElement(false)
    }
    titleView.setAccessibilityElement(false)
    setAccessibilityElement(true)
    setAccessibilityRole(.cell)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  var title: String { titleView.text }

  /// An archived item: its kind's icon, the title, the folder count, the place mark and the time.
  func show(_ row: ArchiveRow, query: String, favicon: NSImage?, flavor: ThemeFlavor, scale: CGFloat) {
    opened = !row.matchedChildren.isEmpty
    indent = 0
    titleView.show(row.title, query: query, font: .systemFont(ofSize: 13, weight: .medium),
                   color: ShellTokens.primaryText.resolve(flavor), highlight: ArchiveTokens.matchHighlight.resolve(flavor))
    chevron.isHidden = !opened
    chevron.image = opened ? SymbolImageCache.shared.symbol(
      "chevron.down", box: 10, weight: .semibold, color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale) : nil
    switch row.kind {
    case .tab(let url):
      icon.image = favicon ?? SidebarGlyphs.letter(for: row.title, url: url, flavor: flavor,
                                                   size: SidebarMetrics.faviconSize, scale: scale)
      countField.isHidden = true
    case .folder(let count):
      icon.image = SymbolImageCache.shared.symbol("folder", box: SidebarMetrics.faviconSize,
                                                  color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
      countField.stringValue = "\(count)"
      countField.isHidden = false
    case .split:
      icon.image = SymbolImageCache.shared.symbol("rectangle.split.2x1", box: SidebarMetrics.faviconSize,
                                                  color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
      countField.isHidden = true
    }
    countField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    switch row.place {
    case .none:
      placeView.image = nil
    case .space(let color):
      placeView.image = ArchiveGlyphs.dot(color ?? ShellTokens.sidebarForeground.resolve(flavor),
                                          size: ArchiveMetrics.dotSize, scale: scale)
    case .littleArkt:
      placeView.image = SymbolImageCache.shared.symbol("macwindow", box: 10,
                                                       color: ShellTokens.sidebarForeground.resolve(flavor), scale: scale)
    }
    placeView.isHidden = placeView.image == nil
    timeField.stringValue = row.time
    timeField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    timeField.isHidden = false
    var label = "\(row.title), \(row.detail), \(row.reason)"
    if case .folder(let count) = row.kind { label += ", \(count) \(count == 1 ? "tab" : "tabs")" }
    setAccessibilityLabel(label)
    toolTip = "\(row.detail), \(row.reason)"
    needsLayout = true
  }

  /// A tab under an opened folder: indented 22, no trailing metadata.
  func showChild(_ child: ArchiveChildRow, parentTitle: String, query: String, favicon: NSImage?, flavor: ThemeFlavor,
                 scale: CGFloat) {
    opened = false
    indent = ArchiveMetrics.childIndent
    titleView.show(child.title, query: query, font: .systemFont(ofSize: 13, weight: .medium),
                   color: ShellTokens.primaryText.resolve(flavor), highlight: ArchiveTokens.matchHighlight.resolve(flavor))
    chevron.isHidden = true
    icon.image = favicon ?? SidebarGlyphs.letter(for: child.title, url: child.url, flavor: flavor,
                                                 size: SidebarMetrics.faviconSize, scale: scale)
    countField.isHidden = true
    placeView.isHidden = true
    timeField.isHidden = true
    setAccessibilityLabel("\(child.title), in \(parentTitle)")
    toolTip = nil
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let h = bounds.height
    let iconSize = SidebarMetrics.faviconSize
    let iconX: CGFloat = opened ? 26 : ArchiveMetrics.faviconLeading + indent
    chevron.frame = NSRect(x: 8, y: ((h - 10) / 2).rounded(), width: 10, height: 10)
    icon.frame = NSRect(x: iconX, y: ((h - iconSize) / 2).rounded(), width: iconSize, height: iconSize)
    let trailing = bounds.width - ArchiveMetrics.timeTrailing
    let timeX = trailing - ArchiveMetrics.timeWidth
    let timeHeight = ceil(timeField.intrinsicContentSize.height)
    timeField.frame = NSRect(x: timeX, y: ((h - timeHeight) / 2).rounded(), width: ArchiveMetrics.timeWidth,
                             height: timeHeight)
    let dotSlot: CGFloat = 10
    placeView.frame = NSRect(x: timeX - ArchiveMetrics.dotToTime - dotSlot, y: ((h - dotSlot) / 2).rounded(),
                             width: dotSlot, height: dotSlot)
    let titleX = icon.frame.maxX + ArchiveMetrics.titleGap
    let limit = timeField.isHidden ? trailing : placeView.frame.minX - ArchiveMetrics.titleToTrailing + 6
    var titleWidth = max(0, limit - titleX)
    if !countField.isHidden {
      let countWidth = ceil(countField.intrinsicContentSize.width)
      titleWidth = min(titleView.naturalWidth, max(0, titleWidth - 6 - countWidth))
      let countHeight = ceil(countField.intrinsicContentSize.height)
      countField.frame = NSRect(x: titleX + titleWidth + 6, y: ((h - countHeight) / 2).rounded(), width: countWidth,
                                height: countHeight)
    }
    titleView.frame = NSRect(x: titleX, y: 0, width: titleWidth, height: h)
  }
}

/// The auto-load row: a small spinner and "Loading more", shown while the next page loads.
@MainActor
final class ArchiveLoadingCellView: NSTableCellView {
  static let identifier = NSUserInterfaceItemIdentifier("ArchiveLoadingCell")
  let spinner = NSProgressIndicator()
  let label = NSTextField(labelWithString: "Loading more")

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 400, height: ArchiveMetrics.loadingRowHeight))
    identifier = Self.identifier
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    label.font = .systemFont(ofSize: 12)
    addSubview(spinner)
    addSubview(label)
    label.setAccessibilityElement(false)
    label.cell?.setAccessibilityElement(false)
    setAccessibilityElement(true)
    setAccessibilityRole(.cell)
    setAccessibilityLabel("Loading more")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func start(flavor: ThemeFlavor) {
    label.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    spinner.startAnimation(nil)
  }

  override func layout() {
    super.layout()
    let labelSize = label.intrinsicContentSize
    let total = 12 + 8 + ceil(labelSize.width)
    let x = ((bounds.width - total) / 2).rounded()
    spinner.frame = NSRect(x: x, y: ((bounds.height - 12) / 2).rounded(), width: 12, height: 12)
    label.frame = NSRect(x: x + 20, y: ((bounds.height - ceil(labelSize.height)) / 2).rounded(),
                         width: ceil(labelSize.width), height: ceil(labelSize.height))
  }
}

// MARK: - Empty state

/// Centered in the list field: a 44 pt tile with a 22 pt glyph, the title (15 semibold) and a detail line.
@MainActor
final class ArchiveEmptyStateView: NSView {
  let titleField = NSTextField(labelWithString: "")
  let detailField = NSTextField(wrappingLabelWithString: "")
  private let tile = CALayer()
  private let glyph = NSImageView()
  private var symbol = "archivebox"

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    tile.cornerRadius = 12
    tile.cornerCurve = .continuous
    layer?.addSublayer(tile)
    glyph.imageScaling = .scaleNone
    titleField.font = .systemFont(ofSize: 15, weight: .semibold)
    titleField.alignment = .center
    detailField.font = .systemFont(ofSize: 12)
    detailField.alignment = .center
    detailField.isSelectable = false
    [glyph, titleField, detailField].forEach(addSubview)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    for field in [titleField, detailField] {
      field.setAccessibilityElement(false)
      field.cell?.setAccessibilityElement(false)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  func show(title: String, detail: String, symbol: String) {
    titleField.stringValue = title
    detailField.stringValue = detail
    self.symbol = symbol
    setAccessibilityLabel("\(title). \(detail)")
    restyle()
    needsLayout = true
  }

  private func restyle() {
    let flavor = archiveFlavor
    ArchiveMotion.set { tile.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor }
    titleField.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    detailField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    glyph.image = SymbolImageCache.shared.symbol(symbol, box: 22, color: ShellTokens.sidebarForeground.resolve(flavor),
                                                 scale: window?.backingScaleFactor ?? 2)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  override func layout() {
    super.layout()
    let width = min(300, bounds.width - 24)
    let titleHeight = ceil(titleField.intrinsicContentSize.height)
    let detailHeight = ceil(detailField.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 200))
      .height ?? 16)
    let total = 44 + 8 + titleHeight + 4 + detailHeight
    var y = ((bounds.height - total) / 2).rounded()
    let tileRect = NSRect(x: ((bounds.width - 44) / 2).rounded(), y: y, width: 44, height: 44)
    ArchiveMotion.set { tile.frame = tileRect }
    glyph.frame = tileRect
    y += 44 + 8
    titleField.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: y, width: width, height: titleHeight)
    y += titleHeight + 4
    detailField.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: y, width: width, height: detailHeight)
  }
}
