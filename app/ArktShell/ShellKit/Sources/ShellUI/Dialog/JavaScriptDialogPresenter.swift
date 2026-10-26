import AppKit
import EngineAPI

// A page's `alert()`, `confirm()` and `prompt()` in the shell's dialog system (#400, docs/design/alerts-sheets-toasts.md
// section 3.3): the engine reports the request with Chromium's own strings, and the shell draws it as the anchored
// panel over the page that asked.

extension DialogContent {
  /// The dialog for a page's request. The title, message and button titles are the engine's. OK is the Return default;
  /// Escape answers Cancel, which for an alert (OK only) is its one answer. The body scrolls past `bodyMaxHeight`,
  /// since Chromium allows 24 lines of 80 characters.
  public static func javaScriptDialog(_ dialog: JavaScriptDialog, width: CGFloat = 420) -> DialogContent {
    DialogContent(title: dialog.title, paragraphs: dialog.message.isEmpty ? [] : [.init(dialog.message)],
                  primaryTitle: dialog.acceptTitle, cancelTitle: dialog.cancelTitle, defaultButton: .primary,
                  width: width,
                  input: dialog.defaultPromptText.map { .init(text: $0, accessibilityLabel: "Response") },
                  bodyMaxHeight: 240)
  }
}

extension JavaScriptDialog {
  /// What the page's call returns for `answer`: an alert's one answer is OK (also Escape); a confirm's Cancel is false;
  /// a prompt's text goes with OK only.
  func response(for answer: DialogContent.Answer, input: String?) -> (accepted: Bool, userInput: String?) {
    let accepted = kind == .alert || answer != .cancel
    return (accepted, accepted && kind == .prompt ? input : nil)
  }
}

/// Shows each pending JavaScript dialog of the tabs the window shows, one per tab, and answers the engine. A dialog
/// of a tab that is not on screen stays pending without a panel and appears when the tab is shown (`refresh()`), as
/// Chromium keeps a background tab's `alert()` pending. The engine ends a dialog on its own (a navigation, a later
/// dialog, the tab closing); that closes the panel without an answer, and an answer that races the end is dropped by
/// the engine.
@MainActor
public final class JavaScriptDialogPresenter {
  /// The page view a tab's dialog points at: top-leading corner 12 pt inside it.
  public typealias Anchor = NSView

  private struct Entry {
    let panel: DialogPanel
    var observers: [NSObjectProtocol]
  }

  private let engine: any EngineClient
  private let anchor: @MainActor (TabID) -> Anchor?
  /// Whether a window can show a panel now: false while it is minimized or its app is hidden. Tests inject it.
  private let windowIsVisible: @MainActor (NSWindow) -> Bool
  /// Observers of the events that bring a window back; a dialog that arrived while it was away shows then.
  private var returnObservers: [NSObjectProtocol] = []
  /// The last refresh found a pending dialog with no page view to point at; the next layout tries again.
  private var retryOnLayout = false
  /// The unanswered dialog of each tab.
  public private(set) var pending: [TabID: JavaScriptDialog] = [:]
  private var entries: [TabID: Entry] = [:]
  /// Reduce Motion, handed to each panel at its entrance. Tests set it.
  var reduceMotion: (@MainActor () -> Bool)?

  /// `anchor` returns the view of a tab that is on screen in a window, nil for one that is not.
  public init(engine: any EngineClient, anchor: @escaping @MainActor (TabID) -> Anchor?,
              windowIsVisible: @escaping @MainActor (NSWindow) -> Bool = { $0.isVisible }) {
    self.engine = engine
    self.anchor = anchor
    self.windowIsVisible = windowIsVisible
    let names: [Notification.Name] = [NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification,
                                      NSApplication.didUnhideNotification]
    returnObservers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
  }

  isolated deinit {
    for observer in returnObservers { NotificationCenter.default.removeObserver(observer) }
  }

  /// The tab whose panel is up, for tests and accessibility.
  public func panel(for tab: TabID) -> DialogPanel? { entries[tab]?.panel }

  public func handle(_ event: EngineEvent) {
    switch event {
    case .dialogRequested(let dialog):
      adopt(dialog)
    case .dialogEnded(let tab, let id):
      guard pending[tab]?.id == id else { return }
      pending[tab] = nil
      dismissPanel(of: tab)
    default:
      break
    }
  }

  /// Takes `dialog` as this window's pending dialog of its tab and shows its panel if the tab is on screen. A dialog
  /// the engine just raised, or one that came with a tab moved here (`release(_:)` of the window it left).
  public func adopt(_ dialog: JavaScriptDialog) {
    if pending[dialog.tab] != nil { dismissPanel(of: dialog.tab) }
    pending[dialog.tab] = dialog
    present(dialog.tab)
  }

  /// Lets go of the tab's pending dialog because the tab moves to another window, which adopts it. The panel goes at
  /// once and nothing here can answer the dialog afterwards, so the answer reaches the page once, from the panel of
  /// the window that adopts it. A prompt's text typed so far becomes the dialog's initial text there. Nil when the tab
  /// has no pending dialog.
  public func release(_ tab: TabID) -> JavaScriptDialog? {
    guard var dialog = pending.removeValue(forKey: tab) else { return nil }
    if dialog.kind == .prompt, let typed = entries[tab]?.panel.inputText { dialog.defaultPromptText = typed }
    dismissPanel(of: tab)
    return dialog
  }

  /// The panel width for a page `anchorWidth` wide: 420 pt, narrower in a narrow page, never under 260.
  static func panelWidth(forAnchorWidth anchorWidth: CGFloat) -> CGFloat {
    min(420, max(260, anchorWidth - 2 * DialogPanel.anchorInset))
  }

  /// Shows the panels of tabs that came on screen, moves those whose page moved, and takes down those whose tab left.
  public func refresh() {
    retryOnLayout = false
    for tab in pending.keys { present(tab) }
  }

  /// The window finished a layout pass: a dialog that found no page view to point at tries again, since the view may
  /// have arrived with it. Nothing pending, or every dialog placed: nothing happens.
  public func layoutDidFinish() {
    if retryOnLayout { refresh() }
  }

  /// Takes every panel down without answering, as the window goes away.
  public func closeAll() {
    for tab in Array(entries.keys) { dismissPanel(of: tab) }
  }

  private func present(_ tab: TabID) {
    guard let dialog = pending[tab] else { return }
    guard let view = anchor(tab) else {
      retryOnLayout = true
      dismissPanel(of: tab)
      return
    }
    guard let window = view.window, windowIsVisible(window) else {
      dismissPanel(of: tab)                  // a window coming back (deminiaturize, unhide, occlusion) refreshes
      return
    }
    let frame = Self.screenFrame(of: view)
    let width = Self.panelWidth(forAnchorWidth: frame.width)
    if let entry = entries[tab] {
      entry.panel.resize(width: width)         // follows the page or window; a no-op at the same width
      entry.panel.reposition(anchoredTo: frame)
      return
    }
    let panel = DialogPanel(content: .javaScriptDialog(dialog, width: width))
    if let reduceMotion { panel.reduceMotion = reduceMotion }
    panel.onAnswer = { [weak self, weak panel] answer in
      self?.answered(tab, dialog, answer, input: panel?.inputText)
    }
    let reposition: @Sendable (Notification) -> Void = { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    view.postsFrameChangedNotifications = true
    let observers = [
      NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main,
                                             using: reposition),
      NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main,
                                             using: reposition),
    ]
    entries[tab] = Entry(panel: panel, observers: observers)
    panel.show(over: window, anchoredTo: frame, takesFocus: true)
  }

  private static func screenFrame(of view: NSView) -> NSRect {
    view.window?.convertToScreen(view.convert(view.bounds, to: nil)) ?? .zero
  }

  /// Takes the tab's panel down at once, with no answer to the engine.
  private func dismissPanel(of tab: TabID) {
    guard let entry = entries.removeValue(forKey: tab) else { return }
    for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
    entry.panel.onAnswer = nil
    entry.panel.close(keyboard: true)
  }

  private func answered(_ tab: TabID, _ dialog: JavaScriptDialog, _ answer: DialogContent.Answer, input: String?) {
    guard pending[tab]?.id == dialog.id else { return }
    pending[tab] = nil
    if let entry = entries.removeValue(forKey: tab) {
      for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
    }
    let response = dialog.response(for: answer, input: input)
    engine.respond(to: dialog.id, accepted: response.accepted, userInput: response.userInput)
    engine.focusPage(of: tab)
  }
}
