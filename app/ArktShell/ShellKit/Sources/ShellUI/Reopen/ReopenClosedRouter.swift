import AppKit

/// The target of File > Reopen Closed Tab (Cmd-Shift-T, KB-010). The window the action reaches down the responder
/// chain handles it as before: the key browser window (its own closes, then the last closed Little Arkt), a key
/// Little Arkt window, or the main window behind a panel. With no window to reach (the only window was a Little Arkt
/// and it closed), the last closed Little Arkt window comes back (#355).
///
/// An explicit target, so the action never reaches the end of the responder chain, which in the Engine build is
/// Chromium's `AppController`. The menu item holds its target weakly: the app keeps the router alive.
@MainActor
public final class ReopenClosedRouter: NSObject, NSMenuItemValidation {
  private let windows: @MainActor () -> ShellWindowSet?
  private let responder: @MainActor (Any?) -> AnyObject?

  /// `windows`: the app's window set. `responder`: what the action reaches down the responder chain; AppKit's
  /// lookup in the app (tests pass their own).
  public init(windows: @escaping @MainActor () -> ShellWindowSet?,
              responder: (@MainActor (Any?) -> AnyObject?)? = nil) {
    self.windows = windows
    self.responder = responder ?? { sender in
      NSApp.target(forAction: ReopenClosedRouter.action, to: nil, from: sender) as AnyObject?
    }
  }

  nonisolated static let action = #selector(ReopenClosedActions.reopenClosedTab(_:))

  /// File > Reopen Closed Tab.
  @objc public func reopenClosedTab(_ sender: Any?) {
    if let target = responder(sender), target !== self {
      NSApp.sendAction(Self.action, to: target, from: sender)
      return
    }
    windows()?.reopenClosedLittleArkt()
  }

  public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if let target = responder(menuItem), target !== self {
      if let validator = target as? NSMenuItemValidation { return validator.validateMenuItem(menuItem) }
      return true
    }
    return windows()?.canReopenClosedLittleArkt ?? false
  }
}

/// Names the `reopenClosedTab:` action for `#selector`.
@objc private protocol ReopenClosedActions {
  func reopenClosedTab(_ sender: Any?)
}
