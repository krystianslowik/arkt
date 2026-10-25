import Foundation

/// Command bar settings (BH-113, spec settings table): whether typed queries may go to the search engine, and
/// whether the user dismissed the privacy notice about it. Stored in the app's user defaults under Arc's key
/// names (`searchSuggestEnabled`, `commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed`), so they
/// survive relaunch; `ephemeral()` keeps them in memory (tests, the scripted smoke), like `ToolbarSetting`.
///
/// The Settings window (#307, waiting on the #305 design review) is the future editor; until it exists the
/// notice's dismiss button is the only writer.
@MainActor
public final class CommandBarSettings {
  /// Arc's "Include search engine suggestions" key (spec settings table: per-profile there, app-level here).
  public static let searchSuggestionsDefaultsKey = "searchSuggestEnabled"
  /// Arc's key for the dismissed privacy notice (BH-113, [S] string and key).
  public static let noticeDismissedDefaultsKey = "commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed"
  /// The default engine's display name (Track C open question 5: a Google placeholder). Nonisolated so the
  /// non-actor results builder reads it.
  nonisolated public static let searchEngineName = "Google"

  private let defaults: UserDefaults?

  /// Whether the bar adds a "Search <engine>" row for typed queries. Defaults to true.
  public private(set) var searchSuggestionsEnabled: Bool
  /// BH-113: once dismissed, the notice never comes back.
  public private(set) var searchSuggestionNoticeDismissed: Bool

  /// Reads the stored values (suggestions on, notice shown when never set) and writes every change back.
  public convenience init(defaults: UserDefaults) { self.init(store: defaults) }

  private init(store: UserDefaults?) {
    defaults = store
    searchSuggestionsEnabled = store?.object(forKey: Self.searchSuggestionsDefaultsKey) as? Bool ?? true
    searchSuggestionNoticeDismissed = store?.bool(forKey: Self.noticeDismissedDefaultsKey) ?? false
  }

  public func setSearchSuggestionsEnabled(_ enabled: Bool) {
    guard enabled != searchSuggestionsEnabled else { return }
    searchSuggestionsEnabled = enabled
    defaults?.set(enabled, forKey: Self.searchSuggestionsDefaultsKey)
  }

  public func dismissSearchSuggestionNotice() {
    guard !searchSuggestionNoticeDismissed else { return }
    searchSuggestionNoticeDismissed = true
    defaults?.set(true, forKey: Self.noticeDismissedDefaultsKey)
  }

  /// Suggestions on, notice not dismissed, and never touches user defaults.
  public static func ephemeral() -> CommandBarSettings { CommandBarSettings(store: nil) }
}
