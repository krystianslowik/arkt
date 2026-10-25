import AppKit

/// Window content view. Owns (back to front) the theme background, the content card, the split container (shown
/// instead of the card for a split, `showsSplit`), the sidebar overlay that hosts the sidebar column, and the sidebar
/// resize handle. Frames come from `ShellLayout` and are set directly (no Auto Layout).
///
/// The sidebar sits above the card so that, hidden (`sidebarVisible == false`, BH-001), it can come out over the page
/// when the pointer reaches the window's left edge (BH-004, GS-018). Docked, the two never overlap.
@MainActor
public final class ShellRootView: NSView {
  public let metrics: ShellMetrics
  /// The Space theme (gradient + grain), crossfaded by the Space pager.
  public let themeBackground: ThemeBackgroundView
  /// The sidebar column (C3): traffic-light strip, favorites, Space page, bottom bar.
  public let sidebarContainer: SidebarContainerView
  /// Hosts `sidebarContainer`: the plain column while docked, the hover-revealed overlay while hidden (#102).
  public let sidebarOverlay: SidebarOverlayView
  public let card: ContentCardView
  /// The pane cards of a shown split, laid out at the card's frame. Hidden until a split is shown (`showsSplit`).
  public let split: SplitContainerView
  public let resizeHandle: SidebarResizeHandle

  public var sidebarWidth: CGFloat {
    didSet { if sidebarWidth != oldValue { needsLayout = true } }
  }
  /// The sidebar is shown (docked). Hidden, the card takes the full width (BH-001) and the left edge reveals the
  /// sidebar as an overlay. Instant either way: Cmd-S is a keyboard action. Each window keeps its own value.
  public var sidebarVisible = true {
    didSet {
      guard sidebarVisible != oldValue else { return }
      sidebarOverlay.isDocked = sidebarVisible
      needsLayout = true
      updateTrackingAreas()
      onSidebarVisibilityChange?(sidebarVisible)
    }
  }
  /// Called when `sidebarVisible` changes, whatever changed it (Cmd-S, the edge drag, a toast's action).
  public var onSidebarVisibilityChange: (@MainActor (Bool) -> Void)?
  /// The split container replaces the single card (S4). The toast moves along, so notices stay on screen.
  public var showsSplit = false {
    didSet {
      guard showsSplit != oldValue else { return }
      card.isHidden = showsSplit
      split.isHidden = !showsSplit
      let toast = card.toastView ?? split.toastView
      card.toastView = nil
      split.toastView = nil
      if showsSplit { split.toastView = toast } else { card.toastView = toast }
    }
  }

  private var revealEdgeArea: NSTrackingArea?
  private var revealEdgeFrame = CGRect.zero

  public init(metrics: ShellMetrics = .standard, sidebar: SidebarContainerView? = nil) {
    self.metrics = metrics
    self.sidebarWidth = metrics.sidebarDefaultWidth
    self.themeBackground = ThemeBackgroundView(frame: .zero)
    let sidebarContainer = sidebar
      ?? SidebarContainerView(source: StubSidebar(), topBarHeight: metrics.sidebarTopBarHeight)
    self.sidebarContainer = sidebarContainer
    self.sidebarOverlay = SidebarOverlayView(sidebar: sidebarContainer)
    self.card = ContentCardView(metrics: metrics)
    self.split = SplitContainerView(metrics: metrics)
    self.resizeHandle = SidebarResizeHandle(metrics: metrics)
    super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    wantsLayer = true
    split.isHidden = true
    for view in [themeBackground, card, split, sidebarOverlay, resizeHandle] {
      view.autoresizingMask = []
      addSubview(view)
    }
    themeBackground.mirror = sidebarOverlay.backdrop
    resizeHandle.onWidthChange = { [weak self] width in
      guard let self else { return }
      switch ShellLayout.resolveDrag(proposedWidth: width, metrics: self.metrics) {
      case .hide:                                                  // BH-002: fully left
        self.sidebarVisible = false
      case .resize(let width):
        self.sidebarWidth = width
        self.sidebarVisible = true                                 // the same drag brought it back
      }
    }
    sidebarOverlay.onRevealProgress = { [weak self] progress in self?.revealProgressDidChange(progress) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  public override func layout() {
    super.layout()
    let l = ShellLayout.compute(bounds: bounds, sidebarWidth: sidebarWidth, sidebarVisible: sidebarVisible,
                                metrics: metrics)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    themeBackground.frame = bounds
    if sidebarOverlay.frame != l.sidebarFrame { sidebarOverlay.frame = l.sidebarFrame }
    card.frame = l.cardFrame
    split.frame = l.cardFrame
    resizeHandle.frame = l.resizeHandleFrame
    CATransaction.commit()
    if revealEdgeFrame != l.revealEdgeFrame {
      revealEdgeFrame = l.revealEdgeFrame
      updateTrackingAreas()
    }
    reapplyTrafficLights()
  }

  /// Sidebar width as laid out (clamped; 0 when hidden).
  public var effectiveSidebarWidth: CGFloat {
    sidebarVisible ? ShellLayout.clampedWidth(sidebarWidth, metrics: metrics) : 0
  }

  // MARK: Traffic lights

  /// Places the traffic lights for the sidebar's state: in the docked column, in the overlay faded with its reveal,
  /// or hidden.
  public func reapplyTrafficLights() {
    guard let window = window as? ShellWindow else { return }
    let placement: ShellWindow.TrafficLightPlacement
    if sidebarVisible {
      placement = .sidebar
    } else if sidebarOverlay.isHidden {
      placement = .hidden
    } else {
      placement = .overlay(origin: sidebarOverlay.frame.origin, alpha: revealProgress)
    }
    window.trafficLightPlacement = placement
    window.layoutTrafficLights(sidebarWidth: sidebarVisible ? effectiveSidebarWidth : sidebarOverlay.frame.width)
  }

  private var revealProgress: CGFloat = 1

  /// Every reveal frame: only the buttons' opacity changes (and their visibility at the ends). Docked, layout places
  /// them.
  private func revealProgressDidChange(_ progress: CGFloat) {
    revealProgress = progress
    guard !sidebarVisible else { return }
    reapplyTrafficLights()
  }

  // MARK: Reveal edge (GS-018)

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let revealEdgeArea { removeTrackingArea(revealEdgeArea) }
    revealEdgeArea = nil
    guard !sidebarVisible, !revealEdgeFrame.isEmpty else { return }
    let area = NSTrackingArea(rect: revealEdgeFrame, options: [.mouseEnteredAndExited, .activeAlways],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    revealEdgeArea = area
  }

  public override func mouseEntered(with event: NSEvent) {
    if event.trackingArea === revealEdgeArea { pointerReachedRevealEdge() } else { super.mouseEntered(with: event) }
  }

  public override func mouseExited(with event: NSEvent) {
    if event.trackingArea === revealEdgeArea { pointerLeftRevealEdge() } else { super.mouseExited(with: event) }
  }

  /// The pointer reached the window's left edge with the sidebar hidden (BH-004).
  public func pointerReachedRevealEdge() { sidebarOverlay.pointerReachedEdge() }
  /// The pointer left the left-edge strip.
  public func pointerLeftRevealEdge() { sidebarOverlay.pointerLeftEdge() }
}
