import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// #116: a relaunch opens the main window where it was, on the Space it showed, with the tab it showed and each
/// Space's selected tab. A Space or tab that is gone falls back to the first-launch behavior; a frame no screen shows
/// is moved onto one. Only the session's first window restores and saves.
@MainActor
final class SessionRestoreTests: XCTestCase {
  private var suiteName = ""

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    suiteName = "SessionRestoreTests.\(UUID().uuidString)"
  }

  override func tearDown() async throws {
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  /// A screen the test machine's screens always contain, so AppKit never constrains the restored frame.
  private static let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 900, height: 620),
                                             visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 600))

  @MainActor private struct World {
    let sidebar = StubSidebar.sample()
    let personal: SpaceID
    let work: SpaceID
    let readingList: NodeID      // Personal, Today
    let teamDocs: NodeID         // Work, Pinned
    let designReview: NodeID     // Work, Today
    let favorite: NodeID

    init() {
      personal = sidebar.spaceOrder[0]
      work = sidebar.spaceOrder[1]
      readingList = sidebar.children(of: .today(personal))[1]
      teamDocs = sidebar.children(of: .pinned(work))[1]
      designReview = sidebar.children(of: .today(work))[0]
      favorite = sidebar.children(of: .favorites(profile: "default"))[0]
    }

    /// What a quit left behind: the user was on Team Docs in Work; Personal had Reading List selected.
    func savedState(frame: CGRect) -> WindowSessionState {
      WindowSessionState(frame: frame, screenFrame: SessionRestoreTests.screen.frame, space: work,
                         currentTab: teamDocs, selectedTabs: [personal: readingList, work: teamDocs])
    }
  }

  private func store() throws -> WindowSessionStore {
    WindowSessionStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
  }

  private func makeSet(_ world: World, store: WindowSessionStore) -> ShellWindowSet {
    let set = ShellWindowSet(engine: InMemoryEngine(), sidebar: world.sidebar, sessionStore: store)
    set.screens = { [Self.screen] }
    return set
  }

  private static let savedFrame = CGRect(x: 40, y: 60, width: 700, height: 500)

  // MARK: Restoring at launch

  func testTheLaunchWindowOpensWhereItWasOnTheSameSpaceAndTab() throws {
    let world = World()
    let store = try store()
    store.save(world.savedState(frame: Self.savedFrame))
    let set = makeSet(world, store: store)

    let window = set.openWindow()
    XCTAssertEqual(window.window?.frame, Self.savedFrame)
    XCTAssertEqual(window.currentSpace, world.work, "the last Space, not the first")
    XCTAssertEqual(window.currentNode, world.teamDocs, "the tab that was current, not the Space's first tab")
    XCTAssertEqual(window.sidebarController.tabToRestore(in: world.personal), world.readingList,
                   "each Space comes back on its own selected tab")
    window.close()
  }

  func testNothingSavedOpensTheFirstTabOfTheFirstSpaceCentered() throws {
    let world = World()
    let set = makeSet(world, store: try store())

    let window = set.openWindow()
    XCTAssertEqual(window.currentSpace, world.personal)
    XCTAssertEqual(window.currentNode, world.sidebar.children(of: .pinned(world.personal)).first)
    XCTAssertEqual(window.window?.frame.size, CGSize(width: 1200, height: 800), "the default size")
    window.close()
  }

  func testAFrameOnNoScreenIsMovedOntoOne() throws {
    let world = World()
    let store = try store()
    store.save(world.savedState(frame: CGRect(x: 5000, y: 4000, width: 700, height: 500)))
    let set = makeSet(world, store: store)

    let window = set.openWindow()
    XCTAssertEqual(window.window?.frame, CGRect(x: 200, y: 100, width: 700, height: 500),
                   "against the corner nearest to where it was, inside the visible area")
    window.close()
  }

  func testADeletedTabFallsBackToTheSpacesFirstTab() throws {
    let world = World()
    let store = try store()
    store.save(world.savedState(frame: Self.savedFrame))
    world.sidebar.removeNode(world.teamDocs)
    let set = makeSet(world, store: store)

    let window = set.openWindow()
    XCTAssertEqual(window.currentSpace, world.work, "the Space is still there")
    XCTAssertEqual(window.currentNode, world.sidebar.children(of: .pinned(world.work)).first)
    XCTAssertEqual(window.sidebarController.tabToRestore(in: world.personal), world.readingList,
                   "the other Space keeps its selected tab")
    window.close()
  }

  func testADeletedSpaceFallsBackToTheFirstSpaceAndItsSelectedTab() throws {
    let world = World()
    let store = try store()
    store.save(world.savedState(frame: Self.savedFrame))
    world.sidebar.removeSpace(world.work)
    let set = makeSet(world, store: store)

    let window = set.openWindow()
    XCTAssertEqual(window.currentSpace, world.personal)
    XCTAssertEqual(window.currentNode, world.readingList, "the first Space's own selected tab")
    XCTAssertEqual(window.window?.frame, Self.savedFrame, "the frame does not depend on the Space")
    window.close()
  }

  func testATabMovedToAnotherSpaceIsNotTakenForTheSavedOne() throws {
    let world = World()
    let store = try store()
    var state = world.savedState(frame: Self.savedFrame)
    state.selectedTabs[world.work] = world.readingList      // a Personal tab recorded for Work (stale)
    state.currentTab = world.readingList
    store.save(state)
    let set = makeSet(world, store: store)

    let window = set.openWindow()
    XCTAssertEqual(window.currentSpace, world.work)
    XCTAssertEqual(window.currentNode, world.sidebar.children(of: .pinned(world.work)).first,
                   "a tab outside the saved Space is ignored")
    window.close()
  }

  func testAFavoriteThatWasCurrentComesBackCurrent() throws {
    let world = World()
    let store = try store()
    var state = world.savedState(frame: Self.savedFrame)
    state.currentTab = world.favorite
    store.save(state)
    let set = makeSet(world, store: store)

    let window = set.openWindow()
    XCTAssertEqual(window.currentNode, world.favorite)
    XCTAssertEqual(window.currentSpace, world.work, "a Favorite belongs to no Space; the last Space stays")
    window.close()
  }

  func testOnlyTheFirstWindowRestoresAndSaves() throws {
    let world = World()
    let store = try store()
    store.save(world.savedState(frame: Self.savedFrame))
    let set = makeSet(world, store: store)

    let first = set.openWindow()
    let second = set.openWindow()
    XCTAssertEqual(second.currentSpace, world.personal, "a New Window opens on the first Space")
    XCTAssertNotEqual(second.window?.frame, Self.savedFrame)

    second.activate(node: world.readingList)
    second.saveSession()
    XCTAssertEqual(store.load(), world.savedState(frame: Self.savedFrame),
                   "a later window does not overwrite the restored window's state")
    first.close()
    second.close()
  }

  // MARK: Saving

  func testSwitchingTabsSavesTheSpaceTheTabAndTheSelections() throws {
    let world = World()
    let store = try store()
    let set = makeSet(world, store: store)
    let window = set.openWindow()

    window.activate(node: world.designReview)
    var saved = try XCTUnwrap(store.load())
    XCTAssertEqual(saved.space, world.work)
    XCTAssertEqual(saved.currentTab, world.designReview)
    XCTAssertEqual(saved.selectedTabs[world.work], world.designReview)
    XCTAssertEqual(saved.frame, window.window?.frame)

    window.activate(node: world.readingList)
    saved = try XCTUnwrap(store.load())
    XCTAssertEqual(saved.space, world.personal)
    XCTAssertEqual(saved.currentTab, world.readingList)
    XCTAssertEqual(saved.selectedTabs[world.work], world.designReview, "Work keeps its selection")
    XCTAssertEqual(saved.selectedTabs[world.personal], world.readingList)
    window.close()
  }

  func testTheFrameIsSavedWhenTheWindowStopsBeingKey() throws {
    let world = World()
    let store = try store()
    let set = makeSet(world, store: store)
    let window = set.openWindow()
    let moved = CGRect(x: 55, y: 70, width: 640, height: 430)

    window.window?.setFrame(moved, display: false)
    window.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
    XCTAssertEqual(store.load()?.frame, moved)
    window.close()
  }

  func testQuitSavesOnceAndTheClosingTabsDoNotOverwriteIt() throws {
    let world = World()
    let store = try store()
    let set = makeSet(world, store: store)
    let window = set.openWindow()
    window.activate(node: world.teamDocs)

    set.saveSessionsForTermination()
    let atQuit = try XCTUnwrap(store.load())
    XCTAssertEqual(atQuit.currentTab, world.teamDocs)

    window.activate(node: world.readingList)      // the engine closing tabs during a quit moves the selection
    XCTAssertEqual(store.load(), atQuit, "the state written at the quit stays")

    set.resumeSessions()                          // the quit was cancelled
    window.activate(node: world.designReview)
    XCTAssertEqual(store.load()?.currentTab, world.designReview)
    window.close()
  }
}
