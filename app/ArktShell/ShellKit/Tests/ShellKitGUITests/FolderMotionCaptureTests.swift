import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The folder motion captures its moving rows once per change of the outline's rows (#603). Two changes of the rows
/// must also start a new capture (#673): a `reloadItem(_:reloadChildren: true)`, and a row-count change the outline's
/// overrides never see. Frames are driven by hand on the test's own clock.
@MainActor
final class FolderMotionCaptureTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private var controller: ShellWindowController!
  private var clock: CFTimeInterval = 1000
  private var other: UUID!
  private var folder: UUID!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let url = { (path: String) in URL(string: "https://example.com/\(path)")! }
    other = try sidebar.addFolder(title: "Other", in: .pinned(space))
    for index in 0..<3 { _ = try sidebar.addTab(url: url("o\(index)"), title: "O\(index)", in: .folder(other)) }
    folder = try sidebar.addFolder(title: "Folder", in: .pinned(space))
    for index in 0..<6 { _ = try sidebar.addTab(url: url("f\(index)"), title: "F\(index)", in: .folder(folder)) }
    let today = try (0..<4).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let source = ModelSidebarSource(sidebar: sidebar, now: { Self.now })
    controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 900), display: false)
    controller.showWindow(nil)
    controller.activate(node: today[0])
    let motion = try outline().folderMotion
    motion.now = { [unowned self] in self.clock }
    motion.drivesFramesItself = false
    motion.reduceMotion = { false }
    controller.window?.contentView?.layoutSubtreeIfNeeded()
  }

  override func tearDown() async throws {
    controller?.close()
    controller = nil
  }

  private func outline() throws -> SidebarOutlineController {
    try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
  }

  private func item(for id: UUID) throws -> Any {
    let outline = try outline()
    return try XCTUnwrap(outline.outlineView.item(atRow: outline.row(for: id)))
  }

  /// Starts closing `folder` on the spring and presents its first frame; returns the captures so far.
  private func startClose() throws -> Int {
    let outline = try outline()
    XCTAssertTrue(outline.isFolderOpen(folder))
    outline.toggleFolder(folder, animated: true)
    nextFrame()
    XCTAssertTrue(outline.folderMotion.isRunning, "the close runs on frames")
    let captures = outline.motionCaptureCount
    nextFrame()
    XCTAssertEqual(outline.motionCaptureCount, captures, "a frame with no change of the rows captures nothing")
    return captures
  }

  private func nextFrame() {
    clock += 1.0 / 120
    (try? outline())?.folderMotion.presentFrame()
  }

  /// `reloadItem(_:reloadChildren: true)` lists the item's children again, so it moves `rowsGeneration`. A reload of
  /// the item alone (the title and favicon updates, #297) does not, and neither reloads the whole outline.
  func testReloadingChildrenMovesTheRowsGeneration() throws {
    let view = try outline().outlineView
    let item = try item(for: other)
    let reloads = view.reloadDataCount

    let start = view.rowsGeneration
    view.reloadItem(item)
    view.reloadItem(item, reloadChildren: false)
    XCTAssertEqual(view.rowsGeneration, start, "a reload of the item alone keeps the rows")

    view.reloadItem(item, reloadChildren: true)
    XCTAssertNotEqual(view.rowsGeneration, start, "a reload of the children moves the rows generation")
    XCTAssertEqual(view.reloadDataCount, reloads, "no reload of the whole outline")
  }

  /// A `reloadItem(_:reloadChildren: true)` in the middle of a close makes the next frame capture the rows again,
  /// even when the row count stays the same.
  func testReloadingChildrenMidMotionCapturesTheRowsAgain() throws {
    let outline = try outline()
    let captures = try startClose()
    let rows = outline.outlineView.numberOfRows

    outline.outlineView.reloadItem(try item(for: other), reloadChildren: true)
    XCTAssertEqual(outline.outlineView.numberOfRows, rows, "the same rows: only the generation tells them apart")
    nextFrame()
    XCTAssertEqual(outline.motionCaptureCount, captures + 1, "the frame after the reload captured the rows again")
  }

  /// A row-count change that skips `SidebarOutlineView`'s overrides (AppKit's own collapse, as its internals would
  /// run it) leaves `rowsGeneration` where it was; the row count in the capture's key still starts a new capture.
  func testARowCountChangeTheOverridesMissCapturesTheRowsAgain() throws {
    let outline = try outline()
    let captures = try startClose()
    let view = outline.outlineView
    let generation = view.rowsGeneration
    let rows = view.numberOfRows

    try collapseSkippingOverrides(try item(for: other), in: view)
    XCTAssertEqual(view.rowsGeneration, generation, "the overrides did not see the collapse")
    XCTAssertLessThan(view.numberOfRows, rows, "the other folder's rows left")
    nextFrame()
    XCTAssertEqual(outline.motionCaptureCount, captures + 1, "the frame after the row-count change captured again")
  }

  /// Runs `NSOutlineView`'s own `collapseItem(_:collapseChildren:)` on `view`, past the subclass's override.
  private func collapseSkippingOverrides(_ item: Any, in view: NSOutlineView) throws {
    typealias Collapse = @convention(c) (AnyObject, Selector, Any?, Bool) -> Void
    let selector = #selector(NSOutlineView.collapseItem(_:collapseChildren:))
    let method = try XCTUnwrap(class_getInstanceMethod(NSOutlineView.self, selector))
    let collapse = unsafeBitCast(method_getImplementation(method), to: Collapse.self)
    collapse(view, selector, item, false)
  }
}
