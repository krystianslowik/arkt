import AppKit

/// The results table. Its rows reach accessibility clients through `axProxyRows`: `NSTableView` publishes neither
/// its row views nor overridden children out of process, so XCUITest's `tableRows` query on `commandBar.results` and
/// VoiceOver row navigation would see no rows otherwise. `CommandBarView` lists the proxy table element in place of
/// the scroll view; the controller supplies each row's label and value from its results.
@MainActor
final class CommandBarTableView: NSTableView {
  let axProxyRows: AXProxyRows
  /// Called after the rows reload and after the selection changes, so the selection indicator follows.
  var onSelectionOrDataChange: (() -> Void)?

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
    onSelectionOrDataChange?()
  }

  override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
    super.selectRowIndexes(indexes, byExtendingSelection: extend)
    axProxyRows.selectionDidChange()
    onSelectionOrDataChange?()
  }
}

/// Root view of the command bar (design/command-bar/README.md): the field row (magnifier, scope chip, field, filter
/// pills, Esc key cap), the notice strip, a hairline, the padded results list and the hint strip, on a glass surface.
/// Frames are set in `layout()`.
@MainActor
final class CommandBarView: NSView {
  let field = NSTextField()
  let magnifier = NSImageView()
  /// The scope chip left of the field (BH-106 "Actions", BH-107 the engine name); hidden in the normal scope.
  let scopeChip = NSTextField(labelWithString: "")
  let pills = CommandBarFilterPills(frame: .zero)
  let escapeKey = CommandBarKeyCapView(frame: .zero)
  /// BH-113: the search-suggestion privacy notice, shown until dismissed.
  let noticeView = NSView()
  let noticeLabel = NSTextField(labelWithString: "")
  let noticeDismissButton = NSButton()
  let divider = NSView()
  let scrollView = NSScrollView()
  let table = CommandBarTableView(frame: .zero)
  let hintStrip = CommandBarHintStrip(frame: .zero)
  let selectionIndicator = CommandBarSelectionIndicator(frame: .zero)
  let selectionMotion = CommandBarSelectionMotion()
  let previewColumn = CommandBarPreviewColumn(frame: .zero)
  let widthMotion = CommandBarWidthMotion()
  /// Width on screen. The panel may already be the wide size while this is still catching up.
  private(set) var drawnWidth: CGFloat = CommandBarGeometry.preferredWidth
  /// While a width spring runs, layout must not snap the mask to the panel's full width.
  private var keepsDrawnWidth = false
  /// Layouts so far. A width frame must not increment it.
  private(set) var layoutCount = 0
  private let widthMask = CALayer()
  private let fieldClip = CALayer()
  /// The header text over the rows that start a group, by row (empty state); those rows are taller by the header.
  var groupHeaders: [Int: String] = [:]
  /// Whether a selection change slides the indicator. Off while results reload, so new results do not slide.
  var selectionAnimates = true
  private let effectView = NSVisualEffectView()
  private let surfaceTint = NSView()
  private let innerEdge = CALayer()
  private let hintDivider = NSView()

  /// The appearance the bar draws in, taken from the window behind it when it shows (the panel itself has no
  /// theme). Setting it recolors every part.
  private(set) var flavor: ThemeFlavor = .dark
  /// Reduce Transparency: an opaque surface instead of the blur. Injected so tests can run both.
  var reduceTransparency: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
  /// Called when the Esc key cap is clicked.
  var onEscapeKey: (() -> Void)? {
    didSet { escapeKey.onClick = onEscapeKey }
  }

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Command bar")
    setAccessibilityIdentifier(AXID.CommandBar.root)
    setAccessibilityValue(AXID.CommandBar.closed)
    layer?.cornerRadius = CommandBarGeometry.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5

    effectView.material = .popover
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.setAccessibilityElement(false)
    addSubview(effectView)
    surfaceTint.wantsLayer = true
    surfaceTint.setAccessibilityElement(false)
    addSubview(surfaceTint)
    innerEdge.borderWidth = 1
    innerEdge.cornerRadius = CommandBarGeometry.cornerRadius
    innerEdge.cornerCurve = .continuous
    layer?.addSublayer(innerEdge)

    magnifier.imageScaling = .scaleProportionallyUpOrDown
    magnifier.setAccessibilityElement(false)
    addSubview(magnifier)

    scopeChip.isHidden = true
    scopeChip.font = .systemFont(ofSize: 13, weight: .medium)
    scopeChip.wantsLayer = true
    scopeChip.layer?.cornerRadius = 6
    scopeChip.layer?.cornerCurve = .continuous
    scopeChip.setAccessibilityIdentifier(AXID.CommandBar.scope)
    addSubview(scopeChip)

    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.wantsLayer = true
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 22)
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.setAccessibilityIdentifierWithCell(AXID.CommandBar.field)
    addSubview(field)

    addSubview(pills)
    escapeKey.configure(CommandBarKeyCaps.escape, flavor: .dark)
    escapeKey.setAccessibilityRole(.button)
    escapeKey.setAccessibilityLabel("Close")
    escapeKey.setAccessibilityIdentifier(AXID.CommandBar.escape)
    addSubview(escapeKey)

    noticeView.isHidden = true
    noticeLabel.stringValue = CommandBarView.noticeText
    noticeLabel.font = .systemFont(ofSize: 12)
    noticeLabel.lineBreakMode = .byTruncatingTail
    noticeLabel.cell?.usesSingleLineMode = true
    noticeLabel.setAccessibilityIdentifier(AXID.CommandBar.notice)
    noticeView.addSubview(noticeLabel)
    noticeDismissButton.wantsLayer = true
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
    table.addSubview(selectionIndicator, positioned: .below, relativeTo: nil)
    table.onSelectionOrDataChange = { [weak self] in
      guard let self else { return }
      syncSelectionIndicator(animated: selectionAnimates)
    }
    selectionMotion.onFrame = { [weak self] in self?.applySelectionOffset() }
    widthMotion.onFrame = { [weak self] width in self?.applyDrawnWidth(CGFloat(width)) }
    widthMask.backgroundColor = NSColor.black.cgColor
    widthMask.cornerRadius = CommandBarGeometry.cornerRadius
    widthMask.cornerCurve = .continuous
    layer?.mask = widthMask
    fieldClip.backgroundColor = NSColor.black.cgColor

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

    hintDivider.wantsLayer = true
    addSubview(hintDivider)
    addSubview(hintStrip)
    addSubview(previewColumn)
    apply(flavor: .dark)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// The least the query field is given before the filter pills are hidden.
  static let minimumFieldWidth: CGFloat = 160

  /// BH-113, [S] string.
  static let noticeText = "We talk to your search engine to help us suggest results."
  static let placeholder = "Search or enter address"

  /// Called with the result row under the pointer when it moves over one [I]. Only moves select, so a pointer
  /// that already rests where the bar appears does not change the selection.
  var onHoverRow: ((Int) -> Void)?
  /// The notice's X.
  var onDismissNotice: (() -> Void)?

  @objc private func dismissNoticeClicked(_ sender: Any?) { onDismissNotice?() }

  // MARK: Appearance

  /// Recolors the bar for `flavor` and applies Reduce Transparency. Called on every show, and when the
  /// accessibility setting may have changed.
  func apply(flavor: ThemeFlavor) {
    self.flavor = flavor
    appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    let opaque = reduceTransparency()
    effectView.isHidden = opaque
    surfaceTint.layer?.backgroundColor = (opaque ? ShellTokens.commandBarSurfaceOpaque
                                                 : ShellTokens.commandBarSurface).resolve(flavor).cgColor
    layer?.borderColor = ShellTokens.commandBarBorder.resolve(flavor).cgColor
    innerEdge.borderColor = ShellTokens.commandBarInnerEdge.resolve(flavor).cgColor
    divider.layer?.backgroundColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    hintDivider.layer?.backgroundColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    field.textColor = ShellTokens.commandBarText.resolve(flavor).nsColor()
    scopeChip.textColor = ShellTokens.commandBarText.resolve(flavor).nsColor()
    scopeChip.layer?.backgroundColor = ShellTokens.commandBarSelectedRow.resolve(flavor).cgColor
    noticeLabel.textColor = ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor()
    escapeKey.configure(CommandBarKeyCaps.escape, flavor: flavor)
    previewColumn.apply(flavor: flavor)
    selectionIndicator.flavorForColors = flavor
    refreshPlaceholder(scopePlaceholder ?? Self.placeholder)
    refreshMagnifier()
    if !noticeView.isHidden { applyNoticeDismissImage() }
  }

  private var scopePlaceholder: String?

  private var shownPlaceholder: (text: String, flavor: ThemeFlavor)?

  func refreshPlaceholder(_ text: String) {
    // A show repeats the previous placeholder: setting it again would redraw the field in the first frame's commit.
    if let shown = shownPlaceholder, shown.text == text, shown.flavor == flavor { return }
    shownPlaceholder = (text, flavor)
    scopePlaceholder = text == Self.placeholder ? nil : text
    field.placeholderAttributedString = NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 22),
      .foregroundColor: ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor(),
    ])
  }

  private func refreshMagnifier() {
    magnifier.image = SymbolImageCache.shared.symbol("magnifyingglass", box: 18,
                                                     color: ShellTokens.commandBarSecondaryText.resolve(flavor),
                                                     scale: shellBackingScale)
  }

  func setScope(title: String?) {
    guard (title ?? "") != scopeChip.stringValue || (title == nil) != scopeChip.isHidden else { return }
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
                                                               color: ShellTokens.commandBarTertiaryText.resolve(flavor),
                                                               scale: shellBackingScale)
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    refreshMagnifier()
    if !noticeView.isHidden { applyNoticeDismissImage() }
  }

  // MARK: Selection and hover

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

  /// The selected row's fill, in table coordinates: the row without its group header.
  func selectionRect(ofRow row: Int) -> NSRect {
    var rect = table.rect(ofRow: row)
    if groupHeaders[row] != nil {
      rect.origin.y += CommandBarGeometry.groupHeaderHeight
      rect.size.height -= CommandBarGeometry.groupHeaderHeight
    }
    return rect
  }

  /// Puts the fill and tick on the selected row, or hides them when no row is selected. The frame is always the target
  /// row; `animated` slides the fill there from the row it was on, by a transform (`CommandBarSelectionMotion`).
  func syncSelectionIndicator(animated: Bool) {
    let row = table.selectedRow
    guard row >= 0, row < table.numberOfRows else {
      selectionMotion.settleNow()
      selectionIndicator.place(on: nil)
      return
    }
    let target = selectionRect(ofRow: row)
    let wasHidden = selectionIndicator.isHidden
    let oldY = selectionIndicator.frame.minY
    selectionIndicator.place(on: target)
    if wasHidden || target.minY != oldY {
      if animated, !wasHidden {
        selectionMotion.move(from: Double(oldY), to: Double(target.minY), in: self)
      } else {
        selectionMotion.settleNow()
      }
    }
    applySelectionOffset()
  }

  /// The indicator's distance behind its row, from the spring (zero at rest).
  private func applySelectionOffset() {
    selectionIndicator.setOffset(CGFloat(selectionMotion.offset(toward: Double(selectionIndicator.frame.minY)) ?? 0))
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

  // MARK: Layout

  /// Remembers `width` so the next layout, which sizes the wide panel, keeps the mask where the spring is.
  func holdDrawnWidth(_ width: CGFloat) {
    drawnWidth = width
    keepsDrawnWidth = true
  }

  func releaseDrawnWidth() { keepsDrawnWidth = false }

  /// A narrowing spring keeps the wide layout so the column can clip away. Layout must not snap the mask open.
  func keepDrawnWidth() { keepsDrawnWidth = true }

  /// Mask and trailing-cluster transform only. No layout.
  func applyDrawnWidth(_ width: CGFloat) {
    drawnWidth = width
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    widthMask.frame = CGRect(x: 0, y: 0, width: max(0, width), height: bounds.height)
    let shift = width - bounds.width
    let transform = CATransform3DMakeTranslation(shift, 0, 0)
    pills.layer?.transform = transform
    escapeKey.layer?.transform = transform
    noticeDismissButton.layer?.transform = transform
    if abs(shift) < 0.5 {
      field.layer?.mask = nil
    } else {
      let anchor = pills.isHidden ? escapeKey.frame.minX : pills.frame.minX
      let fieldWidth = max(0, anchor + shift - 12 - field.frame.minX)
      fieldClip.frame = CGRect(x: 0, y: 0, width: fieldWidth, height: max(field.bounds.height, 1))
      field.layer?.mask = fieldClip
    }
    CATransaction.commit()
  }

  override func layout() {
    layoutCount += 1
    super.layout()
    let g = CommandBarGeometry.self
    let scale = window?.backingScaleFactor ?? 2
    let hairline = 1 / scale
    effectView.frame = bounds
    surfaceTint.frame = bounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    innerEdge.frame = bounds
    CATransaction.commit()

    // Field row: magnifier, [scope chip], field, pills, esc.
    magnifier.frame = NSRect(x: g.inputLeading, y: (g.inputHeight - 18) / 2, width: 18, height: 18)
    var fieldX = magnifier.frame.maxX + 12
    if !scopeChip.isHidden {
      let chipWidth = ceil(scopeChip.fittingSize.width) + 16     // 8 pt padding on each side
      let chipHeight = ceil(scopeChip.fittingSize.height) + 6
      scopeChip.frame = NSRect(x: fieldX, y: (g.inputHeight - chipHeight) / 2, width: chipWidth, height: chipHeight)
      fieldX = scopeChip.frame.maxX + 10
    }
    let escSize = escapeKey.size
    escapeKey.frame = NSRect(x: bounds.width - 14 - escSize.width, y: (g.inputHeight - escSize.height) / 2,
                             width: escSize.width, height: escSize.height)
    let pillsSize = pills.size
    pills.frame = NSRect(x: escapeKey.frame.minX - 8 - pillsSize.width, y: (g.inputHeight - pillsSize.height) / 2,
                         width: pillsSize.width, height: pillsSize.height)
    // The query field keeps a minimum width: in a narrow window the pills give way (the keys still filter).
    let fieldRight = pills.frame.minX - 12
    pills.isHidden = fieldRight - fieldX < Self.minimumFieldWidth
    let fieldHeight = ceil(field.intrinsicContentSize.height)
    let available = (pills.isHidden ? escapeKey.frame.minX - 12 : fieldRight) - fieldX
    field.frame = NSRect(x: fieldX, y: (g.inputHeight - fieldHeight) / 2,
                         width: max(0, available), height: fieldHeight)

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
    hintDivider.isHidden = !hasResults
    hintStrip.isHidden = !hasResults
    divider.frame = NSRect(x: 0, y: dividerY, width: bounds.width, height: hairline)
    let listTop = dividerY + 1 + g.listPadding
    let stripTop = bounds.height - g.hintStripHeight
    hintStrip.frame = NSRect(x: 0, y: stripTop, width: bounds.width, height: g.hintStripHeight)
    hintDivider.frame = NSRect(x: 0, y: stripTop - 1, width: bounds.width, height: hairline)
    let showsColumn = !previewColumn.isHidden && hasResults
    let columnWidth = showsColumn ? g.previewColumnWidth : 0
    let listWidth = showsColumn ? bounds.width - g.listPadding - columnWidth : bounds.width - 2 * g.listPadding
    scrollView.frame = NSRect(x: g.listPadding, y: listTop, width: max(0, listWidth),
                              height: max(0, stripTop - 1 - g.listPadding - listTop))
    if showsColumn {
      previewColumn.frame = NSRect(x: bounds.width - columnWidth, y: divider.frame.maxY,
                                  width: columnWidth, height: max(0, hintDivider.frame.minY - divider.frame.maxY))
    }
    table.tableColumns.first?.width = scrollView.contentSize.width
    syncSelectionIndicator(animated: false)
    if !keepsDrawnWidth, !widthMotion.isRunning { drawnWidth = bounds.width }
    applyDrawnWidth(drawnWidth)
  }
}
