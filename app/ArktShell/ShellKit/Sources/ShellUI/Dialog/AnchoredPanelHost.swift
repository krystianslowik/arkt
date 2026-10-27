import AppKit
import EngineAPI

/// A panel the host can place: a dialog's, or the infobar row's. The host moves and sizes it; the presenter owns what
/// it shows.
@MainActor
protocol AnchoredPanel: AnyObject {
  var panel: NSPanel { get }
  /// Gives the panel `width`; its height follows from its content.
  func resize(width: CGFloat)
  /// Moves the panel to `anchor` (screen coordinates) again.
  func reposition(anchoredTo anchor: NSRect)
  /// Lets go of the callbacks, so a panel going down without an answer reports nothing.
  func detach()
  func close(keyboard: Bool)
}

extension DialogPanel: AnchoredPanel {
  func detach() {
    onAnswer = nil
    onDismiss = nil
  }
}

/// What the dialog presenters share: one panel per tab anchored to the tab's page view, shown only while the window
/// can show it, sized to the page, kept in place as the page or window changes, and retried when the page view is
/// missing or not laid out yet. The presenters own what is pending and how it is answered.
@MainActor
final class AnchoredPanelHost {
  private struct Entry {
    let panel: any AnchoredPanel
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
  /// How much of the top of a tab's page view a strip of the shell's own (the infobar row) covers; panels point at the
  /// page below it, not at the strip. Zero without one.
  var topInset: @MainActor (TabID) -> CGFloat = { _ in 0 }

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

  func panel(for tab: TabID) -> DialogPanel? { entries[tab]?.panel as? DialogPanel }

  /// The panel of `tab` whatever its kind, nil when none is up.
  func anyPanel(for tab: TabID) -> (any AnchoredPanel)? { entries[tab]?.panel }

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
  func place<Panel: AnchoredPanel>(_ tab: TabID, maxWidth: CGFloat, fullWidth: Bool = false,
                                   makePanel: (CGFloat) -> Panel, show: (Panel, NSWindow, NSRect) -> Void) {
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
    var frame = window.convertToScreen(view.convert(view.bounds, to: nil))
    if !frame.isEmpty, !fullWidth {
      // Below the shell's own strip at the top of the page, if there is one (screen coordinates grow upward).
      let inset = min(topInset(tab), frame.height)
      frame.size.height -= inset
    }
    func width(for frame: NSRect) -> CGFloat {
      fullWidth ? frame.width : Self.panelWidth(forAnchorWidth: frame.width, maxWidth: maxWidth)
    }
    if let entry = entries[tab] {
      if !frame.isEmpty { entry.panel.resize(width: width(for: frame)) }
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
    let panel = makePanel(width(for: frame))
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
    if let dialog = entry.panel as? DialogPanel { willDismiss?(tab, dialog) }
    for observer in entry.observers { NotificationCenter.default.removeObserver(observer) }
    entry.panel.detach()
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
