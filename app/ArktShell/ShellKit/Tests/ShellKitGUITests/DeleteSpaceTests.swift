import AppKit
import Archive
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Delete Space (#206, decision on #86): the window asks first, then hands the Space to `onRemoveSpace`, which the app
/// wires to `ArchiveCoordinator.removeSpace` (its pinned and Today items go to the Archive). Removing the last Space
/// shows the empty state.
@MainActor
final class DeleteSpaceTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let controller: ShellWindowController
    var prompts: [SpaceRemovalPrompt] = []
    /// The answer the confirmation gives; nil keeps it pending in `pendingAnswer`.
    var answer: Bool? = true
    var pendingAnswer: (@MainActor (Bool) -> Void)?
    var removed: [UUID] = []
    var archived: [ArchivedItem] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { DeleteSpaceTests.now })
      self.source = source
      controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.onRemoveSpace = { [unowned self] id in
        removed.append(id)
        archived += source.removeSpace(id, at: DeleteSpaceTests.now)
      }
      controller.confirmSpaceRemoval = { [unowned self] prompt, answer in
        prompts.append(prompt)
        if let given = self.answer { answer(given) } else { pendingAnswer = answer }
      }
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func deleteItem() -> NSMenuItem {
    NSMenuItem(title: "Delete Space...", action: #selector(ShellWindowController.deleteSpace(_:)), keyEquivalent: "")
  }

  /// Confirmed: the current Space goes through `onRemoveSpace`, its pinned and Today items are archived, the Space
  /// after it becomes current.
  func testConfirmedDeleteRemovesTheCurrentSpaceAndArchivesItsItems() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let folder = try sidebar.addFolder(title: "F", in: .pinned(work))
    _ = try sidebar.addTab(url: Self.url("p"), title: "P", in: .folder(folder))
    _ = try sidebar.addTab(url: Self.url("t"), title: "T", in: .today(work))
    let other = sidebar.addSpace(title: "Other")
    let harness = Harness(sidebar)
    XCTAssertEqual(harness.controller.currentSpace, work)

    harness.controller.deleteSpace(nil)

    XCTAssertEqual(harness.prompts, [SpaceRemovalPrompt(space: work, title: "Work", hasItems: true)])
    XCTAssertEqual(harness.removed, [work])
    XCTAssertEqual(harness.archived.count, 2, "the pinned folder and the Today tab")
    XCTAssertNil(harness.source.space(work))
    XCTAssertEqual(harness.controller.currentSpace, other)
    harness.controller.close()
  }

  /// Cancelled: nothing is removed.
  func testCancelledDeleteKeepsTheSpace() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(url: Self.url("p"), title: "P", in: .pinned(work))
    let harness = Harness(sidebar)
    harness.answer = false

    harness.controller.deleteSpace(nil)

    XCTAssertEqual(harness.prompts.count, 1)
    XCTAssertTrue(harness.removed.isEmpty)
    XCTAssertNotNil(harness.source.space(work))
    XCTAssertNotNil(harness.source.node(tab))
    harness.controller.close()
  }

  /// An empty Space or one with only Today tabs asks too (#206 plan): the Space itself cannot be restored.
  func testEmptyAndTodayOnlySpacesAskToo() throws {
    var sidebar = SidebarModel.Sidebar()
    let empty = sidebar.addSpace(title: "Empty")
    let today = sidebar.addSpace(title: "Today")
    _ = try sidebar.addTab(url: Self.url("t"), title: "T", in: .today(today))
    let harness = Harness(sidebar)

    harness.controller.deleteSpace(nil)
    harness.controller.deleteSpace(nil)

    XCTAssertEqual(harness.prompts, [SpaceRemovalPrompt(space: empty, title: "Empty", hasItems: false),
                                     SpaceRemovalPrompt(space: today, title: "Today", hasItems: true)])
    XCTAssertEqual(harness.removed, [empty, today])
    harness.controller.close()
  }

  /// The answer removes the Space the prompt named, even when another Space became current while it was open.
  func testTheAnswerRemovesTheSpaceThePromptNamed() throws {
    var sidebar = SidebarModel.Sidebar()
    let first = sidebar.addSpace(title: "First")
    let second = sidebar.addSpace(title: "Second")
    let harness = Harness(sidebar)
    harness.answer = nil

    harness.controller.deleteSpace(nil)
    harness.controller.nextSpace(nil)
    waitUntil("the second Space current") { harness.controller.currentSpace == second }
    let answer = try XCTUnwrap(harness.pendingAnswer)
    answer(true)

    XCTAssertEqual(harness.removed, [first])
    XCTAssertNotNil(harness.source.space(second))
    harness.controller.close()
  }

  /// A Space removed elsewhere while the prompt was open is not removed again.
  func testAnAnswerForASpaceAlreadyGoneDoesNothing() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let harness = Harness(sidebar)
    harness.answer = nil

    harness.controller.deleteSpace(nil)
    _ = harness.source.removeSpace(work, at: Self.now)
    try XCTUnwrap(harness.pendingAnswer)(true)

    XCTAssertTrue(harness.removed.isEmpty)
    harness.controller.close()
  }

  /// Decision on #86: deleting the last Space is allowed and shows the empty state.
  func testDeletingTheLastSpaceShowsTheEmptyState() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    _ = try sidebar.addTab(url: Self.url("t"), title: "T", in: .today(work))
    let harness = Harness(sidebar)
    XCTAssertFalse(harness.controller.isShowingEmptyState)

    harness.controller.deleteSpace(nil)

    XCTAssertEqual(harness.removed, [work])
    XCTAssertTrue(harness.controller.isShowingEmptyState)
    XCTAssertTrue(harness.controller.rootView.card.emptyStateView === harness.controller.emptyState)
    harness.controller.close()
  }

  /// Delete Space is enabled while there is a current Space and the app handles removal.
  func testMenuItemIsEnabledOnlyWithACurrentSpaceAndAHandler() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let harness = Harness(sidebar)
    let item = Self.deleteItem()
    XCTAssertTrue(harness.controller.validateMenuItem(item))

    harness.controller.onRemoveSpace = nil
    XCTAssertFalse(harness.controller.validateMenuItem(item))
    harness.controller.deleteSpace(nil)
    XCTAssertTrue(harness.prompts.isEmpty, "no handler: nothing asks")

    let empty = Harness(SidebarModel.Sidebar())
    XCTAssertFalse(empty.controller.validateMenuItem(item))
    empty.controller.deleteSpace(nil)
    XCTAssertTrue(empty.prompts.isEmpty, "no Space: nothing asks")
    XCTAssertNotNil(harness.source.space(work))
    harness.controller.close()
    empty.controller.close()
  }

  /// The default confirmation is a sheet on the window; its second button (Cancel) keeps the Space and its first
  /// (Delete Space) removes it.
  func testDefaultConfirmationIsASheetOnTheWindow() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    let source = ModelSidebarSource(sidebar: sidebar, now: { Self.now })
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    let window = try XCTUnwrap(controller.window)
    window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    var removed: [UUID] = []
    controller.onRemoveSpace = { id in removed.append(id); _ = source.removeSpace(id, at: Self.now) }

    controller.deleteSpace(nil)
    waitUntil("the confirmation sheet") { window.attachedSheet != nil }
    let alert = try XCTUnwrap(window.attachedSheet)
    XCTAssertTrue(alert.contentView?.firstDescendant(of: NSButton.self) { $0.title == "Delete Space" } != nil)
    window.endSheet(alert, returnCode: .alertSecondButtonReturn)
    waitUntil("the sheet closed") { window.attachedSheet == nil }
    XCTAssertTrue(removed.isEmpty)

    controller.deleteSpace(nil)
    waitUntil("the confirmation sheet again") { window.attachedSheet != nil }
    window.endSheet(try XCTUnwrap(window.attachedSheet), returnCode: .alertFirstButtonReturn)
    waitUntil("the Space removed") { removed == [work] }
    XCTAssertTrue(controller.isShowingEmptyState)
    controller.close()
  }
}

private extension NSView {
  /// The first view of type `T` in this view's subtree, this view included, that `matches`.
  func firstDescendant<T: NSView>(of type: T.Type, where matches: (T) -> Bool) -> T? {
    if let view = self as? T, matches(view) { return view }
    for subview in subviews {
      if let found = subview.firstDescendant(of: type, where: matches) { return found }
    }
    return nil
  }
}
