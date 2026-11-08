import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// #116: exercises the existing window-set boundary with real in-memory engine transitions.
@MainActor
final class MultiWindowLifecycleGateTests: XCTestCase {
  private func fixture() throws -> (ShellWindowSet, InMemoryEngine, WindowSessionStore, ModelSidebarSource) {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let name = "MultiWindowLifecycleGateTests.\(UUID())"
    addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    let store = WindowSessionStore(defaults: defaults)
    var model = SidebarModel.Sidebar()
    let personal = model.addSpace(title: "Personal")
    let work = model.addSpace(title: "Work")
    let url = URL(string: "https://example.test/")!
    for space in [personal, work] {
      _ = try model.addTab(url: url, title: "Pinned 1", in: .pinned(space))
      _ = try model.addTab(url: url, title: "Pinned 2", in: .pinned(space))
      _ = try model.addFolder(title: "Folder", in: .pinned(space))
      _ = try model.addTab(url: url, title: "Today 1", in: .today(space))
      _ = try model.addTab(url: url, title: "Today 2", in: .today(space))
    }
    let sidebar = ModelSidebarSource(sidebar: model)
    let engine = InMemoryEngine()
    let set = ShellWindowSet(engine: engine, sidebar: sidebar, sessionStore: store)
    addTeardownBlock { @MainActor in
      for controller in set.controllers { controller.window?.orderOut(nil) }
    }
    return (set, engine, store, sidebar)
  }

  func testQuitCapturesBothWindowsBeforeEngineTeardownAndKeepsThem() throws {
    let (set, engine, store, sidebar) = try fixture()
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    let personal = sidebar.spaceOrder[0], work = sidebar.spaceOrder[1]
    let a = sidebar.children(of: .today(personal))[1]
    let b = sidebar.children(of: .today(work))[0]
    let c = sidebar.children(of: .pinned(personal))[1]
    let d = sidebar.children(of: .pinned(work))[1]
    first.activate(node: b)
    first.activate(node: a)
    second.activate(node: c)
    second.activate(node: d)
    first.window?.setFrame(CGRect(x: 80, y: 100, width: 720, height: 520), display: false)
    second.window?.setFrame(CGRect(x: 140, y: 160, width: 800, height: 600), display: false)
    let frameA = try XCTUnwrap(first.window?.frame)
    let frameB = try XCTUnwrap(second.window?.frame)
    // Ordinary updates may already have saved the live windows; make quit capture distinguishable.
    store.saveWindows([])
    XCTAssertEqual(store.loadWindows(), [])
    set.saveSessionsForTermination()
    let captured = try XCTUnwrap(store.loadWindows())
    XCTAssertEqual(captured.count, 2)
    guard captured.count == 2 else { return }
    XCTAssertEqual(captured.map(\.currentTab), [a, d])
    XCTAssertEqual(captured.map(\.space), [personal, work])
    XCTAssertEqual(captured.map(\.frame), [frameA, frameB])
    XCTAssertEqual(captured[0].selectedTabs, [personal: a, work: b])
    XCTAssertEqual(captured[1].selectedTabs, [personal: c, work: d])
    let windowIDs = try [first, second].map { try XCTUnwrap($0.engineWindow) }
    for id in windowIDs { engine.engineEndWindow(id, reason: .appQuit) }
    XCTAssertEqual(store.loadWindows(), captured, "teardown must not overwrite the quit snapshot")
  }

  func testClosingOneWindowRemovesOnlyThatWindow() throws {
    let (set, _, store, sidebar) = try fixture()
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    let firstTab = sidebar.children(of: .today(sidebar.spaceOrder[0]))[1]
    let secondTab = sidebar.children(of: .today(sidebar.spaceOrder[1]))[0]
    first.activate(node: firstTab)
    second.activate(node: secondTab)
    second.window?.performClose(nil)
    let saved = try XCTUnwrap(store.loadWindows())
    XCTAssertEqual(saved.map(\.currentTab), [firstTab])
  }

  func testEmptySpaceChangesPersistImmediatelyWithoutAnotherCapture() throws {
    let (set, _, store, sidebar) = try fixture()
    let personal = sidebar.spaceOrder[0], work = sidebar.spaceOrder[1]
    let empty = try sidebar.addSpace(title: "Empty")
    let otherEmpty = try sidebar.addSpace(title: "Other Empty")
    let firstNode = sidebar.children(of: .today(personal))[1]
    let secondNode = sidebar.children(of: .today(work))[0]
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    first.activate(node: firstNode)
    second.activate(node: secondNode)
    let before = try XCTUnwrap(store.loadWindows())
    XCTAssertEqual(before.count, 2)
    guard before.count == 2 else { return }
    XCTAssertEqual(before.map(\.space), [personal, work])
    XCTAssertEqual(before.map(\.currentTab), [firstNode, secondNode])

    for space in [empty, otherEmpty] {
      first.sidebarController.showSpace(space)
      XCTAssertEqual(first.currentSpace, space)
      XCTAssertNil(first.currentNode)
      XCTAssertNil(first.currentTab)
      // No forced save, focus transition or termination capture between switching and reading.
      let saved = try XCTUnwrap(store.loadWindows())
      XCTAssertEqual(saved.count, 2)
      guard saved.count == 2 else { return }
      XCTAssertEqual(saved[0].space, space, "the empty Space must replace the previous saved Space immediately")
      XCTAssertNil(saved[0].currentTab, "an empty Space cannot retain the previously shown tab")
      XCTAssertEqual(saved[0].selectedTabs, before[0].selectedTabs, "other Spaces retain their selected tabs")
      XCTAssertEqual(saved[1], before[1], "switching the first window leaves the second window unchanged")
    }
  }

  func testCancelledQuitRefreshesSurvivingWindowsAndResumesWrites() throws {
    let (set, engine, store, sidebar) = try fixture()
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    let heldNode = sidebar.children(of: .today(sidebar.spaceOrder[0]))[1]
    let otherNode = sidebar.children(of: .today(sidebar.spaceOrder[1]))[0]
    first.activate(node: heldNode)
    second.activate(node: otherNode)
    let held = try XCTUnwrap(first.currentTab)
    engine.holdClose(held)
    set.saveSessionsForTermination()
    let frozen = try XCTUnwrap(store.loadWindows())
    XCTAssertEqual(frozen.map(\.currentTab), [heldNode, otherNode])
    second.window?.performClose(nil)
    XCTAssertTrue(second.isClosed)
    first.activate(node: sidebar.children(of: .pinned(sidebar.spaceOrder[0]))[1])
    XCTAssertEqual(store.loadWindows(), frozen, "closing during suspended capture cannot rewrite the quit snapshot")
    first.window?.performClose(nil)
    XCTAssertTrue(engine.answerDialog(held, accept: false))
    XCTAssertEqual(store.loadWindows(), frozen, "the snapshot stays frozen until the app resumes capture")
    set.resumeSessions()
    XCTAssertFalse(first.isClosed)
    let changed = sidebar.children(of: .pinned(sidebar.spaceOrder[0]))[1]
    XCTAssertEqual(try XCTUnwrap(store.loadWindows()).map(\.currentTab), [changed])
    first.activate(node: heldNode)
    XCTAssertEqual(store.loadWindows()?.first?.currentTab, heldNode)
  }

  func testLaunchRestoresOrderedWindowsAndClampsEachDisconnectedFrame() throws {
    let (set, _, store, sidebar) = try fixture()
    let personal = sidebar.spaceOrder[0], work = sidebar.spaceOrder[1]
    let a = sidebar.children(of: .today(personal))[1]
    let b = sidebar.children(of: .today(work))[0]
    let c = sidebar.children(of: .pinned(personal))[1]
    let d = sidebar.children(of: .pinned(work))[1]
    let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
      visibleFrame: CGRect(x: 0, y: 63, width: 1024, height: 674))
    set.screens = { [screen] }
    let disconnected = CGRect(x: 8000, y: 8000, width: 1920, height: 1080)
    let states = [
      WindowSessionState(frame: CGRect(x: 8100, y: 8100, width: 640, height: 430), screenFrame: disconnected,
                         space: personal, currentTab: a, selectedTabs: [personal: a, work: b]),
      WindowSessionState(frame: CGRect(x: 8400, y: 8200, width: 700, height: 450), screenFrame: disconnected,
                         space: work, currentTab: d, selectedTabs: [personal: c, work: d])
    ]
    store.saveWindows(states)
    let windows = set.restoreWindowsAtLaunch()
    XCTAssertEqual(windows.count, 2)
    guard windows.count == 2 else { return }
    XCTAssertEqual(windows.map(\.currentNode), [a, d])
    XCTAssertEqual(windows.map(\.currentSpace), [personal, work])
    for (window, state) in zip(windows, states) {
      let native = try XCTUnwrap(window.window)
      let expected = WindowFramePlacement.restoredFrame(saved: state.frame, savedScreen: state.screenFrame,
                                                         screens: [screen], minSize: native.minSize)
      XCTAssertEqual(native.frame, expected)
    }
    XCTAssertEqual(windows[0].sidebarController.selectedTabs, states[0].selectedTabs)
    XCTAssertEqual(windows[1].sidebarController.selectedTabs, states[1].selectedTabs)
    for (window, space, selected) in [(windows[0], work, b), (windows[1], personal, c),
                                      (windows[0], personal, a), (windows[1], work, d)] {
      // showSpace only positions the page. The dot/keyboard path selects its remembered tab when it settles;
      // Reduce Motion completes that same path synchronously, without a display-link or wall-clock wait.
      window.pager.reduceMotionForTesting = true
      let index = try XCTUnwrap(window.sidebarController.spaces.firstIndex(of: space))
      window.sidebarController.goToSpace(at: index)
      XCTAssertEqual(window.currentSpace, space)
      XCTAssertEqual(window.currentNode, selected)
    }
  }

  func testBlankAndIncognitoIncludingReopenedWindowsStayOutOfCollection() throws {
    let (set, _, store, sidebar) = try fixture()
    let normal = set.openWindow()
    let node = sidebar.children(of: .today(sidebar.spaceOrder[0]))[1]
    normal.activate(node: node)
    for incognito in [false, true] {
      let privateWindow = set.openWindow(opensFirstTab: false)
      if incognito { privateWindow.makeIncognito() } else { privateWindow.makeBlank() }
      privateWindow.openPrivately(URL(string: "https://private.example.test/")!, inNewPage: true)
      XCTAssertFalse(privateWindow.isClosed)
      set.saveSessionsForTermination()
      XCTAssertEqual(try XCTUnwrap(store.loadWindows()).map(\.currentTab), [node],
                     "the original private window must be excluded while still open")
      set.resumeSessions()
      privateWindow.window?.performClose(nil)
      let reopened = try XCTUnwrap(set.reopenClosedPrivateWindow())
      XCTAssertEqual(reopened.sidebarController.presentation, incognito ? .incognito : .blank)
      set.saveSessionsForTermination()
      XCTAssertEqual(try XCTUnwrap(store.loadWindows()).map(\.currentTab), [node])
      set.resumeSessions()
      reopened.window?.performClose(nil)
    }
  }


  func testExplicitEmptyCollectionDoesNotRestoreLegacyWindow() throws {
    let (set, _, store, sidebar) = try fixture()
    let space = sidebar.spaceOrder[1]
    let tab = sidebar.children(of: .today(space))[0]
    store.save(WindowSessionState(frame: CGRect(x: 100, y: 100, width: 700, height: 500),
                                  space: space, currentTab: tab))
    store.saveWindows([])
    XCTAssertTrue(set.restoreWindowsAtLaunch().isEmpty)
    XCTAssertTrue(set.controllers.isEmpty)
  }

  func testAbsentCollectionFallsBackToLegacyWindow() throws {
    let (set, _, store, sidebar) = try fixture()
    let space = sidebar.spaceOrder[1]
    let tab = sidebar.children(of: .today(space))[0]
    store.save(WindowSessionState(frame: CGRect(x: 100, y: 100, width: 700, height: 500),
                                  space: space, currentTab: tab))
    let windows = set.restoreWindowsAtLaunch()
    XCTAssertEqual(windows.count, 1)
    let window = try XCTUnwrap(windows.first)
    XCTAssertEqual(window.currentSpace, space)
    XCTAssertEqual(window.currentNode, tab)
  }

  func testSharedRestoreSettingControlsLaunchWithoutChangingSavedWindows() throws {
    let (set, _, store, sidebar) = try fixture()
    let name = "MultiWindowLifecycleGateTests.Settings.\(UUID())"
    addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    let settings = AppSettings(defaults: defaults)
    let space = sidebar.spaceOrder[1]
    let tab = sidebar.children(of: .today(space))[0]
    let state = WindowSessionState(frame: CGRect(x: 100, y: 100, width: 700, height: 500),
                                   space: space, currentTab: tab)
    store.saveWindows([state])
    XCTAssertTrue(settings.restoreWindowsOnLaunch, "the documented default is restore")
    settings.restoreWindowsOnLaunch = false
    let reread = AppSettings(defaults: defaults)
    XCTAssertFalse(reread.restoreWindowsOnLaunch)
    XCTAssertTrue(set.restoreWindowsAtLaunch(settings: reread).isEmpty)
    XCTAssertTrue(set.controllers.isEmpty)
    XCTAssertEqual(store.loadWindows(), [state])
    reread.restoreWindowsOnLaunch = true
    let nextLaunch = ShellWindowSet(engine: InMemoryEngine(), sidebar: sidebar, sessionStore: store)
    addTeardownBlock { @MainActor in
      for controller in nextLaunch.controllers { controller.window?.orderOut(nil) }
    }
    let windows = nextLaunch.restoreWindowsAtLaunch(settings: AppSettings(defaults: defaults))
    XCTAssertEqual(windows.count, 1)
    XCTAssertEqual(windows.first?.currentNode, tab)
    let identities = nextLaunch.controllers.map(ObjectIdentifier.init)
    _ = nextLaunch.restoreWindowsAtLaunch(settings: AppSettings(defaults: defaults))
    XCTAssertEqual(nextLaunch.controllers.map(ObjectIdentifier.init), identities,
                   "repeated launch forwarding must not create another window")
  }

  func testCompleteDisabledLaunchPreservesCollectionThenResumesOrdinaryWrites() throws {
    let (set, engine, store, sidebar) = try fixture()
    defer {
      for id in engine.windowIDs { engine.engineEndWindow(id, reason: .appQuit) }
      for controller in set.controllers { controller.close() }
    }
    let settings = AppSettings.ephemeral()
    settings.restoreWindowsOnLaunch = false
    let personal = sidebar.spaceOrder[0], work = sidebar.spaceOrder[1]
    let savedTab = sidebar.children(of: .today(work))[0]
    let saved = WindowSessionState(frame: CGRect(x: 100, y: 100, width: 700, height: 500),
                                   space: work, currentTab: savedTab)
    store.save(saved)
    store.saveWindows([saved])
    let windows = set.openWindowsAtLaunch(settings: settings)
    XCTAssertEqual(windows.count, 1)
    let fresh = try XCTUnwrap(windows.first)
    XCTAssertEqual(fresh.currentSpace, personal, "disabled restore must not apply the legacy session either")
    XCTAssertEqual(store.loadWindows(), [saved], "the complete launch includes the default-window fallback")
    let identities = set.controllers.map(ObjectIdentifier.init)
    _ = set.openWindowsAtLaunch(settings: settings)
    XCTAssertEqual(set.controllers.map(ObjectIdentifier.init), identities)
    XCTAssertEqual(store.loadWindows(), [saved])

    let next = sidebar.children(of: .today(personal))[1]
    fresh.activate(node: next)
    XCTAssertEqual(try XCTUnwrap(store.loadWindows()).map(\.currentTab), [next],
                   "startup suppression must end before ordinary window changes")
  }

  func testDeletedSpaceAndTabFallBackPerRestoredWindow() throws {
    let (set, _, store, sidebar) = try fixture()
    let personal = sidebar.spaceOrder[0], work = sidebar.spaceOrder[1]
    let surviving = sidebar.children(of: .today(personal))[1]
    let deleted = sidebar.children(of: .today(work))[0]
    let frame = CGRect(x: 100, y: 100, width: 700, height: 500)
    store.saveWindows([
      WindowSessionState(frame: frame, space: work, currentTab: deleted, selectedTabs: [personal: surviving]),
      WindowSessionState(frame: frame, space: personal, currentTab: UUID(), selectedTabs: [:])
    ])
    sidebar.removeNode(deleted)
    _ = sidebar.removeSpace(work, at: Date(timeIntervalSince1970: 0))
    let windows = set.restoreWindowsAtLaunch()
    XCTAssertEqual(windows.count, 2)
    guard windows.count == 2 else { return }
    XCTAssertEqual(windows[0].currentSpace, personal)
    XCTAssertEqual(windows[0].currentNode, surviving)
    XCTAssertEqual(windows[1].currentSpace, personal)
    XCTAssertEqual(windows[1].currentNode, sidebar.children(of: .pinned(personal)).first)
  }


  func testFolderCollapseIsIndependentAndDeletedFoldersAreIgnored() throws {
    let (set, _, store, sidebar) = try fixture()
    let space = sidebar.spaceOrder[0]
    let folder = sidebar.children(of: .pinned(space))[2]
    let removed = try sidebar.addFolder(title: "Temporary", in: .pinned(space), at: nil)
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    let firstOutline = try XCTUnwrap(first.sidebarController.currentPage?.outlineController)
    let secondOutline = try XCTUnwrap(second.sidebarController.currentPage?.outlineController)
    firstOutline.toggleFolder(folder, animated: false)
    firstOutline.toggleFolder(removed, animated: false)
    XCTAssertTrue(firstOutline.collapsedFolderIDs.contains(folder))
    XCTAssertFalse(secondOutline.collapsedFolderIDs.contains(folder))
    set.saveSessionsForTermination()
    let saved = try XCTUnwrap(store.loadWindows())
    XCTAssertEqual(saved.count, 2)
    guard saved.count == 2 else { return }
    XCTAssertEqual(saved[0].collapsedFolderIDs, [folder, removed])
    XCTAssertFalse(saved[1].collapsedFolderIDs.contains(folder))
    sidebar.removeNode(removed)
    let restored = ShellWindowSet(engine: InMemoryEngine(), sidebar: sidebar, sessionStore: store)
    addTeardownBlock { @MainActor in
      for controller in restored.controllers { controller.window?.orderOut(nil) }
    }
    let windows = restored.restoreWindowsAtLaunch()
    XCTAssertEqual(windows.count, 2)
    guard windows.count == 2 else { return }
    let restoredFirst = try XCTUnwrap(windows[0].sidebarController.currentPage?.outlineController)
    let restoredSecond = try XCTUnwrap(windows[1].sidebarController.currentPage?.outlineController)
    XCTAssertEqual(restoredFirst.collapsedFolderIDs, [folder])
    XCTAssertFalse(restoredSecond.collapsedFolderIDs.contains(folder))
  }

  func testUnreadableCollectionSurvivesLaunchAndAutomaticWrites() throws {
    let (original, _, _, sidebar) = try fixture()
    let name = "MultiWindowLifecycleGateTests.Unreadable.\(UUID())"
    addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    let unreadable = Data("{\"version\":999,\"windows\":[]}".utf8)
    defaults.set(unreadable, forKey: WindowSessionStore.windowsDefaultsKey)
    let set = ShellWindowSet(engine: InMemoryEngine(), sidebar: sidebar,
                             sessionStore: WindowSessionStore(defaults: defaults))
    addTeardownBlock { @MainActor in
      for controller in set.controllers { controller.window?.orderOut(nil) }
    }
    XCTAssertTrue(set.restoreWindowsAtLaunch().isEmpty)
    _ = set.openWindow()
    set.saveSessionsForTermination()
    set.resumeSessions()
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey), unreadable)
    _ = original
  }

}
