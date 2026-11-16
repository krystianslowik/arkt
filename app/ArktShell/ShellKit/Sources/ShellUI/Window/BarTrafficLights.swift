import AppKit

extension NSWindow {
  /// Close, minimize and zoom at `firstX`, `firstX + spacing` and `firstX + 2 * spacing`, centered in the window's top
  /// bar of `barHeight` (Little Arkt, Settings, Archive and Library windows; the browser window places its own).
  ///
  /// The titlebar container spans the window, as in a stock window: it also hosts AppKit's titlebar decoration, which
  /// draws the window's top rim (a bright edge with rounded corners). Narrowed, that rim ended in a corner next to the
  /// buttons (#808, #863). Only the buttons' host (`NSTitlebarView`) is narrowed to the buttons, so it never takes
  /// clicks from the bar's own controls; the full-width decoration takes none.
  ///
  /// Showing, hiding or fading a standard button makes AppKit lay its titlebar out again (#865). Callers that do so set
  /// that first and call this last.
  func placeTrafficLights(barHeight: CGFloat, firstX: CGFloat, spacing: CGFloat) {
    guard !styleMask.contains(.fullScreen), let close = standardWindowButton(.closeButton),
          let titlebar = close.superview,                    // NSTitlebarView
          let container = titlebar.superview else { return } // NSTitlebarContainerView
    let containerFrame = NSRect(x: 0, y: frame.height - barHeight, width: frame.width, height: barHeight)
    if container.frame != containerFrame { container.frame = containerFrame }
    let width = min(frame.width, firstX * 2 + spacing * 2 + close.frame.width)
    let titlebarFrame = NSRect(x: 0, y: 0, width: width, height: barHeight)
    if titlebar.frame != titlebarFrame { titlebar.frame = titlebarFrame }
    let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for (index, kind) in kinds.enumerated() {
      guard let button = standardWindowButton(kind) else { continue }
      let origin = NSPoint(x: firstX + CGFloat(index) * spacing,
                           y: ((barHeight - button.frame.height) / 2).rounded())
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
  }
}
