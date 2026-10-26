import Foundation
import Testing
@testable import ShellUI

/// Folder Preview's list (BH-093): the folder's tabs, nested ones included; typing selects the first match.
@MainActor
struct FolderPreviewSessionTests {
  private static func url(_ string: String) -> URL { URL(string: string)! }

  /// Folder [Docs (docs.example.com), Inner [Mail (mail.example.org)], split [Notes, Board]].
  private func makeFolder() throws -> (StubSidebar, NodeID, [NodeID]) {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = sidebar.addFolder(title: "Folder", in: .pinned(space))
    let docs = sidebar.addTab(url: Self.url("https://docs.example.com/a"), title: "Docs", in: .folder(folder))
    let inner = sidebar.addFolder(title: "Inner", in: .folder(folder))
    let mail = sidebar.addTab(url: Self.url("https://mail.example.org/"), title: "Mail", in: .folder(inner))
    let board = sidebar.addTab(url: Self.url("https://board.example.net/"), title: "Board", in: .folder(folder))
    let split = try sidebar.addToSplit(.new(url: Self.url("https://notes.example.com/"), title: "Notes"),
                                       target: board, at: 0, orientation: .horizontal).split
    return (sidebar, folder, [docs, mail] + sidebar.children(of: .split(split)))
  }

  @Test func listsEveryTabUnderTheFolderInSidebarOrder() throws {
    let (sidebar, folder, tabs) = try makeFolder()
    let session = FolderPreviewSession(folder: folder, in: sidebar)
    #expect(session.items.map(\.node) == tabs)
    #expect(session.items.map(\.title) == ["Docs", "Mail", "Notes", "Board"])
    #expect(session.items[1].host == "mail.example.org")
    #expect(session.highlighted == 0, "the first tab is highlighted before any typing")
  }

  @Test func typingFiltersByTitleOrHostAndSelectsTheFirstMatch() throws {
    let (sidebar, folder, tabs) = try makeFolder()
    var session = FolderPreviewSession(folder: folder, in: sidebar)
    session.query = "example.com"
    #expect(session.matches.map(\.node) == [tabs[0], tabs[2]])
    #expect(session.highlightedNode == tabs[0])
    session.query = "BOA"
    #expect(session.highlightedNode == tabs[3], "case-insensitive")
    session.query = "zzz"
    #expect(session.matches.isEmpty)
    #expect(session.highlightedNode == nil)
  }

  @Test func arrowsMoveTheHighlightWithinTheMatches() throws {
    let (sidebar, folder, tabs) = try makeFolder()
    var session = FolderPreviewSession(folder: folder, in: sidebar)
    session.move(by: 1)
    #expect(session.highlightedNode == tabs[1])
    session.move(by: 10)
    #expect(session.highlightedNode == tabs[3], "stops at the last match")
    session.move(by: -10)
    #expect(session.highlightedNode == tabs[0], "stops at the first match")
    session.query = "o"                       // Docs, Mail (host .org), Notes, Board
    session.move(by: 2)
    session.query = "oa"
    #expect(session.highlightedNode == tabs[3], "a new query highlights its first match again")
  }

  @Test func aSearchFoundOffTheMainThreadAppliesLikeTyping() async throws {
    let (sidebar, folder, tabs) = try makeFolder()
    var session = FolderPreviewSession(folder: folder, in: sidebar)
    #expect(!session.searchesOffMain, "a small folder filters as it types")
    session.move(by: 2)
    let matches = await FolderPreviewSession.matches(of: "BOA", in: session.items)
    session.apply(query: "BOA", matches: matches)
    #expect(session.query == "BOA")
    #expect(session.highlightedNode == tabs[3], "the first match is highlighted")
    session.query = "BOA"
    #expect(session.matches.map(\.node) == [tabs[3]], "the same text again changes nothing")
  }

  @Test func anEmptyFolderHasNoHighlight() {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = sidebar.addFolder(title: "Empty", in: .pinned(space))
    let session = FolderPreviewSession(folder: folder, in: sidebar)
    #expect(session.items.isEmpty)
    #expect(session.highlightedNode == nil)
  }
}
