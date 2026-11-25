import AppKit

/// Tells a window when AppKit has laid its titlebar out again on its own, so the window places its traffic lights again
/// before the next draw (#989).
///
/// AppKit lays the titlebar out on many changes (a new title, a subtitle, a represented URL, the edited state): the
/// buttons go back to AppKit's own places and their host (`NSTitlebarView`) to the window's full width, over the top of
/// the content. The windows place the buttons in their root view's `layout()`, so `onRelayout` asks for that pass.
/// It does not move them here: a view moved from inside its own frame-change notification keeps the frame AppKit is
/// still setting, so the button AppKit moves last would stay where AppKit put it.
@MainActor
final class TitlebarRelayoutObserver: NSObject {
  private let onRelayout: @MainActor () -> Void
  // The views watched now, held weakly and compared by identity: AppKit may replace them (full screen).
  private weak var container: NSView?
  private weak var host: NSView?
  private weak var close: NSView?
  private weak var miniaturize: NSView?
  private weak var zoom: NSView?
  private var isPlacing = false

  /// `onRelayout` is called for each frame change of the titlebar container, the buttons' host or a button that the
  /// window did not make itself.
  init(onRelayout: @escaping @MainActor () -> Void) {
    self.onRelayout = onRelayout
  }

  /// Runs `body`, which places the titlebar, ignoring the frame changes it makes (and the ones AppKit makes while it
  /// shows, hides or fades a button), then watches the views it placed.
  func placing(in window: NSWindow, _ body: () -> Void) {
    guard !isPlacing else { return }
    isPlacing = true
    body()
    isPlacing = false
    watch(window)
  }

  /// Runs on every placement (each overlay frame too), so the common case, the same views as before, allocates nothing.
  private func watch(_ window: NSWindow) {
    guard let close = window.standardWindowButton(.closeButton),
          let host = close.superview,                        // NSTitlebarView
          let container = host.superview else { return }     // NSTitlebarContainerView
    let miniaturize = window.standardWindowButton(.miniaturizeButton)
    let zoom = window.standardWindowButton(.zoomButton)
    if container === self.container, host === self.host, close === self.close, miniaturize === self.miniaturize,
       zoom === self.zoom { return }
    let center = NotificationCenter.default
    center.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
    for view in [container, host, close, miniaturize, zoom].compactMap({ $0 }) {
      view.postsFrameChangedNotifications = true
      center.addObserver(self, selector: #selector(titlebarFrameDidChange(_:)),
                         name: NSView.frameDidChangeNotification, object: view)
    }
    (self.container, self.host, self.close, self.miniaturize, self.zoom) = (container, host, close, miniaturize, zoom)
  }

  @objc private func titlebarFrameDidChange(_ notification: Notification) {
    guard !isPlacing else { return }
    onRelayout()
  }
}
