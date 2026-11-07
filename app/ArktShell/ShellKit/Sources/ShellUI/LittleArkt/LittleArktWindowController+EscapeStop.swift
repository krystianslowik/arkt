import AppKit
import EngineAPI

// Esc stops a loading page in a Little Arkt window (KB-055, #757), by the main window's rule
// (`ShellWindowController+EscapeStop.swift`, #614): only an Esc the page passed on reaches the shell, and the window's
// own Esc owners keep it first. Little Arkt has no Peek, find bar or command bar; its owners are a pending page dialog,
// HTML fullscreen, a sheet and the top bar's Space chooser.
extension LittleArktWindowController {
  /// The rule, apart from the window so every owner can be tested: the main window's, with this window's owners.
  nonisolated static func escapeStopsLoading(isLoading: Bool, dialogShown: Bool, tabFullscreen: Bool,
                                             sheetAttached: Bool, menuOpen: Bool) -> Bool {
    !menuOpen && ShellWindowController.escapeStopsLoading(
      isLoading: isLoading, peekOpen: false, findBarOpen: false, commandBarVisible: false, dialogShown: dialogShown,
      tabFullscreen: tabFullscreen, sheetAttached: sheetAttached)
  }

  /// An unmodified Esc the page of `tab` did not use: sends Stop when that page is the one this window shows and the
  /// engine's active tab, is loading and nothing else owns the key. True when it did. Stop goes through the engine
  /// like Cmd-., so it acts on the active tab, which is why an Esc from any other tab of the window is left alone.
  /// Only while the window is open: during Open in the page is on its way to the main window.
  ///
  /// The Chromium engine does not name the tab (`unhandledKeyDown:inTab:nil`). Then the Esc counts as the shown
  /// page's only while the first responder is inside that page.
  func stopLoadingOnEscape(_ event: NSEvent, in tab: TabID?) -> Bool {
    guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
          isOpen, let engineWindow, let shown = shownTab,
          engine.latestActiveTab(in: engineWindow) == shown else { return false }
    if let tab {
      guard tab == shown else { return false }
    } else {
      guard let page = engine.contentView(for: shown), let responder = window.firstResponder as? NSView,
            responder.isDescendant(of: page) else { return false }
    }
    guard let snapshot = engine.snapshot(of: shown) else { return false }
    let stops = Self.escapeStopsLoading(
      isLoading: snapshot.isLoading, dialogShown: javaScriptDialogs.pending[shown] != nil,
      tabFullscreen: snapshot.isTabFullscreen, sheetAttached: !window.sheets.isEmpty, menuOpen: isChooserOpen)
    guard stops, engineHost.validate(.stop) else { return false }
    engineHost.dispatch(.stop, disposition: .currentTab)
    return true
  }
}

extension LittleArktWindowController: NSMenuDelegate {
  public func menuWillOpen(_ menu: NSMenu) { isChooserOpen = true }
  public func menuDidClose(_ menu: NSMenu) { isChooserOpen = false }
}
