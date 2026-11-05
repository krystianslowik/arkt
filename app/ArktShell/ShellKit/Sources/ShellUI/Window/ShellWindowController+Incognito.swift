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
  /// of their own instead, one without a row. A tab the engine opens here (`engineDidCreateTab`) is one too (#559).
  private func keepVisitsOutOfTheSharedSidebar() {
    isPrivateWindow = true
    commandBar.onOpen = { [weak self] url, _ in self?.openPrivately(url) }
    sidebarController.onPasteAndGo = { [weak self] url in self?.openPrivately(url) }
  }

  /// Loads `url` in the shown private page: the first visit creates it, later ones navigate it. The tab has no
  /// sidebar node, so nothing is written to the shared sidebar. A page the engine closed is made again.
  private func openPrivately(_ url: URL) {
    if let shown = privateTab, engine.snapshot(of: shown) != nil {
      engine.navigate(shown, to: url)
      showPrivatePage(shown)
      return
    }
    let tab = engine.createTab(url: url, in: ensureEngineWindow())
    keepsWindowWithoutEngine = false
    privateTabs.append(tab)
    showPrivatePage(tab)
    activateEngineTab(tab)
  }

  /// A tab the engine opened in this window on its own (#559): a `target=_blank` link, `window.open` or
  /// `chrome.tabs.create`. It becomes a private page. One the engine made active, or the first page of an empty
  /// window, is shown; any other is queued just behind the shown page, so it is the next one shown when that page
  /// closes, unless the engine activates it first.
  func adoptPrivatePage(_ tab: TabID) {
    guard !privateTabs.contains(tab) else { return }
    let isActive = engineWindow.map { engine.latestActiveTab(in: $0) == tab } ?? false
    if isActive || currentTab == nil {
      privateTabs.append(tab)
      showPrivatePage(tab)
      if isActive { engineActiveTab = tab } else { activateEngineTab(tab) }
    } else {
      privateTabs.insert(tab, at: max(privateTabs.count - 1, 0))
    }
  }

  /// Shows `tab`, one of this window's private pages, and makes it the one a command-bar visit navigates.
  private func showPrivatePage(_ tab: TabID) {
    privateTabs.removeAll { $0 == tab }
    privateTabs.append(tab)
    hideSplit()
    currentTab = tab
    rootView.card.setContent(engine.contentView(for: tab))
    setShown([])
    refreshAddress()
  }

  /// The events of the private pages, which have no row to route them through. The address bar and the Back and
  /// Forward state follow the shown page; an engine activation shows its page. When the engine closes the shown page
  /// (a script, an extension), the page shown before it comes back, over the engine's own pick; with none left the
  /// window is empty, and the next visit makes a new one.
  func handlePrivateTabEvent(_ event: EngineEvent) -> Bool {
    let tab = event.tabID
    guard privateTabs.contains(tab) else { return false }
    switch event {
    case .urlChanged, .historyChanged:
      if tab == currentTab { refreshAddress() }
    case .activeTabChanged:
      engineDidActivate(tab) { showPrivatePage(tab) }
    case .tabClosed(_, let reason):
      privateTabClosed(tab, reason: reason)
    default:
      return false
    }
    return true
  }

  private func privateTabClosed(_ tab: TabID, reason: CloseReason) {
    privateTabs.removeAll { $0 == tab }
    guard currentTab == tab else { return }
    let windowIsClosing = isWindowCloseRequested || reason == .windowClosing || reason == .appTerminating
    if !windowIsClosing, let next = privateTab {
      // The engine picks a successor of its own; the shell's choice is the page before this one.
      expectEngineReactivation()
      showPrivatePage(next)
      activateEngineTab(next)
      return
    }
    currentTab = nil
    rootView.card.setContent(nil)
    refreshAddress()
  }
}
