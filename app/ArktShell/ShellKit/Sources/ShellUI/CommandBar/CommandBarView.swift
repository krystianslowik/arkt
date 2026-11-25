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

  #if DEBUG
  /// How many times the rows were reloaded, for tests: a typed keystroke refreshes the rows in place instead (#606,
  /// #839). Debug builds only.
  private(set) var reloadDataCount = 0
  #endif

  override func reloadData() {
    #if DEBUG
    reloadDataCount += 1
    #endif
    super.reloadData()
    rowsDidChange()
  }

  /// The rows' contents changed, by a reload or in place: accessibility follows.
  func rowsDidChange() {
    axProxyRows.invalidate()
  }

  override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
    super.selectRowIndexes(indexes, byExtendingSelection: extend)
    axProxyRows.selectionDidChange()
  }
}

/// Root view of the command bar (design/command-bar/README.md): the field row (magnifier and field), a hairline and
/// the padded results list, on a glass surface. Frames are set in `layout()`.
@MainActor
final class CommandBarView: NSView {
  let field = NSTextField()
  let magnifier = NSImageView()
  let divider = NSView()
  let scrollView = NSScrollView()
  let table = CommandBarTableView(frame: .zero)
  /// Layouts so far.
  private(set) var layoutCount = 0
  let effectView = NSVisualEffectView()
  let surfaceTint = NSView()
  private let innerEdge = CALayer()

  /// The appearance the bar draws in, taken from the window behind it when it shows (the panel itself has no
  /// theme). Setting it recolors every part.
  private(set) var flavor: ThemeFlavor = .dark
  /// Reduce Transparency: an opaque surface instead of the blur. Injected so tests can run both.
  var reduceTransparency: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
  /// Increase Contrast: a 1 pt edge, and tertiary text in the secondary color. Injected so tests can run both.
  var increaseContrast: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
  /// Whether the last `apply(flavor:)` drew the Increase Contrast variant.
  private(set) var drawsIncreasedContrast = false

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilitySubrole(.dialog)
    setAccessibilityLabel("Command bar")
    setAccessibilityIdentifier(AXID.CommandBar.root)
    layer?.cornerRadius = CommandBarGeometry.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true

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

    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = ShellType.commandInput.font
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    field.cell?.lineBreakMode = .byClipping
    field.setAccessibilityLabel(Self.placeholder)
    field.setAccessibilityIdentifierWithCell(AXID.CommandBar.field)
    addSubview(field)

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

    // One tracking area for the life of the view (never per show): pointer moves select the row under them.
    table.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                         owner: self, userInfo: nil))

    scrollView.documentView = table
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.automaticallyAdjustsContentInsets = false
    addSubview(scrollView)
    apply(flavor: .dark)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  static let placeholder = "Search or enter address"

  /// Called with the result row under the pointer when it moves over one. Only moves select, so a pointer that
  /// already rests where the bar appears does not change the selection.
  var onHoverRow: ((Int) -> Void)?

  // MARK: Appearance

  /// Recolors the bar for `flavor` and applies Reduce Transparency and Increase Contrast. Called on every show.
  func apply(flavor: ThemeFlavor) {
    self.flavor = flavor
    appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    let opaque = reduceTransparency()
    drawsIncreasedContrast = increaseContrast()
    effectView.isHidden = opaque
    surfaceTint.layer?.backgroundColor = (opaque ? ShellTokens.commandBarSurfaceOpaque
                                                 : ShellTokens.commandBarSurface).resolve(flavor).cgColor
    // The 0.5 pt outer edge; Increase Contrast draws the 1 pt `increasedContrastEdge` as a layer border instead, so
    // nothing changes size.
    layer?.borderWidth = drawsIncreasedContrast ? 1 : 0.5
    layer?.borderColor = (drawsIncreasedContrast ? ShellTokens.increasedContrastEdge : ShellTokens.commandBarBorder)
      .resolve(flavor).cgColor
    innerEdge.borderColor = ShellTokens.commandBarInnerEdge.resolve(flavor).cgColor
    divider.layer?.backgroundColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    field.textColor = ShellTokens.commandBarText.resolve(flavor).nsColor()
    refreshPlaceholder()
    refreshMagnifier()
  }

  private var shownPlaceholder: (flavor: ThemeFlavor, increasedContrast: Bool)?

  private func refreshPlaceholder() {
    // A show repeats the previous placeholder: setting it again would redraw the field in the first frame's commit.
    if let shown = shownPlaceholder, shown.flavor == flavor, shown.increasedContrast == drawsIncreasedContrast { return }
    shownPlaceholder = (flavor, drawsIncreasedContrast)
    let color = drawsIncreasedContrast ? ShellTokens.commandBarSecondaryText : ShellTokens.commandBarTertiaryText
    field.placeholderAttributedString = NSAttributedString(string: Self.placeholder, attributes: [
      .font: ShellType.commandInput.font,
      .foregroundColor: color.resolve(flavor).nsColor(),
    ])
  }

  private func refreshMagnifier() {
    magnifier.image = SymbolImageCache.shared.symbol("magnifyingglass", box: CommandBarGeometry.magnifierSize,
                                                     color: ShellTokens.commandBarSecondaryText.resolve(flavor),
                                                     scale: shellBackingScale)
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    refreshMagnifier()
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
    if row >= 0, row < table.numberOfRows { onHoverRow?(row) }
  }

  // MARK: Layout

  override func layout() {
    layoutCount += 1
    super.layout()
    let g = CommandBarGeometry.self
    let scale = window?.backingScaleFactor ?? 2
    effectView.frame = bounds
    surfaceTint.frame = bounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    innerEdge.frame = bounds
    CATransaction.commit()

    magnifier.frame = NSRect(x: g.inputLeading, y: (g.inputHeight - g.magnifierSize) / 2, width: g.magnifierSize,
                             height: g.magnifierSize)
    let fieldX = magnifier.frame.maxX + g.magnifierGap - g.labelInset
    let fieldHeight = ceil(field.intrinsicContentSize.height)
    field.frame = NSRect(x: fieldX, y: ((g.inputHeight - fieldHeight) / 2).rounded(),
                         width: max(0, bounds.width - g.inputLeading - fieldX), height: fieldHeight)

    let hasResults = bounds.height > g.inputHeight
    divider.isHidden = !hasResults
    scrollView.isHidden = !hasResults
    divider.frame = NSRect(x: 0, y: g.inputHeight, width: bounds.width, height: 1 / scale)
    let listTop = g.inputHeight + 1 + g.listTopPadding
    scrollView.frame = NSRect(x: g.listSidePadding, y: listTop, width: max(0, bounds.width - 2 * g.listSidePadding),
                              height: max(0, bounds.height - listTop - g.listBottomPadding))
    table.tableColumns.first?.width = scrollView.contentSize.width
  }
}
