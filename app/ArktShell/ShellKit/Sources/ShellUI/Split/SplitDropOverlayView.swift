import AppKit

/// What a drop at the pointer would do.
public enum SplitDropTarget: Equatable, Sendable {
  /// Nothing: no preview, and the drag is refused here.
  case none
  /// The new or moved pane lands at this frame, in the overlay's (and the split container's) coordinates.
  case pane(CGRect)
  /// The drop is taken but refused with a notice: the split is full (BH-116). No preview.
  case full
}

/// The drop target for sidebar tabs dragged onto the page (S7, GS-011). It covers the content area only while a sidebar
/// drag runs: page views (WKWebView now, Chromium's view later) register for drags themselves and are the deepest view
/// under the pointer, and a permanent target above them would also take their clicks. It accepts only the private
/// `.sidebarNode` type, and `hitTest` returns nil, so clicks always reach the page.
///
/// While the pointer moves, one translucent preview layer shows where the pane will land. Its frame is set directly
/// with actions disabled, and only when the zone under the pointer changes.
@MainActor
public final class SplitDropOverlayView: NSView {
  /// What a drop of `node` in `zone` would do; `bounds` is the content area. Asked once per zone change.
  var onTarget: (@MainActor (_ node: NodeID, _ zone: SplitDropZone, _ bounds: CGRect) -> SplitDropTarget)?
  /// Performs the drop of `node` in `zone`; false when it was refused.
  var onDrop: (@MainActor (_ node: NodeID, _ zone: SplitDropZone) -> Bool)?
  /// The tab being dragged; set when the overlay is shown for a drag.
  var node: NodeID?

  /// The drop preview: a translucent rounded rect at the would-be pane frame.
  let previewLayer = CALayer()
  /// Preview frame changes so far (tests check that a pointer moving inside one zone changes nothing).
  private(set) var previewUpdateCount = 0
  private var lastZone: SplitDropZone?
  private var lastBounds: CGRect = .null
  private var lastTarget: SplitDropTarget = .none

  public init(metrics: ShellMetrics = .standard) {
    super.init(frame: .zero)
    wantsLayer = true
    registerForDraggedTypes([.sidebarNode])
    previewLayer.cornerRadius = metrics.cardCornerRadius
    previewLayer.cornerCurve = .continuous
    previewLayer.borderWidth = 2
    previewLayer.isHidden = true
    layer?.addSublayer(previewLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Clicks pass through to the page below; drags find the overlay through its registered type.
  public override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// Starts a drag of `node`: forgets the last zone and hides the preview.
  func begin(node: NodeID) {
    self.node = node
    reset()
  }

  /// Ends the drag: the preview hides and the next drag starts fresh.
  func end() {
    node = nil
    reset()
  }

  // MARK: Preview and drop (driven by the dragging callbacks below, and by tests)

  /// Moves the preview to the target of the zone under `point` (overlay coordinates) and returns that target.
  @discardableResult
  func preview(at point: CGPoint) -> SplitDropTarget {
    let zone = SplitDropZone.zone(for: point, in: bounds)
    guard zone != lastZone || bounds != lastBounds else { return lastTarget }
    lastZone = zone
    lastBounds = bounds
    let target = zone.flatMap { zone in node.flatMap { onTarget?($0, zone, bounds) } } ?? .none
    lastTarget = target
    showPreview(for: target)
    return target
  }

  /// Drops `node` at `point`: the window performs it, or refuses it (a full split shows its toast there).
  func drop(node: NodeID, at point: CGPoint) -> Bool {
    guard let zone = SplitDropZone.zone(for: point, in: bounds) else { return false }
    return onDrop?(node, zone) ?? false
  }

  private func reset() {
    lastZone = nil
    lastBounds = .null
    lastTarget = .none
    showPreview(for: .none)
  }

  private func showPreview(for target: SplitDropTarget) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if case .pane(let frame) = target {
      if previewLayer.isHidden { applyColors() }
      previewLayer.frame = frame
      previewLayer.isHidden = false
      previewUpdateCount += 1
    } else {
      previewLayer.isHidden = true
    }
    CATransaction.commit()
  }

  /// The accent color resolved for the current appearance, read when the preview appears.
  private func applyColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      previewLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
      previewLayer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
    }
  }

  // MARK: NSDraggingDestination

  public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    // An Opt-drag (copy, GS-014) duplicates on the sidebar rows only; the page moves the tab.
    guard sender.draggingSourceOperationMask.contains(.move) else { return [] }
    return preview(at: convert(sender.draggingLocation, from: nil)) == .none ? [] : .move
  }

  public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    reset()
  }

  public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let point = convert(sender.draggingLocation, from: nil)
    reset()
    guard let string = sender.draggingPasteboard.string(forType: .sidebarNode), let node = UUID(uuidString: string)
    else { return false }
    return drop(node: node, at: point)
  }
}
