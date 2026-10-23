import AppKit
import Archive
import CoreBridge
import SidebarModel
import XCTest
@testable import ShellUI

/// The Archive window (E5c) over a stub data source, plus the outline cache pruning it depends on: a restore can put
/// a node back under the id the outline last saw.
@MainActor
final class ArchiveWindowTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    windows.forEach { $0.close() }
    windows = []
  }

  private func makeWindow(_ source: StubArchiveSource) -> ArchiveWindowController {
    let controller = ArchiveWindowController(dataSource: source)
    if let window = controller.window { windows.append(window) }
    return controller
  }

  private static func rows(_ count: Int, from start: Int = 0) -> [ArchiveRow] {
    (start..<start + count).map {
      ArchiveRow(id: UUID(), title: "Item \($0)", detail: "a.example - Work - 1 hour ago", reason: "Closed")
    }
  }

  private func cell(_ controller: ArchiveWindowController, row: Int) throws -> ArchiveRowCellView {
    let view = controller.tableView.view(atColumn: 0, row: row, makeIfNecessary: true)
    return try XCTUnwrap(view as? ArchiveRowCellView)
  }

  // MARK: - Window

  func testWindowShapeAndTitle() throws {
    let controller = makeWindow(StubArchiveSource())
    let window = try XCTUnwrap(controller.window)
    XCTAssertEqual(window.title, "Archive")
    XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, NSSize(width: 600, height: 480))
    XCTAssertTrue(window.styleMask.contains(.titled))
    XCTAssertFalse(window.isReleasedWhenClosed, "the app fronts the same window again")
    XCTAssertTrue(controller.tableView.enclosingScrollView != nil)
  }

  /// Escape (`cancelOperation:` up the responder chain from the table) closes the window like its close button.
  func testEscapeClosesTheWindow() throws {
    let controller = makeWindow(StubArchiveSource())
    let window = try XCTUnwrap(controller.window)
    window.orderFront(nil)
    XCTAssertTrue(window.makeFirstResponder(controller.tableView))
    XCTAssertTrue(window.isVisible)

    controller.tableView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

    XCTAssertFalse(window.isVisible)
  }

  func testListsRowsAndReportsUnreadableItems() async throws {
    let source = StubArchiveSource()
    source.pages = [ArchiveListPage(rows: Self.rows(3), unreadable: 3, mayHaveMore: true)]
    let controller = makeWindow(source)

    await controller.reload()

    XCTAssertEqual(source.calls, [.loadPage])
    XCTAssertEqual(controller.tableView.numberOfRows, 3)
    let first = try cell(controller, row: 0)
    XCTAssertEqual(first.titleField.stringValue, "Item 0")
    XCTAssertEqual(first.detailField.stringValue, "a.example - Work - 1 hour ago - Closed")
    first.layoutSubtreeIfNeeded()
    XCTAssertGreaterThanOrEqual(first.titleField.frame.minY, first.detailField.frame.maxY, "title above detail")
    XCTAssertGreaterThan(first.detailField.frame.width, 0)
    XCTAssertFalse(controller.footerLabel.isHidden)
    XCTAssertEqual(controller.footerLabel.stringValue, "3 items could not be read")
    XCTAssertFalse(controller.loadMoreButton.isHidden)
  }

  func testFooterAndLoadMoreHiddenWhenNothingIsMissing() async throws {
    let source = StubArchiveSource()
    source.pages = [ArchiveListPage(rows: Self.rows(2), unreadable: 0, mayHaveMore: false)]
    let controller = makeWindow(source)

    await controller.reload()

    XCTAssertTrue(controller.footerLabel.isHidden)
    XCTAssertTrue(controller.loadMoreButton.isHidden)
  }

  func testOneUnreadableItemUsesTheSingular() async throws {
    let source = StubArchiveSource()
    source.pages = [ArchiveListPage(rows: [], unreadable: 1, mayHaveMore: false)]
    let controller = makeWindow(source)

    await controller.reload()

    XCTAssertEqual(controller.footerLabel.stringValue, "1 item could not be read")
  }

  func testFailedLoadSaysSo() async throws {
    let source = StubArchiveSource()
    source.pages = [ArchiveListPage(rows: [], unreadable: 0, mayHaveMore: false, failed: true)]
    let controller = makeWindow(source)

    await controller.reload()

    XCTAssertFalse(controller.footerLabel.isHidden)
    XCTAssertEqual(controller.footerLabel.stringValue, "The Archive could not be read.")
  }

  func testLoadMoreAppendsTheNextPageAndHidesWhenDone() async throws {
    let source = StubArchiveSource()
    let first = Self.rows(2)
    source.pages = [
      ArchiveListPage(rows: first, unreadable: 0, mayHaveMore: true),
      ArchiveListPage(rows: first + Self.rows(1, from: 2), unreadable: 0, mayHaveMore: false),
    ]
    let controller = makeWindow(source)
    await controller.reload()

    await controller.loadMore()

    XCTAssertEqual(source.calls, [.loadPage, .loadMore])
    XCTAssertEqual(controller.tableView.numberOfRows, 3)
    XCTAssertTrue(controller.loadMoreButton.isHidden)
  }

  func testLoadMoreButtonAsksTheSource() async throws {
    let source = StubArchiveSource()
    source.pages = [
      ArchiveListPage(rows: Self.rows(1), unreadable: 0, mayHaveMore: true),
      ArchiveListPage(rows: Self.rows(2), unreadable: 0, mayHaveMore: false),
    ]
    let controller = makeWindow(source)
    await controller.reload()

    controller.loadMoreButton.performClick(nil)
    await controller.pendingLoad?.value

    XCTAssertEqual(source.calls, [.loadPage, .loadMore])
    XCTAssertEqual(controller.tableView.numberOfRows, 2)
  }

  func testShowingAgainReloads() async throws {
    let source = StubArchiveSource()
    source.pages = [
      ArchiveListPage(rows: Self.rows(1), unreadable: 0, mayHaveMore: false),
      ArchiveListPage(rows: Self.rows(2), unreadable: 0, mayHaveMore: false),
    ]
    let controller = makeWindow(source)

    controller.show()
    await controller.pendingLoad?.value
    XCTAssertEqual(controller.tableView.numberOfRows, 1)
    controller.close()
    controller.show()
    await controller.pendingLoad?.value

    XCTAssertEqual(source.calls, [.loadPage, .loadPage])
    XCTAssertEqual(controller.tableView.numberOfRows, 2)
  }

  // MARK: - Data source changes (#88)

  /// An outbox change while the window is on screen refreshes it at the loaded depth.
  func testDataSourceChangeRefreshesTheVisibleWindow() async throws {
    let source = StubArchiveSource()
    source.pages = [
      ArchiveListPage(rows: Self.rows(1), unreadable: 0, mayHaveMore: false),
      ArchiveListPage(rows: Self.rows(2), unreadable: 0, mayHaveMore: false),
    ]
    let controller = makeWindow(source)
    controller.show()
    await controller.pendingLoad?.value

    source.onChange?()
    await controller.pendingLoad?.value

    XCTAssertEqual(source.calls, [.loadPage, .refresh])
    XCTAssertEqual(controller.tableView.numberOfRows, 2)
  }

  /// A hidden window does not read; showing it loads anyway.
  func testDataSourceChangeIsIgnoredWhileHidden() async throws {
    let source = StubArchiveSource()
    let controller = makeWindow(source)
    controller.show()
    await controller.pendingLoad?.value
    controller.close()

    source.onChange?()
    await controller.pendingLoad?.value

    XCTAssertEqual(source.calls, [.loadPage])
  }

  /// The selected row stays selected across a refresh that moves it (a new entry above it).
  func testRefreshKeepsTheSelectedRow() async throws {
    let source = StubArchiveSource()
    let rows = Self.rows(2)
    let newer = Self.rows(1, from: 9)
    source.pages = [
      ArchiveListPage(rows: rows, unreadable: 0, mayHaveMore: false),
      ArchiveListPage(rows: newer + rows, unreadable: 0, mayHaveMore: false),
    ]
    let controller = makeWindow(source)
    controller.show()
    await controller.pendingLoad?.value
    controller.tableView.selectRowIndexes([1], byExtendingSelection: false)

    source.onChange?()
    await controller.pendingLoad?.value

    XCTAssertEqual(controller.tableView.selectedRow, 2)
    XCTAssertTrue(controller.restoreButton.isEnabled)
  }

  // MARK: - Restore

  func testRestoreButtonFollowsSelectionAndCanRestore() async throws {
    let source = StubArchiveSource()
    source.pages = [ArchiveListPage(rows: Self.rows(2), unreadable: 0, mayHaveMore: false)]
    let controller = makeWindow(source)
    await controller.reload()
    XCTAssertFalse(controller.restoreButton.isEnabled, "no selection")

    controller.tableView.selectRowIndexes([1], byExtendingSelection: false)
    XCTAssertTrue(controller.restoreButton.isEnabled)

    source.canRestore = false
    controller.tableView.selectRowIndexes([0], byExtendingSelection: false)
    XCTAssertFalse(controller.restoreButton.isEnabled, "no Space to restore into")
  }

  /// #89: opened with no Space, a row selected, Restore is off; creating a Space turns it on without a selection
  /// change. Runs the app's list model over a model source.
  func testCreatingASpaceEnablesRestore() async throws {
    let source = ModelSidebarSource()
    let item = ArchivedItem(
      reason: .manual, archivedAt: .now, source: .unknown, section: .today,
      snapshot: NodeSnapshot(kind: .tab(TabItem(url: URL(string: "https://a.example")!, title: "A")), createdAt: .now))
    let store = FixedArchiveStore(items: [item])
    let model = ArchiveListModel(
      source: source, store: store, coordinator: ArchiveCoordinator(source: source, store: store))
    let controller = ArchiveWindowController(dataSource: model)
    if let window = controller.window { windows.append(window) }
    controller.show()
    await controller.pendingLoad?.value
    controller.tableView.selectRowIndexes([0], byExtendingSelection: false)
    XCTAssertFalse(controller.restoreButton.isEnabled, "no Space to restore into")

    try source.addSpace(title: "Work")
    await controller.pendingLoad?.value

    XCTAssertEqual(controller.tableView.selectedRow, 0)
    XCTAssertTrue(controller.restoreButton.isEnabled)
  }

  func testRestoreButtonRestoresTheSelectedRowAndDropsIt() async throws {
    let source = StubArchiveSource()
    let rows = Self.rows(3)
    source.pages = [ArchiveListPage(rows: rows, unreadable: 0, mayHaveMore: false)]
    let controller = makeWindow(source)
    await controller.reload()
    controller.tableView.selectRowIndexes([1], byExtendingSelection: false)

    controller.restoreButton.performClick(nil)

    XCTAssertEqual(source.calls.last, .restore(rows[1].id))
    XCTAssertEqual(controller.rows.map(\.id), [rows[0].id, rows[2].id])
    XCTAssertEqual(controller.tableView.numberOfRows, 2)
  }

  func testDoubleClickRestoresTheRow() async throws {
    let source = StubArchiveSource()
    let rows = Self.rows(2)
    source.pages = [ArchiveListPage(rows: rows, unreadable: 0, mayHaveMore: false)]
    let controller = makeWindow(source)
    await controller.reload()
    let table = controller.tableView
    table.selectRowIndexes([0], byExtendingSelection: false)

    let action = try XCTUnwrap(table.doubleAction)
    XCTAssertTrue(NSApp.sendAction(action, to: table.target, from: table))

    XCTAssertEqual(source.calls.last, .restore(rows[0].id))
    XCTAssertEqual(controller.rows.map(\.id), [rows[1].id])
  }

  func testRestoreRefusedKeepsTheRow() async throws {
    let source = StubArchiveSource()
    source.restoreSucceeds = false
    let rows = Self.rows(1)
    source.pages = [ArchiveListPage(rows: rows, unreadable: 0, mayHaveMore: false)]
    let controller = makeWindow(source)
    await controller.reload()
    controller.tableView.selectRowIndexes([0], byExtendingSelection: false)

    controller.restoreSelected(nil)

    XCTAssertEqual(source.calls.last, .restore(rows[0].id))
    XCTAssertEqual(controller.tableView.numberOfRows, 1)
  }

  // MARK: - Outline cache pruning (E2b), through ModelSidebarSource

  /// Remove a folder that has children and is expanded, then insert a node under the same id with another title and
  /// other children: the outline shows the new title and children, not the cached ones.
  func testRemoveThenInsertUnderTheSameIdShowsFreshChildrenAndTitle() throws {
    let source = ModelSidebarSource()
    let space = try source.addSpace(title: "Work")
    let folder = try source.mutate { try $0.addFolder(title: "Old Folder", in: .pinned(space)) }
    let oldChildren = try (0..<2).map { index in
      try source.addTab(url: URL(string: "https://old\(index).example")!, title: "Old \(index)", in: .folder(folder))
    }
    let controller = SidebarController(source: source)
    host(controller)
    let outlineController = try XCTUnwrap(controller.currentPage?.outlineController)
    let outline = try XCTUnwrap(controller.view.currentOutline)
    XCTAssertEqual(outline.numberOfRows, 1 + 2 + 1, "folder, its two children (expanded), divider")
    XCTAssertGreaterThanOrEqual(outlineController.row(for: oldChildren[0]), 0)

    let archived = source.archive([folder], reason: .manual, at: .now)
    XCTAssertEqual(archived.map(\.id), [folder])
    XCTAssertEqual(outline.numberOfRows, 1, "only the divider is left")

    let fresh = (0..<3).map { index in
      NodeSnapshot(kind: .tab(TabItem(url: URL(string: "https://new\(index).example")!, title: "New \(index)")),
                   createdAt: .now)
    }
    try source.mutate {
      try $0.insert(NodeSnapshot(id: folder, kind: .folder(FolderItem(title: "New Folder")), createdAt: .now,
                                 children: fresh), in: .pinned(space))
    }

    XCTAssertEqual(outline.numberOfRows, 1 + 3 + 1)
    let folderRow = outlineController.row(for: folder)
    XCTAssertEqual(folderRow, 0)
    XCTAssertEqual(try title(outline, row: folderRow), "New Folder")
    for (offset, child) in fresh.enumerated() {
      let row = outlineController.row(for: child.id)
      XCTAssertEqual(row, 1 + offset, "fresh child \(offset) shown under the folder")
      XCTAssertEqual(outline.level(forRow: row), 1)
      XCTAssertEqual(try title(outline, row: row), "New \(offset)")
    }
    for child in oldChildren { XCTAssertLessThan(outlineController.row(for: child), 0, "stale child is gone") }
  }

  private func host(_ controller: SidebarController) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 190, height: 800), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    window.setContentSize(NSSize(width: 190, height: 800))
    controller.view.layoutSubtreeIfNeeded()
    windows.append(window)
  }

  private func title(_ outline: NSOutlineView, row: Int) throws -> String {
    let view = outline.view(atColumn: 0, row: row, makeIfNecessary: true)
    if let tab = view as? SidebarTabCellView { return tab.titleField.stringValue }
    let field = try XCTUnwrap(view?.subviews.compactMap { $0 as? NSTextField }.first, "row \(row) has a title")
    return field.stringValue
  }
}

/// An archive table that always holds the same items; writes are accepted and dropped.
private actor FixedArchiveStore: ArchiveStoring {
  let stored: [ArchivedItem]

  init(items: [ArchivedItem]) { stored = items }

  func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int { items.count }
  func items(matching filter: ArchiveFilter, limit: Int?) async throws -> ArchivePage {
    ArchivePage(items: Array(stored.prefix(limit ?? stored.count)), unreadable: 0)
  }
  func remove(_ ids: [NodeID]) async throws {}
}

/// Returns the queued pages in order (the last one repeats) and records every call.
@MainActor
private final class StubArchiveSource: ArchiveListDataSource {
  enum Call: Equatable {
    case loadPage
    case loadMore
    case refresh
    case restore(UUID)
  }

  var onChange: (@MainActor () -> Void)?
  var canRestore = true
  var restoreSucceeds = true
  var pages: [ArchiveListPage] = []
  private(set) var calls: [Call] = []
  private var served = 0

  func loadPage() async -> ArchiveListPage {
    calls.append(.loadPage)
    return next()
  }

  func loadMore() async -> ArchiveListPage {
    calls.append(.loadMore)
    return next()
  }

  func refresh() async -> ArchiveListPage {
    calls.append(.refresh)
    return next()
  }

  func restore(_ id: UUID) -> Bool {
    calls.append(.restore(id))
    return restoreSucceeds
  }

  private func next() -> ArchiveListPage {
    defer { served += 1 }
    return pages.isEmpty ? ArchiveListPage(rows: [], unreadable: 0, mayHaveMore: false) : pages[min(served, pages.count - 1)]
  }
}
