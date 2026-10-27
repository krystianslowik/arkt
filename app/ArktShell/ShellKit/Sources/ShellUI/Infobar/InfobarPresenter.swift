import AppKit
import EngineAPI

// A tab's infobars in the shell (#400, docs/design/alerts-sheets-toasts.md section 5): the engine reports each tab's whole
// list, and the shell draws it as a strip flush with the top of the page view while the tab is on screen in this window.
// The engine reserves the strip's height at the top of the tab's container, so the page sits below it; buttons, links and
// the close button go to the engine, which decides whether an infobar goes.

/// Shows the infobars of the tabs the window shows, one strip per tab, and acts on them. A tab keeps its list while it
/// is hidden (the strip leaves with the page and comes back when the tab is shown again) and across a move to another
/// window (the engine reports the list again there). The panel follows the page view the way a dialog does
/// (`AnchoredPanelHost`).
@MainActor
public final class InfobarPresenter {
  private let engine: any EngineClient
  let host: AnchoredPanelHost
  private var retryScheduled = false
  /// The infobars of each tab, in the engine's order; a tab with none has no entry.
  public private(set) var infobars: [TabID: [Infobar]] = [:]
  /// Reduce Motion, handed to each strip. Tests set it.
  var reduceMotion: (@MainActor () -> Bool)?
  /// The corner radius of the page card at the top of a tab's page view; the strip's top corners follow it.
  var cornerRadius: @MainActor (NSView) -> CGFloat = { InfobarPresenter.cardCornerRadius(of: $0) }
  private let anchor: @MainActor (TabID) -> NSView?

  /// `anchor` returns the view of a tab that is on screen in this window, nil for one that is not.
  public init(engine: any EngineClient, anchor: @escaping @MainActor (TabID) -> NSView?,
              windowIsVisible: @escaping @MainActor (NSWindow) -> Bool = { $0.isVisible }) {
    self.engine = engine
    self.anchor = anchor
    host = AnchoredPanelHost(anchor: anchor, windowIsVisible: windowIsVisible)
    host.refresh = { [weak self] in self?.refresh() }
  }

  /// The height the strip takes at the top of `tab`'s page: 40 pt per infobar.
  public func height(of tab: TabID) -> CGFloat {
    CGFloat(infobars[tab]?.count ?? 0) * InfobarMetrics.rowHeight
  }

  /// The strip of `tab` while it is up, for tests and accessibility.
  func strip(for tab: TabID) -> InfobarPanel? { host.anyPanel(for: tab) as? InfobarPanel }

  public func handle(_ event: EngineEvent) {
    guard case .infobarsChanged(let tab, let list) = event else { return }
    infobars[tab] = list.isEmpty ? nil : list
    if list.isEmpty {
      host.dismiss(tab)
    } else {
      present(tab)
      scheduleRetryIfNeeded()
    }
  }

  /// Shows the strips of tabs that came on screen and moves those whose page moved.
  public func refresh() {
    host.beginRefresh()
    for tab in infobars.keys { present(tab) }
  }

  /// The window finished a layout pass: a strip that found no page view to point at tries again.
  public func layoutDidFinish() {
    host.layoutDidFinish()
  }

  private func scheduleRetryIfNeeded() {
    guard host.retryOnLayout, !retryScheduled else { return }
    retryScheduled = true
    DispatchQueue.main.async { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.retryScheduled = false
        if self.host.retryOnLayout { self.refresh() }
      }
    }
  }

  /// Takes every strip down, as the window goes away.
  public func closeAll() {
    host.dismissAll()
  }

  private func present(_ tab: TabID) {
    guard let list = infobars[tab] else { return }
    strip(for: tab)?.update(list)
    host.place(tab, maxWidth: .greatestFiniteMagnitude, fullWidth: true) { width in
      let panel = InfobarPanel(infobars: list, width: width)
      if let reduceMotion { panel.reduceMotion = reduceMotion }
      panel.onAction = { [weak self] infobar, action in self?.engine.act(on: infobar.id, action: action) }
      return panel
    } show: { [weak self] panel, window, frame in
      let radius = self.flatMap { presenter in presenter.anchor(tab).map { presenter.cornerRadius($0) } } ?? 0
      panel.show(over: window, anchoredTo: frame, topCornerRadius: radius)
    }
  }

  /// The corner radius the page card clips its content with: the first rounded, clipping layer from the page view up.
  static func cardCornerRadius(of view: NSView) -> CGFloat {
    var current: NSView? = view
    while let candidate = current {
      if let layer = candidate.layer, layer.masksToBounds, layer.cornerRadius > 0 { return layer.cornerRadius }
      current = candidate.superview
    }
    return 0
  }
}
