import AppKit

/// Lays out the pane cards of one split side by side or stacked, with a `SplitDividerView` in each gap. Each pane is
/// a `ContentCardView` (its own rounded clip, hairline, shadow and Toolbar). Frames come from `SplitLayout` and are
/// set directly with actions disabled; no Auto Layout. A divider drag keeps `liveFactors` here and sets frames per
/// event; the source hears about it once, through `onCommitFactors`, when the drag ends.
@MainActor
public final class SplitContainerView: NSView {
  /// Pane cards in pane order. Only the first `paneCount` show; cards are reused across `show` calls, never rebuilt.
  public var paneCards: [ContentCardView] { Array(cards.prefix(paneCount)) }
  /// The dividers between the shown panes (`paneCount - 1`), reused like the cards.
  public var dividers: [SplitDividerView] { Array(dividerViews.prefix(max(0, paneCount - 1))) }
  public private(set) var paneCount = 0
  public private(set) var axis: SplitAxis = .sideBySide
  /// The factors on screen: the shown ones while idle, the dragged ones during a drag.
  public private(set) var liveFactors: [Double] = []
  /// The focused pane draws the stronger border. PARITY(NEEDS-RUNTIME-CHECK RT-37)
  public var focusedIndex = 0 {
    didSet { if focusedIndex != oldValue { updateBorderEmphasis() } }
  }
  /// Pacing of the last finished divider drag.
  public private(set) var lastPacing: FrameStats?

  /// The new factors after a drag, a double-click or an accessibility adjustment; called once per change, and not
  /// for a drag that ends where it began.
  public var onCommitFactors: (@MainActor ([Double]) -> Void)?
  /// A click asked to focus (or, on a closed pane's placeholder, to reopen) pane N.
  public var onFocusRequest: (@MainActor (Int) -> Void)?

  let pacer = FramePacer()
  private var pacerSession = 0
  private let metrics: ShellMetrics
  private var cards: [ContentCardView] = []
  private var dividerViews: [SplitDividerView] = []
  private var placeholders: [Int: SplitPanePlaceholderView] = [:]
  private var draggingIndex: Int?
  /// `liveFactors` when the running drag began; a drag that ends there commits nothing.
  private var factorsAtDragStart: [Double] = []

  /// The gap between pane cards; it is the divider's hit area. TODO(measure) PARITY(NEEDS-RUNTIME-CHECK RT-37)
  public var gap: CGFloat { metrics.cardInsetRight }

  public init(metrics: ShellMetrics = .standard) {
    self.metrics = metrics
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.splitGroup)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }

  public override func accessibilitySplitters() -> [Any]? { dividers }

  // MARK: Showing panes

  /// Shows `panes` (at most `SplitLayoutInfo.maximumPanes`) along `axis` with `factors` (normalized here). A nil
  /// pane is a closed pane and shows a placeholder (decision 6). Ends any running drag without committing.
  public func show(panes: [NSView?], axis: SplitAxis, factors: [Double]) {
    cancelDrag()
    let panes = Array(panes.prefix(SplitLayoutInfo.maximumPanes))
    // Detach pages that move to another card first: `setContent` on their old card would otherwise pull them out
    // of the new one.
    for (index, card) in cards.enumerated() {
      guard let content = card.contentView else { continue }
      if index >= panes.count || panes[index] !== content { card.setContent(nil) }
    }
    while cards.count < panes.count { cards.append(makeCard()) }
    while dividerViews.count < max(0, panes.count - 1) { dividerViews.append(makeDivider(dividerViews.count)) }
    for (index, card) in cards.enumerated() {
      let shown = index < panes.count
      card.isHidden = !shown
      card.setContent(shown ? panes[index] : nil)
      card.setEmptyState(shown && panes[index] == nil ? placeholder(at: index) : nil)
    }
    for (index, divider) in dividerViews.enumerated() {
      divider.isHidden = index >= panes.count - 1
      divider.axis = axis
    }
    paneCount = panes.count
    self.axis = axis
    liveFactors = SplitLayout.normalized(factors, count: panes.count)
    focusedIndex = min(max(focusedIndex, 0), max(0, panes.count - 1))
    updateBorderEmphasis()
    applyFrames()
  }

  // MARK: Layout

  public override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    needsLayout = true
  }

  /// A move between 1x and 2x screens puts the pane edges on the new pixel grid.
  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    needsLayout = true
  }

  /// A window resize keeps `liveFactors` and only recomputes frames.
  public override func layout() {
    super.layout()
    applyFrames()
  }

  private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

  private func applyFrames() {
    guard paneCount > 0 else { return }
    let frames = SplitLayout.frames(in: bounds, axis: axis, factors: liveFactors, gap: gap, scale: backingScale)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (card, frame) in zip(cards, frames.panes) where card.frame != frame { card.frame = frame }
    for (divider, frame) in zip(dividerViews, frames.dividers) where divider.frame != frame { divider.frame = frame }
    CATransaction.commit()
  }

  private func updateBorderEmphasis() {
    for (index, card) in cards.enumerated() { card.borderEmphasis = index == focusedIndex ? 1 : 0.5 }
  }

  // MARK: Divider drag (driven by SplitDividerView)

  /// Main-axis position (from the leading edge) of an event's pointer.
  func mainAxisPosition(of event: NSEvent) -> CGFloat {
    SplitLayout.position(of: convert(event.locationInWindow, from: nil), in: bounds, axis: axis)
  }

  /// Where pane `index` currently ends along the main axis, measured from the leading edge.
  func dividerPosition(_ index: Int) -> CGFloat {
    let available = mainLength - gap * CGFloat(max(0, paneCount - 1))
    let lead = liveFactors.prefix(index + 1).reduce(0, +)
    return available * CGFloat(lead) + gap * CGFloat(index)
  }

  private var mainLength: CGFloat { axis == .sideBySide ? bounds.width : bounds.height }

  func beginDividerDrag(_ index: Int) {
    guard draggingIndex == nil, dividers.indices.contains(index) else { return }
    draggingIndex = index
    factorsAtDragStart = liveFactors
    pacerSession = pacer.begin("split-divider", in: self)
  }

  func dragDivider(_ index: Int, to position: CGFloat) {
    guard draggingIndex == index else { return }
    liveFactors = SplitLayout.factors(dragging: index, to: position, in: bounds, axis: axis, factors: liveFactors,
                                      gap: gap, minimum: SplitLayout.minimumPaneLength)
    applyFrames()
  }

  func endDividerDrag(_ index: Int) {
    guard draggingIndex == index else { return }
    draggingIndex = nil
    if let stats = pacer.end(session: pacerSession) { lastPacing = stats }
    // A plain click on the gap (or the first click of a double-click) moved nothing: no source write.
    if liveFactors != factorsAtDragStart { onCommitFactors?(liveFactors) }
  }

  /// Double-click on a divider: every pane gets an equal share, committed once. [I] PARITY(NEEDS-RUNTIME-CHECK RT-33)
  func equalize() {
    guard draggingIndex == nil, paneCount >= 2 else { return }
    let equal = SplitLayout.equalShares(paneCount)
    // Already equal (every new split starts that way): no source write.
    guard liveFactors != equal else { return }
    liveFactors = equal
    applyFrames()
    onCommitFactors?(liveFactors)
  }

  /// Accessibility increment or decrement: moves divider `index` by `delta` points and commits once.
  func nudgeDivider(_ index: Int, by delta: CGFloat) -> Bool {
    guard draggingIndex == nil, dividers.indices.contains(index) else { return false }
    let factors = SplitLayout.factors(dragging: index, to: dividerPosition(index) + delta, in: bounds, axis: axis,
                                      factors: liveFactors, gap: gap, minimum: SplitLayout.minimumPaneLength)
    guard factors != liveFactors else { return false }
    liveFactors = factors
    applyFrames()
    onCommitFactors?(liveFactors)
    return true
  }

  /// Ends a running drag where it is, without committing (a new `show`, or the view leaving its window).
  private func cancelDrag() {
    guard draggingIndex != nil else { return }
    draggingIndex = nil
    if let stats = pacer.end(session: pacerSession) { lastPacing = stats }
  }

  /// Leaving the window ends any drag (the pacer's display link would otherwise keep ticking).
  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil { cancelDrag() }
  }

  // MARK: Building blocks

  private func makeCard() -> ContentCardView {
    let card = ContentCardView(metrics: metrics)
    card.autoresizingMask = []
    addSubview(card, positioned: .below, relativeTo: dividerViews.first)
    return card
  }

  private func makeDivider(_ index: Int) -> SplitDividerView {
    let divider = SplitDividerView(index: index)
    divider.container = self
    addSubview(divider, positioned: .above, relativeTo: nil)
    return divider
  }

  private func placeholder(at index: Int) -> SplitPanePlaceholderView {
    if let existing = placeholders[index] { return existing }
    let view = SplitPanePlaceholderView()
    view.onClick = { [weak self] in self?.onFocusRequest?(index) }
    placeholders[index] = view
    return view
  }
}

/// What a closed pane shows (decision 6): an empty card; a click asks to reopen the page. [I]
/// PARITY(NEEDS-RUNTIME-CHECK RT-36)
@MainActor
final class SplitPanePlaceholderView: NSView {
  var onClick: (@MainActor () -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel("Reopen page")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) { onClick?() }

  override func accessibilityPerformPress() -> Bool {
    onClick?()
    return true
  }
}
