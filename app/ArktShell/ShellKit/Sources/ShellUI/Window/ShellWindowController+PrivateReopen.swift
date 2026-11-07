import AppKit
import EngineAPI

/// A blank or incognito window that closed with pages (#746): what Reopen Closed Tab in another private window brings
/// back, for as long as the app runs. Held in memory by `ShellWindowSet`; never written anywhere.
public struct ClosedPrivateWindow: Equatable, Sendable {
  public var presentation: SidebarPresentation
  /// Its pages' URLs in open order (the Pages list's order).
  public var pages: [URL]
  /// Which of `pages` was shown; nil when none was.
  public var shownIndex: Int?
  public var frame: CGRect

  public init(presentation: SidebarPresentation, pages: [URL], shownIndex: Int?, frame: CGRect) {
    self.presentation = presentation
    self.pages = pages
    self.shownIndex = shownIndex
    self.frame = frame
  }
}

/// Reopening closed private pages and windows (#746). A private page the user closes (Cmd-W, its row's X, Close
/// Oldest) is parked as a normal page is and goes on this window's own stack, so Cmd-Shift-T and Cmd-Z bring it back
/// with its history, here only. A private window that closes with pages is handed to the window set, which reopens it
/// from another private window. A normal window never sees either.
extension ShellWindowController {
  // MARK: Pages

  /// A user close of private page `tab` is about to happen: parks a copy of it and puts the close on the stack.
  func rememberPrivateClose(of tab: TabID) {
    guard isPrivateWindow else { return }
    let closed = ClosedPrivatePage(tab: tab, parked: park(tab), url: engine.snapshot(of: tab)?.url)
    closeParked(reopenStack.push(.privatePage(closed)))
  }

  /// The close of private page `tab` was cancelled at its leave-site prompt: it never happened.
  func forgetPrivateClose(of tab: TabID) {
    closeParked(reopenStack.remove(privatePage: tab))
  }

  /// Brings a closed private page back as this window's shown page, at the bottom of the Pages list: its parked copy
  /// when that is still open, else a new page on its URL. At the cap nothing opens: the cap toast says why and the
  /// close goes back on the stack. True when something happened that ends the reopen.
  func reopen(_ closed: ClosedPrivatePage) -> Bool {
    guard isPrivateWindow else {
      assertionFailure("a private page's close is only ever on a private window's stack")
      closeParked(ClosedItem.privatePage(closed).parkedTabs)
      return false
    }
    guard !privatePageOrder.isFull else {
      closeParked(reopenStack.push(.privatePage(closed)))
      showPrivatePageCapToast()
      return true
    }
    if let copy = closed.parked {
      parkedTabs.remove(copy)
      if engine.snapshot(of: copy) != nil {
        privatePageOrder.append(copy)
        showPrivatePage(copy)
        activateEngineTab(copy)
        return true
      }
    }
    guard let url = closed.url else { return false }
    openPrivately(url, inNewPage: true)
    return true
  }

  // MARK: The window

  /// This window's pages as a closed private window; nil for a normal window or one without pages.
  private var closedPrivateWindowRecord: ClosedPrivateWindow? {
    guard isPrivateWindow, let window else { return nil }
    let pages = privatePageOrder.pages.compactMap { tab in
      (engine.snapshot(of: tab)?.url ?? privatePageURLs[tab]).map { (tab, $0) }
    }
    guard !pages.isEmpty else { return nil }
    return ClosedPrivateWindow(presentation: sidebarController.presentation, pages: pages.map(\.1),
                               shownIndex: pages.firstIndex { $0.0 == currentTab }, frame: window.frame)
  }

  /// The window's close began: its pages are noted before they close. A close already under way keeps its note.
  func holdClosingPrivateWindow() {
    guard closingPrivateWindow == nil else { return }
    closingPrivateWindow = closedPrivateWindowRecord
  }

  /// The window closed: the noted pages go to the window set.
  func handOverClosedPrivateWindow() {
    defer { closingPrivateWindow = nil }
    guard isPrivateWindow, !isClosed, let closed = closingPrivateWindow ?? closedPrivateWindowRecord else { return }
    onPrivateWindowClosed?(closed)
  }

  /// Opens `closed`'s pages here, in their order, and shows the one it showed.
  func restorePages(of closed: ClosedPrivateWindow) {
    for url in closed.pages { openPrivately(url, inNewPage: true) }
    if let index = closed.shownIndex, privatePageOrder.pages.indices.contains(index) {
      selectPrivatePage(privatePageOrder.pages[index])
    }
  }
}
