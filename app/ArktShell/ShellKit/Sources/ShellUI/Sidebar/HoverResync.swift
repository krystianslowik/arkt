import AppKit

extension NSView {
  /// A view scrolled, shifted or reused under a still pointer gets no enter or exit event; tracking areas are updated
  /// after all of those, so the hover state is read from the pointer then. Only in the key window of the active app,
  /// and only when no other window covers the pointer. Calls `sync` with the pointer in window coordinates (nil: the
  /// pointer is not over this window), or not at all when no resync should run. Shared by sidebar rows and Favorite
  /// tiles.
  func resyncHoverWithPointer(_ sync: (NSPoint?) -> Void) {
    guard NSApp.isActive, let window, window.isKeyWindow else { return }
    let covered = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
      != window.windowNumber
    sync(covered ? nil : window.mouseLocationOutsideOfEventStream)
  }
}
