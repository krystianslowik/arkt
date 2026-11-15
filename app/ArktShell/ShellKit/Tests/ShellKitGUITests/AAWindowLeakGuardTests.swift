import AppKit
import XCTest

/// The window leak guard (#805): a test class that finishes with windows it opened still alive fails the run.
/// The guard covers every class that runs after this one; a full GUI run (`--filter ShellKitGUITests`) selects it.
@MainActor
final class AAWindowLeakGuardTests: XCTestCase {
  /// XCTest runs test classes in name order, so this class runs first and installs the guard for every class after
  /// it. Keep the name sorting first.
  override class func setUp() {
    super.setUp()
    MainActor.assumeIsolated { WindowLeakObserver.install() }
  }

  private var recorded: [String] = []
  private var kept: [NSWindow] = []

  override func setUp() async throws { _ = NSApplication.shared }

  override func tearDown() async throws {
    for window in kept { window.close() }
    kept.removeAll()
    recorded.removeAll()
  }

  private func makeGuard(allowlist: [String: Int] = WindowLeakGuard.knownLeakyClasses) -> WindowLeakGuard {
    WindowLeakGuard(allowlist: allowlist) { [unowned self] in recorded.append($0) }
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
                          backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    return window
  }

  func testTheGuardIsInstalledWhenThisClassIsSelected() {
    XCTAssertTrue(WindowLeakObserver.isInstalled)
  }

  func testAClassThatKeepsAClosedWindowAliveFails() {
    let leakGuard = makeGuard()
    leakGuard.classWillStart("LeakyTests")
    let window = makeWindow()
    window.orderFront(nil)
    window.close()
    kept.append(window)        // a test case property that tearDown did not clear
    leakGuard.classDidFinish("LeakyTests")
    XCTAssertEqual(recorded.count, 1)
    XCTAssertTrue(recorded.first?.hasPrefix("LeakyTests left 1 window(s) open after its last test: NSWindow(hidden)x1")
                  ?? false, "\(recorded)")
  }

  func testAClassThatKeepsAVisibleWindowFails() {
    let leakGuard = makeGuard()
    leakGuard.classWillStart("VisibleTests")
    let window = makeWindow()
    window.orderFront(nil)
    kept.append(window)
    leakGuard.classDidFinish("VisibleTests")
    XCTAssertEqual(recorded.count, 1)
    XCTAssertTrue(recorded.first?.contains("NSWindowx1") ?? false, "\(recorded)")
  }

  func testAClassThatClosesAndReleasesItsWindowsPasses() {
    let leakGuard = makeGuard()
    leakGuard.classWillStart("CleanTests")
    autoreleasepool {
      let window = makeWindow()
      window.orderFront(nil)
      window.close()
    }
    leakGuard.classDidFinish("CleanTests")
    XCTAssertEqual(recorded, [])
  }

  func testWindowsOpenBeforeTheClassStartedAreNotItsLeaks() {
    let earlier = makeWindow()
    earlier.orderFront(nil)
    kept.append(earlier)
    let leakGuard = makeGuard()
    leakGuard.classWillStart("LaterTests")
    leakGuard.classDidFinish("LaterTests")
    XCTAssertEqual(recorded, [])
    XCTAssertEqual(WindowLeakGuard.leftOpen(before: [ObjectIdentifier(earlier)], after: [earlier]), [])
  }

  func testEachClassIsComparedWithItsOwnStart() {
    let leakGuard = makeGuard()
    leakGuard.classWillStart("FirstTests")
    let window = makeWindow()
    kept.append(window)
    leakGuard.classDidFinish("FirstTests")
    leakGuard.classWillStart("SecondTests")
    leakGuard.classDidFinish("SecondTests")
    XCTAssertEqual(recorded.count, 1)
    XCTAssertTrue(recorded.first?.hasPrefix("FirstTests ") ?? false, "\(recorded)")
  }

  func testAKnownLeakyClassIsReportedButDoesNotFail() {
    let name = "FixtureLeakyTests"
    let leakGuard = makeGuard(allowlist: [name: 0])
    leakGuard.classWillStart(name)
    kept.append(makeWindow())
    leakGuard.classDidFinish(name)
    XCTAssertEqual(recorded, [])
  }

  func testAClassWhoseStartWasNotSeenIsNotJudged() {
    let leakGuard = makeGuard()
    kept.append(makeWindow())
    leakGuard.classDidFinish("UnseenTests")
    XCTAssertEqual(recorded, [])
  }

  func testSystemWindowTypesAreAllowed() {
    XCTAssertTrue(WindowLeakGuard.systemWindowTypes.contains("TUINSWindow"))
    XCTAssertFalse(WindowLeakGuard.systemWindowTypes.contains("NSWindow"))
  }

  func testTheKindsListCountsWindowsByClassAndVisibility() {
    let shown = makeWindow()
    shown.orderFront(nil)
    let hidden = makeWindow()
    kept += [shown, hidden]
    XCTAssertEqual(WindowLeakGuard.kinds([shown, hidden, hidden]), "NSWindowx1,NSWindow(hidden)x2")
  }
}
