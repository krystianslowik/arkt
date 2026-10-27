import AppKit

/// The quick lookup bar (#354, docs/design/little-arkt.md "Quick lookup"): the command bar's results over the current
/// desktop, with the "Little Arkt" tag before the field. Return opens the result in a new Little Arkt window; Esc
/// closes the bar with nothing opened. It is keyboard-initiated, so it has no open or close animation.
///
/// Screen-anchored rather than tied to a browser window: the system-wide hotkey (BH-130) reaches it while another app,
/// a full-screen one included, is frontmost. It reuses the command bar's geometry, results and row views without
/// editing them.
@MainActor
public final class LittleArktLookupController: NSObject, NSTextFieldDelegate, NSTableViewDataSource,
  NSTableViewDelegate, NSWindowDelegate {
  /// Return on a URL or search result: open it in a new Little Arkt window.
  public var onOpen: ((URL) -> Void)?
  /// Return on a "Switch to Tab" result: the main window shows that tab.
  public var onSwitch: ((NodeID) -> Void)?
  public var openTabsProvider: () -> [CommandBarResults.OpenTab] = { [] }

  public private(set) var isVisible = false
  public private(set) var results: [CommandBarResults.Result] = []

  let panel = LittleArktLookupPanel()
  let barView = LittleArktLookupView()
  /// Test seam: stands in for the screen's backing scale.
  var backingScaleOverride: CGFloat?
  private var screen: NSScreen?
  /// This show activated the app (the hotkey fired while another app was frontmost), so hiding hands activation back.
  private var activatedApp = false
  private var cellScale: CGFloat = 0

  private var backingScale: CGFloat { backingScaleOverride ?? screen?.backingScaleFactor ?? 2 }

  public override init() {
    super.init()
    panel.contentView = barView
    panel.delegate = self
    barView.field.delegate = self
    barView.table.dataSource = self
    barView.table.delegate = self
    barView.table.target = self
    barView.table.action = #selector(rowClicked(_:))
    // Accessibility rows read the results, not row views: a row never laid out still has its title and caption.
    barView.table.axProxyRows.content = { [weak self] row in
      guard let self, results.indices.contains(row) else { return nil }
      return AXProxyRowContent(identifier: AXID.LittleArktLookup.row, label: results[row].title,
                               value: results[row].accessibilityCaption)
    }
    barView.onHoverRow = { [weak self] row in self?.select(row, scroll: false) }
    NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive(_:)),
                                           name: NSApplication.didResignActiveNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: Show and hide

  /// Shows the bar on `screen` (the display with the pointer, else the main one), empty, over whatever is frontmost.
  public func show(on screen: NSScreen?) {
    guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
    self.screen = screen
    activatedApp = !NSApp.isActive
    if activatedApp { NSApp.activate() }
    barView.field.stringValue = ""
    reloadResults(display: false)
    panel.isPresented = true
    panel.orderFrontRegardless()
    isVisible = true
    panel.makeKey()
    if barView.field.currentEditor() == nil { panel.makeFirstResponder(barView.field) }
    barView.field.currentEditor()?.selectAll(nil)
    panel.contentView?.layoutSubtreeIfNeeded()
  }

  /// Esc, Return and losing key status. `returnActivation` hands the app back to the one that was frontmost before a
  /// hotkey show; Return passes false, so the new Little Arkt window stays key.
  public func hide(returningActivation: Bool = true) {
    guard isVisible else { return }
    isVisible = false
    panel.isPresented = false
    panel.orderOut(nil)
    if returningActivation, activatedApp, NSApp.isActive {
      activatedApp = false
      NSApp.deactivate()
    }
  }

  /// Clicking into another app dismisses the bar, like the command bar.
  public func windowDidResignKey(_ notification: Notification) {
    hide(returningActivation: false)
  }

  /// The bar never outlives the app's activation (a hotkey show activates Arkt; another app taking over closes it).
  @objc private func appDidResignActive(_ notification: Notification) {
    hide(returningActivation: false)
  }

  // MARK: Field and keys

  public func controlTextDidChange(_ obj: Notification) {
    reloadResults(display: true)
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)): hide(); return true
    case #selector(NSResponder.insertNewline(_:)): commit(); return true
    case #selector(NSResponder.moveDown(_:)): moveSelection(+1); return true
    case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
    case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): movePage(+1); return true
    case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): movePage(-1); return true
    default: return false
    }
  }

  /// Return on the selected result. `.restore`, actions and Spaces are not offered here (no providers), so it only closes the bar.
  public func commit() {
    commit(row: max(barView.table.selectedRow, 0))
  }

  private func commit(row: Int) {
    guard row < results.count else { hide(); return }
    switch results[row].kind {
    case .open(let url), .search(let url), .pasteAndGo(let url), .siteSearch(let url):
      hide(returningActivation: false)
      onOpen?(url)
    case .switchTo(let node):
      hide(returningActivation: false)
      onSwitch?(node)
    case .restore, .action, .switchSpace, .noMatch:
      hide()
    }
  }

  @objc private func rowClicked(_ sender: Any?) {
    let row = barView.table.clickedRow
    if row >= 0 { commit(row: row) }
  }

  /// Test hook: same path as typing into the field.
  func setQueryForTesting(_ query: String) {
    barView.field.stringValue = query
    controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: barView.field))
  }

  // MARK: Results

  /// Reloads the rows when they changed, keeps the first one selected, and sizes the panel to the row count.
  private func reloadResults(display: Bool) {
    let fresh = CommandBarResults.make(query: barView.field.stringValue, openTabs: openTabsProvider())
    let scale = backingScale
    if fresh != results || scale != cellScale {
      results = fresh
      cellScale = scale
      barView.table.reloadData()
    }
    if !results.isEmpty, barView.table.selectedRow != 0 {
      barView.table.selectRowIndexes([0], byExtendingSelection: false)
    }
    resizePanel(display: display)
  }

  /// The frame follows the result count, top edge pinned; `display` redraws now for a keystroke.
  private func resizePanel(display: Bool) {
    guard let screen else { return }
    let frame = LittleArktLookup.frame(in: screen.visibleFrame, rowCount: results.count)
    guard panel.frame != frame else { return }
    panel.setFrame(frame, display: display)
    barView.needsLayout = true
  }

  /// Up / Down wrap at the ends, as the command bar does (KB-085).
  private func moveSelection(_ delta: Int) {
    guard let next = CommandBarSelection.step(from: barView.table.selectedRow, by: delta, count: results.count)
    else { return }
    select(next, scroll: true)
  }

  private func movePage(_ pages: Int) {
    guard let next = CommandBarSelection.page(from: barView.table.selectedRow, by: pages, count: results.count)
    else { return }
    select(next, scroll: true)
  }

  /// `scroll` is false for hover: the row under the pointer is already visible.
  private func select(_ row: Int, scroll: Bool) {
    guard row >= 0, row < results.count else { return }
    if barView.table.selectedRow != row { barView.table.selectRowIndexes([row], byExtendingSelection: false) }
    if scroll { barView.table.scrollRowToVisible(row) }
  }

  // MARK: Table

  public func numberOfRows(in tableView: NSTableView) -> Int { results.count }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: LittleArktLookupCellView.identifier, owner: nil) as? LittleArktLookupCellView
      ?? LittleArktLookupCellView(frame: .zero)
    cell.configure(results[row], scale: cellScale)
    return cell
  }

  public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = tableView.makeView(withIdentifier: LittleArktLookupRowView.identifier, owner: nil) as? LittleArktLookupRowView
      ?? LittleArktLookupRowView(frame: .zero)
    rowView.identifier = LittleArktLookupRowView.identifier
    rowView.setAccessibilityIdentifier(AXID.LittleArktLookup.row)
    if results.indices.contains(row) {
      rowView.setAccessibilityLabel(results[row].title)
      rowView.setAccessibilityValue(results[row].accessibilityCaption)
    }
    return rowView
  }
}

// MARK: - Panel

/// The floating panel hosting the lookup bar: created once per app, the same shape as the command bar's panel but not
/// tied to a parent window. `.canJoinAllSpaces` and `.fullScreenAuxiliary` let it show on the current desktop and
/// over a full-screen app; `animationBehavior` is `.none` because the bar is keyboard-initiated.
@MainActor
final class LittleArktLookupPanel: NSPanel {
  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: LittleArktGeometry.preferredWidth,
                                   height: LittleArktGeometry.inputHeight),
               styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
    level = .statusBar                              // over another app's full-screen window (needs a check on screen)
    hidesOnDeactivate = true
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    animationBehavior = .none
    appearance = NSAppearance(named: .darkAqua)     // the command bar's dark surface, on every Space
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    alphaValue = 0
    ignoresMouseEvents = true
  }

  /// Presented is alpha 1 and clickable; hidden is alpha 0 and inert. No animation either way.
  var isPresented = false {
    didSet {
      guard isPresented != oldValue else { return }
      alphaValue = isPresented ? 1 : 0
      ignoresMouseEvents = !isPresented
      contentView?.setAccessibilityValue(isPresented ? AXID.LittleArktLookup.open : AXID.LittleArktLookup.closed)
    }
  }

  override var canBecomeKey: Bool { isPresented }
  override var canBecomeMain: Bool { false }

  override func isAccessibilityElement() -> Bool { isPresented && super.isAccessibilityElement() }
  override func accessibilityChildren() -> [Any]? { isPresented ? super.accessibilityChildren() : [] }
}

// MARK: - View

/// The lookup bar: the "Little Arkt" tag, the input, the divider and the results table. Frames are set in `layout()`,
/// like the command bar's.
@MainActor
final class LittleArktLookupView: NSView {
  let tagView = LittleArktLookupTagView()
  let field = NSTextField()
  let divider = NSView()
  let scrollView = NSScrollView()
  let table = LittleArktLookupTableView(frame: .zero)

  /// Space between the tag and the field.
  static let tagGap: CGFloat = 10

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.LittleArktLookup.root)
    setAccessibilityValue(AXID.LittleArktLookup.closed)
    layer?.cornerRadius = LittleArktGeometry.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.backgroundColor = ShellTokens.lookupSurface.cgColor
    layer?.borderWidth = 1
    layer?.borderColor = ShellTokens.lookupBorder.cgColor

    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 18)
    field.textColor = ShellTokens.lookupText.nsColor()
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.placeholderAttributedString = NSAttributedString(string: LittleArktLookup.placeholder, attributes: [
      .font: NSFont.systemFont(ofSize: 18),
      .foregroundColor: ShellTokens.lookupSecondaryText.nsColor(),
    ])
    field.setAccessibilityIdentifierWithCell(AXID.LittleArktLookup.field)
    field.setAccessibilityLabel(LittleArktLookup.fieldLabel)
    addSubview(tagView)
    addSubview(field)

    divider.wantsLayer = true
    divider.layer?.backgroundColor = ShellTokens.lookupDivider.cgColor
    addSubview(divider)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
    table.addTableColumn(column)
    table.headerView = nil
    table.style = .plain
    table.rowHeight = LittleArktGeometry.rowHeight
    table.intercellSpacing = .zero
    table.selectionHighlightStyle = .none
    table.backgroundColor = .clear
    table.refusesFirstResponder = true            // the field keeps focus; arrows are routed by the controller
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.axProxyRows.setParent(self)             // the results reach accessibility as `littleArkt.lookup.results`
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

  /// Called with the result row under the pointer when it moves over one.
  var onHoverRow: ((Int) -> Void)?

  /// The input, the tag and, while results show, the proxy results table in place of the scroll view (`AXProxyRows`).
  override func accessibilityChildren() -> [Any]? {
    let children = (super.accessibilityChildren() ?? []).filter { child in
      let view = (child as? NSView) ?? (child as? NSCell)?.controlView
      return !(view?.isDescendant(of: scrollView) ?? false)
    }
    return scrollView.isHidden ? children : children + [table.axProxyRows.element]
  }

  override func mouseMoved(with event: NSEvent) {
    let point = table.convert(event.locationInWindow, from: nil)
    guard table.visibleRect.contains(point) else { return }
    let row = table.row(at: point)
    if row >= 0 { onHoverRow?(row) }
  }

  override func layout() {
    super.layout()
    let g = LittleArktGeometry.self
    let tagSize = tagView.intrinsicSize
    tagView.frame = NSRect(x: g.inputLeading, y: ((g.inputHeight - tagSize.height) / 2).rounded(),
                       width: tagSize.width, height: tagSize.height)
    let fieldHeight = ceil(field.intrinsicContentSize.height)
    let fieldX = tagView.frame.maxX + Self.tagGap
    field.frame = NSRect(x: fieldX, y: (g.inputHeight - fieldHeight) / 2,
                         width: max(0, bounds.width - fieldX - g.inputLeading), height: fieldHeight)
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

/// The tag before the input: the design's `accent` fill with `onAccent` text, 22 pt high, 6 pt corners.
@MainActor
final class LittleArktLookupTagView: NSView {
  static let height: CGFloat = 22
  static let cornerRadius: CGFloat = 6
  static let horizontalPadding: CGFloat = 8

  private let label = NSTextField(labelWithString: LittleArktLookup.tag)

  /// The tag's text, for the tests.
  var text: String { label.stringValue }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = Self.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.backgroundColor = BrandTokens.accent.resolve(.dark).cgColor
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    label.textColor = BrandTokens.onAccent.resolve(.dark).nsColor()
    label.lineBreakMode = .byTruncatingTail
    addSubview(label)
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityIdentifier(AXID.LittleArktLookup.tag)
    setAccessibilityLabel(LittleArktLookup.tag)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// The fill and the text with the padding; the tag never truncates in the app's copy.
  var intrinsicSize: NSSize {
    NSSize(width: ceil(label.fittingSize.width) + 2 * Self.horizontalPadding, height: Self.height)
  }

  override func layout() {
    super.layout()
    let height = ceil(label.intrinsicContentSize.height)
    label.frame = NSRect(x: Self.horizontalPadding, y: (bounds.height - height) / 2,
                         width: max(0, bounds.width - 2 * Self.horizontalPadding), height: height)
  }
}

/// The results table with its own accessibility proxy identifier, so the lookup rows are distinct from Cmd-T's.
@MainActor
final class LittleArktLookupTableView: NSTableView {
  let axProxyRows = AXProxyRows(identifier: AXID.LittleArktLookup.results)

  override init(frame frameRect: NSRect) {
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
