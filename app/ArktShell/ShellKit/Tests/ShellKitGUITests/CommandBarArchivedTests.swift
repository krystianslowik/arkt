import AppKit
import XCTest
@_spi(Smoke) @testable import ShellUI

/// #111: archived matches reach the command bar through its async provider; Enter restores instead of opening.
@MainActor
final class CommandBarArchivedTests: XCTestCase {
  private var parent: NSWindow!
  private var bar: CommandBarController!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    parent = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 700), styleMask: [.titled],
                      backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    parent.orderFront(nil)
    bar = CommandBarController(parent: parent)
  }

  override func tearDown() async throws {
    bar.invalidate()
    parent.close()
  }

  private func waitForArchived() async {
    for _ in 0..<200 where !bar.results.contains(where: { $0.kind.name == "restore" }) { await Task.yield() }
  }

  func testArchivedMatchesArriveAndEnterRestores() async throws {
    let match = CommandBarResults.ArchivedMatch(id: UUID(), title: "Expense report template",
                                                subtitle: "sheets.example, Work, archived Sep 22")
    var asked: [String] = []
    bar.archivedProvider = { query in
      asked.append(query)
      return query.isEmpty ? [] : [match]
    }
    var restored: [UUID] = []
    var opened: [URL] = []
    bar.onRestoreArchived = { restored.append($0) }
    bar.onOpen = { url, _ in opened.append(url) }
    bar.show(.newTab)

    bar.setQueryForTesting("expense")
    await waitForArchived()

    XCTAssertEqual(asked.last, "expense")
    XCTAssertEqual(bar.results.map(\.kind.name), ["restore", "search"])
    let cell = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 0, makeIfNecessary: true)
      as? CommandBarCellView)
    XCTAssertEqual(cell.hint.stringValue, "Restore from Archive")

    bar.commit()

    XCTAssertEqual(restored, [match.id])
    XCTAssertTrue(opened.isEmpty, "no duplicate tab")
    XCTAssertFalse(bar.isVisible)
  }

  /// A reply for an older query never shows under a newer one.
  func testAStaleReplyIsDropped() async throws {
    var replies: [String: CheckedContinuation<[CommandBarResults.ArchivedMatch], Never>] = [:]
    bar.archivedProvider = { query in await withCheckedContinuation { replies[query] = $0 } }
    bar.show(.newTab)
    bar.setQueryForTesting("old")
    bar.setQueryForTesting("new")
    for _ in 0..<50 where replies.count < 2 { await Task.yield() }

    replies["old"]?.resume(returning: [CommandBarResults.ArchivedMatch(id: UUID(), title: "Old", subtitle: "")])
    for _ in 0..<50 { await Task.yield() }
    XCTAssertFalse(bar.results.contains { $0.kind.name == "restore" })

    replies["new"]?.resume(returning: [CommandBarResults.ArchivedMatch(id: UUID(), title: "New", subtitle: "")])
    await waitForArchived()
    XCTAssertEqual(bar.results.first?.title, "New")
  }
}
