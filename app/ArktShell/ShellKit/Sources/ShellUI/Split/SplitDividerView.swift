import AppKit

/// The gap between two pane cards of a split, and its hit area. Dragging moves the gap (only the two adjacent
/// panes change); a double-click equalizes every pane, mirroring `SidebarResizeHandle`. The drag itself is run by
/// the owning `SplitContainerView`, which sets frames directly and commits the factors once on mouse-up.
@MainActor
public final class SplitDividerView: NSView {
  /// Accessibility step, in points along the main axis, for increment and decrement.
  static let accessibilityStep: CGFloat = 24

  /// The divider sits between pane `index` and pane `index + 1`.
  public internal(set) var index: Int
  public internal(set) var axis: SplitAxis = .sideBySide {
    didSet {
      guard axis != oldValue else { return }
      setAccessibilityOrientation(Self.accessibilityOrientation(for: axis))
      window?.invalidateCursorRects(for: self)
    }
  }
  weak var container: SplitContainerView?
  /// Pointer position minus the divider's position at mouse-down, so the gap does not jump under the pointer.
  private var grabOffset: CGFloat = 0
  private var isMouseDragging = false

  init(index: Int) {
    self.index = index
    super.init(frame: .zero)
    autoresizingMask = []
    setAccessibilityElement(true)
    setAccessibilityRole(.splitter)
    setAccessibilityLabel("Split View divider")
    setAccessibilityOrientation(Self.accessibilityOrientation(for: axis))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var mouseDownCanMoveWindow: Bool { false }

  // MARK: Programmatic drag (mouse events, tests and the frame-time gate share these)

  /// Starts a drag: the container begins its "split-divider" pacing session.
  public func beginDrag() { container?.beginDividerDrag(index) }

  /// Moves the divider so pane `index` ends at main-axis `position` (from the container's leading edge) and sets
  /// the frames immediately.
  public func drag(to position: CGFloat) { container?.dragDivider(index, to: position) }

  /// Ends the drag: stops the pacing and commits the factors once. A no-op without a running drag.
  public func endDrag() { container?.endDividerDrag(index) }

  // MARK: Mouse

  private var cursor: NSCursor {
    axis == .sideBySide ? NSCursor.columnResize(directions: .all) : NSCursor.rowResize(directions: .all)
  }

  public override func resetCursorRects() {
    addCursorRect(bounds, cursor: cursor)
  }

  public override func mouseDown(with event: NSEvent) {
    guard let container else { return }
    if event.clickCount == 2 {
      container.equalize()
      return
    }
    let pointer = container.mainAxisPosition(of: event)
    grabOffset = pointer - container.dividerPosition(index)
    isMouseDragging = true
    beginDrag()
    cursor.set()
  }

  public override func mouseDragged(with event: NSEvent) {
    guard isMouseDragging, let container else { return }
    // AppKit coalesces drag events: at most one frame update per event, no timers.
    drag(to: container.mainAxisPosition(of: event) - grabOffset)
    // The pointer can outrun the gap at the minimum; keep the resize cursor until mouse-up.
    cursor.set()
  }

  public override func mouseUp(with event: NSEvent) {
    guard isMouseDragging else { return }
    isMouseDragging = false
    endDrag()
    if !bounds.contains(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
    window?.invalidateCursorRects(for: self)
  }

  // MARK: Accessibility

  /// Pane `index`'s share of the split's main axis.
  public override func accessibilityValue() -> Any? {
    guard let factors = container?.liveFactors, factors.indices.contains(index) else { return nil }
    return NSNumber(value: factors[index])
  }

  public override func accessibilityPerformIncrement() -> Bool {
    container?.nudgeDivider(index, by: Self.accessibilityStep) ?? false
  }

  public override func accessibilityPerformDecrement() -> Bool {
    container?.nudgeDivider(index, by: -Self.accessibilityStep) ?? false
  }

  /// A splitter between side-by-side panes is a vertical line.
  private static func accessibilityOrientation(for axis: SplitAxis) -> NSAccessibilityOrientation {
    axis == .sideBySide ? .vertical : .horizontal
  }
}
