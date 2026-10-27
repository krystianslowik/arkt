import AppKit
import EngineAPI

/// What the dialog presenters share: one panel per tab anchored to the tab's page view, shown only while the window
/// can show it, sized to the page, kept in place as the page or window changes, and retried when the page view is
/// missing or not laid out yet. The presenters own what is pending and how it is answered.
@MainActor
final class AnchoredPanelHost {
  private struct Entry {
    let panel: DialogPanel
    let observers: [NSObjectProtocol]
    /// The page view the panel points at, and whose frame the observers watch.
    weak var anchorView: NSView?
  }

  private let anchor: @MainActor (TabID) -> NSView?
  /// Whether a window can show a panel now: false while it is minimized or its app is hidden. Tests inject it.
  private let windowIsVisible: @MainActor (NSWindow) -> Bool
  private var entries: [TabID: Entry] = [:]
  private var returnObservers: [NSObjectProtocol] = []
  private var spaceObserver: NSObjectProtocol?
  /// Watches the frame of a page view that has no bounds yet, so its first layout shows the panel without waiting for
  /// the window's root layout.
  private var unlaidOutObservers: [NSObjectProtocol] = []
  /// The last placement found a pending dialog with no page view to point at, or one with empty bounds; the next
  /// layout or frame change tries again.
  private(set) var retryOnLayout = false
  /// Called before a panel goes down without an answer, so a presenter can keep what the panel holds.
  var willDismiss: (@MainActor (TabID, DialogPanel) -> Void)?

  /// Places every pending dialog again; the host calls it when a window comes back or the page moves. The presenter
  /// sets it right after creating the host.
  var refresh: (@MainActor () -> Void)?

  /// `anchor` returns the view of a tab that is on screen in a window, nil for one that is not.
  init(anchor: @escaping @MainActor (TabID) -> NSView?, windowIsVisible: @escaping @MainActor (NSWindow) -> Bool) {
    self.anchor = anchor
    self.windowIsVisible = windowIsVisible
    let names: [Notification.Name] = [NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification,
                                      NSApplication.didUnhideNotification]
    returnObservers = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh?() }
      }
    }
    // A Space change moves windows off and on screen without any window notification of its own.
    spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh?() }
      }
  }

  isolated deinit {
    for observer in returnObservers + unlaidOutObservers { NotificationCenter.default.removeObserver(observer) }
    if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
  }

  /// The panel width for a page `anchorWidth` wide: `maxWidth`, narrower in a narrow page, never under 260.
  static func panelWidth(forAnchorWidth anchorWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
    min(maxWidth, max(260, anchorWidth - 2 * DialogPanel.anchorInset))
  }

  func panel(for tab: TabID) -> DialogPanel? { entries[tab]?.panel }

  /// Call before placing every pending dialog again.
  func beginRefresh() {
    retryOnLayout = false
    for observer in unlaidOutObservers { NotificationCenter.default.removeObserver(observer) }
    unlaidOutObservers = []
  }

  /// The window finished a layout pass: a dialog that found no page view to point at tries again, since the view may
  /// have arrived with it.
  func layoutDidFinish() {
    if retryOnLayout { refresh?() }
  }

  /// Puts the panel of `tab` in place. Down it goes, without an answer, when the tab has no page view or its window
  /// cannot show it, or when the tab moved to another window or page view; a panel already up follows its page's
  /// frame and width. Otherwise `makePanel` builds a new one for the page's width (at most `maxWidth`) and `show`
  /// presents it. A page not laid out yet waits for its first frame change.
  func place(_ tab: TabID, maxWidth: CGFloat, makePanel: (CGFloat) -> DialogPanel,
             show: (DialogPanel, NSWindow, NSRect) -> Void) {
    guard let view = anchor(tab) else {
      retryOnLayout = true
      dismiss(tab)
      return
    }
    guard let window = view.window, windowIsVisible(window) else {
      dismiss(tab)                           // a window coming back (deminiaturize, unhide, occlusion) refreshes
      return
    }
    // The tab reached another window or page view without a hand-off (a pane or Peek move): the panel and its
    // observers belong to the old ones, so it goes down unanswered and a new one is made for the new view.
    if let entry = entries[tab], entry.panel.panel.parent !== window || entry.anchorView !== view {
      dismiss(tab)
    }
    let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
    if let entry = entries[tab] {
      if !frame.isEmpty { entry.panel.resize(width: Self.panelWidth(forAnchorWidth: frame.width, maxWidth: maxWidth)) }
      entry.panel.reposition(anchoredTo: frame)                  // an empty frame holds its input protection
      return
    }
    guard !frame.isEmpty else {
      // Not laid out yet: never place a panel at the screen origin. The view's own first frame change retries.
      retryOnLayout = true
      view.postsFrameChangedNotifications = true
      unlaidOutObservers.append(NotificationCenter.default.addObserver(
        forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.refresh?() }
        })
      return
    }
    let panel = makePanel(Self.panelWidth(forAnchorWidth: frame.width, maxWidth: maxWidth))
    let reposition: @Sendable (Notification) -> Void = { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh?() }
    }
    view.postsFrameChangedNotifications = true
    let observers = [
      NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main,
                                             using: reposition),
      NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main,
                                             using: reposition),
    ]
    entries[tab] = Entry(panel: panel, observers: observers, anchorView: view)
    show(panel, window, frame)
  }

  /// Takes the tab's panel down at once, with no answer to the engine.
  func dismiss(_ tab: TabID) {
    guard let entry = entries.removeValue(forKey: tab) else { return }
    willDismiss?(tab, entry.panel)
    for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
    entry.panel.onAnswer = nil
    entry.panel.onDismiss = nil
    entry.panel.close(keyboard: true)
  }

  /// Lets go of the tab's panel because the user answered it: the panel closes itself.
  func forget(_ tab: TabID) {
    if let entry = entries.removeValue(forKey: tab) {
      for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
    }
  }

  func dismissAll() {
    for tab in Array(entries.keys) { dismiss(tab) }
  }
}
