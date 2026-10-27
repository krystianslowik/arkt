#if DEBUG || ARKT_SMOKE_BUILD || ARKT_TEST_SWITCHES
import Foundation

/// Parsing of the environment overrides that Debug, Profile (`ARKT_SMOKE_BUILD`) and Engine (`ARKT_TEST_SWITCHES`)
/// builds accept. Release and Distribution builds compile none of it. Pure: it reads only the dictionary it is given, so ShellKit's
/// `ShellUITests` compile this file through a symlink and test it (the app target has no test target).
/// `AppEnvironment` passes the process environment.
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
  static let skipOnboardingKey = "ARKT_SKIP_ONBOARDING"
  static let defaultBrowserKey = "ARKT_DEFAULT_BROWSER"
  static let appearanceKey = "ARKT_APPEARANCE"

  /// A pinned app appearance (`ARKT_APPEARANCE=light|dark`), for window screenshots in both appearances without
  /// changing the system setting; nil follows the system.
  enum Appearance: Equatable { case light, dark }

  var appearance: Appearance? {
    switch value(Self.appearanceKey) {
    case "light": .light
    case "dark": .dark
    default: nil
    }
  }

  /// The first run is not shown (`ARKT_SKIP_ONBOARDING=1`): UI tests that start from the empty state.
  var skipsOnboarding: Bool { environment[Self.skipOnboardingKey] == "1" }

  /// What the default-browser check answers instead of asking macOS.
  enum DefaultBrowser: Equatable { case isDefault, notDefault }

  /// `ARKT_DEFAULT_BROWSER=default|notDefault`; in strict UI-test mode `notDefault` when unset, so a test run never
  /// changes the real default browser. Nil: the real check and the real system prompt.
  var defaultBrowser: DefaultBrowser? {
    switch value(Self.defaultBrowserKey) {
    case "default": .isDefault
    case "notDefault": .notDefault
    default: isUITest ? .notDefault : nil
    }
  }

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
