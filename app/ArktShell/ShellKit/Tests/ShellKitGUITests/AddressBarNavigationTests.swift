import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@_spi(Smoke) @testable import ShellUI

/// #784: what the user types in the address field (Cmd-L) reaches the engine as an address-bar navigation, in a
/// normal and in a private window; every other navigation keeps `navigate`. InMemoryEngine records the calls.
@MainActor
final class AddressBarNavigationTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private func makeSet() -> (ShellWindowSet, InMemoryEngine) {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    _ = try? sidebar.addTab(url: EngineWorld.url("shared"), title: "Shared", in: .today(work))
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return (set, engine)
  }

  /// Cmd-L, `text` typed over the prefilled address, Return.
  private func type(_ text: String, in window: ShellWindowController, engine: InMemoryEngine) {
    window.commandBar.show(.currentTab(window.currentTab.flatMap { engine.snapshot(of: $0)?.url }))
    window.commandBar.setQueryForTesting(text)
    window.commandBar.commit()
  }

  func testTypedAddressNavigatesTheCurrentTabFromTheAddressBar() throws {
    let (set, engine) = makeSet()
    let window = set.openWindow(opensFirstTab: true)
    let tab = try XCTUnwrap(window.currentTab)

    type("next.example", in: window, engine: engine)

    XCTAssertEqual(engine.addressBarNavigations.map(\.tab), [tab])
    XCTAssertEqual(engine.addressBarNavigations.map(\.url.host), ["next.example"])
    XCTAssertEqual(engine.snapshot(of: tab)?.url?.host, "next.example", "it still navigates the tab")
  }

  /// The case the transition changes: the URL on screen typed again (not the untouched prefill, which reloads).
  func testRetypingTheShownURLIsAnAddressBarNavigationToo() throws {
    let (set, engine) = makeSet()
    let window = set.openWindow(opensFirstTab: true)
    let tab = try XCTUnwrap(window.currentTab)
    let shown = try XCTUnwrap(engine.snapshot(of: tab)?.url)

    type(" \(shown.absoluteString)", in: window, engine: engine)

    XCTAssertEqual(engine.addressBarNavigations.map(\.url), [shown])
    XCTAssertEqual(engine.history(of: tab)?.back, [], "the back list does not grow")
  }

  /// Cmd-L, Return on the untouched address reloads (KB-004): no navigation of either kind.
  func testUntouchedPrefillIsNotANavigation() throws {
    let (set, engine) = makeSet()
    let window = set.openWindow(opensFirstTab: true)
    let tab = try XCTUnwrap(window.currentTab)

    window.commandBar.show(.currentTab(engine.snapshot(of: tab)?.url))
    window.commandBar.commit()

    XCTAssertEqual(engine.addressBarNavigations.count, 0)
  }

  func testNewTabFromTheCommandBarIsNotANavigation() throws {
    let (set, engine) = makeSet()
    let window = set.openWindow(opensFirstTab: true)

    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("other.example")
    window.commandBar.commit()

    XCTAssertEqual(engine.addressBarNavigations.count, 0, "Cmd-T creates its tab with the URL")
  }

  func testPrivateWindowAddressNavigatesTheShownPageFromTheAddressBar() throws {
    let (set, engine) = makeSet()
    let window = set.openWindow(opensFirstTab: false)
    window.makeIncognito()
    window.sidebarController.view.privatePages.reduceMotion = { true }
    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("first-page.example")
    window.commandBar.commit()
    let page = try XCTUnwrap(window.currentTab)
    XCTAssertEqual(engine.addressBarNavigations.count, 0, "the first page is created, not navigated")

    type("second-page.example", in: window, engine: engine)

    XCTAssertEqual(engine.addressBarNavigations.map(\.tab), [page])
    XCTAssertEqual(engine.addressBarNavigations.map(\.url.host), ["second-page.example"])
  }

  /// Reopening a closed private page navigates nothing from the address bar.
  func testOpeningAPrivatePageInCodeIsNotAnAddressBarNavigation() throws {
    let (set, engine) = makeSet()
    let window = set.openWindow(opensFirstTab: false)
    window.makeIncognito()
    window.sidebarController.view.privatePages.reduceMotion = { true }
    window.openPrivately(EngineWorld.url("first"))
    window.openPrivately(EngineWorld.url("second"))

    XCTAssertEqual(engine.addressBarNavigations.count, 0)
    XCTAssertEqual(window.currentTab.flatMap { engine.snapshot(of: $0)?.url }, EngineWorld.url("second"))
  }
}
