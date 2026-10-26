import Foundation

/// One-time copy of the app's settings from the old bundle id (`dev.arkt.ArktShell`) to the product id
/// (`dev.arkt.Arkt`, #128). UserDefaults is keyed by bundle id, so without it every setting would reset on upgrade.
///
/// Every key of the old persistent domain is copied into the new one, never over a key the new domain already has.
/// The old domain is only read. The flag is set after a copy; an empty old domain changes nothing, so a later
/// launch can still migrate. Run it before anything reads the settings. Pure over the two suites it is given, so
/// `ShellUITests` compile this file through a symlink and test it (the app target has no test target).
///
/// Not migrated: Saved Application State, the default-browser registration and macOS permission grants; all of
/// them are bound to the bundle id by the system.
struct LegacyDefaultsMigration {
  static let legacyBundleID = "dev.arkt.ArktShell"
  static let flagKey = "migratedFromLegacyBundleID"

  /// Defaults that hold the old domain and the domain's name.
  let legacy: UserDefaults
  let legacyDomain: String
  /// Defaults that receive the keys and the new domain's name.
  let current: UserDefaults
  let currentDomain: String

  /// The migration of the running app: the old domain read through the standard defaults, the new one is its own.
  static func forThisApp(bundleIdentifier: String) -> LegacyDefaultsMigration {
    LegacyDefaultsMigration(legacy: .standard, legacyDomain: legacyBundleID,
                            current: .standard, currentDomain: bundleIdentifier)
  }

  /// Copies the old values when the flag is not set and the old domain has any. Returns whether it copied.
  @discardableResult
  func runIfNeeded() -> Bool {
    guard !current.bool(forKey: Self.flagKey),
          let old = legacy.persistentDomain(forName: legacyDomain), !old.isEmpty else { return false }
    let existing = current.persistentDomain(forName: currentDomain) ?? [:]
    for (key, value) in old where existing[key] == nil {
      current.set(value, forKey: key)
    }
    current.set(true, forKey: Self.flagKey)
    return true
  }
}
