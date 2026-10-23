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

  init() throws {
    let id = UUID().uuidString
    let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    root = temp.appendingPathComponent("arkt-uitest-\(id)", isDirectory: true)
    dataDirectory = root.appendingPathComponent("data", isDirectory: true)
    // Always set, even when no import is wanted: an empty folder keeps the app's Arc existence check off the real
    // Arc folder.
    arcDirectory = root.appendingPathComponent("arc", isDirectory: true)
    defaultsSuite = Self.suitePrefix + id

    for url in [root, dataDirectory, arcDirectory] {
      try Self.checkSafe(url.path, under: temp.path)
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
    return env
  }

  /// Every path in `environment`, for tests that assert the app was given nothing else.
  var handedOutPaths: [String] { [dataDirectory.path, arcDirectory.path] }

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

  /// A sandbox path must sit under the temp folder and must not look like the real Arkt or Arc folders. The check
  /// is case sensitive: the sandbox's own `arc` folder is lowercase, and a UUID is uppercase hex.
  static func checkSafe(_ path: String, under temp: String) throws {
    guard path.hasPrefix(temp),
          !path.contains("/Library/Application Support/"),
          !path.contains("Arc") else { throw UnsafePath(path: path) }
  }
}
