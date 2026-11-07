import EngineAPI

/// The pages of a blank or incognito window in the order they were opened (#668, design/private-pages, "Order"):
/// the rows of the window's Pages list, oldest at the top. Showing a page never moves it. `privateTabs` keeps the
/// order pages come back in when the shown one closes; this list is separate and only says where the rows go and
/// which page Close Oldest picks. A page enters once, when it becomes a private page, and leaves when it closes.
struct PrivatePageOrder: Equatable {
  /// The most pages one private window keeps (maintainer decision 2). The next page of any kind is refused.
  static let cap = 20

  private(set) var pages: [TabID] = []

  var isFull: Bool { pages.count >= Self.cap }

  /// Adds `tab` at the bottom. False when it is listed already or the window is full: a refused page enters neither
  /// this list nor `privateTabs`.
  @discardableResult
  mutating func append(_ tab: TabID) -> Bool {
    guard !isFull, !pages.contains(tab) else { return false }
    pages.append(tab)
    return true
  }

  mutating func remove(_ tab: TabID) {
    pages.removeAll { $0 == tab }
  }

  /// Close Oldest's pick: the top row that is neither `shown` nor playing sound (a muted page that still plays counts
  /// as playing). Nil when every page is one of those; the cap toast then has no action.
  func oldestClosable(shown: TabID?, isPlaying: (TabID) -> Bool) -> TabID? {
    pages.first { $0 != shown && !isPlaying($0) }
  }

  /// Whether Close Oldest spares the page for its sound: it plays, muted or not (Chromium keeps a muted page that plays
  /// audible). A muted page that went quiet keeps its mute button (`TabAudio.muted`) but is not playing.
  static func isPlaying(_ snapshot: TabSnapshot) -> Bool { snapshot.isAudible }

  /// The toast for a page refused at the cap (design/private-pages, "Past the cap").
  static func capToast(canCloseOldest: Bool) -> Toast {
    canCloseOldest
      ? Toast(text: "This window has \(cap) pages open, the most it keeps.", glyph: "rectangle.stack",
              actionTitle: "Close Oldest")
      : Toast(text: "This window has \(cap) pages open. Close one to open another.", glyph: "rectangle.stack")
  }
}
