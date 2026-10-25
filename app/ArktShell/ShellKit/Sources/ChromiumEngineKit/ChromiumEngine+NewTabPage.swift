import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - The New Tab page of a Dock reopen (#299)

/// A Dock reopen with no window arrives as a `.reopen` request, and Chromium's `chrome::NewEmptyWindow` puts its New
/// Tab page in the new window. The first Dock reopen of a session can also take Chromium's startup path
/// (`AppController`'s session restore attempt, then `StartupBrowserCreator`), a `.startupURL` request whose window
/// gets the New Tab page when no URL was given; it is handled the same way. Arc opens an empty window there, so the page is kept out of the shell's tables: it is
/// not listed or announced and its events are dropped, which leaves the shell an empty window (no Today row). The
/// page stays in the `Browser`, which would close with its last tab, until another tab joins the window (the first
/// tab the user opens, or one from an extension); then it closes without an event. A page that navigates away (a
/// menu command run with no window, such as Show All History, opens its page in that tab) is listed then, with the
/// URL it navigated to.
extension ChromiumEngine {
  /// True when `handle`, the first tab of a Dock reopen's or startup window, is kept back: the New Tab page, or a tab with no
  /// page yet (Chromium may insert it before its navigation starts; it is listed once a page other than the New Tab
  /// page arrives).
  func keepsBack(_ handle: any ArktTabHandle, url: URL?, in window: EngineWindowID) -> Bool {
    guard windows[window]?.keepsNewTabPage == true else { return false }
    windows[window]?.keepsNewTabPage = false
    guard Self.isNewTabPage(url) || Self.isBlank(url) else { return false }
    windows[window]?.newTabPage = handle
    return true
  }

  /// Closes the window's kept New Tab page once another tab is in the window, so the window stays open.
  func closeNewTabPage(in window: EngineWindowID) {
    guard let record = windows[window], let page = record.newTabPage,
          record.browser.tabs.contains(where: { $0 !== page }) else { return }
    windows[window]?.newTabPage = nil
    retired[ObjectIdentifier(page)] = page        // its facade TabClosed is dropped
    _ = page.close(mode: .skipUnloadHandlers)
  }

  /// The kept page navigated: a page other than the New Tab page is listed from now on, as the window's active tab
  /// when it is.
  func newTabPageNavigated(_ handle: any ArktTabHandle, to url: URL?) {
    guard !Self.isNewTabPage(url), !Self.isBlank(url),
          let window = windowIDs.first(where: { windows[$0]?.newTabPage === handle }) else { return }
    windows[window]?.newTabPage = nil
    adopt(handle, in: window, origin: .engine, url: url, title: handle.title)
    if let id = tabByHandle[ObjectIdentifier(handle)], windows[window]?.browser.activeTab === handle {
      activeTabChanged(id)
    }
  }

  /// The kept page closed or left its window.
  func forgetNewTabPage(_ handle: any ArktTabHandle) {
    for window in windowIDs where windows[window]?.newTabPage === handle { windows[window]?.newTabPage = nil }
  }

  /// Chromium's New Tab page (`chrome://newtab/`, `chrome://new-tab-page/`).
  static func isNewTabPage(_ url: URL?) -> Bool {
    guard let url, url.scheme == "chrome" else { return false }
    return url.host() == "newtab" || url.host() == "new-tab-page"
  }
}
