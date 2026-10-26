import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// #331: every sidebar width or visibility change saves that window's state, the session's first window restores it
/// at open, and a new window keeps the defaults.
@MainActor
final class SidebarStatePersistenceTests: XCTestCase {
  private var suiteName = ""

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    suiteName = "SidebarStatePersistenceTests.\(UUID().uuidString)"
  }

  override func tearDown() async throws {
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  private func defaults() throws -> UserDefaults { try XCTUnwrap(UserDefaults(suiteName: suiteName)) }

  private func store() throws -> SidebarWindowStateStore {
    SidebarWindowStateStore(defaults: try defaults())
  }

  private func makeController(_ store: SidebarWindowStateStore) -> ShellWindowController {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample(),
                                           sidebarStateStore: store)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  // MARK: Saving on change

  func testCmdSSavesTheHiddenStateAndBack() throws {
    let store = try store()
    let controller = makeController(store)

    controller.toggleSidebarVisibility(nil)
    XCTAssertEqual(store.state(), SidebarWindowState(width: ShellMetrics.standard.sidebarDefaultWidth,
                                                     isVisible: false))

    controller.toggleSidebarVisibility(nil)
    XCTAssertEqual(try XCTUnwrap(store.state()).isVisible, true)
    controller.close()
  }

  func testTheEdgeDragAndItsHideSaveTheWidth() throws {
    let store = try store()
    let controller = makeController(store)

    controller.rootView.resizeHandle.onWidthChange?(260)
    XCTAssertEqual(store.state(), SidebarWindowState(width: 260, isVisible: true))

    controller.rootView.resizeHandle.onWidthChange?(20)      // fully left: hides (BH-002)
    XCTAssertEqual(try XCTUnwrap(store.state()).isVisible, false)
    controller.close()
  }

  func testTheDoubleClickResetSavesTheDefaultWidth() throws {
    let store = try store()
    let controller = makeController(store)
    controller.rootView.sidebarWidth = 320
    let handle = controller.rootView.resizeHandle
    let window = try XCTUnwrap(controller.window)
    let point = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
    let event = try XCTUnwrap(NSEvent.mouseEvent(
      with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, eventNumber: 0, clickCount: 2, pressure: 1))

    handle.mouseDown(with: event)

    XCTAssertEqual(store.state(), SidebarWindowState(width: ShellMetrics.standard.sidebarDefaultWidth, isVisible: true))
    controller.close()
  }

  func testTheToastActionSavesTheShownState() throws {
    let store = try store()
    let controller = makeController(store)
    controller.toggleSidebarVisibility(nil)
    XCTAssertEqual(try XCTUnwrap(store.state()).isVisible, false)

    controller.open(try XCTUnwrap(URL(string: "https://example.com/")), inNewTab: true)
    controller.toasts.performActionForTesting()               // "Show Sidebar"

    XCTAssertTrue(controller.isSidebarVisible)
    XCTAssertEqual(try XCTUnwrap(store.state()).isVisible, true)
    controller.close()
  }

  // MARK: Adopting at open

  func testAdoptingTheSavedStateRestoresTheWidthAndTheHiddenSidebar() throws {
    let store = try store()
    store.save(width: 260, isVisible: false)
    let controller = makeController(store)

    controller.adoptSavedSidebarState()

    XCTAssertEqual(controller.rootView.sidebarWidth, 260)
    XCTAssertFalse(controller.isSidebarVisible)
    let overlay = controller.rootView.sidebarOverlay
    XCTAssertTrue(overlay.isHidden, "concealed: no reveal until the pointer reaches the edge")
    XCTAssertFalse(overlay.isRevealed)
    XCTAssertEqual(controller.rootView.effectiveSidebarWidth, 0, "the card takes the full width")
    let window = try XCTUnwrap(controller.window as? ShellWindow)
    let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
    XCTAssertTrue(close.isHidden, "no traffic lights over the page")
    controller.close()
  }

  func testAdoptingClampsAnOutOfRangeWidth() throws {
    let store = try store()
    store.save(width: 5000, isVisible: true)
    let controller = makeController(store)

    controller.adoptSavedSidebarState()

    XCTAssertEqual(controller.rootView.sidebarWidth, ShellMetrics.standard.sidebarMaxWidth)
    controller.close()
  }

  func testAWindowWithNothingSavedKeepsTheDefaults() throws {
    let store = try store()
    let controller = makeController(store)

    controller.adoptSavedSidebarState()

    XCTAssertEqual(controller.rootView.sidebarWidth, ShellMetrics.standard.sidebarDefaultWidth)
    XCTAssertTrue(controller.isSidebarVisible)
    controller.close()
  }

  // MARK: First window only

  /// The session's first window adopts the saved state; a later window (New Window) keeps the defaults.
  func testTheFirstWindowOfASessionAdoptsAndALaterOneKeepsTheDefaults() throws {
    let store = try store()
    store.save(width: 300, isVisible: false)
    let engine = InMemoryEngine()
    let set = ShellWindowSet(engine: engine, sidebar: StubSidebar.sample(), sidebarStateStore: store)

    let first = set.openWindow()
    XCTAssertEqual(first.rootView.sidebarWidth, 300, "the launch window restores the saved width")
    XCTAssertFalse(first.isSidebarVisible, "and the saved hidden state")

    let second = set.openWindow()
    XCTAssertEqual(second.rootView.sidebarWidth, ShellMetrics.standard.sidebarDefaultWidth)
    XCTAssertTrue(second.isSidebarVisible, "a new window opens with the defaults")
    first.close()
    second.close()
  }
}
