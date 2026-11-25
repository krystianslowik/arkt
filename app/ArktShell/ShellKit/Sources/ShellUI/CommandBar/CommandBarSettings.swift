import Foundation

/// Command bar settings: "Include search engine suggestions" (#562, spec settings table), whether typed text may go to
/// the search engine for suggestions. Stored in the app's user defaults under Arc's key name (`searchSuggestEnabled`),
/// so it survives relaunch; `ephemeral()` keeps it in memory (tests, the scripted smoke), like `ToolbarSetting`.
@MainActor
public final class CommandBarSettings {
  /// Arc's "Include search engine suggestions" key (spec settings table: per-profile there, app-level here).
  public static let searchSuggestionsDefaultsKey = "searchSuggestEnabled"
  /// The default engine's display name (Track C open question 5: a Google placeholder). Nonisolated so the
  /// non-actor results builder reads it.
  nonisolated public static let searchEngineName = "Google"

  private let defaults: UserDefaults?

  /// Whether the Search group lists the engine's suggestions below the Search for row. Defaults to true.
  public private(set) var searchSuggestionsEnabled: Bool

  /// Reads the stored value (suggestions on when never set) and writes every change back.
  public convenience init(defaults: UserDefaults) { self.init(store: defaults) }

  private init(store: UserDefaults?) {
    defaults = store
    searchSuggestionsEnabled = store?.object(forKey: Self.searchSuggestionsDefaultsKey) as? Bool ?? true
  }

  public func setSearchSuggestionsEnabled(_ enabled: Bool) {
    guard enabled != searchSuggestionsEnabled else { return }
    searchSuggestionsEnabled = enabled
    defaults?.set(enabled, forKey: Self.searchSuggestionsDefaultsKey)
  }

  /// Suggestions on, and never touches user defaults.
  public static func ephemeral() -> CommandBarSettings { CommandBarSettings(store: nil) }
}
