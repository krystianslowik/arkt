import AppKit

/// Invisible strip centered on the sidebar's trailing edge. Dragging reports the proposed width
/// (unclamped; the owner clamps); a double-click restores the default width.
@MainActor
public final class SidebarResizeHandle: NSView {
  /// Which ways the sidebar edge can still move; drives the cursor shape at the limits.
  public enum Directions: Equatable, Sendable { case both, widenOnly, narrowOnly }

  public var onWidthChange: ((CGFloat) -> Void)?
  private let metrics: ShellMetrics
  private var dragStartX: CGFloat = 0
  private var dragStartWidth: CGFloat = 0
  private var isDragging = false

  public init(metrics: ShellMetrics = .standard) {
    self.metrics = metrics
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public nonisolated static func allowedDirections(width: CGFloat, metrics: ShellMetrics) -> Directions {
    if width <= metrics.sidebarMinWidth { return .widenOnly }
    if width >= metrics.sidebarMaxWidth { return .narrowOnly }
    return .both
  }

  public override var mouseDownCanMoveWindow: Bool { false }

  /// The handle is centered on the sidebar edge, so its midX is the current sidebar width.
  private var currentWidth: CGFloat { frame.midX }

  private var cursor: NSCursor {
    switch Self.allowedDirections(width: currentWidth, metrics: metrics) {
    case .both: return NSCursor.columnResize(directions: .all)
    case .widenOnly: return NSCursor.columnResize(directions: .right)
    case .narrowOnly: return NSCursor.columnResize(directions: .left)
    }
  }

  public override func resetCursorRects() {
    addCursorRect(bounds, cursor: cursor)
  }

  public override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 {
      onWidthChange?(metrics.sidebarDefaultWidth)
      return
    }
    isDragging = true
    dragStartX = event.locationInWindow.x
    dragStartWidth = currentWidth
    cursor.set()
  }

  public override func mouseDragged(with event: NSEvent) {
    guard isDragging else { return }
    onWidthChange?(dragStartWidth + event.locationInWindow.x - dragStartX)
    // The pointer usually outruns the handle mid-drag; keep the resize cursor until mouseUp.
    superview?.layoutSubtreeIfNeeded()
    cursor.set()
  }

  public override func mouseUp(with event: NSEvent) {
    guard isDragging else { return }
    isDragging = false
    let inside = bounds.contains(convert(event.locationInWindow, from: nil))
    if !inside { NSCursor.arrow.set() }
    window?.invalidateCursorRects(for: self)
  }
}
