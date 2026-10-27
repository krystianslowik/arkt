import AppKit
import EngineAPI

// A site's permission request in the shell's dialog system (#400, docs/design/alerts-sheets-toasts.md sections 3.2 and
// 3.3): the engine reports the request with Chromium's own strings, and the shell draws it as the anchored panel over
// the page that asked, with three stacked neutral answers and no Return default.

extension DialogContent {
  /// How long after a permission prompt appears that presses and Return are ignored (Chrome's input protection), so a
  /// keystroke or click meant for the page cannot grant a permission.
  public static let permissionInputProtection: TimeInterval = 0.5

  /// The dialog for a site's request: "example.com wants to", what it wants as a list, then Allow (while visiting the
  /// site), Allow this time when the engine offers it, and Block. Every string is the engine's. The answers carry equal
  /// weight (neutral pills) and nothing is the Return default, so the prompt does not steer toward Allow; Escape closes
  /// it without an answer, as the engine's own panel does.
  public static func permissionRequest(_ request: PermissionRequest, width: CGFloat = 320) -> DialogContent {
    DialogContent(title: request.title, listItems: request.items, primaryTitle: request.allowTitle,
                  secondaryTitle: request.allowThisTimeTitle, cancelTitle: request.blockTitle, defaultButton: .none,
                  width: width, stackedButtons: true, neutralPrimary: true, escapeDismisses: true,
                  inputProtection: permissionInputProtection)
  }
}

extension PermissionChoice {
  init(_ answer: DialogContent.Answer) {
    switch answer {
    case .primary: self = .allow
    case .secondary: self = .allowThisTime
    case .cancel: self = .block
    }
  }
}

/// Shows each pending permission request of the tabs the window shows, one per tab, and answers the engine. The panel
/// does not take key focus: the page keeps its text field until the user clicks the prompt. The engine ends a request
/// on its own (a navigation, the tab hidden or closing, the site withdrawing it) and asks again for a tab that comes
/// back; an end closes the panel with no answer, and an answer that races the end is dropped by the engine.
@MainActor
public final class PermissionPresenter {
  private let engine: any EngineClient
  private let host: AnchoredPanelHost
  private var retryScheduled = false
  /// The unanswered request of each tab.
  public private(set) var pending: [TabID: PermissionRequest] = [:]
  /// Reduce Motion, handed to each panel at its entrance. Tests set it.
  var reduceMotion: (@MainActor () -> Bool)?
  /// The clock of the input protection, handed to each panel. Tests set it.
  var clock: (@MainActor () -> TimeInterval)?
  /// Whether a panel's window is really visible (not occluded), handed to each panel. Tests set it.
  var isOnScreen: (@MainActor () -> Bool)?

  /// `anchor` returns the view of a tab that is on screen in a window, nil for one that is not.
  public init(engine: any EngineClient, anchor: @escaping @MainActor (TabID) -> NSView?,
              windowIsVisible: @escaping @MainActor (NSWindow) -> Bool = { $0.isVisible }) {
    self.engine = engine
    host = AnchoredPanelHost(anchor: anchor, windowIsVisible: windowIsVisible)
    host.refresh = { [weak self] in self?.refresh() }
  }

  /// The tab whose panel is up, for tests and accessibility.
  public func panel(for tab: TabID) -> DialogPanel? { host.panel(for: tab) }

  public func handle(_ event: EngineEvent) {
    switch event {
    case .permissionRequested(let request):
      if pending[request.tab] != nil { host.dismiss(request.tab) }
      pending[request.tab] = request
      present(request.tab)
      scheduleRetryIfNeeded()
    case .permissionEnded(let tab, let id):
      guard pending[tab]?.id == id else { return }
      pending[tab] = nil
      host.dismiss(tab)
    default:
      break
    }
  }

  /// Shows the panels of tabs that came on screen and moves those whose page moved.
  public func refresh() {
    host.beginRefresh()
    for tab in pending.keys { present(tab) }
  }

  /// The window finished a layout pass: a request that found no page view to point at tries again.
  public func layoutDidFinish() {
    host.layoutDidFinish()
  }

  /// A request that arrives before its tab has a page view does not wait for the window's next root layout: it tries
  /// once more on the next turn of the run loop (a new tab's view is placed within the same turn), then falls back to
  /// the layout and frame callbacks.
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

  /// Takes every panel down without answering, as the window goes away.
  public func closeAll() {
    host.dismissAll()
  }

  private func present(_ tab: TabID) {
    guard let request = pending[tab] else { return }
    host.place(tab, maxWidth: 320) { width in
      let panel = DialogPanel(content: .permissionRequest(request, width: width))
      if let reduceMotion { panel.reduceMotion = reduceMotion }
      if let clock { panel.clock = clock }
      if let isOnScreen { panel.isOnScreen = isOnScreen }
      panel.onAnswer = { [weak self] answer in self?.answered(tab, request, PermissionChoice(answer)) }
      panel.onDismiss = { [weak self] in self?.answered(tab, request, .dismiss) }
      return panel
    } show: { panel, window, frame in
      panel.show(over: window, anchoredTo: frame)
    }
  }

  private func answered(_ tab: TabID, _ request: PermissionRequest, _ choice: PermissionChoice) {
    guard pending[tab]?.id == request.id else { return }
    pending[tab] = nil
    host.forget(tab)
    engine.respond(toPermission: request.id, choice: choice)
  }
}
