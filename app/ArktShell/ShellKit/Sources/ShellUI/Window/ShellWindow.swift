import AppKit

/// Visually borderless shell window. A real `.borderless` window would lose the traffic lights, key-window
/// behavior and resizing, so this is a titled, full-size-content window with a hidden, transparent titlebar
/// whose standard buttons are moved into the sidebar.
@MainActor
public final class ShellWindow: NSWindow {
  public var metrics = ShellMetrics.standard

  public init(contentRect: NSRect) {
    super.init(contentRect: contentRect,
               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
               backing: .buffered, defer: false)
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = false   // window drags come from WindowDragView (sidebar, theme gaps)
    tabbingMode = .disallowed
    isReleasedWhenClosed = false
    minSize = NSSize(width: 640, height: 420)
    collectionBehavior.insert(.fullScreenPrimary)
    setAccessibilityIdentifier(AXID.Shell.window)
  }

  /// Moves close/minimize/zoom so the close button's top-left sits at `metrics.trafficLightOrigin`
  /// (window coordinates, measured from the top-left). AppKit resets these frames on several events;
  /// ShellRootView.layout() and the window controller call this again each time.
  ///
  /// The titlebar container is narrowed to the sidebar so it never sits over (and steals clicks from) the
  /// content card; it is never narrower than the three buttons, so they stay hit-testable with the
  /// sidebar hidden.
  public func layoutTrafficLights(sidebarWidth: CGFloat) {
    guard !styleMask.contains(.fullScreen) else { return }
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    guard let close = standardWindowButton(.closeButton),
          let titlebar = close.superview,                    // NSTitlebarView
          let container = titlebar.superview else { return } // NSTitlebarContainerView
    let origin = metrics.trafficLightOrigin
    // As tall as the sidebar's traffic-light strip, so the sidebar URL bar below it keeps its clicks, and never
    // shorter than the buttons' bottom edge, so they stay hit-testable.
    let height = max(metrics.sidebarTopBarHeight, origin.y + close.frame.height)
    let buttonsExtent = origin.x * 2 + CGFloat(kinds.count - 1) * metrics.trafficLightSpacing + close.frame.width
    let width = min(frame.width, max(sidebarWidth, buttonsExtent))
    let containerFrame = NSRect(x: 0, y: frame.height - height, width: width, height: height)
    if container.frame != containerFrame { container.frame = containerFrame }
    for (index, kind) in kinds.enumerated() {
      guard let button = standardWindowButton(kind) else { continue }
      let x = origin.x + CGFloat(index) * metrics.trafficLightSpacing
      let y = titlebar.bounds.height - origin.y - button.frame.height   // titlebar view is not flipped
      let target = NSPoint(x: x, y: y)
      if button.frame.origin != target { button.setFrameOrigin(target) }
    }
  }
}
