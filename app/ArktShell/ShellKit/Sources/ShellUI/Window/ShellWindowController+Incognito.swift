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
    sidebarController.view.privatePages.onSelect = { [weak self] tab in self?.selectPrivatePage(tab) }
    updateEmptyState()
    refreshPrivatePages()
  }

  /// Loads `url` in the shown private page: the first visit creates it, later ones navigate it. `inNewPage` (Paste
  /// URL as New Tab) makes a new private page instead, shown over the others. The tab has no sidebar node, so nothing
  /// is written to the shared sidebar. A page the engine closed is made again.
  func openPrivately(_ url: URL, inNewPage: Bool = false) {
    if !inNewPage, let shown = privateTab, engine.snapshot(of: shown) != nil {
      engine.navigate(shown, to: url)
      showPrivatePage(shown)
      return
    }
    guard !privatePageOrder.isFull else {          // #668: the 21st page does not open
      showPrivatePageCapToast()
      return
    }
    let tab = engine.createTab(url: url, in: ensureEngineWindow())
    keepsWindowWithoutEngine = false
    privatePageOrder.append(tab)
    privateTabs.append(tab)
    showPrivatePage(tab)
    activateEngineTab(tab)
  }

  /// A tab the engine opened in this window on its own (#559): a `target=_blank` link, `window.open` or
  /// `chrome.tabs.create`. It becomes a private page. One the engine made active, or the first page of an empty
  /// window, is shown; any other is queued just behind the shown page, so it is the next one shown when that page
  /// closes, unless the engine activates it first. Either way its row goes at the bottom of the Pages list (#668).
  /// Past the cap the tab is closed before it shows: the page's new tab never opens.
  func adoptPrivatePage(_ tab: TabID) {
    guard !privateTabs.contains(tab) else { return }
    let isActive = engineWindow.map { engine.latestActiveTab(in: $0) == tab } ?? false
    guard privatePageOrder.append(tab) else {
      refuseEngineTab(tab, wasActive: isActive)
      return
    }
    if isActive || currentTab == nil {
      privateTabs.append(tab)
      showPrivatePage(tab)
      if isActive { engineActiveTab = tab } else { activateEngineTab(tab) }
    } else {
      privateTabs.insert(tab, at: max(privateTabs.count - 1, 0))
      refreshPrivatePages()
    }
  }

  /// A tab the engine opened past the cap: it closes without its unload handlers, the shown page stays shown (the
  /// engine's pick of a successor is answered with it), and the cap toast says why.
  private func refuseEngineTab(_ tab: TabID, wasActive: Bool) {
    if wasActive, currentTab != nil { expectEngineReactivation() }
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    if wasActive, let shown = currentTab, let engineWindow, engine.latestActiveTab(in: engineWindow) != shown {
      activateEngineTab(shown)
    }
    if let engineWindow, engine.latestActiveTab(in: engineWindow) == currentTab { expectsEngineReactivation = false }
    showPrivatePageCapToast()
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
    refreshPrivatePages()
  }

  /// A row of the Pages list was clicked: its page is shown. The list does not reorder.
  func selectPrivatePage(_ tab: TabID) {
    guard privateTabs.contains(tab), tab != currentTab else { return }
    showPrivatePage(tab)
    activateEngineTab(tab)
  }

  /// Cmd-W on a private page (#668): the page closes (its leave-site prompt first) and the page shown before it comes
  /// back. False on the last page or without one, where Cmd-W closes the window as before.
  func closeShownPrivatePage() -> Bool {
    guard isPrivateWindow, let shown = currentTab, privateTabs.contains(shown) else { return false }
    return closePrivatePage(shown)
  }

  /// Closes `tab`, one of this window's private pages, unless it is the last one. False when it is not closed here.
  @discardableResult
  func closePrivatePage(_ tab: TabID) -> Bool {
    guard privateTabs.contains(tab), privateTabs.count > 1 else { return false }
    engine.closeTab(tab)
    return true
  }

  // MARK: The Pages list and the cap (#668)

  /// Hands the Pages list its rows: every private page in open order, the shown one current.
  func refreshPrivatePages() {
    guard isPrivateWindow else { return }
    let rows = privatePageOrder.pages.compactMap { tab -> PrivatePageRowContent? in
      guard let snapshot = engine.snapshot(of: tab) else { return nil }
      return PrivatePageRowContent(tab: tab, title: snapshot.title, url: snapshot.url, favicon: snapshot.faviconData,
                                   isShown: tab == currentTab)
    }
    sidebarController.view.privatePages.setPages(rows)
  }

  /// The page Close Oldest would close now: the earliest-opened page that is neither shown nor playing sound.
  var privatePageToCloseOldest: TabID? {
    privatePageOrder.oldestClosable(shown: currentTab) { [engine] in
      engine.snapshot(of: $0).map(PrivatePageOrder.isPlaying) ?? false
    }
  }

  /// The toast for a page refused at the cap, with Close Oldest while a page can be closed. Close Oldest picks again
  /// when pressed (a page may have started playing since) and does not open the refused page.
  func showPrivatePageCapToast() {
    if rootView.themeBackground.themes.isEmpty {      // these windows have no Space theme
      toasts.view?.theme = ToastView.plainTheme(sidebarController.view.flavor)
    }
    let toast = PrivatePageOrder.capToast(canCloseOldest: privatePageToCloseOldest != nil)
    guard toast.actionTitle != nil else {
      toasts.show(toast)
      return
    }
    toasts.show(toast) { [weak self] in self?.closeOldestPrivatePage() }
  }

  func closeOldestPrivatePage() {
    guard let oldest = privatePageToCloseOldest else { return }
    engine.closeTab(oldest)
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
      refreshPrivatePages()
    case .titleChanged, .faviconChanged, .audibleChanged, .mutedChanged:
      refreshPrivatePages()
    case .activeTabChanged:
      engineDidActivate(tab) { showPrivatePage(tab) }
    case .tabClosed(_, let reason):
      privateTabClosed(tab, reason: reason)
    case .closeCancelled:
      // The user stayed on the page: the window close is off, as for a row (`closeWasCancelled`).
      isWindowCloseRequested = false
      stampsShownTabsOnWindowClose = false
    default:
      return false
    }
    return true
  }

  private func privateTabClosed(_ tab: TabID, reason: CloseReason) {
    privateTabs.removeAll { $0 == tab }
    privatePageOrder.remove(tab)
    if tab == engineActiveTab { engineActiveTab = nil }
    guard currentTab == tab else {
      refreshPrivatePages()
      return
    }
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
    refreshPrivatePages()
  }
}
