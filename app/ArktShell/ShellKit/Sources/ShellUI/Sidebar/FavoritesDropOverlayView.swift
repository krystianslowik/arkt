import AppKit

/// The drop target for sidebar drags on the Favorites band (BH-047): a tab dropped above the Space title becomes a
/// Favorite. It covers the band only; the Space page below is its outline's drop target (#104), which also takes a
/// Favorite dragged down onto it. Like the split overlay, it exists only while a sidebar drag runs, accepts only the
/// private `.sidebarNode` type, and its `hitTest` returns nil so clicks always pass through.
///
/// While a favorite-able tab hovers the band, one translucent highlight covers it. The zone math is
/// `FavoritesDrop`'s; the closures answer the target and perform the drop, so tests drive `preview(at:)` and
/// `drop(node:at:)` directly (the `SplitDropOverlayView` pattern).
@MainActor
public final class FavoritesDropOverlayView: NSView {
  /// What a drop of `node` at `point` would target, given the band rect and the bounds (overlay coordinates).
  /// Nil: the drop is refused here.
  var onTarget: (@MainActor (_ node: NodeID, _ point: CGPoint, _ band: CGRect, _ bounds: CGRect)
    -> SidebarLocation?)?
  /// Performs the drop of `node` on `location`; false when it was refused (a full Favorites section toasts there).
  var onDrop: (@MainActor (_ node: NodeID, _ location: SidebarLocation) -> Bool)?
  /// The tab being dragged; set when the overlay is shown for a drag.
  private(set) var node: NodeID?

  /// The highlight over the Favorites band while a drop there is offered.
  let highlightLayer = CALayer()
  private var band: CGRect = .null
  private var lastTarget: SidebarLocation?

  public init() {
    super.init(frame: .zero)
    wantsLayer = true
    registerForDraggedTypes([.sidebarNode])
    highlightLayer.cornerRadius = FavoritesLayout.tileCornerRadius
    highlightLayer.cornerCurve = .continuous
    highlightLayer.borderWidth = 2
    highlightLayer.isHidden = true
    layer?.addSublayer(highlightLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  /// Clicks pass through to the sidebar below; drags find the overlay through its registered type.
  public override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Starts a drag of `node`: the band rect (overlay coordinates) and the highlight reset.
  func begin(node: NodeID, band: CGRect) {
    self.node = node
    self.band = band
    lastTarget = nil
    showHighlight(false)
  }

  /// Ends the drag: the highlight hides and the next drag starts fresh.
  func end() {
    node = nil
    band = .null
    lastTarget = nil
    showHighlight(false)
  }

  // MARK: Preview and drop (driven by the dragging callbacks below, and by tests)

  /// The target of a drop at `point` (overlay coordinates); updates the band highlight on a change.
  @discardableResult
  func preview(at point: CGPoint) -> SidebarLocation? {
    let target = node.flatMap { onTarget?($0, point, band, bounds) ?? nil }
    if target != lastTarget {
      lastTarget = target
      if case .favorites = target { showHighlight(true) } else { showHighlight(false) }
    }
    return target
  }

  /// Drops `node` at `point`: the window performs it, or refuses it (a full Favorites section shows its toast).
  func drop(node: NodeID, at point: CGPoint) -> Bool {
    guard let target = onTarget?(node, point, band, bounds) else { return false }
    return onDrop?(node, target) ?? false
  }

  private func showHighlight(_ shown: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if shown, highlightLayer.isHidden { applyColors() }
    highlightLayer.frame = band
    highlightLayer.isHidden = !shown
    CATransaction.commit()
  }

  /// The accent color resolved for the current appearance, read when the highlight appears.
  private func applyColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      highlightLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
      highlightLayer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
    }
  }

  // MARK: NSDraggingDestination

  public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    // An Opt-drag (copy, GS-014) duplicates on the page's rows only; the band moves.
    guard sender.draggingSourceOperationMask.contains(.move) else { return [] }
    return preview(at: convert(sender.draggingLocation, from: nil)) == nil ? [] : .move
  }

  public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    lastTarget = nil
    showHighlight(false)
  }

  public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let point = convert(sender.draggingLocation, from: nil)
    lastTarget = nil
    showHighlight(false)
    guard let string = sender.draggingPasteboard.string(forType: .sidebarNode), let node = UUID(uuidString: string)
    else { return false }
    return drop(node: node, at: point)
  }
}
