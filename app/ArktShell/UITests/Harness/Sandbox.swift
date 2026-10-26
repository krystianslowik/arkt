import Foundation
import XCTest

/// A throwaway home for one app launch: data folder, Arc folder and defaults suite, all under
/// `<NSTemporaryDirectory()>/arkt-uitest-<UUID>/`. Nothing it hands out can point at the user's real data
/// (plan, Rules: "Never touch real data").
final class Sandbox {
  /// Prefix of every suite name a sandbox creates; `remove()` refuses to clear any other domain.
  static let suitePrefix = "dev.arkt.uitest."

  let root: URL
  let dataDirectory: URL
  let arcDirectory: URL
  let defaultsSuite: String
  /// `ARKT_AUTOSAVE_DELAY_MS` for the launch, when a test needs a fixed debounce.
  var autosaveDelayMilliseconds: Int?
  /// The first run (onboarding) is shown on a new profile. Off by default, so tests start from the empty state;
  /// `OnboardingTests` turn it on.
  var showsOnboarding = false

  init() throws {
    let id = UUID().uuidString
    let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    root = temp.appendingPathComponent("arkt-uitest-\(id)", isDirectory: true)
    dataDirectory = root.appendingPathComponent("data", isDirectory: true)
    // Always set, even when no import is wanted: an empty folder keeps the app's Arc existence check off the real
    // Arc folder.
    arcDirectory = root.appendingPathComponent("arc", isDirectory: true)
    defaultsSuite = Self.suitePrefix + id

    for url in [dataDirectory, arcDirectory] {
      try Self.checkSafe(url.path, root: root.path, under: temp.path)
    }
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: arcDirectory, withIntermediateDirectories: true)
  }

  /// The strict UI-test environment (`ARKT_UITEST=1` plus every override it requires).
  var environment: [String: String] {
    var env = [
      "ARKT_UITEST": "1",
      "ARKT_DATA_DIR": dataDirectory.path,
      "ARKT_ARC_DIR": arcDirectory.path,
      "ARKT_DEFAULTS_SUITE": defaultsSuite,
    ]
    if let autosaveDelayMilliseconds {
      env["ARKT_AUTOSAVE_DELAY_MS"] = String(autosaveDelayMilliseconds)
    }
    if !showsOnboarding { env["ARKT_SKIP_ONBOARDING"] = "1" }
    // Never the real default browser: the first run's check answers "not default" and Make default asks nobody.
    env["ARKT_DEFAULT_BROWSER"] = "notDefault"
    return env
  }

  /// Every path in `environment`, for tests that assert the app was given nothing else.
  var handedOutPaths: [String] { [dataDirectory.path, arcDirectory.path] }

  /// Renders the synthetic Arc fixtures into `arcDirectory` with `server.base`, launches the app's import phase,
  /// waits for `.notRunning` (30 s times the scale), asserts `data/Arkt.sqlite` exists, and returns the rendered
  /// fixture checksums (Task U6, #171).
  @MainActor
  @discardableResult
  func seedFromArcFixture(server: FixtureServer) throws -> ArcFixture.Checksums {
    let checksums = try ArcFixture.render(into: arcDirectory, base: server.base)
    let app = try ArktUITestCase.makeApplication()
    var env = environment
    env["ARKT_SMOKE"] = "import"
    app.launchEnvironment = env
    app.launchArguments = ArktUITestCase.launchArguments
    app.launch()
    guard Waits.until("seed import to finish", timeout: 30, { app.state == .notRunning }) else {
      if app.state != .notRunning { app.terminate() }
      throw HarnessError("seed import did not finish within \(Waits.scaled(30)) s")
    }
    let database = dataDirectory.appendingPathComponent("Arkt.sqlite")
    guard FileManager.default.fileExists(atPath: database.path) else {
      throw HarnessError("seed import did not create \(database.path)")
    }
    return checksums
  }

  /// Deletes the folder and the defaults suite. Safe to call more than once.
  func remove() {
    try? FileManager.default.removeItem(at: root)
    guard defaultsSuite.hasPrefix(Self.suitePrefix) else { return }
    UserDefaults().removePersistentDomain(forName: defaultsSuite)
  }

  /// Names and sizes of everything under the sandbox, for failure attachments. No file contents.
  func listing() -> String {
    guard let enumerator = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return "(no sandbox)" }
    var lines: [String] = []
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
      let relative = String(url.path.dropFirst(root.path.count))
      if values?.isDirectory == true {
        lines.append("\(relative)/")
      } else {
        lines.append("\(relative) \(values?.fileSize ?? 0)")
      }
    }
    return lines.sorted().joined(separator: "\n")
  }

  // MARK: - Path guard

  struct UnsafePath: Error, CustomStringConvertible {
    let path: String
    var description: String { "sandbox refused unsafe path \(path)" }
  }

  /// A handed-out sandbox path must sit under the sandbox `root` (with a trailing `/`), `root` must sit under `temp`
  /// (with a trailing `/`), and neither may look like the real Arkt or Arc folders (#199). The check is case
  /// sensitive: the sandbox's own `arc` folder is lowercase, and a UUID is uppercase hex.
  static func checkSafe(_ path: String, root: String, under temp: String = NSTemporaryDirectory()) throws {
    let tempPrefix = temp.hasSuffix("/") ? temp : temp + "/"
    let rootPrefix = root.hasSuffix("/") ? root : root + "/"
    guard !temp.isEmpty,
          !root.isEmpty,
          root.hasPrefix(tempPrefix),
          path.hasPrefix(rootPrefix),
          !path.contains("/Library/Application Support/"),
          !path.contains("Arc") else { throw UnsafePath(path: path) }
  }
}
