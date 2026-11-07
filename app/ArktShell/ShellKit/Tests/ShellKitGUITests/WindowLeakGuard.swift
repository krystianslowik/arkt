import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Fails a GUI test run when a test class finishes with windows it opened still alive (#805).
///
/// XCTest keeps every test case object until the whole run ends. A class that stores its window controller in an
/// instance property and only calls `close()` in `tearDown` keeps one hidden window, with its whole view tree, per
/// test. In a long GUI batch those windows pile up (the pacing batch of #671 reached 101 windows and 27,653 views),
/// and every later test runs in that heavier process. Close the windows and clear the properties that hold them in
/// `tearDown`.
///
/// The guard compares `NSApp.windows` when a class starts with the list when it finishes. A finished class's run takes
/// no more issues, so the failure is recorded on the next test that starts (the next class's first test, or
/// `ZZWindowLeakGuardEndTests` after the last class) and names the class that leaked. `AAWindowLeakGuardTests`
/// installs it and runs first. A full GUI run (`--filter ShellKitGUITests`) selects both; a filter that leaves out
/// `AAWindowLeakGuardTests` runs unguarded.
@MainActor
final class WindowLeakGuard {
  /// Windows the system opens on its own (the text input window); never a test's leak.
  static let systemWindowTypes: Set<String> = ["TUINSWindow"]

  /// Test classes whose windows outlive the test although `tearDown` closes them and clears its properties: something
  /// outside the test still holds them. Each entry names the issue that tracks its fix. Keep it short.
  static let knownLeakyClasses: [String: Int] = [
    "CrashedLittleArktTests": 817,
    "DownloadsWindowTests": 817,
    "LittleArktEscapeStopTests": 817,
  ]

  private let record: (String) -> Void
  private let printsLeaks: Bool
  private var openAtStart: [String: Set<ObjectIdentifier>] = [:]

  /// `record` receives the failure message for a class that left windows open. `printsLeaks` prints a
  /// `window.leak class=... windows=N kinds=[...]` line for every leak, allowed classes included.
  init(printsLeaks: Bool = false, record: @escaping (String) -> Void) {
    self.printsLeaks = printsLeaks
    self.record = record
  }

  func classWillStart(_ name: String, windows: [NSWindow] = NSApp?.windows ?? []) {
    openAtStart[name] = Set(windows.map(ObjectIdentifier.init))
  }

  func classDidFinish(_ name: String, windows: [NSWindow] = NSApp?.windows ?? []) {
    let left = Self.leftOpen(before: openAtStart.removeValue(forKey: name) ?? [], after: windows)
    guard !left.isEmpty else { return }
    if printsLeaks { print("window.leak class=\(name) windows=\(left.count) kinds=[\(Self.kinds(left))]") }
    guard Self.knownLeakyClasses[name] == nil else { return }
    record("\(name) left \(left.count) window(s) open after its last test: \(Self.kinds(left)). "
      + "Close them and clear the properties that hold them in tearDown (#805).")
  }

  /// The windows in `after` that were not open in `before`, except windows the system owns.
  static func leftOpen(before: Set<ObjectIdentifier>, after: [NSWindow]) -> [NSWindow] {
    after.filter { !before.contains(ObjectIdentifier($0)) && !systemWindowTypes.contains("\(type(of: $0))") }
  }

  /// `NSWindow(hidden)x2,NSWindowx1`: windows counted by class and visibility, sorted.
  static func kinds(_ windows: [NSWindow]) -> String {
    var counts: [String: Int] = [:]
    for window in windows { counts["\(type(of: window))\(window.isVisible ? "" : "(hidden)")", default: 0] += 1 }
    return counts.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: ",")
  }
}

/// Feeds each test class's suite to the guard and records its failures on the next test that starts. XCTest calls
/// observers on the main thread.
@MainActor
final class WindowLeakObserver: NSObject, @preconcurrency XCTestObservation {
  private static var installed = false
  private var pending: [String] = []
  private lazy var leakGuard = WindowLeakGuard(printsLeaks: true) { [unowned self] in pending.append($0) }

  /// Adds the observer once per process.
  static func install() {
    guard !installed else { return }
    installed = true
    XCTestObservationCenter.shared.addTestObserver(WindowLeakObserver())
  }

  static var isInstalled: Bool { installed }

  func testSuiteWillStart(_ testSuite: XCTestSuite) {
    if let name = Self.className(of: testSuite) { leakGuard.classWillStart(name) }
  }

  func testSuiteDidFinish(_ testSuite: XCTestSuite) {
    if let name = Self.className(of: testSuite) { leakGuard.classDidFinish(name) }
  }

  func testCaseWillStart(_ testCase: XCTestCase) {
    let messages = pending
    pending.removeAll()
    for message in messages { testCase.record(XCTIssue(type: .assertionFailure, compactDescription: message)) }
  }

  /// The test class name when `suite` holds the tests of one class (`SpacePagerTests`), else nil.
  private static func className(of suite: XCTestSuite) -> String? {
    guard let first = suite.tests.first as? XCTestCase,
          suite.tests.allSatisfy({ type(of: $0) == type(of: first) }) else { return nil }
    return String(describing: type(of: first))
  }
}

extension ShellWindowSet {
  /// Closes the set's windows and, on an `InMemoryEngine`, its engine windows. The engine keeps each window's host and
  /// the host keeps the engine, so without the engine-side close the windows outlive the test (#805).
  func closeAllForTesting() {
    if let engine = engine as? InMemoryEngine {
      for id in engine.windowIDs { engine.closeWindow(id) }
    }
    for little in littleArkts { little.window.close() }
    for controller in controllers { controller.close() }
  }
}
