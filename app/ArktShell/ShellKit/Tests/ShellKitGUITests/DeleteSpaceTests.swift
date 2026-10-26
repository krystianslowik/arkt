import AppKit
import Archive
@testable import CoreBridge
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

  /// The default confirmation is the shared Arkt sheet on the window (decision 1): the Space's swatch, the counts
  /// line, Cancel and a quiet red Delete Space with no key; focus starts on Cancel. While the sheet is open the item
  /// is disabled and a second request opens no second sheet. Cancel keeps the Space, Delete Space removes it.
  func testDefaultConfirmationIsTheSharedSheetOnTheWindow() throws {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    _ = try sidebar.addTab(url: Self.url("p"), title: "P", in: .pinned(work))
    for index in 0..<3 { _ = try sidebar.addTab(url: Self.url("t\(index)"), title: "T", in: .today(work)) }
    let source = ModelSidebarSource(sidebar: sidebar, now: { Self.now })
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    let window = try XCTUnwrap(controller.window)
    window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    var removed: [UUID] = []
    controller.onRemoveSpace = { id in removed.append(id); _ = source.removeSpace(id, at: Self.now) }

    controller.deleteSpace(nil)
    waitUntil("the confirmation sheet") { window.attachedSheet != nil }
    let sheet = try XCTUnwrap(controller.spaceRemovalSheet)
    XCTAssertTrue(window.attachedSheet === sheet.window)
    let view = sheet.view
    XCTAssertEqual(view.titleField.stringValue, "Delete the Space \u{201C}Work\u{201D}?")
    XCTAssertEqual(view.paragraphFields.map(\.stringValue), [
      "Its pinned tabs, folders and Today tabs move to the Archive, where you can restore them.",
      "1 pinned tab, 3 Today tabs",
    ])
    guard case .spaceSwatch? = view.iconView?.icon else { return XCTFail("the Space's swatch is the icon") }
    let delete = view.primaryButton
    let cancel = try XCTUnwrap(view.cancelButton)
    XCTAssertEqual(delete.title, "Delete Space")
    XCTAssertEqual(delete.style, .destructive)
    XCTAssertTrue(delete.hasDestructiveAction)
    XCTAssertEqual(delete.keyEquivalent, "")
    XCTAssertEqual(cancel.keyEquivalent, "")
    XCTAssertEqual(delete.displayedTitleColor, AlertTokens.destructiveText.resolve(delete.archiveFlavor))
    XCTAssertTrue(sheet.window?.firstResponder === cancel, "focus starts on Cancel")
    XCTAssertEqual(view.accessibilityLabel(), "Delete the Space \u{201C}Work\u{201D}?")
    XCTAssertEqual(delete.accessibilityHelp(), "Deletes the Space")
    XCTAssertFalse(controller.validateMenuItem(Self.deleteItem()))
    controller.deleteSpace(nil)
    XCTAssertTrue(window.attachedSheet === sheet.window)
    XCTAssertEqual(window.sheets.count, 1, "no second sheet queued")

    cancel.performClick(nil)
    waitUntil("the sheet closed") { window.attachedSheet == nil }
    XCTAssertTrue(removed.isEmpty)
    XCTAssertNil(controller.spaceRemovalSheet)

    controller.deleteSpace(nil)
    waitUntil("the confirmation sheet again") { window.attachedSheet != nil }
    try XCTUnwrap(controller.spaceRemovalSheet).view.primaryButton.performClick(nil)
    waitUntil("the Space removed") { removed == [work] }
    XCTAssertTrue(controller.isShowingEmptyState)
    controller.close()
  }

  /// A stray Return on the sheet deletes nothing, and Escape answers Cancel (keys sent to the sheet window).
  func testAStrayReturnDeletesNothingAndEscapeCancels() throws {
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
    let sheetWindow = try XCTUnwrap(window.attachedSheet)
    for (characters, code) in [("\r", UInt16(36)), ("\u{3}", UInt16(76))] {     // Return, keypad Enter
      let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: sheetWindow.windowNumber, context: nil,
                                                 characters: characters, charactersIgnoringModifiers: characters,
                                                 isARepeat: false, keyCode: code))
      if !sheetWindow.performKeyEquivalent(with: event) { sheetWindow.sendEvent(event) }
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    XCTAssertTrue(removed.isEmpty, "Return deleted nothing")
    XCTAssertNotNil(source.space(work))
    XCTAssertTrue(window.attachedSheet === sheetWindow, "the sheet is still up")

    sheetWindow.cancelOperation(nil)
    waitUntil("the sheet closed") { window.attachedSheet == nil }
    XCTAssertTrue(removed.isEmpty)
    XCTAssertNotNil(source.space(work))
    controller.close()
  }
}
