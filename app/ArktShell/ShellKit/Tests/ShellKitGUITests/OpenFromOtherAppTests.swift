import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// #446: a link or file another app opens with Arkt (`application(_:open:)` forwards the URLs to the session, which
/// forwards them to `ShellWindowSet.openFromOtherApp`). Web and file URLs each become a new Today tab in the primary
/// window; every other scheme is ignored. The set is driven directly: no LaunchServices, no app launch.
@MainActor
final class OpenFromOtherAppTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private func makeSet() throws -> ShellWindowSet {
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: InMemoryEngine(), sidebar: source)
    sets.append(set)
    return set
  }

  /// The URLs of the Today tabs of the window's current Space, top first.
  private func todayURLs(_ controller: ShellWindowController) -> [String] {
    guard let space = controller.currentSpace else { return [] }
    return controller.sidebar.children(of: .today(space)).compactMap { node in
      if case .tab(_, let url, _)? = controller.sidebar.node(node) { return url.absoluteString }
      return nil
    }
  }

  private func url(_ string: String) throws -> URL { try XCTUnwrap(URL(string: string)) }

  // MARK: Web and file URLs

  func testAWebURLBecomesANewTodayTabOnTopInThePrimaryWindow() throws {
    let set = try makeSet()
    let window = set.openWindow()
    let before = todayURLs(window)

    set.openFromOtherApp([try url("https://example.com/from-another-app")])

    XCTAssertEqual(todayURLs(window), ["https://example.com/from-another-app"] + before)
    XCTAssertEqual(set.controllers.count, 1, "no second window")
    let node = try XCTUnwrap(window.currentNode)
    guard case .tab(_, let opened, _)? = window.sidebar.node(node) else { return XCTFail("the new tab is current") }
    XCTAssertEqual(opened.absoluteString, "https://example.com/from-another-app")
  }

  func testPlainHTTPAndAnUppercaseSchemeCountAsWeb() throws {
    let set = try makeSet()
    let window = set.openWindow()
    let before = todayURLs(window)

    set.openFromOtherApp([try url("http://example.com/plain"), try url("HTTPS://example.com/upper")])

    XCTAssertEqual(todayURLs(window).count, before.count + 2)
    XCTAssertTrue(todayURLs(window).contains("http://example.com/plain"))
  }

  func testAFileURLBecomesANewTodayTab() throws {
    let set = try makeSet()
    let window = set.openWindow()
    let before = todayURLs(window)
    let file = URL(fileURLWithPath: "/tmp/arkt-open-from-other-app.html")

    set.openFromOtherApp([file])

    XCTAssertEqual(todayURLs(window), [file.absoluteString] + before)
  }

  func testEachQualifyingURLInOneOpenBecomesItsOwnTab() throws {
    let set = try makeSet()
    let window = set.openWindow()
    let before = todayURLs(window)
    let file = URL(fileURLWithPath: "/tmp/arkt-open-from-other-app.pdf")

    set.openFromOtherApp([try url("https://example.com/one"), try url("mailto:someone@example.com"), file])

    XCTAssertEqual(todayURLs(window), [file.absoluteString, "https://example.com/one"] + before,
                   "two tabs, the mailto link skipped, each new tab on top")
  }

  /// Windows share one sidebar, so the new row is listed in both; only the primary window shows it.
  func testTheLinkIsShownInThePrimaryWindowOnly() throws {
    let set = try makeSet()
    let first = set.openWindow()
    let second = set.openWindow(opensFirstTab: false)
    let primary = try XCTUnwrap(set.primary)
    let other = primary === first ? second : first
    let otherNode = other.currentNode
    let before = todayURLs(primary).count

    set.openFromOtherApp([try url("https://example.com/primary-only")])

    XCTAssertEqual(todayURLs(primary).count, before + 1)
    let shown = try XCTUnwrap(primary.currentNode)
    guard case .tab(_, let opened, _)? = primary.sidebar.node(shown) else { return XCTFail("the new tab is current") }
    XCTAssertEqual(opened.absoluteString, "https://example.com/primary-only")
    XCTAssertEqual(other.currentNode, otherNode, "the other window keeps what it showed")
    XCTAssertEqual(set.controllers.count, 2)
  }

  // MARK: Ignored URLs

  func testOtherSchemesAreIgnored() throws {
    let set = try makeSet()
    let window = set.openWindow()
    let before = todayURLs(window)
    let current = window.currentNode

    set.openFromOtherApp(try [
      "mailto:someone@example.com", "ftp://example.com/file", "javascript:alert(1)", "data:text/html,hello",
      "arkt://settings", "tel:+15555550100", "example.com/no-scheme",
    ].map(url))

    XCTAssertEqual(todayURLs(window), before, "no tab for a non-web, non-file URL")
    XCTAssertEqual(window.currentNode, current)
    XCTAssertEqual(set.controllers.count, 1)
  }

  // MARK: No window open

  /// Current behaviour, kept as it is: with every window closed a link opens a window first and opens its tab there.
  func testWithNoWindowOpenAWindowIsCreatedForTheLink() throws {
    let set = try makeSet()
    XCTAssertTrue(set.controllers.isEmpty)

    set.openFromOtherApp([try url("https://example.com/cold")])

    let window = try XCTUnwrap(set.controllers.first)
    XCTAssertEqual(set.controllers.count, 1)
    XCTAssertTrue(window.window?.isVisible ?? false)
    XCTAssertEqual(todayURLs(window).first, "https://example.com/cold")
  }

  /// Current behaviour, kept as it is: a window comes forward even when no URL qualifies.
  func testWithNoWindowOpenAnIgnoredURLStillBringsAWindowForward() throws {
    let set = try makeSet()

    set.openFromOtherApp([try url("mailto:someone@example.com")])

    let window = try XCTUnwrap(set.controllers.first)
    XCTAssertTrue(window.window?.isVisible ?? false)
    XCTAssertFalse(todayURLs(window).contains("mailto:someone@example.com"))
  }
}
