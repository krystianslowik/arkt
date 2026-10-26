import Foundation
import Testing
@testable import ShellUI

/// The open switcher's rows and highlight (BH-008 to BH-010).
struct TabSwitcherSessionTests {
  private let rows = (0..<5).map { _ in UUID() }

  @Test func `no rows open no session`() {
    #expect(TabSwitcherSession(rows: [], direction: .forward) == nil)
  }

  @Test func `opening forward highlights the first row and backward the last`() throws {
    let forward = try #require(TabSwitcherSession(rows: rows, direction: .forward))
    #expect(forward.highlight == 0)
    #expect(forward.highlighted == rows[0])
    let backward = try #require(TabSwitcherSession(rows: rows, direction: .backward))
    #expect(backward.highlight == 4)
  }

  @Test func `more than five rows are cut to five`() throws {
    let many = (0..<8).map { _ in UUID() }
    let session = try #require(TabSwitcherSession(rows: many, direction: .forward))
    #expect(session.rows == Array(many.prefix(TabSwitcherSession.maximumRows)))
  }

  @Test func `the highlight wraps in both directions`() throws {
    var session = try #require(TabSwitcherSession(rows: rows, direction: .forward))
    session.move(.backward)
    #expect(session.highlight == 4)
    session.move(.forward)
    #expect(session.highlight == 0)
    for _ in 0..<3 { session.move(.forward) }
    #expect(session.highlight == 3)
  }

  @Test func `closing the highlighted row highlights the row that took its place`() throws {
    var session = try #require(TabSwitcherSession(rows: rows, direction: .forward))
    session.move(.forward)
    let empty = session.remove(rows[1])
    #expect(!empty)
    #expect(session.rows == [rows[0], rows[2], rows[3], rows[4]])
    #expect(session.highlighted == rows[2])
  }

  @Test func `closing the last row moves the highlight up`() throws {
    var session = try #require(TabSwitcherSession(rows: rows, direction: .backward))
    _ = session.remove(rows[4])
    #expect(session.highlighted == rows[3])
  }

  @Test func `removing a row above the highlight keeps the highlighted tab`() throws {
    var session = try #require(TabSwitcherSession(rows: rows, direction: .forward))
    for _ in 0..<3 { session.move(.forward) }
    _ = session.remove(rows[0])
    #expect(session.highlighted == rows[3])
  }

  @Test func `removing an unknown tab changes nothing`() throws {
    var session = try #require(TabSwitcherSession(rows: rows, direction: .forward))
    let before = session
    let removed = session.remove(UUID())
    #expect(!removed)
    #expect(session == before)
  }

  @Test func `closing every row empties the session`() throws {
    var session = try #require(TabSwitcherSession(rows: Array(rows.prefix(2)), direction: .forward))
    let result = session.remove(rows[0])
    #expect(!result)
    let next = session.remove(rows[1])
    #expect(next)
    #expect(session.rows.isEmpty)
  }
}
