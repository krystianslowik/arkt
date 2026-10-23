import AppKit

/// Background surface (sidebar, theme gaps around the card) that drags the window, since the window
/// itself is not movable by background.
@MainActor
public class WindowDragView: NSView {
  public override var mouseDownCanMoveWindow: Bool { true }

  public override func mouseDown(with event: NSEvent) {
    guard event.clickCount == 2 else {
      window?.performDrag(with: event)
      return
    }
    // Same behavior as a titlebar double-click (System Settings > Desktop & Dock).
    switch TitlebarDoubleClickAction(defaultsValue: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")) {
    case .zoom: window?.performZoom(nil)
    case .minimize: window?.performMiniaturize(nil)
    case .none: break
    }
  }
}

/// What a double-click on window background does, from the global `AppleActionOnDoubleClick` default.
enum TitlebarDoubleClickAction: Equatable {
  case zoom, minimize, none

  init(defaultsValue: String?) {
    switch defaultsValue {
    case "Minimize": self = .minimize
    case "None": self = .none
    default: self = .zoom   // "Maximize", "Fill", unset, or unknown
    }
  }
}
