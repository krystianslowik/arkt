import CoreGraphics
import Foundation
import Testing
@testable import ShellUI

/// When the preview column shows, what it says, and which request it keeps (#372). Pure: no window, no clock.
struct CommandBarPreviewTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }
  /// 2026-10-27 15:30:00 UTC. Shared with `CommandBarRelativeTimeTests`.
  private let now = Date(timeIntervalSince1970: 1_793_115_000)

  private func facts(
    _ kind: CommandBarRowKind,
    title: String = "Pull requests",
    host: String = "example.test",
    space: String? = nil,
    time: String? = nil,
    alsoOpen: Bool = false,
    url: String = "https://example.test/pulls",
    node: NodeID? = nil
  ) -> CommandBarPreviewFacts {
    CommandBarPreviewFacts(rowKind: kind, title: title, host: host, spaceTitle: space, timeText: time,
                           isAlsoOpen: alsoOpen, url: URL(string: url)!, node: node)
  }

  // MARK: When it shows

  @Test func `only an open tab or a history row with a query has a preview`() {
    let node = UUID()
    let tab = facts(.openTab, space: "Work", time: "12 min ago", node: node)
    let history = facts(.history, time: "Yesterday")
    #expect(CommandBarPreview.content(for: tab, queryIsEmpty: false) != nil)
    #expect(CommandBarPreview.content(for: history, queryIsEmpty: false) != nil)
    #expect(CommandBarPreview.content(for: tab, queryIsEmpty: true) == nil, "an empty query stays the narrow bar")
    #expect(CommandBarPreview.content(for: history, queryIsEmpty: true) == nil)
    for kind in [CommandBarRowKind.searchSuggestion, .siteSearch, .action, .pasteAndGo, .archived, .address, .space,
                 .noMatch] {
      #expect(CommandBarPreview.content(for: facts(kind), queryIsEmpty: false) == nil, "\(kind)")
    }
  }

  // MARK: Meta line and primary action

  @Test func `an open tab says where it is open and offers Switch to Tab`() throws {
    let node = UUID()
    let content = try #require(CommandBarPreview.content(
      for: facts(.openTab, space: "Work", time: "12 min ago", node: node), queryIsEmpty: false))
    #expect(content.title == "Pull requests")
    #expect(content.meta == "example.test · open in Work, 12 min ago")
    #expect(content.showsOpenDot)
    #expect(content.primaryTitle == "Switch to Tab")
    #expect(content.splitTitle == "Split View")
    #expect(content.thumbnail == .liveTab(node))
    #expect(content.node == node)
  }

  @Test func `a missing space or time drops that clause`() throws {
    let openSpace = try #require(CommandBarPreview.content(
      for: facts(.openTab, space: "Work", node: UUID()), queryIsEmpty: false))
    #expect(openSpace.meta == "example.test · open in Work")
    #expect(openSpace.showsOpenDot)
    let openTime = try #require(CommandBarPreview.content(
      for: facts(.openTab, time: "Now", node: UUID()), queryIsEmpty: false))
    #expect(openTime.meta == "example.test · open, Now")
  }

  @Test func `history that is not open says visited and offers Open`() throws {
    let content = try #require(CommandBarPreview.content(
      for: facts(.history, time: "Yesterday"), queryIsEmpty: false))
    #expect(content.meta == "example.test · visited Yesterday")
    #expect(!content.showsOpenDot)
    #expect(content.primaryTitle == "Open")
    #expect(content.splitTitle == "Split View")
    #expect(content.thumbnail == .cachedPage(URL(string: "https://example.test/pulls")!))
    #expect(content.node == nil)
  }

  @Test func `history with no time still says visited`() throws {
    let content = try #require(CommandBarPreview.content(for: facts(.history), queryIsEmpty: false))
    #expect(content.meta == "example.test · visited")
    #expect(!content.showsOpenDot)
    #expect(content.primaryTitle == "Open")
  }

  @Test func `history of an open tab switches to it but keeps the visited line and the cached thumbnail`() throws {
    let node = UUID()
    let content = try #require(CommandBarPreview.content(
      for: facts(.history, time: "12 min ago", alsoOpen: true, node: node), queryIsEmpty: false))
    #expect(content.meta == "example.test · visited 12 min ago")
    #expect(!content.showsOpenDot)
    #expect(content.primaryTitle == "Switch to Tab")
    #expect(content.thumbnail == .cachedPage(URL(string: "https://example.test/pulls")!))
    #expect(content.node == node)
  }

  @Test func `the preview clock says ago except for Now and Yesterday`() {
    func preview(_ secondsAgo: TimeInterval) -> String {
      CommandBarRelativeTime.preview(from: now.addingTimeInterval(-secondsAgo), to: now, calendar: calendar)
    }
    #expect(preview(0) == "Now")
    #expect(preview(12 * 60) == "12 min ago")
    #expect(preview(3 * 3600) == "3 h ago")
    #expect(preview(16 * 3600) == "Yesterday")
    #expect(preview(3 * 86_400) == "3 d ago")
  }

  // MARK: Rows the bar builds

  @Test func `a typed query fills the open tab preview and leaves every other row without one`() throws {
    var input = CommandBarResults.Input()
    input.now = now
    input.openTabs = [CommandBarResults.OpenTab(node: UUID(), title: "Pull requests",
                                                url: URL(string: "https://example.test/pulls")!,
                                                lastViewed: now.addingTimeInterval(-12 * 60), spaceTitle: "Work")]
    input.spaces = [CommandBarResults.Space(id: UUID(), title: "Pull Space")]
    input.actions = [CommandBarAction(id: "pull", title: "Pull action")]
    input.archived = [CommandBarResults.ArchivedMatch(id: UUID(), title: "Pull archive", subtitle: "example.test")]
    let rows = CommandBarResults.make(query: "Pull", input: input)
    let tab = try #require(rows.first { $0.rowKind == .openTab })
    let content = try #require(CommandBarPreview.content(for: tab.previewFacts, queryIsEmpty: false))
    #expect(content.meta == "example.test · open in Work, 12 min ago")
    #expect(content.primaryTitle == "Switch to Tab")
    #expect(content.showsOpenDot)
    for row in rows where row.rowKind != .openTab {
      #expect(row.previewFacts == nil, "\(row.rowKind)")
      #expect(CommandBarPreview.content(for: row.previewFacts, queryIsEmpty: false) == nil)
    }
    #expect(CommandBarPreview.content(for: tab.previewFacts, queryIsEmpty: true) == nil)
  }

  @Test func `history sits after open tabs and before spaces, and a closed visit offers Open`() throws {
    var input = CommandBarResults.Input()
    input.now = now
    let openNode = UUID()
    input.openTabs = [CommandBarResults.OpenTab(node: openNode, title: "Pull requests",
                                                url: URL(string: "https://example.test/pulls")!, spaceTitle: "Work")]
    input.history = [
      CommandBarResults.HistoryVisit(title: "Notes", url: URL(string: "https://notes.example.test/today")!,
                                    visited: now.addingTimeInterval(-12 * 60)),
      CommandBarResults.HistoryVisit(title: "Pull requests", url: URL(string: "https://example.test/pulls")!,
                                    visited: now.addingTimeInterval(-3600), openTab: openNode),
    ]
    input.spaces = [CommandBarResults.Space(id: UUID(), title: "Pull Space")]
    let rows = CommandBarResults.make(query: "Pull", input: input)
    let kinds = rows.map(\.rowKind)
    let tab = try #require(kinds.firstIndex(of: .openTab))
    let history = try #require(kinds.firstIndex(of: .history))
    let space = try #require(kinds.firstIndex(of: .space))
    #expect(tab < history && history < space)

    let notes = CommandBarResults.make(query: "Notes", input: input)
    let closed = try #require(notes.first { $0.rowKind == .history })
    #expect(closed.timeText == "12 min", "the row keeps the short time; the preview adds ago")
    let content = try #require(CommandBarPreview.content(for: closed.previewFacts, queryIsEmpty: false))
    #expect(content.primaryTitle == "Open")
    #expect(content.meta == "notes.example.test · visited 12 min ago")
    #expect(!content.showsOpenDot)
    #expect(content.thumbnail == .cachedPage(URL(string: "https://notes.example.test/today")!))

    let openAgain = try #require(rows.first { $0.rowKind == .history })
    let openContent = try #require(CommandBarPreview.content(for: openAgain.previewFacts, queryIsEmpty: false))
    #expect(openContent.primaryTitle == "Switch to Tab")
    #expect(!openContent.showsOpenDot)
    #expect(openContent.node == openNode)
  }

  // MARK: Stale thumbnails

  @Test func `a thumbnail token from an earlier selection is dropped`() {
    var gate = CommandBarThumbnailGate()
    let first = gate.begin()
    let second = gate.begin()
    #expect(!gate.accepts(first))
    #expect(gate.accepts(second))
    #expect(!gate.accepts(0))
    let third = gate.begin()
    #expect(!gate.accepts(second))
    #expect(gate.accepts(third))
  }

  // MARK: Geometry

  @Test func `the wide bar keeps the narrow bar's leading edge and the column's metrics`() {
    typealias G = CommandBarGeometry
    #expect(G.previewWidth == 968)
    #expect(G.previewColumnWidth == 300)
    #expect(G.previewColumnPadding == 12)
    #expect(G.previewThumbnailHeight == 116)
    #expect(G.previewThumbnailRadius == 10)
    #expect(G.previewButtonHeight == 30)
    #expect(G.previewButtonRadius == 8)
    let parent = CGRect(x: 100, y: 50, width: 1280, height: 800)
    let height = G.contentHeight(rowCount: 5)
    let narrow = G.frame(parentFrame: parent, contentHeight: height)
    let wide = G.frame(parentFrame: parent, contentHeight: height, showsPreview: true)
    #expect(wide.width == 968)
    #expect(wide.minX == narrow.minX, "the list's leading edge does not move")
    #expect(wide.height == narrow.height, "the column does not grow the bar")
    #expect(wide.maxY == narrow.maxY)
  }

  @Test func `a window that cannot hold 968 keeps the leading edge and clips to the window`() {
    let parent = CGRect(x: 0, y: 0, width: 900, height: 700)
    let narrow = CommandBarGeometry.frame(parentFrame: parent, contentHeight: 200)
    let wide = CommandBarGeometry.frame(parentFrame: parent, contentHeight: 200, showsPreview: true)
    #expect(wide.minX == narrow.minX)
    #expect(wide.maxX == parent.maxX)
    #expect(wide.width < 968)
    #expect(CommandBarGeometry.previewColumnWidth == 300, "the column is not narrowed")
  }
}
