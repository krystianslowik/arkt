import AppKit
import Carbon.HIToolbox

/// A drop the window performs (#104): the dragged nodes, where they go, and how.
public struct SidebarDropRequest: Equatable, Sendable {
  public var nodes: [NodeID]
  public var target: SidebarDropTarget
  /// Opt-drag (GS-014): copies land at the target and the originals stay.
  public var duplicate: Bool
  /// The drag started in another window: the receiving window shows the dropped tab and takes its page over
  /// without a reload (Tab Handoff, #300).
  public var fromOtherWindow: Bool

  public init(nodes: [NodeID], target: SidebarDropTarget, duplicate: Bool, fromOtherWindow: Bool) {
    self.nodes = nodes; self.target = target; self.duplicate = duplicate; self.fromOtherWindow = fromOtherWindow
  }
}

/// One Space page's outline as a drag source and a drop target (#104). The outline forwards the dragging callbacks
/// here; the rules are `SidebarDropResolver`'s, the motion `SidebarDropPreview`'s, and every drop goes to the window
/// through `onDrop`, which performs it on the source. Tests drive `update(at:payload:)`, `perform(...)` and `exit()`
/// directly, the overlays' pattern.
@MainActor
public final class SidebarOutlineDrop {
  public let preview: SidebarDropPreview
  /// Performs a drop; false when it was refused (the window reports why).
  public var onDrop: (@MainActor (SidebarDropRequest) -> Bool)?
  /// Dropped text or a link (GS-015): a new tab for `url` at `placement`; false when refused.
  public var onTextDrop: (@MainActor (_ url: URL, _ title: String, _ placement: SidebarDropPlacement) -> Bool)?
  /// The pointer rested at the page's edge (GS-012): -1 for the previous Space, 1 for the next.
  public var onEdgeDwell: (@MainActor (Int) -> Void)?
  /// A drag that started here ended over no window (GS-013): one tab, released at a screen point.
  public var onDragOut: (@MainActor (NodeID, NSPoint) -> Void)?

  var reduceMotion: @MainActor () -> Bool {
    get { preview.reduceMotion }
    set { preview.reduceMotion = newValue }
  }
  /// The motion and dwell clock, shared with the preview's display link.
  var now: @MainActor () -> Double {
    get { preview.now }
    set { preview.now = newValue }
  }
  /// BH-024: a light tick when the drop point moves to a new place.
  var haptic: @MainActor () -> Void = {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
  }
  /// Whether the drag that just ended was cancelled with Escape (AppKit reports a cancel and a miss alike).
  var endedByEscape: @MainActor () -> Bool = {
    guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
    return Int(event.keyCode) == kVK_Escape
  }
  /// The frames of the app's visible windows, screen coordinates.
  var windowFrames: @MainActor () -> [CGRect] = { NSApp.windows.filter(\.isVisible).map(\.frame) }

  /// What a drag that starts here carries; set when the session begins, cleared when it ends.
  public internal(set) var sourcePayload: SidebarDragPayload?

  private unowned let controller: SidebarOutlineController
  private var outline: SidebarOutlineView { controller.outlineView }
  private var dwell = SpaceEdgeDwell()
  private var springLoad = FolderSpringLoad()
  /// The rows as the resolver sees them, read once per hover: a drag changes no row until it drops.
  private var rows: [SidebarDropRow]?
  private var lastTarget: SidebarDropTarget?
  /// Folders this drag opened by resting on them: a cancel closes them again, a drop keeps open the ones it lands in.
  private var springOpened: [NodeID] = []

  init(controller: SidebarOutlineController) {
    self.controller = controller
    preview = SidebarDropPreview(outline: controller.outlineView)
    controller.outlineView.registerForDraggedTypes([.sidebarNode, .sidebarNodes, .URL, .string])
  }

  // MARK: Destination

  /// Previews a drop of `payload` at `point` (outline coordinates) and returns its target; nil is refused here.
  @discardableResult
  public func update(at point: NSPoint, payload: SidebarDragPayload) -> SidebarDropTarget? {
    let t = now()
    let target = resolve(at: point, payload: payload)
    if target != lastTarget {
      lastTarget = target
      if target != nil { haptic() }
    }
    preview.show(target, at: t)
    springLoadFolder(under: target, at: t)
    let visible = outline.visibleRect
    if let step = dwell.update(x: point.x - visible.minX, width: visible.width, at: t) { onEdgeDwell?(step) }
    return target
  }

  /// Opens a closed folder the drag rests on, on #109's folder spring. The rows change, so they are read again.
  private func springLoadFolder(under target: SidebarDropTarget?, at t: Double) {
    var closed: NodeID?
    if case .folder(let folder, _)? = target, !controller.isFolderOpen(folder) { closed = folder }
    guard let folder = springLoad.update(closedFolder: closed, at: t) else { return }
    controller.toggleFolder(folder, animated: true)
    springOpened.append(folder)
    rows = nil
    lastTarget = nil
    preview.show(nil, at: t)
  }

  /// The drag left this outline or was cancelled over it: the rows spring back, and the folders it opened close.
  public func exit() {
    rows = nil
    lastTarget = nil
    dwell.reset()
    springLoad.reset()
    // Closing a folder changes which row is where, so the rows drop their shifts at once and the folder's own
    // close animation is the motion.
    let closedFolder = closeSpringOpenedFolders(keeping: [])
    preview.clear(dropped: closedFolder, at: now())
  }

  /// Closes the folders this drag opened, except `keep`; true when one closed.
  private func closeSpringOpenedFolders(keeping keep: Set<NodeID>) -> Bool {
    let closing = springOpened.filter { !keep.contains($0) && controller.isFolderOpen($0) }
    springOpened = []
    for folder in closing.reversed() { controller.toggleFolder(folder, animated: true) }
    return !closing.isEmpty
  }

  /// The folders a drop at `target` lands in, the innermost first and every folder above it.
  private func folders(holding target: SidebarDropTarget?) -> Set<NodeID> {
    var location: SidebarLocation?
    switch target {
    case .insert(let at, _, _, _)?: location = at
    case .folder(let folder, _)?: location = .folder(folder)
    case .split(let node, _, _)?: location = controller.source.parent(of: node)
    case nil: location = nil
    }
    var found: Set<NodeID> = []
    while let container = location?.containerNode, found.insert(container).inserted {
      location = controller.source.parent(of: container)
    }
    return found
  }

  /// Drops `payload` at `point`: the window performs it. The preview closes at once either way.
  @discardableResult
  public func perform(payload: SidebarDragPayload, at point: NSPoint, duplicate: Bool, fromOtherWindow: Bool)
    -> Bool {
    rows = nil                                        // read fresh: the source may have changed during the drag
    let target = resolve(at: point, payload: payload)
    _ = closeSpringOpenedFolders(keeping: folders(holding: target))
    endHover(dropped: true)
    guard let target else { return false }
    return onDrop?(SidebarDropRequest(nodes: payload.nodes, target: target, duplicate: duplicate,
                                      fromOtherWindow: fromOtherWindow)) ?? false
  }

  /// Drops `text` (a link or anything to search for) at `point` as a new tab (GS-015).
  @discardableResult
  public func performText(_ text: String, at point: NSPoint) -> Bool {
    rows = nil
    let target = resolve(at: point, payload: SidebarDragPayload(nodes: [], isSingleTab: false))
    _ = closeSpringOpenedFolders(keeping: folders(holding: target))
    endHover(dropped: true)
    guard let url = SidebarTextDrop.url(for: text) else { return false }
    let placement = SidebarTextDrop.location(for: target, space: controller.spaceID)
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return onTextDrop?(url, url.host() ?? trimmed, placement) ?? false
  }

  private func endHover(dropped: Bool) {
    rows = nil
    lastTarget = nil
    dwell.reset()
    springLoad.reset()
    preview.clear(dropped: dropped, at: now())
  }

  private func resolve(at point: NSPoint, payload: SidebarDragPayload) -> SidebarDropTarget? {
    let rows = self.rows ?? displayedRows()
    self.rows = rows
    guard let point = laidOutPoint(forShown: point) else { return lastTarget }
    let row = outline.row(at: point)
    var fractionY: CGFloat = 0
    var fractionX: CGFloat = 0
    if row >= 0 {
      let rect = outline.rect(ofRow: row)
      fractionY = rect.height > 0 ? (point.y - rect.minY) / rect.height : 0
      fractionX = rect.width > 0 ? (point.x - rect.minX) / rect.width : 0
    } else if point.y < 0 {
      return nil
    }
    return SidebarDropResolver.target(
      rows: rows, row: row >= 0 ? row : nil, fractionY: fractionY, fractionX: fractionX, payload: payload,
      space: controller.spaceID, todayCount: controller.source.children(of: .today(controller.spaceID)).count)
  }

  /// Where `point`, over the rows as they are shown, falls in the outline's layout. An open gap shows every row from
  /// its row on one pitch lower (the settled preview, so the answer does not depend on the spring's frame): a point
  /// in the gap is nil, which keeps the current target, and a point below it moves up one pitch.
  private func laidOutPoint(forShown point: NSPoint) -> NSPoint? {
    guard case .insert(_, _, let gapRow, _)? = lastTarget, !reduceMotion(), gapRow >= 0,
          gapRow < outline.numberOfRows else { return point }
    let gapTop = outline.rect(ofRow: gapRow).minY
    let pitch = SidebarMetrics.rowPitch
    if point.y < gapTop { return point }
    if point.y < gapTop + pitch { return nil }
    return NSPoint(x: point.x, y: point.y - pitch)
  }

  /// Every displayed row, described from the source.
  private func displayedRows() -> [SidebarDropRow] {
    let source = controller.source
    let space = controller.spaceID
    return (0..<outline.numberOfRows).map { row in
      let level = max(outline.level(forRow: row), 0)
      guard let item = outline.item(atRow: row) as? OutlineItem, let id = item.nodeID,
            let location = source.parent(of: id) else {
        return SidebarDropRow(node: nil, kind: .divider, location: .today(space), index: 0, level: 0)
      }
      let index = source.children(of: location).firstIndex(of: id) ?? 0
      let kind: SidebarDropRow.Kind
      switch source.node(id) {
      case .folder?: kind = .folder(expanded: controller.isFolderOpen(id))   // a closed folder may show a peek row
      case .split?: kind = .split
      case .tab?, nil:
        if case .split(let split) = location { kind = .pane(split: split) } else { kind = .tab }
      }
      return SidebarDropRow(node: id, kind: kind, location: location, index: index, level: level)
    }
  }

  // MARK: NSDraggingDestination (forwarded by the outline)

  /// The nodes a sidebar drag carries, nil for any other drag.
  func payload(from info: any NSDraggingInfo) -> SidebarDragPayload? {
    let pasteboard = info.draggingPasteboard
    let nodes = pasteboard.string(forType: .sidebarNodes).flatMap(SidebarDragPayload.nodes(fromPasteboardString:))
      ?? pasteboard.string(forType: .sidebarNode).flatMap(UUID.init(uuidString:)).map { [$0] }
    guard let nodes else { return nil }
    let single = nodes.count == 1 && { if case .tab? = controller.source.node(nodes[0]) { true } else { false } }()
    return SidebarDragPayload(nodes: nodes, isSingleTab: single)
  }

  func draggingUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
    let point = outline.convert(info.draggingLocation, from: nil)
    autoscroll(at: point)
    if let payload = payload(from: info) {
      guard update(at: point, payload: payload) != nil else { return [] }
      return info.draggingSourceOperationMask == .copy ? .copy : .move
    }
    guard text(from: info) != nil else { return [] }
    update(at: point, payload: SidebarDragPayload(nodes: [], isSingleTab: false))
    return .copy
  }

  func performDragOperation(_ info: any NSDraggingInfo) -> Bool {
    let point = outline.convert(info.draggingLocation, from: nil)
    if let payload = payload(from: info) {
      let sourceWindow = (info.draggingSource as? NSView)?.window
      return perform(payload: payload, at: point, duplicate: info.draggingSourceOperationMask == .copy,
                     fromOtherWindow: sourceWindow != nil && sourceWindow !== outline.window)
    }
    guard let text = text(from: info) else {
      endHover(dropped: true)
      return false
    }
    return performText(text, at: point)
  }

  private func text(from info: any NSDraggingInfo) -> String? {
    let pasteboard = info.draggingPasteboard
    if let url = NSURL(from: pasteboard) as URL?, !url.isFileURL { return url.absoluteString }
    return pasteboard.string(forType: .string)
  }

  /// Scrolls the page while the pointer rests near its top or bottom edge, a few points per update.
  private func autoscroll(at point: NSPoint) {
    guard let clip = outline.enclosingScrollView?.contentView else { return }
    let visible = outline.visibleRect
    let band: CGFloat = 24
    var delta: CGFloat = 0
    if point.y < visible.minY + band { delta = -8 } else if point.y > visible.maxY - band { delta = 8 }
    guard delta != 0 else { return }
    let maxY = max(outline.bounds.height - visible.height, 0)
    let y = min(max(visible.minY + delta, 0), maxY)
    guard y != visible.minY else { return }
    clip.scroll(to: NSPoint(x: visible.minX, y: y))
    outline.enclosingScrollView?.reflectScrolledClipView(clip)
  }

  // MARK: Source

  /// A drag from this outline began carrying `payload`.
  func sourceBegan(_ payload: SidebarDragPayload, session: NSDraggingSession?) {
    sourcePayload = payload
    // A cancelled drag image slides home; under Reduce Motion it just disappears.
    session?.animatesToStartingPositionsOnCancelOrFail = !reduceMotion()
  }

  /// The drag from this outline ended at `screenPoint` with `operation`: a tab released over no window opens in a
  /// new one (GS-013).
  func sourceEnded(at screenPoint: NSPoint, operation: NSDragOperation) {
    defer { sourcePayload = nil }
    guard let payload = sourcePayload, let node = payload.nodes.first,
          SidebarDragOut.opensWindow(operation: operation, endedByEscape: endedByEscape(), endPoint: screenPoint,
                                     windowFrames: windowFrames(), payload: payload) else { return }
    onDragOut?(node, screenPoint)
  }
}

// MARK: - The outline forwards its dragging callbacks

extension SidebarOutlineView {
  public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    dropHandler?.draggingUpdated(sender) ?? []
  }

  public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    dropHandler?.draggingUpdated(sender) ?? []
  }

  public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
    dropHandler?.exit()
  }

  public override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

  public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    dropHandler?.performDragOperation(sender) ?? false
  }

  public override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {}

  public override func draggingEnded(_ sender: any NSDraggingInfo) {
    dropHandler?.exit()
  }
}
