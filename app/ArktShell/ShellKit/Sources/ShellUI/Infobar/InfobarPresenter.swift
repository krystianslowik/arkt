import AppKit
import EngineAPI

// A tab's infobars in the shell (#400, docs/design/alerts-sheets-toasts.md section 5): the engine reports each tab's whole
// list, and the shell draws it as a strip flush with the top of the page view while the tab is on screen in this window.
// The engine reserves the strip's height at the top of the tab's container, so the page sits below it; buttons, links and
// the close button go to the engine, which decides whether an infobar goes. While an element of the tab's page is in
// HTML fullscreen the strip is down and takes no height (#581), as Chromium hides its infobars then; the list stays and
// the strip comes back when the page leaves fullscreen.

/// Shows the infobars of the tabs the window shows, one strip per tab, and acts on them. A tab keeps its list while it
/// is hidden (the strip leaves with the page and comes back when the tab is shown again) and across a move to another
/// window (the engine reports the list again there). The panel follows the page view the way a dialog does
/// (`AnchoredPanelHost`).
@MainActor
public final class InfobarPresenter {
  private let engine: any EngineClient
  let host: AnchoredPanelHost
  private let anchor: @MainActor (TabID) -> NSView?
  /// Gives the keyboard to `tab`'s page when it leaves the strip (Esc, F6, the strip going down while it held it). The
  /// window sets it.
  public var focusPage: (@MainActor (TabID) -> Void)?
  private var retryScheduled = false
  /// The infobars of each tab, in the engine's order; a tab with none has no entry.
  public private(set) var infobars: [TabID: [Infobar]] = [:]
  /// Reduce Motion, handed to each strip. Tests set it.
  var reduceMotion: (@MainActor () -> Bool)?
  /// The corner radius of the page card at the top of a tab's page view; the strip's top corners follow it.
  var cornerRadius: @MainActor (NSView) -> CGFloat = { InfobarPresenter.cardCornerRadius(of: $0) }
  /// The infobars of each tab that have been on screen in this window. Only an infobar new to the screen fades in and
  /// is announced: a strip made again for the same rows (a tab or Space switch, the tab leaving HTML fullscreen) shows
  /// at once and says nothing (#477 review, #581). An infobar leaves the set when it leaves the tab's list.
  private var seen: [TabID: Set<InfobarID>] = [:]
  /// Asks VoiceOver to read an infobar's message as it first appears. Tests replace it.
  var announce: @MainActor (NSPanel, String) -> Void = { panel, message in
    NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
      .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
    ])
  }

  /// `anchor` returns the view of a tab that is on screen in this window, nil for one that is not.
  public init(engine: any EngineClient, anchor: @escaping @MainActor (TabID) -> NSView?,
              windowIsVisible: @escaping @MainActor (NSWindow) -> Bool = { $0.isVisible }) {
    self.engine = engine
    self.anchor = anchor
    host = AnchoredPanelHost(anchor: anchor, windowIsVisible: windowIsVisible)
    host.refresh = { [weak self] in self?.refresh() }
  }

  /// The height the strip takes at the top of `tab`'s page: 40 pt per infobar, none while the tab is in HTML
  /// fullscreen. Dialogs and permission prompts point at the page below it.
  public func height(of tab: TabID) -> CGFloat {
    guard !isFullscreen(tab) else { return 0 }
    return CGFloat(infobars[tab]?.count ?? 0) * InfobarMetrics.rowHeight
  }

  /// An element of `tab`'s page fills the screen (HTML fullscreen), as the engine reports it now.
  private func isFullscreen(_ tab: TabID) -> Bool { engine.snapshot(of: tab)?.isTabFullscreen == true }

  /// The strip of `tab` while it is up, for tests and accessibility.
  func strip(for tab: TabID) -> InfobarPanel? { host.anyPanel(for: tab) as? InfobarPanel }

  /// Takes a tab's new list, and its HTML fullscreen changes: the strip goes down while the tab is fullscreen and
  /// comes back with the same rows when it leaves.
  public func handle(_ event: EngineEvent) {
    switch event {
    case .infobarsChanged(let tab, let list):
      infobars[tab] = list.isEmpty ? nil : list
      let ids = Set(list.map(\.id))
      let kept = seen[tab]?.intersection(ids) ?? []
      seen[tab] = kept.isEmpty ? nil : kept
      if list.isEmpty {
        host.dismiss(tab)
      } else {
        present(tab)
        scheduleRetryIfNeeded()
      }
    case .tabFullscreenChanged(let tab, _):
      guard infobars[tab] != nil else { return }
      present(tab)
      scheduleRetryIfNeeded()
    default:
      return
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

  /// F6 from a page (#478): puts the keyboard in the strip of `tab`, or, when the engine did not name the tab, of the
  /// tab whose page holds `responder`. False when that tab shows no strip with a control to reach; the page keeps the
  /// keyboard then.
  public func focusStrip(of tab: TabID?, holding responder: NSResponder?) -> Bool {
    let target = tab ?? infobars.keys.first { tab in
      guard let view = responder as? NSView, let page = anchor(tab) else { return false }
      return view.isDescendant(of: page)
    }
    guard let target, let strip = strip(for: target) else { return false }
    return strip.focusKeyboard()
  }

  /// Takes every strip down, as the window goes away.
  public func closeAll() {
    host.dismissAll()
  }

  private func present(_ tab: TabID) {
    guard let list = infobars[tab] else { return }
    guard !isFullscreen(tab) else {
      host.dismiss(tab)
      return
    }
    strip(for: tab)?.update(list)
    let before = seen[tab] ?? []
    let fresh = list.map(\.id).filter { !before.contains($0) }
    host.place(tab, maxWidth: .greatestFiniteMagnitude, fullWidth: true) { width in
      let panel = InfobarPanel(infobars: list, width: width)
      if let reduceMotion { panel.reduceMotion = reduceMotion }
      panel.onAction = { [weak self] infobar, action in self?.engine.act(on: infobar.id, action: action) }
      // The page takes the keyboard back only while it is on screen in this window.
      panel.onKeyboardExit = { [weak self] in
        guard let self, anchor(tab) != nil else { return }
        focusPage?(tab)
      }
      return panel
    } show: { [weak self] panel, window, page, frame in
      let radius = self?.cornerRadius(page) ?? 0
      // A strip of new infobars fades in as one; one that brings back rows already seen shows at once and fades in only
      // the rows that are new.
      let allNew = fresh.count == list.count
      panel.show(over: window, anchoredTo: frame, topCornerRadius: radius, fadeIn: allNew)
      if !allNew { panel.fadeIn(fresh) }
    }
    // Announced once, when the strip first shows the infobar.
    guard let strip = strip(for: tab), !fresh.isEmpty else { return }
    let shown = Set(strip.infobars.map(\.id))
    for infobar in list where fresh.contains(infobar.id) && shown.contains(infobar.id) {
      announce(strip.panel, infobar.message)
    }
    seen[tab, default: []].formUnion(fresh.filter { shown.contains($0) })
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
