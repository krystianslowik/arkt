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

  nonisolated override func setUpWithError() throws {
    try super.setUpWithError()
    continueAfterFailure = false
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
  func makeApp() throws -> XCUIApplication {
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

  /// Launches the app into `sandbox` and waits for its window.
  @discardableResult
  func launch(_ sandbox: Sandbox, extraEnv: [String: String] = [:]) throws -> XCUIApplication {
    if self.sandbox == nil {
      addTeardownBlock { @MainActor [self] in cleanUp() }
    }
    self.sandbox = sandbox
    let app = try makeApp()
    self.app = app
    app.launchEnvironment = sandbox.environment.merging(extraEnv) { _, extra in extra }
    app.launchArguments = Self.launchArguments
    app.launch()
    waitFor(shellWindow(of: app))
    return app
  }

  /// The browser window. `shell.window` arrives with the accessibility identifiers (U4a, #167); until then the
  /// app's first window.
  func shellWindow(of app: XCUIApplication) -> XCUIElement {
    app.windows.firstMatch
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
