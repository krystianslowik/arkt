import AppKit

/// Session restore for the main window (#116): the frame and screen, the Space, the current tab and each Space's
/// selected tab are saved as they change and applied by the session's first window at launch. The Spaces and tabs
/// themselves persist through the database; this is only which of them was on screen.
extension ShellWindowController {
  /// The state to save now; nil without a window.
  func currentSessionState() -> WindowSessionState? {
    guard let window else { return nil }
    return .capturing(frame: window.frame, windowedFrame: frameBeforeFullScreen,
                      isFullScreen: window.styleMask.contains(.fullScreen), screenFrame: window.screen?.frame,
                      space: sidebarController.currentSpace, currentTab: currentNode,
                      selectedTabs: sidebarController.selectedTabs)
  }

  /// Saves the window's state, unless this is not the restored window, a quit froze saving, or the window is going
  /// away (its tabs closing would otherwise leave an empty selection behind).
  func saveSession() {
    guard savesSession, !isClosed, !isWindowCloseRequested, let state = currentSessionState() else { return }
    sessionStore.save(state)
  }

  /// Applies the saved Space and selections to the sidebar before the first tab is shown, and returns the saved
  /// current tab when it is still a tab of that Space (or a Favorite). Nil: show the Space's own pick.
  func restoreSession(_ state: WindowSessionState) -> NodeID? {
    sidebarController.restoreSelections(state.selectedTabs)
    if let space = state.space { sidebarController.showSpace(space) }
    guard let tab = state.currentTab, case .tab? = sidebar.node(tab) else { return nil }
    if let space = sidebar.spaceID(containing: tab) { return space == sidebarController.currentSpace ? tab : nil }
    if case .favorites? = sidebar.section(containing: tab) { return tab }
    return nil
  }

  /// Moves the window to its saved frame, clamped to the connected screens. True when it was moved.
  @discardableResult
  func applySavedFrame(_ state: WindowSessionState, screens: [ScreenGeometry]) -> Bool {
    guard let window,
          let frame = WindowFramePlacement.restoredFrame(saved: state.frame, savedScreen: state.screenFrame,
                                                         screens: screens, minSize: window.minSize) else { return false }
    window.setFrame(frame, display: false)
    return true
  }
}
