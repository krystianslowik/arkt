import AppKit
import Motion

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
  /// Toasts while a split is shown (the single card is hidden then): above every pane, centered on the whole content
  /// area like on the single card [I] (BH-190 deferred). `ShellRootView.showsSplit` moves it here and back.
  var toastView: ToastView? {
    didSet {
      guard toastView !== oldValue else { return }
      oldValue?.removeFromSuperview()
      if let toastView { addSubview(toastView, positioned: .above, relativeTo: nil) }
      needsLayout = true
    }
  }

  /// The new factors after a drag, a double-click or an accessibility adjustment; called once per change, and not
  /// for a drag that ends where it began.
  public var onCommitFactors: (@MainActor ([Double]) -> Void)?
  /// A click asked to focus (or, on a closed pane's placeholder, to reopen) pane N.
  public var onFocusRequest: (@MainActor (Int) -> Void)?
  /// Pane N's close button was clicked or pressed (#388).
  public var onCloseRequest: (@MainActor (Int) -> Void)?
  /// Read when a reflow starts; tests replace it. Reduce Motion swaps the spring for a short crossfade.
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { for card in cards { card.closeButton?.reducesMotion = reduceMotion } }
  }
  /// A reflow is moving the panes to their frames.
  public var isReflowing: Bool { reflow != nil }

  let pacer = FramePacer()
  private var pacerSession = 0
  private let metrics: ShellMetrics
  private var cards: [ContentCardView] = []
  private var dividerViews: [SplitDividerView] = []
  private var placeholders: [Int: SplitPanePlaceholderView] = [:]
  private var draggingIndex: Int?
  /// `liveFactors` when the running drag began; a drag that ends there commits nothing.
  private var factorsAtDragStart: [Double] = []
  /// The running reflow (#388): where each shown pane started (nil: already at its target), the spring's length in
  /// points and how far along it is.
  private var reflow: (from: [CGRect?], distance: Double, progress: CGFloat)?
  /// The reflow's clock; tests freeze it and step the driver themselves.
  var reflowClock: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  private(set) lazy var reflowDriver = SpringDriver(now: { [weak self] in self?.reflowClock() ?? CACurrentMediaTime() },
                                                    reduceMotion: { [weak self] in self?.reduceMotion() ?? true })

  /// The gap between pane cards; it is the divider's hit area. TODO(measure) PARITY(NEEDS-RUNTIME-CHECK RT-37)
  public var gap: CGFloat { metrics.cardInsetRight }

  public init(metrics: ShellMetrics = .standard) {
    self.metrics = metrics
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.splitGroup)
    setAccessibilityIdentifier(AXID.Split.container)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }

  public override func accessibilitySplitters() -> [Any]? { dividers }

  public override func accessibilityChildren() -> [Any]? {
    NSAccessibility.unignoredChildren(from: paneCards + dividers + (toastView.map { [$0] } ?? []))
  }

  // MARK: Showing panes

  /// Shows `panes` (at most `SplitLayoutInfo.maximumPanes`) along `axis` with `factors` (normalized here). A nil
  /// pane is a closed pane and shows a placeholder (decision 6). Ends any running drag without committing.
  ///
  /// `animated` (a pane closed by its X, #388): every page still shown moves from where it is on screen to its new
  /// frame on one interruptible spring; a reflow still running hands over its position and speed. The model state
  /// (`paneCount`, `liveFactors`, the cards' pages) changes at once; only the presented frames move. Reduce Motion
  /// sets the frames at once under a short crossfade.
  public func show(panes: [NSView?], axis: SplitAxis, factors: [Double], animated: Bool = false) {
    cancelDrag()
    let onScreen = animated ? framesOnScreen() : [:]
    let handover = endReflow()
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
      card.allowsClose = shown && panes[index] != nil
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
    if animated { beginReflow(from: onScreen, handover: handover) }
    applyFrames()
  }

  // MARK: Reflow (#388)

  /// Each shown page's card frame as it is on screen now, by page.
  private func framesOnScreen() -> [ObjectIdentifier: CGRect] {
    var frames: [ObjectIdentifier: CGRect] = [:]
    for card in paneCards {
      guard let page = card.contentView else { continue }
      frames[ObjectIdentifier(page)] = card.frame
    }
    return frames
  }

  /// Starts the spring from `onScreen` (by page) to the current layout. A page new to the split starts at its target.
  private func beginReflow(from onScreen: [ObjectIdentifier: CGRect],
                           handover: (value: Double, velocity: Double, distance: Double)?) {
    guard paneCount > 0, bounds.width > 0, bounds.height > 0 else { return }
    if reduceMotion() {
      SplitReflow.crossfade(layer)
      return
    }
    let targets = targetFrames().panes
    let from: [CGRect?] = paneCards.map { card in card.contentView.flatMap { onScreen[ObjectIdentifier($0)] } }
    let distance = SplitReflow.distance(from: zip(from, targets).map { $0 ?? $1 }, to: targets)
    guard distance >= 0.5 else { return }
    let velocity = handover.map {
      SplitReflow.carriedVelocity($0.velocity, distance: $0.distance, progress: $0.value / max($0.distance, 1),
                                  newDistance: distance)
    } ?? 0
    reflow = (from, distance, 0)
    reflowDriver.animate(in: self, from: 0, to: distance, initialVelocity: velocity,
                         parameters: SplitReflow.parameters) { [weak self] value in
      guard let self, self.reflow != nil else { return }
      self.reflow?.progress = CGFloat(value / distance)
      self.applyFrames()
    } completion: { [weak self] finished in
      guard finished, let self else { return }
      self.reflow = nil
      self.applyFrames()
    }
  }

  /// Ends a running reflow where it is (the next `applyFrames` sets the targets). Returns its spring state, so a new
  /// reflow can carry its speed.
  @discardableResult
  private func endReflow() -> (value: Double, velocity: Double, distance: Double)? {
    guard let running = reflow else { return nil }
    reflow = nil
    guard let state = reflowDriver.stop() else { return nil }
    return (state.value, state.velocity, running.distance)
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
    layoutToast()
  }

  private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

  private func targetFrames() -> SplitFrames {
    SplitLayout.frames(in: bounds, axis: axis, factors: liveFactors, gap: gap, scale: backingScale)
  }

  /// The layout's frames, or while a reflow runs, each pane on its way there and the dividers in the gaps between.
  private func applyFrames() {
    guard paneCount > 0 else { return }
    var frames = targetFrames()
    if let reflow {
      frames.panes = zip(frames.panes, reflow.from).map { target, from in
        from.map { SplitReflow.frame(from: $0, to: target, progress: reflow.progress, scale: backingScale) } ?? target
      }
      frames.dividers = SplitReflow.dividers(between: frames.panes, axis: axis)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (card, frame) in zip(cards, frames.panes) where card.frame != frame { card.frame = frame }
    for (divider, frame) in zip(dividerViews, frames.dividers) where divider.frame != frame { divider.frame = frame }
    CATransaction.commit()
  }

  private func layoutToast() {
    guard let toastView else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    toastView.frame = toastView.frame(centeredIn: bounds)
    CATransaction.commit()
  }

  private func updateBorderEmphasis() {
    for (index, card) in cards.enumerated() {
      let focused = index == focusedIndex
      card.borderEmphasis = focused ? 1 : 0.5
      card.setAccessibilitySelected(focused)
    }
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
    endReflow()
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
    endReflow()
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
    endReflow()
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
    if window == nil {
      cancelDrag()
      if endReflow() != nil { applyFrames() }
    }
  }

  // MARK: Pointer

  /// The pane a mouse-down at `point` (in this view) focuses: nil outside every pane and on a shown close button,
  /// whose click closes its pane instead of focusing it first.
  public func paneIndex(forMouseDownAt point: CGPoint) -> Int? {
    guard let index = paneCards.firstIndex(where: { !$0.isHidden && $0.frame.contains(point) }) else { return nil }
    if let button = paneCards[index].closeButton, button.isRevealed, !button.isHidden,
       button.bounds.contains(button.convert(point, from: self)) {
      return nil
    }
    return index
  }

  // MARK: Building blocks

  private func makeCard() -> ContentCardView {
    let card = ContentCardView(metrics: metrics)
    let index = cards.count
    card.setAccessibilityIdentifier(AXID.Split.pane)
    card.autoresizingMask = []
    card.installCloseButton()
    card.closeButton?.reducesMotion = reduceMotion
    card.onClose = { [weak self] in self?.onCloseRequest?(index) }
    addSubview(card, positioned: .below, relativeTo: dividerViews.first)
    return card
  }

  private func makeDivider(_ index: Int) -> SplitDividerView {
    let divider = SplitDividerView(index: index)
    divider.container = self
    addSubview(divider, positioned: toastView == nil ? .above : .below, relativeTo: toastView)
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
    setAccessibilityIdentifier(AXID.Split.reopen)
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
