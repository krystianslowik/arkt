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
    bar.barView.widthMotion.drivesFramesItself = false
  }

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    bar.invalidate()
    parent.close()
    bar = nil
    parent = nil
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

  /// #880: a reply that lands after the bar hid leaves the hidden bar alone: no rows, no preview, no width spring,
  /// no thumbnail load and nothing said aloud.
  func testAReplyAfterHideIsDropped() async throws {
    let open = CommandBarResults.OpenTab(node: UUID(), title: "Pull requests",
                                         url: URL(string: "https://example.test/pulls")!,
                                         lastViewed: Date().addingTimeInterval(-60), spaceTitle: "Work")
    bar.openTabsProvider = { [open] }
    var announcements: [String] = []
    bar.announce = { text, _ in announcements.append(text) }
    var thumbnailRequests = 0
    bar.thumbnailForPreview = { _ in thumbnailRequests += 1; return nil }
    bar.dismissFinisher = { $0() }
    var replies: [CheckedContinuation<[CommandBarResults.ArchivedMatch], Never>] = []
    bar.archivedProvider = { _ in await withCheckedContinuation { replies.append($0) } }
    bar.show(.newTab)
    bar.setQueryForTesting("pull")
    for _ in 0..<50 where replies.isEmpty { await Task.yield() }
    XCTAssertEqual(replies.count, 1)
    XCTAssertNotNil(bar.barView.previewColumn.content, "the open tab's preview is up before the hide")

    bar.hide()
    let rowsAtHide = bar.results
    announcements = []
    thumbnailRequests = 0
    XCTAssertNil(bar.barView.previewColumn.content)
    XCTAssertFalse(bar.barView.widthMotion.isRunning)

    replies[0].resume(returning: [CommandBarResults.ArchivedMatch(id: UUID(), title: "Pull request notes",
                                                                  subtitle: "")])
    for _ in 0..<50 { await Task.yield() }

    XCTAssertFalse(bar.isVisible)
    XCTAssertEqual(bar.results, rowsAtHide, "the hidden bar's rows stay as they were")
    XCTAssertFalse(bar.results.contains { $0.kind.name == "restore" })
    XCTAssertNil(bar.barView.previewColumn.content, "no preview on the hidden bar")
    XCTAssertFalse(bar.barView.widthMotion.isRunning, "no width spring on the hidden panel")
    XCTAssertEqual(thumbnailRequests, 0, "no thumbnail load for the hidden bar")
    XCTAssertEqual(announcements, [], "nothing said aloud for the hidden bar")
  }

  /// #880: the reply of an earlier show is dropped when a later show holds the same text without searching again
  /// (text set without an edit, as a prefill is); a search the later show starts still lands.
  func testAReplyFromAnEarlierShowIsDroppedAfterAReshowWithTheSameText() async throws {
    var replies: [CheckedContinuation<[CommandBarResults.ArchivedMatch], Never>] = []
    bar.archivedProvider = { _ in await withCheckedContinuation { replies.append($0) } }
    bar.dismissFinisher = { $0() }
    bar.show(.newTab)
    bar.setQueryForTesting("expense")
    for _ in 0..<50 where replies.isEmpty { await Task.yield() }
    XCTAssertEqual(replies.count, 1)
    bar.hide()
    bar.show(.newTab)
    bar.barView.field.stringValue = "expense"           // the same text, and no search of its own

    replies[0].resume(returning: [CommandBarResults.ArchivedMatch(id: UUID(), title: "Old", subtitle: "")])
    for _ in 0..<50 { await Task.yield() }
    XCTAssertFalse(bar.results.contains { $0.kind.name == "restore" }, "the earlier show's reply is dropped")

    bar.setQueryForTesting("expense")
    for _ in 0..<50 where replies.count < 2 { await Task.yield() }
    XCTAssertEqual(replies.count, 2)
    replies[1].resume(returning: [CommandBarResults.ArchivedMatch(id: UUID(), title: "New", subtitle: "")])
    await waitForArchived()
    XCTAssertEqual(bar.results.first { $0.kind.name == "restore" }?.title, "New")
  }

  /// #880: a second show while the bar is up (no hide in between) is a new show too; the first show's reply is
  /// dropped even when the field holds its text again.
  func testAReplyFromAnEarlierShowIsDroppedAfterAShowWithoutAHide() async throws {
    var replies: [CheckedContinuation<[CommandBarResults.ArchivedMatch], Never>] = []
    bar.archivedProvider = { _ in await withCheckedContinuation { replies.append($0) } }
    bar.show(.newTab)
    bar.setQueryForTesting("expense")
    for _ in 0..<50 where replies.isEmpty { await Task.yield() }
    XCTAssertEqual(replies.count, 1)
    bar.show(.newTab)
    XCTAssertTrue(bar.isVisible)
    bar.barView.field.stringValue = "expense"

    replies[0].resume(returning: [CommandBarResults.ArchivedMatch(id: UUID(), title: "Old", subtitle: "")])
    for _ in 0..<50 { await Task.yield() }
    XCTAssertFalse(bar.results.contains { $0.kind.name == "restore" }, "the earlier show's reply is dropped")
  }
}
