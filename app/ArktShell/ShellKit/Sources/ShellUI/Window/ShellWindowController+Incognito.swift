import AppKit

extension ShellWindowController {
  /// File > New Blank Window (Ctrl-Cmd-N, BH-170): this window, with no sidebar items. The shared sidebar stays.
  func makeBlank() {
    savesSession = false
    sidebarController.present(.blank)
    keepVisitsOutOfTheSharedSidebar()
  }

  /// File > New Incognito Window (Cmd-Shift-N, BH-174): the same window, plus the sidebar label. A visit here is not
  /// written to the shared sidebar, which is what a relaunch restores.
  func makeIncognito() {
    savesSession = false
    sidebarController.present(.incognito)
    keepVisitsOutOfTheSharedSidebar()
  }

  /// Command bar and Paste and Go would add a Today tab on the shared sidebar. These windows drop that write.
  /// An engine-created tab still reaches the shared sidebar: that observer has no seam on this type.
  private func keepVisitsOutOfTheSharedSidebar() {
    commandBar.onOpen = { _, _ in }
    sidebarController.onPasteAndGo = { _ in }
  }
}
