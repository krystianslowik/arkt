import AppKit

/// Vertical-only scroller for one Space's outline. No background; the theme shows through.
/// Locks each trackpad gesture to one axis and forwards horizontal ones to the Space pager (BH-035, GS-001).
@MainActor
public final class SidebarScrollView: NSScrollView {
  /// Receives horizontal gestures (the `SpacePagerView`).
  public weak var horizontalGestureTarget: SpacePagerView?
  private var lock = ScrollAxisLock<NSEvent>()

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    drawsBackground = false
    contentView.drawsBackground = false
    hasVerticalScroller = true
    hasHorizontalScroller = false
    horizontalScrollElasticity = .none
    verticalScrollElasticity = .allowed
    autohidesScrollers = true
    scrollerStyle = .overlay
    borderType = .noBorder
    automaticallyAdjustsContentInsets = false
    contentInsets = NSEdgeInsetsZero
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override func scrollWheel(with event: NSEvent) {
    guard event.phase != [] else {
      // Momentum after a horizontal gesture belongs to the pager (it ignores it: the spring owns the
      // settle). Legacy mouse wheels have no phases and always scroll.
      if event.momentumPhase != [], lock.axis == .horizontal { route(event, horizontal: true) }
      else { super.scrollWheel(with: event) }
      return
    }
    let starts = event.phase.contains(.began) || event.phase.contains(.mayBegin)
    let ends = event.phase.contains(.ended) || event.phase.contains(.cancelled)
    if starts { horizontalGestureTarget?.gestureMayBegin() }   // freeze a running Space settle
    let ready = lock.feed(event, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, starts: starts, ends: ends)
    if lock.axis == .vertical, !ready.isEmpty { horizontalGestureTarget?.gestureEndedWithoutPaging() }
    for e in ready { route(e, horizontal: lock.axis == .horizontal) }
  }

  private func route(_ event: NSEvent, horizontal: Bool) {
    if horizontal, let target = horizontalGestureTarget { target.scrollWheel(with: event) }
    else { super.scrollWheel(with: event) }
  }
}
