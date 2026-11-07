import AppKit
import EngineAPI

// Esc stops a loading page (KB-055, #614), as View > Stop and Cmd-. do (KB-054). Esc goes to the page first (decided
// 2026-10-25); only an Esc the page passed on reaches the shell, through the engine's unhandled key path. The window's
// other Esc owners keep it before Stop: an open Peek, find bar or command bar (which is also where the URL is edited),
// a pending page dialog, HTML fullscreen and a sheet. A permission prompt takes neither focus nor Esc, so it is not
// one. Window full screen (#613) does not take Esc yet.
extension ShellWindowController {
  /// The rule, apart from the window so every owner can be tested: a loading page stops only when no owner is open.
  nonisolated static func escapeStopsLoading(isLoading: Bool, peekOpen: Bool, findBarOpen: Bool,
                                             commandBarVisible: Bool, dialogShown: Bool, tabFullscreen: Bool,
                                             sheetAttached: Bool) -> Bool {
    isLoading && !peekOpen && !findBarOpen && !commandBarVisible && !dialogShown && !tabFullscreen && !sheetAttached
  }

  /// An unmodified Esc the page of `tab` did not use: sends Stop when that page is the window's active tab, is loading
  /// and nothing else owns the key. True when it did. Stop goes through the engine like Cmd-., so it acts on the
  /// window's active tab, which is why an Esc from any other tab is left alone.
  func stopLoadingOnEscape(_ event: NSEvent, in tab: TabID?) -> Bool {
    guard event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
          let tab, let engineWindow, engine.latestActiveTab(in: engineWindow) == tab,
          let snapshot = engine.snapshot(of: tab) else { return false }
    let stops = Self.escapeStopsLoading(
      isLoading: snapshot.isLoading, peekOpen: peek.session != nil, findBarOpen: findBar.isOpen(tab),
      commandBarVisible: commandBar.isVisible,
      dialogShown: javaScriptDialogs.pending[tab] != nil,
      tabFullscreen: snapshot.isTabFullscreen, sheetAttached: !(window?.sheets.isEmpty ?? true))
    guard stops, engineHost.validate(.stop) else { return false }
    engineHost.dispatch(.stop, disposition: .currentTab)
    return true
  }
}
