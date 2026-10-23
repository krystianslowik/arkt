import AppKit

/// What a hover resync reads from AppKit and the window server. Tests inject their own, so they depend neither on
/// the real pointer nor on which window is key or on screen.
@MainActor
struct HoverPointerLookup {
  /// Whether the window is on screen at all.
  var isVisible: (NSWindow) -> Bool
  /// The pointer in screen coordinates.
  var mouseLocation: () -> NSPoint
  /// The number of the frontmost window a click at a screen point would hit (a window-server query).
  var windowNumber: (NSPoint) -> Int

  static var system: HoverPointerLookup {
    HoverPointerLookup(isVisible: { $0.isVisible },
                       mouseLocation: { NSEvent.mouseLocation },
                       windowNumber: { NSWindow.windowNumber(at: $0, belowWindowWithWindowNumber: 0) })
  }

  /// The pointer in `window` coordinates; nil when another window (a child panel such as the command bar, or another
  /// app's window) is frontmost under it.
  func pointer(in window: NSWindow) -> NSPoint? {
    let screen = mouseLocation()
    guard windowNumber(screen) == window.windowNumber else { return nil }
    return window.convertPoint(fromScreen: screen)
  }
}

/// A view that hosts hover rows or tiles (the sidebar outline, the Favorites grid) and resyncs all of them from one
/// pointer lookup.
@MainActor
protocol HoverResyncHost: AnyObject {
  func setNeedsHoverResync()
}

extension NSView {
  /// A row or tile scrolled, shifted or reused under a still pointer gets no enter or exit event. Tracking areas are
  /// updated after all of those, so the row then asks the host it sits in to read the pointer again.
  func setNeedsHoverResyncInHost() {
    var view = superview
    while let current = view {
      if let host = current as? HoverResyncHost {
        host.setNeedsHoverResync()
        return
      }
      view = current.superview
    }
  }
}

/// Coalesces the resync requests of one host (every row asks on a scroll) into one pointer lookup on the next
/// main-queue turn. Tracking areas are active always, so hover shows in background windows too: the resync runs in
/// any visible window, key or not, and treats a pointer under another window as outside.
@MainActor
final class HoverResyncScheduler {
  var lookup = HoverPointerLookup.system
  private weak var view: NSView?
  private let sync: (NSPoint?) -> Void
  private var isScheduled = false

  /// `sync` receives the pointer in window coordinates (nil: the pointer is not over this window) and updates every
  /// hover row or tile of the host.
  init(view: NSView, sync: @escaping (NSPoint?) -> Void) {
    self.view = view
    self.sync = sync
  }

  func setNeeded() {
    guard !isScheduled else { return }
    isScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isScheduled = false
      self.resyncNow()
    }
  }

  /// Reads the pointer once and syncs the host; does nothing when the host is not in a visible window.
  func resyncNow() {
    guard let window = view?.window, lookup.isVisible(window) else { return }
    sync(lookup.pointer(in: window))
  }
}
