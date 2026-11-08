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
      for window in set.controllers { window.window?.orderOut(nil) }
      for little in set.littleArkts { little.window.orderOut(nil) }
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
