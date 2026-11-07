import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Exercises the window set's shell-owned record boundary, not the engine's crash flag transport.
@MainActor
final class RecoveryPageSourceTests: XCTestCase {
  private func page(_ path: String, source: NodeID) -> ShellRecoveryPage {
    ShellRecoveryPage(title: path, url: URL(string: "https://example.invalid/\(path)")!,
                      kind: .peek, sourceNode: source)
  }

  func testRestoresLastPeekPerSourceAndKeepsBothPagesAlive() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Test")
    let first = sidebar.addTab(url: URL(string: "https://example.invalid/a")!, title: "A", in: .today(space))
    let second = sidebar.addTab(url: URL(string: "https://example.invalid/b")!, title: "B", in: .today(space))
    let records = RecordingRecoveryPages([page("old", source: first), page("second", source: second),
                                          page("new", source: first)])
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: sidebar, recoveryPageSource: records)
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    host.peek.animator.drivesDisplayLink = false
    defer { host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    panel.restorePressed()
    host.peek.animator.settleNow()
    host.activate(node: first)
    let firstPeek = try XCTUnwrap(host.peek.session)
    XCTAssertEqual(firstPeek.source, host.currentTab)
    XCTAssertEqual(engine.snapshot(of: firstPeek.tab)?.url?.path, "/new")
    host.peek.animator.settleNow()
    host.activate(node: second)
    let secondPeek = try XCTUnwrap(host.peek.session)
    XCTAssertEqual(secondPeek.source, host.currentTab)
    XCTAssertEqual(engine.snapshot(of: secondPeek.tab)?.url?.path, "/second")
    XCTAssertNotEqual(firstPeek.tab, secondPeek.tab)
    XCTAssertNotNil(engine.snapshot(of: firstPeek.tab))
    XCTAssertEqual(host.peek.hiddenPeeks[firstPeek.source]?.tab, firstPeek.tab)
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }

  func testRoutesToRegularWindowShowingSourceInsteadOfOfferHost() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Test")
    let first = sidebar.addTab(url: URL(string: "https://example.invalid/a")!, title: "A", in: .today(space))
    let second = sidebar.addTab(url: URL(string: "https://example.invalid/b")!, title: "B", in: .today(space))
    let records = RecordingRecoveryPages([page("peek", source: second)])
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: sidebar, recoveryPageSource: records)
    let host = set.openWindow()
    let other = set.openWindow(opensFirstTab: false)
    host.window?.isReleasedWhenClosed = false
    other.window?.isReleasedWhenClosed = false
    defer { host.close(); other.close() }
    host.activate(node: first)
    other.activate(node: second)
    let source = try XCTUnwrap(other.currentTab)
    set.beginSessionRecovery(engine.crashedSession)
    let owner = try XCTUnwrap([host, other].first { $0.rootView.subviews.contains { $0 is RestorePagesView } })
    try XCTUnwrap(owner.rootView.subviews.compactMap { $0 as? RestorePagesView }.first).restorePressed()
    XCTAssertEqual(other.peek.session?.source, source)
    XCTAssertEqual(other.peek.session.flatMap { engine.snapshot(of: $0.tab)?.url }?.path, "/peek")
    XCTAssertNil(host.peek.session)
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }

  func testLiveAndHiddenPeekAreNotReplaced() throws {
    _ = NSApplication.shared
    for hidden in [false, true] {
      let engine = InMemoryEngine()
      let sidebar = StubSidebar()
      let space = sidebar.addSpace(title: "Test")
      let first = sidebar.addTab(url: URL(string: "https://example.invalid/a")!, title: "A", in: .today(space))
      let second = sidebar.addTab(url: URL(string: "https://example.invalid/b")!, title: "B", in: .today(space))
      let records = RecordingRecoveryPages([page("recovered", source: first)])
      engine.crashedSession.simulateCrashedExit()
      let set = ShellWindowSet(engine: engine, sidebar: sidebar, recoveryPageSource: records)
      let host = set.openWindow()
      host.window?.isReleasedWhenClosed = false
      host.peek.animator.drivesDisplayLink = false
      defer { host.close() }
      host.activate(node: first)
      let source = try XCTUnwrap(host.currentTab)
      host.peek.open(URL(string: "https://example.invalid/live")!, from: source)
      let existing = try XCTUnwrap(host.peek.session)
      host.peek.animator.settleNow()
      if hidden { host.activate(node: second) }
      set.beginSessionRecovery(engine.crashedSession)
      let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
      panel.restorePressed()
      let preservedTab = hidden ? host.peek.hiddenPeeks[source]?.tab : host.peek.session?.tab
      XCTAssertEqual(preservedTab, existing.tab)
      XCTAssertEqual(engine.snapshot(of: existing.tab)?.url?.path, "/live")
      XCTAssertNotNil(panel.superview)
      XCTAssertEqual(engine.crashedSession.dismissals, 0)
    }
  }

  func testPartialFailureRollsBackAndRetryRestoresBoth() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Test")
    let first = sidebar.addTab(url: URL(string: "https://example.invalid/a")!, title: "A", in: .today(space))
    let second = sidebar.addTab(url: URL(string: "https://example.invalid/b")!, title: "B", in: .today(space))
    let records = RecordingRecoveryPages([page("one", source: first), page("two", source: second),
      ShellRecoveryPage(title: "Window", url: URL(string: "https://example.invalid/little")!, kind: .littleArkt)])
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: sidebar, recoveryPageSource: records)
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    host.peek.animator.drivesDisplayLink = false
    defer { set.littleArkts.forEach { $0.window.close() }; host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    engine.unavailableContentURLs = [records.pages[1].url]
    panel.restorePressed()
    XCTAssertNil(host.peek.session)
    XCTAssertTrue(host.peek.hiddenPeeks.isEmpty)
    XCTAssertTrue(set.littleArkts.isEmpty)
    XCTAssertEqual(engine.crashedSession.dismissals, 0)
    engine.unavailableContentURLs = []
    panel.restorePressed()
    XCTAssertEqual(host.peek.hiddenPeeks.count, 1)
    XCTAssertNotNil(host.peek.session)
    XCTAssertEqual(set.littleArkts.count, 1)
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }

  func testOfferSnapshotPrecedesBeginEvenAfterSourceChanges() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let old = ShellRecoveryPage(title: "Old", url: URL(string: "https://example.invalid/old")!, kind: .littleArkt)
    let records = RecordingRecoveryPages([old])
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample(), recoveryPageSource: records)
    records.pages = []
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    defer { host.close() }
    set.beginSessionRecovery(engine.crashedSession)
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    XCTAssertTrue(panel.rowLabels.contains { $0.stringValue.contains("Old") })
  }

  func testRecordsOpenNavigationTitleAndCloseButNotPrivatePages() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Test")
    let node = sidebar.addTab(url: URL(string: "https://example.invalid/source")!, title: "Source", in: .today(space))
    let other = sidebar.addTab(url: URL(string: "https://example.invalid/other")!, title: "Other", in: .today(space))
    let records = RecordingRecoveryPages([])
    let set = ShellWindowSet(engine: engine, sidebar: sidebar, recoveryPageSource: records)
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    host.peek.animator.drivesDisplayLink = false
    defer { set.littleArkts.forEach { $0.window.close() }; host.close() }
    host.activate(node: node)
    host.peek.open(URL(string: "https://example.invalid/peek")!, from: try XCTUnwrap(host.currentTab))
    let peek = try XCTUnwrap(host.peek.session?.tab)
    let little = set.openLittleArkt(url: URL(string: "https://example.invalid/little")!)
    let littleTab = try XCTUnwrap(little.shownTab)
    XCTAssertEqual(records.pages.count, 2)
    XCTAssertEqual(records.pages.filter { $0.kind == .peek }.count, 1)
    XCTAssertEqual(records.pages.filter { $0.kind == .littleArkt }.count, 1)
    XCTAssertEqual(records.pages.first(where: { $0.kind == .peek })?.sourceNode, node)
    host.peek.animator.settleNow()
    let writesBeforeHide = records.writes
    host.activate(node: other)
    XCTAssertEqual(records.writes, writesBeforeHide)
    XCTAssertEqual(host.peek.hiddenPeeks.count, 1)
    engine.navigate(peek, to: URL(string: "https://example.invalid/hidden")!)
    engine.setDocumentTitle(peek, "Hidden")
    XCTAssertEqual(records.pages.first(where: { $0.kind == .peek })?.title, "Hidden")
    XCTAssertEqual(records.pages.first(where: { $0.kind == .peek })?.url.path, "/hidden")
    XCTAssertEqual(records.pages.first(where: { $0.kind == .peek })?.sourceNode, node)
    host.activate(node: node)
    host.peek.animator.settleNow()
    engine.navigate(peek, to: URL(string: "https://example.invalid/next")!)
    engine.setDocumentTitle(peek, "Next")
    engine.navigate(littleTab, to: URL(string: "https://example.invalid/later")!)
    engine.setDocumentTitle(littleTab, "Later")
    XCTAssertEqual(records.pages.first(where: { $0.kind == .peek })?.url.path, "/next")
    XCTAssertEqual(records.pages.first(where: { $0.kind == .peek })?.title, "Next")
    XCTAssertEqual(records.pages.first(where: { $0.kind == .littleArkt })?.url.path, "/later")
    XCTAssertEqual(records.pages.first(where: { $0.kind == .littleArkt })?.title, "Later")
    let before = records.pages
    for mode in [ShellWindowSet.WindowKind.blank, .incognito] {
      let window = set.openWindow(opensFirstTab: true, kind: mode)
      window.window?.isReleasedWhenClosed = false
      if let tab = window.currentTab { engine.navigate(tab, to: URL(string: "https://example.invalid/private")!) }
      window.close()
    }
    XCTAssertEqual(records.pages, before)
    host.peek.close(.control)
    host.peek.animator.settleNow()
    XCTAssertFalse(records.pages.contains { $0.kind == .peek })
    little.window.close()
    XCTAssertTrue(records.pages.isEmpty)
  }

  func testHiddenPeekClosesAndUnchangedMetadataDoesNotWrite() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Test")
    let first = sidebar.addTab(url: URL(string: "https://example.invalid/a")!, title: "A", in: .today(space))
    let second = sidebar.addTab(url: URL(string: "https://example.invalid/b")!, title: "B", in: .today(space))
    let records = RecordingRecoveryPages([])
    let set = ShellWindowSet(engine: engine, sidebar: sidebar, recoveryPageSource: records)
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    host.peek.animator.drivesDisplayLink = false
    defer { host.close() }
    host.activate(node: first)
    host.peek.open(URL(string: "https://example.invalid/peek")!, from: try XCTUnwrap(host.currentTab))
    let tab = try XCTUnwrap(host.peek.session?.tab)
    engine.setDocumentTitle(tab, "Title")
    let writes = records.writes
    engine.setDocumentTitle(tab, "Title")
    XCTAssertEqual(records.writes, writes)
    host.peek.animator.settleNow()
    host.activate(node: second)
    XCTAssertEqual(records.pages.first?.sourceNode, first)
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    XCTAssertTrue(records.pages.isEmpty)
  }

  func testLaunchOfferIsCapturedBeforeLiveWritesAndDismissesOnce() throws {
    _ = NSApplication.shared
    let engine = InMemoryEngine()
    let old = ShellRecoveryPage(title: "Old", url: URL(string: "https://example.invalid/old")!, kind: .littleArkt)
    let records = RecordingRecoveryPages([old])
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample(), recoveryPageSource: records)
    set.beginSessionRecovery(engine.crashedSession)
    let little = set.openLittleArkt(url: URL(string: "https://example.invalid/live")!)
    let host = set.openWindow()
    host.window?.isReleasedWhenClosed = false
    defer { little.window.close(); host.close() }
    let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
    XCTAssertTrue(panel.rowLabels.contains { $0.stringValue.contains("Old") })
    XCTAssertFalse(records.pages.contains(old))
    panel.dismissPressed()
    panel.dismissPressed()
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
  }

  func testCleanQuitClearsRecordsButCancelledQuitDoesNot() {
    _ = NSApplication.shared
    let records = RecordingRecoveryPages([])
    let set = ShellWindowSet(engine: InMemoryEngine(), sidebar: StubSidebar.sample(), recoveryPageSource: records)
    let little = set.openLittleArkt(url: URL(string: "https://example.invalid/live")!)
    defer { little.window.close() }
    XCTAssertEqual(records.pages.count, 1)
    set.finishSessionRecovery(cleanQuit: false)
    XCTAssertEqual(records.pages.count, 1)
    if let tab = little.shownTab {
      set.engine.navigate(tab, to: URL(string: "https://example.invalid/resumed")!)
    }
    XCTAssertEqual(records.pages.first?.url.path, "/resumed")
    set.finishSessionRecovery(cleanQuit: true)
    XCTAssertTrue(records.pages.isEmpty)
    if let tab = little.shownTab {
      set.engine.navigate(tab, to: URL(string: "https://example.invalid/after-quit")!)
    }
    little.window.close()
    XCTAssertTrue(records.pages.isEmpty)
  }
}

@MainActor
private final class RecordingRecoveryPages: RecoveryPageSource {
  var writes = 0
  var pages: [ShellRecoveryPage] { didSet { writes += 1 } }
  init(_ pages: [ShellRecoveryPage]) { self.pages = pages }
}
