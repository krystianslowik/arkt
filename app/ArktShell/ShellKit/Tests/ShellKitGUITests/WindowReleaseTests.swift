import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// A closed window goes away with its controller, and the engine goes with the last object that holds it (#817).
/// Each test builds its objects inside an autorelease pool, closes them the way the app does, lets go of every strong
/// reference, and checks weak references once the pool has drained. A retain cycle keeps them alive and fails here.
@MainActor
final class WindowReleaseTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  /// A weak reference with a name for the failure message.
  private final class Probe {
    weak var object: AnyObject?
    let name: String
    init(_ object: AnyObject, _ name: String) {
      self.object = object
      self.name = name
    }
  }

  private func assertReleased(_ probes: [Probe], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(probes.isEmpty, "the test made no probes", file: file, line: line)
    let alive = probes.filter { $0.object != nil }.map(\.name)
    XCTAssertEqual(alive, [], "still alive after the close", file: file, line: line)
  }

  // MARK: Little Arkt

  @MainActor
  private struct LittleArktFixture {
    let engine: InMemoryEngine
    let set: ShellWindowSet
    let main: ShellWindowController
    let little: LittleArktWindowController
    let id: EngineWindowID

    var probes: [Probe] {
      var probes = [Probe(engine, "engine"), Probe(set, "window set"), Probe(main, "main controller"),
                    Probe(little, "Little Arkt controller"), Probe(little.window, "Little Arkt window"),
                    Probe(little.engineHost, "Little Arkt host")]
      if let window = main.window { probes.append(Probe(window, "main window")) }
      return probes
    }
  }

  /// A main window and a page popup in a Little Arkt window, on an in-memory engine that builds its hosts through the
  /// set, as the app wires a real engine.
  private func makeLittleArkt() throws -> LittleArktFixture {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [weak engine] in engine?.host(of: $0) })
    set.littleArktReduceMotion = { true }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    let main = set.openWindow()
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: try XCTUnwrap(URL(string: "arkt-test://page/SignIn")), isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    return LittleArktFixture(engine: engine, set: set, main: main, little: little, id: id)
  }

  /// The main window closes as Close Window does; the engine closes what is left, as it does at quit.
  private func closeTheRest(_ fixture: LittleArktFixture) {
    fixture.main.close()
    for id in fixture.engine.windowIDs { fixture.engine.closeWindow(id) }
  }

  func testALittleArktWindowTheUserClosedIsReleasedWithItsEngine() throws {
    var probes: [Probe] = []
    try autoreleasepool {
      let fixture = try makeLittleArkt()
      probes = fixture.probes
      fixture.little.window.performClose(nil)
      waitUntil("the Little Arkt window closed") { fixture.little.isClosed && fixture.set.littleArkts.isEmpty }
      XCTAssertFalse(fixture.engine.windowIDs.contains(fixture.id))
      closeTheRest(fixture)
    }
    assertReleased(probes)
  }

  func testALittleArktWindowItsPageClosedIsReleasedWithItsEngine() throws {
    var probes: [Probe] = []
    try autoreleasepool {
      let fixture = try makeLittleArkt()
      probes = fixture.probes
      fixture.engine.closeWindow(fixture.id)                // window.close() in the page
      waitUntil("the faded window closed") { fixture.little.isClosed && fixture.set.littleArkts.isEmpty }
      closeTheRest(fixture)
    }
    assertReleased(probes)
  }

  // MARK: Downloads

  func testAClosedDownloadsLibraryIsReleasedWithItsCenterAndEngine() throws {
    var probes: [Probe] = []
    let folder = FileManager.default.temporaryDirectory.appending(path: "arkt-release-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try autoreleasepool {
      let engine = InMemoryEngine(downloadFolder: folder)
      let center = try XCTUnwrap(DownloadsCenter(engine: engine, settings: AppSettings.ephemeral()))
      center.announce = { _ in }
      let browser = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
      center.primaryWindow = { [weak browser] in browser }
      center.attach(to: browser)
      browser.showWindow(nil)
      center.showLibrary()
      let library = center.library
      let window = try XCTUnwrap(library.window)
      probes = [Probe(engine, "engine"), Probe(center, "center"), Probe(center.model, "model"),
                Probe(library, "Library controller"), Probe(window, "Library window"),
                Probe(browser, "browser controller")]
      window.close()
      browser.close()
      for id in engine.windowIDs { engine.closeWindow(id) }
    }
    assertReleased(probes)
  }
}
