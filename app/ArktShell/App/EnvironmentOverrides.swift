#if DEBUG || ARKT_SMOKE_BUILD
import Foundation

/// Parsing of the environment overrides that Debug and Profile builds (`ARKT_SMOKE_BUILD`) accept. Release builds
/// compile none of it. Pure: it reads only the dictionary it is given, so ShellKit's `ShellUITests` compile this file
/// through a symlink and test it (the app target has no test target). `AppEnvironment` passes the process
/// environment.
struct EnvironmentOverrides {
  static let dataDirectoryKey = "ARKT_DATA_DIR"
  static let arcDirectoryKey = "ARKT_ARC_DIR"
  static let defaultsSuiteKey = "ARKT_DEFAULTS_SUITE"
  static let autosaveDelayKey = "ARKT_AUTOSAVE_DELAY_MS"
  /// Accepted `ARKT_AUTOSAVE_DELAY_MS` values; anything else keeps the default delay.
  static let autosaveDelayMilliseconds = 0...600_000

  let environment: [String: String]

  /// The `ARKT_DEFAULTS_SUITE` name; nil when unset or empty. Check it with `isUsableSuiteName` before use.
  var defaultsSuiteName: String? { value(Self.defaultsSuiteKey) }

  /// `ARKT_AUTOSAVE_DELAY_MS` as a delay; nil when unset, not an integer or out of range.
  var autosaveDelay: Duration? {
    guard let text = value(Self.autosaveDelayKey), let milliseconds = Int(text),
          Self.autosaveDelayMilliseconds.contains(milliseconds) else { return nil }
    return .milliseconds(milliseconds)
  }

  /// False for a name that would resolve to the real defaults: the app's own domain or the global domain, compared
  /// without regard to case as the defaults system does. Also false for a name that reads as a path: one with a
  /// slash (an absolute one is opened as a plist file) or a leading dot (a hidden file, `.` or `..`).
  static func isUsableSuiteName(_ name: String, bundleIdentifier: String?) -> Bool {
    guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return false }
    let reserved = [bundleIdentifier, UserDefaults.globalDomain].compactMap { $0 }
    return !reserved.contains { name.caseInsensitiveCompare($0) == .orderedSame }
  }

  private func value(_ key: String) -> String? {
    guard let value = environment[key], !value.isEmpty else { return nil }
    return value
  }

  #if DEBUG
  static let uiTestKey = "ARKT_UITEST"

  /// Strict UI-test mode (`ARKT_UITEST=1`): the app refuses to start unless every override is set.
  var isUITest: Bool { environment[Self.uiTestKey] == "1" }

  /// The names of the overrides strict mode needs that are unset, empty or (for the suite) unusable, in key order.
  func missingUITestOverrides(bundleIdentifier: String?) -> [String] {
    var missing: [String] = []
    if value(Self.dataDirectoryKey) == nil { missing.append(Self.dataDirectoryKey) }
    if value(Self.arcDirectoryKey) == nil { missing.append(Self.arcDirectoryKey) }
    if !(defaultsSuiteName.map { Self.isUsableSuiteName($0, bundleIdentifier: bundleIdentifier) } ?? false) {
      missing.append(Self.defaultsSuiteKey)
    }
    return missing
  }
  #endif
}
#endif
