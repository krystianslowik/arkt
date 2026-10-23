import AppKit

/// Window content view. Owns (back to front) the theme background, the sidebar container, the content card, the
/// split container (shown instead of the card for a split, `showsSplit`) and the sidebar resize handle. Frames come
/// from `ShellLayout` and are set directly (no Auto Layout).
@MainActor
public final class ShellRootView: NSView {
  public let metrics: ShellMetrics
  /// The Space theme (gradient + grain), crossfaded by the Space pager.
  public let themeBackground: ThemeBackgroundView
  /// The sidebar column (C3): traffic-light strip, favorites, Space page, bottom bar.
  public let sidebarContainer: SidebarContainerView
  public let card: ContentCardView
  /// The pane cards of a shown split, laid out at the card's frame. Hidden until a split is shown (`showsSplit`).
  public let split: SplitContainerView
  public let resizeHandle: SidebarResizeHandle

  public var sidebarWidth: CGFloat {
    didSet { if sidebarWidth != oldValue { needsLayout = true } }
  }
  public var sidebarVisible = true {
    didSet { if sidebarVisible != oldValue { needsLayout = true } }
  }
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

  public init(metrics: ShellMetrics = .standard, sidebar: SidebarContainerView? = nil) {
    self.metrics = metrics
    self.sidebarWidth = metrics.sidebarDefaultWidth
    self.themeBackground = ThemeBackgroundView(frame: .zero)
    self.sidebarContainer = sidebar
      ?? SidebarContainerView(source: StubSidebar(), topBarHeight: metrics.sidebarTopBarHeight)
    self.card = ContentCardView(metrics: metrics)
    self.split = SplitContainerView(metrics: metrics)
    self.resizeHandle = SidebarResizeHandle(metrics: metrics)
    super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    wantsLayer = true
    split.isHidden = true
    for view in [themeBackground, sidebarContainer, card, split, resizeHandle] {
      view.autoresizingMask = []
      addSubview(view)
    }
    resizeHandle.onWidthChange = { [weak self] width in
      guard let self else { return }
      self.sidebarWidth = ShellLayout.clampedWidth(width, metrics: self.metrics)
    }
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
    sidebarContainer.frame = l.sidebarFrame
    card.frame = l.cardFrame
    split.frame = l.cardFrame
    resizeHandle.frame = l.resizeHandleFrame
    CATransaction.commit()
    (window as? ShellWindow)?.layoutTrafficLights(sidebarWidth: l.sidebarFrame.width)
  }

  /// Sidebar width as laid out (clamped; 0 when hidden).
  public var effectiveSidebarWidth: CGFloat {
    sidebarVisible ? ShellLayout.clampedWidth(sidebarWidth, metrics: metrics) : 0
  }
}
