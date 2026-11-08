import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// #116: an engine-requested regular window arrives before the complete launch decision.
@MainActor
final class QueuedWindowLaunchGateTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private var suites: [String] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { set.closeAllForTesting() }
    sets.removeAll()
    for name in suites { UserDefaults().removePersistentDomain(forName: name) }
    suites.removeAll()
  }

  private func fixture() throws -> (ShellWindowSet, InMemoryEngine, WindowSessionStore, UserDefaults, ModelSidebarSource) {
    let name = "QueuedWindowLaunchGateTests.\(UUID())"
    suites.append(name)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    let store = WindowSessionStore(defaults: defaults)
    var model = SidebarModel.Sidebar()
    for title in ["Personal", "Work"] {
      let space = model.addSpace(title: title)
      _ = try model.addFolder(title: "Folder", in: .pinned(space))
      for tab in ["One", "Two"] {
        _ = try model.addTab(url: URL(string: "https://example.test/\(tab)")!, title: tab, in: .today(space))
      }
    }
    let sidebar = ModelSidebarSource(sidebar: model)
    let engine = InMemoryEngine()
    // Proposed seam: enabled by App before embedderReady can deliver queued requests.
    let set = ShellWindowSet(engine: engine, sidebar: sidebar, sessionStore: store,
                             hostLookup: { [weak engine] in engine?.host(of: $0) },
                             defersLaunchCapture: true)
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("set must outlive engine requests") }
      return set.host(for: request)
    }
    sets.append(set)
    return (set, engine, store, defaults, sidebar)
  }

  private func states(_ sidebar: ModelSidebarSource) -> [WindowSessionState] {
    let a = sidebar.spaceOrder[0], b = sidebar.spaceOrder[1]
    let aTabs = sidebar.children(of: .today(a)), bTabs = sidebar.children(of: .today(b))
    let screen = CGRect(x: 8000, y: 8000, width: 1920, height: 1080)
    return [
      WindowSessionState(frame: CGRect(x: 8100, y: 8100, width: 640, height: 430), screenFrame: screen,
                         space: a, currentTab: aTabs[0], selectedTabs: [a: aTabs[0], b: bTabs[1]],
                         collapsedFolderIDs: [sidebar.children(of: .pinned(a))[0]]),
      WindowSessionState(frame: CGRect(x: 8400, y: 8200, width: 700, height: 450), screenFrame: screen,
                         space: b, currentTab: bTabs[0], selectedTabs: [a: aTabs[1], b: bTabs[0]],
                         collapsedFolderIDs: [sidebar.children(of: .pinned(b))[0]])
    ]
  }

  private func queue(_ engine: InMemoryEngine, in set: ShellWindowSet, offTheRecord: Bool = false) throws -> (ShellWindowController, EngineWindowID, TabID, URL) {
    let url = URL(string: "https://startup.example.test/path")!
    let id = try XCTUnwrap(engine.openEngineWindow(EngineWindowRequest(
      kind: .startupURL, profile: EngineProfileID("default"), initialURL: url, isOffTheRecord: offTheRecord)))
    let controller = try XCTUnwrap(set.controllers.first { $0.engineWindow == id })
    let tab = try XCTUnwrap(engine.tabIDs.first { engine.snapshot(of: $0)?.window == id })
    XCTAssertEqual(engine.snapshot(of: tab)?.url, url)
    XCTAssertEqual(controller.isPrivateWindow, offTheRecord)
    return (controller, id, tab, url)
  }

  func testQueuedRegularWindowPreservesThenRestoresBothSavedWindows() throws {
    let (set, engine, store, defaults, sidebar) = try fixture()
    let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
                                visibleFrame: CGRect(x: 0, y: 63, width: 1024, height: 674))
    set.screens = { [screen] }
    let saved = states(sidebar)
    store.save(saved[1])
    let legacyBytes = try XCTUnwrap(defaults.data(forKey: WindowSessionStore.defaultsKey))
    store.saveWindows(saved)
    let (queued, id, tab, url) = try queue(engine, in: set)
    XCTAssertEqual(store.loadWindows(), saved, "adoption and its startup tab cannot capture before the decision")
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.defaultsKey), legacyBytes)

    let restored = set.openWindowsAtLaunch(settings: .ephemeral(), defaultWindowAllowed: false)
    XCTAssertEqual(restored.count, 2)
    XCTAssertEqual(set.controllers.count, 3, "the queued window plus both saved windows; no fallback")
    XCTAssertEqual(restored.map(\.currentNode), saved.map(\.currentTab))
    XCTAssertEqual(restored.map(\.currentSpace), saved.map(\.space))
    for (window, state) in zip(restored, saved) {
      XCTAssertEqual(window.sidebarController.selectedTabs, state.selectedTabs)
      XCTAssertEqual(window.sidebarController.collapsedFolderIDs, state.collapsedFolderIDs)
      let native = try XCTUnwrap(window.window)
      XCTAssertEqual(native.frame, WindowFramePlacement.restoredFrame(saved: state.frame, savedScreen: state.screenFrame,
                                                                       screens: [screen], minSize: native.minSize))
    }
    XCTAssertTrue(set.controllers.contains { $0 === queued })
    XCTAssertEqual(queued.engineWindow, id)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, url)
    XCTAssertEqual(engine.snapshot(of: tab)?.window, id)
    XCTAssertEqual(set.controllers.map(ObjectIdentifier.init), ([queued] + restored).map(ObjectIdentifier.init))
    let identities = set.controllers.map(ObjectIdentifier.init)
    _ = set.openWindowsAtLaunch(settings: .ephemeral(), defaultWindowAllowed: false)
    XCTAssertEqual(set.controllers.map(ObjectIdentifier.init), identities, "no duplicate restore or adoption")

    let changed = try XCTUnwrap(restored.first)
    let next = sidebar.children(of: .today(sidebar.spaceOrder[0]))[1]
    changed.activate(node: next)
    let persisted = try XCTUnwrap(store.loadWindows())
    XCTAssertEqual(persisted.count, 3, "capture resumes for the queued and both restored regular windows")
    guard persisted.count == 3 else { return }
    XCTAssertEqual(persisted, try set.controllers.map { try XCTUnwrap($0.currentSessionState()) })
    XCTAssertEqual(persisted[1].currentTab, next)
    var changedSelections = saved[0].selectedTabs
    changedSelections[sidebar.spaceOrder[0]] = next
    XCTAssertEqual(persisted[1].selectedTabs, changedSelections)
    XCTAssertEqual(persisted[1].collapsedFolderIDs, saved[0].collapsedFolderIDs)
    XCTAssertEqual(persisted[2].space, saved[1].space)
    XCTAssertEqual(persisted[2].currentTab, saved[1].currentTab)
    XCTAssertEqual(persisted[2].selectedTabs, saved[1].selectedTabs)
    XCTAssertEqual(persisted[2].collapsedFolderIDs, saved[1].collapsedFolderIDs)
    XCTAssertEqual(engine.snapshot(of: tab)?.window, id)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, url)
  }

  func testDisabledRestoreKeepsQueuedWindowAndResumesLaterWrites() throws {
    let (set, engine, store, _, sidebar) = try fixture()
    let saved = states(sidebar)
    store.saveWindows(saved)
    let (queued, id, tab, url) = try queue(engine, in: set)
    XCTAssertEqual(store.loadWindows(), saved)
    let settings = AppSettings.ephemeral()
    settings.restoreWindowsOnLaunch = false
    _ = set.openWindowsAtLaunch(settings: settings, defaultWindowAllowed: false)
    XCTAssertEqual(set.controllers.count, 1)
    XCTAssertTrue(set.controllers.first === queued)
    XCTAssertEqual(queued.engineWindow, id)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, url)
    XCTAssertEqual(store.loadWindows(), saved, "disabled launch must preserve the prior collection through the decision")
    let next = sidebar.children(of: .today(sidebar.spaceOrder[0]))[1]
    queued.activate(node: next)
    XCTAssertEqual(try XCTUnwrap(store.loadWindows()).map(\.currentTab), [next])
  }

  func testQueuedWindowWithExplicitEmptyOrLegacyCollection() throws {
    for explicitEmpty in [true, false] {
      let (set, engine, store, defaults, sidebar) = try fixture()
      let legacy = states(sidebar)[0]
      store.save(legacy)
      let legacyBytes = try XCTUnwrap(defaults.data(forKey: WindowSessionStore.defaultsKey))
      if explicitEmpty { store.saveWindows([]) }
      _ = try queue(engine, in: set)
      XCTAssertEqual(store.loadWindows(), explicitEmpty ? [] : [legacy])
      XCTAssertEqual(defaults.data(forKey: WindowSessionStore.defaultsKey), legacyBytes)
      let restored = set.openWindowsAtLaunch(settings: .ephemeral(), defaultWindowAllowed: false)
      XCTAssertEqual(restored.count, explicitEmpty ? 0 : 1)
      XCTAssertEqual(set.controllers.count, explicitEmpty ? 1 : 2)
      if !explicitEmpty { XCTAssertEqual(restored.first?.currentNode, legacy.currentTab) }
    }
  }

  func testQueuedPrivateOnlyLaunchDoesNotRestoreRegularHistory() throws {
    let (set, engine, store, defaults, sidebar) = try fixture()
    let saved = states(sidebar)
    store.save(saved[1])
    store.saveWindows(saved)
    let collectionBytes = try XCTUnwrap(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey))
    let legacyBytes = try XCTUnwrap(defaults.data(forKey: WindowSessionStore.defaultsKey))
    let (queued, id, tab, url) = try queue(engine, in: set, offTheRecord: true)
    XCTAssertTrue(queued.isPrivateWindow)
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey), collectionBytes)
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.defaultsKey), legacyBytes)

    let restored = set.openWindowsAtLaunch(settings: .ephemeral(), defaultWindowAllowed: false)
    XCTAssertTrue(restored.isEmpty, "an explicit private-only startup must not reveal saved regular history")
    XCTAssertEqual(set.controllers.count, 1)
    XCTAssertTrue(set.controllers.first === queued)
    XCTAssertTrue(queued.isPrivateWindow)
    XCTAssertEqual(queued.engineWindow, id)
    XCTAssertEqual(engine.snapshot(of: tab)?.window, id)
    XCTAssertEqual(engine.snapshot(of: tab)?.url, url)
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey), collectionBytes)
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.defaultsKey), legacyBytes)
    _ = set.openWindowsAtLaunch(settings: .ephemeral(), defaultWindowAllowed: false)
    XCTAssertEqual(set.controllers.count, 1)
    XCTAssertTrue(set.controllers.first === queued)
    XCTAssertEqual(store.loadWindows(), saved)
  }

  func testQueuedWindowDoesNotRewriteUnreadableCollection() throws {
    let (set, engine, _, defaults, sidebar) = try fixture()
    let payload = Data(#"{"version":999,"windows":[]}"#.utf8)
    defaults.set(payload, forKey: WindowSessionStore.windowsDefaultsKey)
    let (queued, _, _, _) = try queue(engine, in: set)
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey), payload)
    _ = set.openWindowsAtLaunch(settings: .ephemeral(), defaultWindowAllowed: false)
    XCTAssertEqual(set.controllers.count, 1)
    queued.activate(node: sidebar.children(of: .today(sidebar.spaceOrder[0]))[1])
    XCTAssertEqual(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey), payload)
  }
}
