import Foundation

/// The one-off Copy URL tip (BH-196, #404): after `manualCopyThreshold` manual link copies (the sidebar's Copy Link),
/// a toast suggests Cmd-Shift-C, once. Someone who already uses Copy URL is never shown it. The shown date is stored
/// under Arc's key (`superCopyUpsellLastSeen`, [O]); the copy count and the shortcut flag are Arkt's own keys [I].
/// `ephemeral()` keeps everything in memory (tests, the smoke), like `CommandBarSettings`.
@MainActor
public final class CopyLinkEducation {
  /// Arc's key for when the tip was shown ([O]).
  public static let lastSeenDefaultsKey = "superCopyUpsellLastSeen"
  /// Manual copies counted so far [I].
  public static let manualCopiesDefaultsKey = "copyLinkManualCopyCount"
  /// Copy URL was used, so the tip is not needed [I].
  public static let shortcutUsedDefaultsKey = "copyLinkShortcutUsed"
  /// The manual copy that brings the tip [I]: Arc's threshold is unpublished.
  public static let manualCopyThreshold = 3

  /// The tip. The key must match the Edit menu's Copy URL (`MainMenuKeyEquivalentTests.testTheCopyURLTipNamesTheMenusKey`).
  public static let toast = Toast(text: "Copy links faster by pressing \u{21E7}\u{2318}C",
                                  announcement: "Copy links faster by pressing Shift-Command-C", isPolite: true)

  private let defaults: UserDefaults?
  private let now: () -> Date
  private var manualCopies: Int
  private var shortcutUsed: Bool
  private var lastSeen: Date?

  public convenience init(defaults: UserDefaults, now: @escaping () -> Date = Date.init) {
    self.init(store: defaults, now: now)
  }

  private init(store: UserDefaults?, now: @escaping () -> Date) {
    defaults = store
    self.now = now
    manualCopies = store?.integer(forKey: Self.manualCopiesDefaultsKey) ?? 0
    shortcutUsed = store?.bool(forKey: Self.shortcutUsedDefaultsKey) ?? false
    lastSeen = store?.object(forKey: Self.lastSeenDefaultsKey) as? Date
  }

  /// Counts a manual copy; true when this one should show the tip (it is then marked as seen).
  public func recordManualCopy() -> Bool {
    guard !shortcutUsed, lastSeen == nil else { return false }
    manualCopies += 1
    defaults?.set(manualCopies, forKey: Self.manualCopiesDefaultsKey)
    guard manualCopies >= Self.manualCopyThreshold else { return false }
    let seen = now()
    lastSeen = seen
    defaults?.set(seen, forKey: Self.lastSeenDefaultsKey)
    return true
  }

  /// Copy URL was used: the tip is never shown.
  public func recordShortcutUse() {
    guard !shortcutUsed else { return }
    shortcutUsed = true
    defaults?.set(true, forKey: Self.shortcutUsedDefaultsKey)
  }

  /// Never touches user defaults.
  public static func ephemeral() -> CopyLinkEducation { CopyLinkEducation(store: nil, now: Date.init) }
}
