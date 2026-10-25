import AppKit
import XCTest

/// Base class of every UI test: resolves the app under test, refuses bundles that do not accept the environment
/// overrides, launches it into a per-test `Sandbox` and cleans up after it (plan, decisions 5 to 7). Main actor, like
/// `XCUIApplication`.
@MainActor
class ArktUITestCase: XCTestCase {
  /// Info.plist key the Debug (and Profile) builds set to `YES`; Release says `NO`.
  static let overridesKey = "ArktEnvironmentOverrides"

  /// Launch arguments of every launch (plan, Rules): no restored windows, English UI.
  static let launchArguments = [
    "-ApplePersistenceIgnoreState", "YES",
    "-NSQuitAlwaysKeepsWindows", "NO",
    "-AppleLanguages", "(en)",
    "-AppleLocale", "en_US",
  ]

  private(set) var sandbox: Sandbox?
  private(set) var app: XCUIApplication?
  /// The loopback server for this test's pages (decision 2); started by `fixtureServer()`, stopped after the test.
  private var server: FixtureServer?

  nonisolated override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
  }

  /// Waits for a condition that needs sidebar outline rows, which are missing from the accessibility tree on the macOS
  /// 26 runner (#269). Only this wait is an expected failure, and non-strict: it passes where the rows are exposed
  /// (macOS 27) and is reported as an expected failure where they are not. Any other failure in the test still fails
  /// it, and the checks after this call still run. Returns whether the condition held, so the caller can skip the
  /// assertions that need the rows.
  @discardableResult
  func waitForOutlineRows(
    _ what: @autoclosure () -> String,
    timeout: TimeInterval? = nil,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @MainActor () -> Bool
  ) -> Bool {
    let options = XCTExpectedFailure.Options()
    options.isStrict = false
    // A failure inside the expected-failure block must not end the test: the checks after it still have to run.
    let previous = continueAfterFailure
    continueAfterFailure = true
    defer { continueAfterFailure = previous }
    let description = what()
    var held = false
    XCTExpectFailure("Outline rows are not in the out-of-process accessibility tree on macOS 26 (#269)", options: options) {
      held = Waits.until(description, timeout: timeout, file: file, line: line, condition)
    }
    return held
  }

  /// The test's loopback page server, started on first use and stopped in tear-down. Tests type only its URLs
  /// (plan, Rules: "No network").
  func fixtureServer() async throws -> FixtureServer {
    if let server { return server }
    let started = try await FixtureServer.start()
    server = started
    addTeardownBlock { @MainActor [self] in
      server?.stop()
      server = nil
    }
    return started
  }

  /// Runs as a tear-down block registered by `launch`. On failure attaches the artifacts; then stops the app if it still runs (a kill, only here) and removes the
  /// sandbox.
  private func cleanUp() {
    let failed = (testRun?.totalFailureCount ?? 0) > 0
    if let app {
      if failed { attachFailureArtifacts(app) }
      if app.state != .notRunning { app.terminate() }
    }
    if let sandbox {
      if failed { attach(name: "sandbox listing", text: sandbox.listing()) }
      sandbox.remove()
    }
    sandbox = nil
    app = nil
  }

  // MARK: - App

  /// The bundle under test: `ARKT_UITEST_APP` (another engine build, decision 6) or the `ArktShell.app` built next
  /// to this runner.
  static func appURL() -> URL {
    if let path = ProcessInfo.processInfo.environment["ARKT_UITEST_APP"], !path.isEmpty {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    return Bundle.main.bundleURL.deletingLastPathComponent()
      .appendingPathComponent("ArktShell.app", isDirectory: true)
  }

  /// A proxy for the app under test, or a failure before anything is launched: the bundle must declare
  /// `ArktEnvironmentOverrides = YES`, and no instance of it may be running already (`launch()` would terminate it).
  static func makeApplication() throws -> XCUIApplication {
    let url = Self.appURL()
    let plistURL = url.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plistURL),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
      throw HarnessError("cannot read \(plistURL.path)")
    }
    guard plist[Self.overridesKey] as? String == "YES" else {
      throw HarnessError("\(url.lastPathComponent) does not declare \(Self.overridesKey) = YES; refusing to launch")
    }
    if let bundleID = plist["CFBundleIdentifier"] as? String {
      let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      guard running.isEmpty else {
        let pids = running.map { String($0.processIdentifier) }.joined(separator: ", ")
        throw HarnessError("\(bundleID) is already running (pid \(pids)); quit it before running the UI tests")
      }
    }
    return XCUIApplication(url: url)
  }

  func makeApp() throws -> XCUIApplication {
    try Self.makeApplication()
  }

  /// Environment keys owned by `Sandbox` that `extraEnv` may never override (#199).
  static let reservedEnvironmentKeys: Set<String> = [
    "ARKT_UITEST",
    "ARKT_DATA_DIR",
    "ARKT_ARC_DIR",
    "ARKT_DEFAULTS_SUITE",
  ]

  /// Merges `extraEnv` into `sandbox.environment`, refusing any key that `Sandbox` owns or already sets (#199).
  static func mergedEnvironment(sandbox: Sandbox, extraEnv: [String: String]) throws -> [String: String] {
    let base = sandbox.environment
    let forbidden = reservedEnvironmentKeys.union(base.keys)
    let collisions = extraEnv.keys.filter { forbidden.contains($0) }.sorted()
    guard collisions.isEmpty else {
      throw HarnessError("extraEnv cannot override sandbox keys: \(collisions.joined(separator: ", "))")
    }
    return base.merging(extraEnv) { current, _ in current }
  }

  /// Launches the app into `sandbox` and waits for its window.
  @discardableResult
  func launch(_ sandbox: Sandbox, extraEnv: [String: String] = [:]) throws -> XCUIApplication {
    let environment = try Self.mergedEnvironment(sandbox: sandbox, extraEnv: extraEnv)
    // One sandbox per test; a relaunch (quit, then launch again) reuses it.
    if let current = self.sandbox, current !== sandbox {
      throw HarnessError("a test launches into one sandbox only")
    }
    if self.sandbox == nil {
      addTeardownBlock { @MainActor [self] in cleanUp() }
    }
    self.sandbox = sandbox
    let app = try makeApp()
    self.app = app
    app.launchEnvironment = environment
    app.launchArguments = Self.launchArguments
    app.launch()
    waitFor(shellWindow(of: app))
    return app
  }

  /// The browser window (`AXID.Shell.window`, U4a #167 / #199).
  func shellWindow(of app: XCUIApplication) -> XCUIElement {
    app.windows[AXID.Shell.window]
  }

  /// Quits the way a user does (Cmd-Q, so `applicationShouldTerminate` flushes) and waits until the app has exited.
  /// The key goes only to the app under test: it is activated first and must be frontmost before the key is typed.
  func quit(_ app: XCUIApplication) {
    app.activate()
    guard waitFor(app, .runningForeground) else { return }
    app.typeKey("q", modifierFlags: .command)
    waitFor(app, .notRunning)
  }

  // MARK: - Failure artifacts

  /// The window only, never the whole screen (decision 7), the accessibility tree and nothing else.
  private func attachFailureArtifacts(_ app: XCUIApplication) {
    let window = shellWindow(of: app)
    if app.state != .notRunning, window.exists {
      let shot = XCTAttachment(screenshot: window.screenshot())
      shot.name = "window"
      shot.lifetime = .keepAlways
      add(shot)
    }
    if app.state != .notRunning {
      attach(name: "accessibility tree", text: app.debugDescription)
    }
  }

  private func attach(name: String, text: String) {
    let attachment = XCTAttachment(string: text)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

/// A harness precondition that failed before or around a launch.
struct HarnessError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
