import AppKit
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Component integration at the real window set, not AppSession, app launch or engine-requested windows.
@MainActor
final class RoutedOpenFromOtherAppTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets {
      let regular = set.controllers
      let little = set.littleArkts
      // Hiding a window does not end its engine host, display links or close animation.
      if let engine = set.engine as? InMemoryEngine {
        for id in engine.windowIDs { engine.engineEndWindow(id, reason: .appQuit) }
        XCTAssertTrue(engine.windowIDs.isEmpty, "the fixture must release every engine window")
      } else {
        XCTFail("routed-open fixtures require their controlled InMemoryEngine")
      }
      for controller in regular { controller.window?.close() }
      for controller in little {
        controller.finishMotion()
        controller.window.close()
      }
      XCTAssertTrue(set.controllers.isEmpty, "regular fixture windows must close")
      XCTAssertTrue(set.littleArkts.isEmpty, "Little Arkt fixture windows must finish closing")
    }
    sets = []
  }

  private func fixture(_ routing: LinkRouting) async throws
    -> (ShellWindowSet, InMemoryEngine, LinkRoutingSettingsModel, UUID, UUID) {
    var world = try EngineWorld.make()
    let second = world.sidebar.addSpace(title: "Other")
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source)
    sets.append(set) // Register cleanup before creating any windows.
    set.littleArktReduceMotion = { true }
    let model = LinkRoutingSettingsModel(state: RoutingOpenStore(routing))
    await model.load()
    XCTAssertTrue(model.isLoaded)
    // Proposed seam: nil leaves the historical #446 path intact. The model maps Core's result to a plain value.
    set.externalLinkDestination = { url in model.destination(for: url) }
    return (set, engine, model, world.space, second)
  }

  private func urls(_ set: ShellWindowSet, in space: UUID) -> [String] {
    set.sidebar.children(of: .today(space)).compactMap {
      if case .tab(_, let url, _)? = set.sidebar.node($0) { return url.absoluteString }
      return nil
    }
  }

  private func littleURLs(_ set: ShellWindowSet, _ engine: InMemoryEngine) -> [URL] {
    set.littleArkts.compactMap { little in
      little.engineWindow.flatMap { engine.activeTab(in: $0) }.flatMap { engine.snapshot(of: $0)?.url }
    }
  }

  // Exercises the Shell resolver/dispatch boundary; it does not exercise App or OS forwarding.
  func testRoutedActivityPreservesUnansweredRecoveryThroughCancelledQuit() async throws {
    for restore in [false, true] {
      var world = try EngineWorld.make()
      let destination = world.sidebar.addSpace(title: "Destination")
      let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
      let old = ShellRecoveryPage(title: "Prior", url: URL(string: "https://example.invalid/prior")!,
                                  kind: .littleArkt)
      let records = RoutedRecoveryPages([old])
      let engine = InMemoryEngine()
      engine.crashedSession.simulateCrashedExit()
      let set = ShellWindowSet(engine: engine, sidebar: source, recoveryPageSource: records)
      sets.append(set)
      set.littleArktReduceMotion = { true }
      let model = LinkRoutingSettingsModel(state: RoutingOpenStore(LinkRouting(routes: [])))
      await model.load()
      XCTAssertTrue(model.isLoaded)
      set.externalLinkDestination = { model.destination(for: $0) }
      let host = set.openWindow()
      let privateWindow = set.openWindow(opensFirstTab: false)
      privateWindow.makeIncognito()
      let privatePages = privateWindow.privatePageOrder.pages
      NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: privateWindow.window)
      set.beginSessionRecovery(engine.crashedSession)
      let panel = try XCTUnwrap(host.rootView.subviews.compactMap { $0 as? RestorePagesView }.first)
      let spaceURL = URL(string: "https://example.invalid/routed-space")!
      let littleURL = URL(string: "https://example.invalid/routed-little")!
      model.setDefaultDestination(.space(destination))
      model.appendRoute(.init(condition: .matches(littleURL.absoluteString), destination: .littleArkt))
      XCTAssertEqual(set.openFromOtherApp([spaceURL, littleURL]), [.dispatched(spaceURL), .dispatched(littleURL)])
      XCTAssertEqual(host.currentSpace, destination)
      XCTAssertEqual(urls(set, in: destination), [spaceURL.absoluteString])
      XCTAssertEqual(privateWindow.privatePageOrder.pages, privatePages)
      XCTAssertEqual(littleURLs(set, engine), [littleURL])
      XCTAssertEqual(records.pages, [old])
      XCTAssertEqual(engine.crashedSession.dismissals, 0)
      records.isSuspended = true
      set.finishSessionRecovery(cleanQuit: true)
      let tab = try XCTUnwrap(set.littleArkts.first?.shownTab)
      let changed = URL(string: "https://example.invalid/changed")!
      engine.navigate(tab, to: changed)
      XCTAssertEqual(records.pages, [old])
      records.isSuspended = false
      set.finishSessionRecovery(cleanQuit: false)
      XCTAssertEqual(records.pages, [old])
      if restore { panel.restorePressed() } else { panel.dismissPressed() }
      XCTAssertEqual(engine.crashedSession.dismissals, 1)
      XCTAssertEqual(Set(records.pages.map(\.url)), Set(restore ? [changed, old.url] : [changed]))
      XCTAssertTrue(records.pages.allSatisfy { $0.kind == .littleArkt })
    }
  }

  func testEmptyRecoveryAcknowledgmentRecordsAlreadyRoutedLittleArkt() async throws {
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let orphan = ShellRecoveryPage(title: "Orphan", url: URL(string: "https://example.invalid/orphan")!,
                                   kind: .peek, sourceNode: UUID())
    let records = RoutedRecoveryPages([orphan])
    let engine = InMemoryEngine()
    engine.crashedSession.simulateCrashedExit()
    let set = ShellWindowSet(engine: engine, sidebar: source, recoveryPageSource: records)
    sets.append(set)
    set.littleArktReduceMotion = { true }
    let model = LinkRoutingSettingsModel(state: RoutingOpenStore(LinkRouting(routes: [])))
    await model.load()
    XCTAssertTrue(model.isLoaded)
    set.externalLinkDestination = { model.destination(for: $0) }
    model.setDefaultDestination(.littleArkt)
    let target = URL(string: "https://example.invalid/routed-before-notice")!
    XCTAssertEqual(set.openFromOtherApp([target]), [.dispatched(target)])
    XCTAssertEqual(records.pages, [orphan])
    set.beginSessionRecovery(engine.crashedSession)
    XCTAssertEqual(engine.crashedSession.dismissals, 1)
    XCTAssertEqual(records.pages.map(\.url), [target])
    XCTAssertEqual(records.pages.first?.kind, .littleArkt)
  }

  func testConfiguredLittleArktOpensARealWindowWithoutAddingToday() async throws {
    let (set, engine, _, first, second) = try await fixture(LinkRouting(routes: []))
    let regular = set.openWindow()
    let before = urls(set, in: first)
    let current = regular.currentNode
    let target = URL(string: "https://example.com/little")!
    set.openFromOtherApp([target])
    XCTAssertEqual(littleURLs(set, engine), [target])
    XCTAssertEqual(urls(set, in: first), before)
    XCTAssertTrue(urls(set, in: second).isEmpty)
    XCTAssertEqual(regular.currentNode, current)
  }

  func testExplicitSpaceCreatesAndSelectsTodayOnlyThere() async throws {
    let (set, _, model, first, second) = try await fixture(LinkRouting(routes: []))
    model.setDefaultDestination(.space(second))
    let regular = set.openWindow()
    let before = urls(set, in: first)
    let target = URL(string: "https://example.com/space")!
    set.openFromOtherApp([target])
    XCTAssertEqual(regular.currentSpace, second)
    XCTAssertEqual(urls(set, in: second).first, target.absoluteString)
    XCTAssertEqual(urls(set, in: first), before)
    XCTAssertEqual(regular.currentNode, set.sidebar.children(of: .today(second)).first)
    XCTAssertTrue(set.littleArkts.isEmpty)
  }

  func testMostRecentSpaceUsesRegularWindowWhenPrivateWindowIsPrimary() async throws {
    for incognito in [false, true] {
      let (set, _, model, first, second) = try await fixture(LinkRouting(routes: []))
      model.setDefaultDestination(.mostRecentSpace)
      let regular = set.openWindow()
      regular.sidebarController.showSpace(second)
      let privateWindow = set.openWindow(opensFirstTab: false)
      if incognito { privateWindow.makeIncognito() } else { privateWindow.makeBlank() }
      NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: privateWindow.window)
      XCTAssertTrue(set.primary === privateWindow)
      let pages = privateWindow.privatePageOrder.pages
      let before = urls(set, in: first)
      let target = URL(string: incognito ? "https://example.com/incognito" : "https://example.com/blank")!
      set.openFromOtherApp([target])
      XCTAssertEqual(privateWindow.privatePageOrder.pages, pages)
      XCTAssertEqual(regular.currentSpace, second)
      XCTAssertEqual(urls(set, in: second).first, target.absoluteString)
      XCTAssertEqual(regular.currentNode, set.sidebar.children(of: .today(second)).first)
      XCTAssertEqual(urls(set, in: first), before)
      XCTAssertTrue(set.littleArkts.isEmpty)
    }
  }

  func testOrderedRealModelMatchesAndReversalChooseDifferentDestinations() async throws {
    let (set, engine, model, first, second) = try await fixture(LinkRouting(routes: []))
    let regular = set.openWindow()
    let before = urls(set, in: first)
    let target = URL(string: "https://example.com/Path?q=One")!
    let absent = LinkRouting.Route(condition: .contains("absent"), destination: .mostRecentSpace)
    let contains = LinkRouting.Route(condition: .contains("EXAMPLE.COM/path"), destination: .space(second))
    let exact = LinkRouting.Route(condition: .matches(target.absoluteString), destination: .littleArkt)
    model.appendRoute(absent)
    model.appendRoute(contains)
    model.appendRoute(exact)
    set.openFromOtherApp([target])
    XCTAssertEqual(urls(set, in: second), [target.absoluteString])
    XCTAssertEqual(regular.currentSpace, second)
    XCTAssertTrue(set.littleArkts.isEmpty)
    model.replaceRoute(at: 1, with: exact)
    model.replaceRoute(at: 2, with: contains)
    set.openFromOtherApp([target])
    XCTAssertEqual(littleURLs(set, engine), [target])
    XCTAssertEqual(urls(set, in: second), [target.absoluteString])
    XCTAssertEqual(urls(set, in: first), before)
  }

  func testAllPrivateWindowsCreateRegularHostAndMissingDestinationsAreReported() async throws {
    let (set, _, model, first, _) = try await fixture(LinkRouting(routes: []))
    model.setDefaultDestination(.mostRecentSpace)
    let privateWindow = set.openWindow(opensFirstTab: false)
    privateWindow.makeIncognito()
    let pages = privateWindow.privatePageOrder.pages
    let target = URL(string: "https://example.com/regular")!
    XCTAssertEqual(set.openFromOtherApp([target]), [.dispatched(target)])
    XCTAssertEqual(privateWindow.privatePageOrder.pages, pages)
    XCTAssertEqual(urls(set, in: first).first, target.absoluteString)
    XCTAssertTrue(set.controllers.contains { !$0.isPrivateWindow })

    let missing = UUID()
    model.setDefaultDestination(.space(missing))
    XCTAssertEqual(set.openFromOtherApp([target]), [.missingSpace(target, missing)])
    set.externalLinkDestination = { _ in nil }
    XCTAssertEqual(set.openFromOtherApp([target]), [.unresolved(target)])
    XCTAssertEqual(urls(set, in: first).filter { $0 == target.absoluteString }.count, 1)
  }

  func testBatchPreservesQualifyingURLsAndSkipsOtherSchemes() async throws {
    let (set, engine, model, first, second) = try await fixture(LinkRouting(routes: []))
    model.setDefaultDestination(.space(second))
    let regular = set.openWindow()
    let before = urls(set, in: first)
    let web = URL(string: "HTTPS://example.com/upper")!
    let file = URL(fileURLWithPath: "/tmp/arkt-routing-synthetic.pdf")
    let little = URL(string: "https://example.com/little-batch")!
    model.appendRoute(.init(condition: .matches(little.absoluteString), destination: .littleArkt))
    set.openFromOtherApp([web, URL(string: "mailto:person@example.com")!, little, file])
    XCTAssertEqual(urls(set, in: second), [file.absoluteString, web.absoluteString])
    XCTAssertEqual(regular.currentNode, set.sidebar.children(of: .today(second)).first)
    XCTAssertEqual(urls(set, in: first), before)
    XCTAssertEqual(littleURLs(set, engine), [little])
  }

  func testRefusedProfileSelectionDoesNotDispatchIntoTheUnchangedSpace() throws {
    for mostRecent in [false, true] {
      var sidebar = Sidebar()
      let otherProfile = sidebar.addSpace(title: "Other profile", profile: "other")
      let local = sidebar.addSpace(title: "Regular", profile: "default")
      let source = ModelSidebarSource(sidebar: sidebar, now: { EngineWorld.now })
      let set = ShellWindowSet(engine: InMemoryEngine(), sidebar: source)
      sets.append(set)
      if !mostRecent {
        let regular = set.openWindow(opensFirstTab: false)
        XCTAssertEqual(regular.currentSpace, local)
      }
      // The cold Most Recent path chooses the first Space, which is also in the other profile.
      set.externalLinkDestination = { _ in mostRecent ? .mostRecentSpace : .space(otherProfile) }
      let before = urls(set, in: local)
      let target = URL(string: "https://example.com/profile-selection")!
      let result = set.openFromOtherApp([target])
      if result == [.dispatched(target)] {
        // A future profile-capable host can dispatch, but it must actually reach the requested Space.
        XCTAssertTrue(set.controllers.contains { $0.currentSpace == otherProfile })
        XCTAssertEqual(urls(set, in: otherProfile), [target.absoluteString])
      } else {
        XCTAssertEqual(result, [.unresolved(target)])
        XCTAssertTrue(urls(set, in: otherProfile).isEmpty)
      }
      XCTAssertEqual(urls(set, in: local), before, "a refused Space selection must not open in the old Space")
      XCTAssertTrue(set.littleArkts.isEmpty)
    }
  }
}

private actor RoutingOpenStore: LinkRoutingSettingsStoring {
  private var value: LinkRouting
  init(_ value: LinkRouting) { self.value = value }
  func loadLinkRouting() async throws -> LinkRouting { value }
  func updateLinkRouting(at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void) async throws
    -> LinkRouting {
    change(&value)
    return value
  }
}

@MainActor
private final class RoutedRecoveryPages: RecoveryPageSource {
  var isSuspended = false
  private var stored: [ShellRecoveryPage]
  var pages: [ShellRecoveryPage] {
    get { stored }
    set { if !isSuspended { stored = newValue } }
  }
  init(_ pages: [ShellRecoveryPage]) { stored = pages }
}
