import AppKit

/// Vertical-only scroller for one Space's outline. No background; the theme shows through.
/// Trackpad gestures go through the Space pager, which locks each gesture to one axis for every page (BH-035,
/// GS-001, #986): horizontal ones page the Spaces, vertical ones come back here and scroll the outline.
@MainActor
public final class SidebarScrollView: NSScrollView {
  /// Decides each trackpad gesture's axis and pages horizontal ones (the `SpacePagerView`).
  public weak var horizontalGestureTarget: SpacePagerView?
  /// A scroll by the user (wheel or trackpad); the overflow pill leaves on it (BH-018).
  var onUserScroll: (@MainActor () -> Void)?

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

  /// Legacy mouse wheels have no phases and always scroll. A gesture's events can arrive on any page's scroll view
  /// as the pages move under the pointer, so the axis is not decided here but by the pager, for the whole gesture.
  public override func scrollWheel(with event: NSEvent) {
    onUserScroll?()
    guard let pager = horizontalGestureTarget, event.phase != [] || event.momentumPhase != [] else {
      super.scrollWheel(with: event)
      return
    }
    for e in pager.routeGestureEvent(event) { super.scrollWheel(with: e) }
  }
}
