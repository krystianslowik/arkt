import AppKit
import EngineAPI

extension ShellWindowController {
  /// File > New Blank Window (Ctrl-Cmd-N, BH-170): this window, with no sidebar items. The shared sidebar stays.
  public func makeBlank() {
    savesSession = false
    sidebarController.present(.blank)
    keepVisitsOutOfTheSharedSidebar()
  }

  /// File > New Incognito Window (Cmd-Shift-N, BH-174): the same window, plus the sidebar label. A visit here is not
  /// written to the shared sidebar, which is what a relaunch restores.
  public func makeIncognito() {
    savesSession = false
    sidebarController.present(.incognito)
    keepVisitsOutOfTheSharedSidebar()
  }

  /// Command bar and Paste and Go would add a Today tab on the shared sidebar. These windows load the page in a tab
  /// of their own instead, one without a row.
  /// An engine-created tab still reaches the shared sidebar: that observer has no seam on this type.
  private func keepVisitsOutOfTheSharedSidebar() {
    commandBar.onOpen = { [weak self] url, _ in self?.openPrivately(url) }
    sidebarController.onPasteAndGo = { [weak self] url in self?.openPrivately(url) }
  }

  /// Loads `url` in this window's one private page: the first visit creates it, later ones navigate it. The tab has
  /// no sidebar node, so nothing is written to the shared sidebar. A page the engine closed is made again.
  private func openPrivately(_ url: URL) {
    let tab: TabID
    if let existing = privateTab, engine.snapshot(of: existing) != nil {
      engine.navigate(existing, to: url)
      tab = existing
    } else {
      tab = engine.createTab(url: url, in: ensureEngineWindow())
      keepsWindowWithoutEngine = false
      privateTab = tab
    }
    hideSplit()
    currentTab = tab
    rootView.card.setContent(engine.contentView(for: tab))
    setShown([])
    refreshAddress()
  }
}
