import CoreBridge
import Foundation
import Persistence

/// Where Arkt keeps its data, where Arc's data would be and which defaults hold app settings. Debug, Profile
/// (`ARKT_SMOKE_BUILD`) and Engine (`ARKT_CHROMIUM_ENGINE`, development only) builds accept overrides
/// (`EnvironmentOverrides`) so development, smoke and UI test runs never touch the real folders or defaults.
enum AppEnvironment {
  /// Arkt's data folder. `@concurrent`: `applicationSupport()` may create the folder, and the main thread never
  /// waits on disk.
  @concurrent
  static func databaseLocation() async throws -> DatabaseLocation {
    #if DEBUG || ARKT_SMOKE_BUILD || ARKT_CHROMIUM_ENGINE
    if let path = ProcessInfo.processInfo.environment["ARKT_DATA_DIR"] {
      return DatabaseLocation(directory: URL(fileURLWithPath: path, isDirectory: true))
    }
    #endif
    return try .applicationSupport()
  }

  /// `<data folder>/Favicons` (decision 8). `@concurrent`: the store resolves symlinks on the disk. nil only if the
  /// folder were inside Arc's (never for Arkt's own data folder); favicons are then not persisted.
  @concurrent
  static func faviconStore(in location: DatabaseLocation) async -> FaviconStore? {
    try? FaviconStore(directory: location.directory.appendingPathComponent("Favicons", isDirectory: true))
  }

  /// Arc's data folder; read only after the user asks for an import. Debug and Profile builds may point it at a
  /// fixture copy.
  static var arcDirectory: URL {
    #if DEBUG || ARKT_SMOKE_BUILD || ARKT_CHROMIUM_ENGINE
    if let path = ProcessInfo.processInfo.environment["ARKT_ARC_DIR"] {
      return URL(fileURLWithPath: path, isDirectory: true)
    }
    #endif
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
  }

  /// The defaults that hold app-level settings (the Toolbar). Debug and Profile builds use the
  /// `ARKT_DEFAULTS_SUITE` suite when it is set, so a test run never writes the real defaults; a suite name that
  /// would resolve to the real defaults stops the app instead of falling back to them.
  static var userDefaults: UserDefaults {
    #if DEBUG || ARKT_SMOKE_BUILD || ARKT_CHROMIUM_ENGINE
    if let suite = overrides.defaultsSuiteName {
      guard EnvironmentOverrides.isUsableSuiteName(suite, bundleIdentifier: Bundle.main.bundleIdentifier),
            let defaults = UserDefaults(suiteName: suite) else {
        preconditionFailure("unusable \(EnvironmentOverrides.defaultsSuiteKey)")
      }
      return defaults
    }
    #endif
    return .standard
  }

  /// The sidebar autosave debounce. Debug and Profile builds take `ARKT_AUTOSAVE_DELAY_MS` (0 to 600000), so a test
  /// can quit inside the debounce deterministically.
  static var autosaveDelay: Duration {
    #if DEBUG || ARKT_SMOKE_BUILD || ARKT_CHROMIUM_ENGINE
    if let delay = overrides.autosaveDelay { return delay }
    #endif
    return SidebarAutosaver.defaultDelay
  }

  #if DEBUG || ARKT_SMOKE_BUILD || ARKT_CHROMIUM_ENGINE
  private static var overrides: EnvironmentOverrides {
    EnvironmentOverrides(environment: ProcessInfo.processInfo.environment)
  }
  #endif

  #if DEBUG
  /// Strict UI-test mode (`ARKT_UITEST=1`, Debug builds only).
  static var isUITest: Bool { overrides.isUITest }

  /// The overrides strict UI-test mode needs that are missing; the app exits before any disk access when this is not
  /// empty. Key names only.
  static func missingUITestOverrides() -> [String] {
    overrides.missingUITestOverrides(bundleIdentifier: Bundle.main.bundleIdentifier)
  }

  /// The end-to-end data smoke phase (E6, Debug builds only), from `ARKT_SMOKE`. Separate from the scripted UI smoke
  /// (`-ArktSmoke YES`), which never opens the database.
  static var smokePhase: SmokePhase? {
    ProcessInfo.processInfo.environment["ARKT_SMOKE"].flatMap(SmokePhase.init(rawValue:))
  }

  enum SmokePhase: String {
    /// Imports from `arcDirectory` without the summary sheet, prints the counts and quits.
    case `import`
    /// Prints the counts and quits.
    case verify
  }
  #endif
}
