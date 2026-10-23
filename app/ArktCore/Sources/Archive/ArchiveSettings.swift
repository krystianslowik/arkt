import Foundation

/// "Archive tabs after" per profile (BH-081, BH-083, BH-179) and "Archive Little Arcs after:" (BH-137). Defaults are
/// Arc's fresh-install values: 12 hours for tabs (BH-080), 6 hours for Little Arc (BH-137). `never` is a real option
/// (BH-081); whether the picker shows it is the UI's call (BH-082).
/// Decoding is lossy per field and per profile entry: an unknown or malformed value falls back to its default and
/// never fails the group.
public struct ArchiveSettings: Hashable, Sendable, Codable {
  /// The profile name of Arc's Default profile, as `Space.profile` stores it.
  public static let defaultProfile = "default"

  public enum Scope: Hashable, Sendable {
    case thisProfile
    case allProfiles
  }

  /// Only profiles with their own value. Lookups go through `tabThreshold(forProfile:)`.
  public private(set) var tabThresholdsByProfile: [String: AutoArchiveThreshold]
  public var littleArcThreshold: AutoArchiveThreshold

  public init(
    tabThresholdsByProfile: [String: AutoArchiveThreshold] = [:],
    littleArcThreshold: AutoArchiveThreshold = .littleArcDefault
  ) {
    self.tabThresholdsByProfile = tabThresholdsByProfile
    self.littleArcThreshold = littleArcThreshold
  }

  /// The profile's own value, else the Default profile's (new profiles inherit it, BH-083), else 12 hours (BH-080).
  /// Inheritance is resolved here at lookup, so a later change to Default reaches every profile without its own value.
  // PARITY(NEEDS-RUNTIME-CHECK BH-083): Arc may instead copy Default's value when a profile is created; the
  // difference shows only when Default changes afterwards.
  public func tabThreshold(forProfile profile: String) -> AutoArchiveThreshold {
    tabThresholdsByProfile[profile] ?? tabThresholdsByProfile[Self.defaultProfile] ?? .tabsDefault
  }

  /// BH-083: Arc asks "apply to all Profiles or only this Profile". `.allProfiles` sets `profile`, every
  /// `knownProfiles` entry and the Default profile, so profiles created later inherit it too.
  public mutating func setTabThreshold(
    _ threshold: AutoArchiveThreshold, forProfile profile: String, scope: Scope, knownProfiles: [String] = []
  ) {
    switch scope {
    case .thisProfile:
      tabThresholdsByProfile[profile] = threshold
    case .allProfiles:
      for name in Set(knownProfiles + [profile, Self.defaultProfile]) { tabThresholdsByProfile[name] = threshold }
    }
  }

  private enum CodingKeys: String, CodingKey { case tabThresholdsByProfile, littleArcThreshold }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = try? container.decodeIfPresent(
      [String: Lossy<AutoArchiveThreshold>].self, forKey: .tabThresholdsByProfile)
    tabThresholdsByProfile = (raw ?? nil)?.compactMapValues(\.value) ?? [:]
    littleArcThreshold =
      ((try? container.decodeIfPresent(Lossy<AutoArchiveThreshold>.self, forKey: .littleArcThreshold)) ?? nil)?
      .value ?? .littleArcDefault
  }
}

/// Archive bookkeeping, not user-facing settings. Decoding is lossy per field.
public struct ArchiveState: Hashable, Sendable, Codable {
  /// When auto-archive started on this install (Arc: `autoArchiveStartTime` in Arc's archive JSON). Set
  /// once by `resolveAutoArchiveStart(now:)`; it is `AutoArchiveInput.startedAt`, so idle time never counts from
  /// before it.
  public var autoArchiveStartedAt: Date?
  /// BH-089: the education banner is shown once and not again after dismissal.
  public var educationBannerDismissed: Bool

  public init(autoArchiveStartedAt: Date? = nil, educationBannerDismissed: Bool = false) {
    self.autoArchiveStartedAt = autoArchiveStartedAt
    self.educationBannerDismissed = educationBannerDismissed
  }

  /// The auto-archive start, setting it to `now` the first time. The caller persists the state
  /// (`SettingsStore.resolveAutoArchiveStart(now:)` does both in one transaction).
  public mutating func resolveAutoArchiveStart(now: Date) -> Date {
    if let autoArchiveStartedAt { return autoArchiveStartedAt }
    autoArchiveStartedAt = now
    return now
  }

  private enum CodingKeys: String, CodingKey { case autoArchiveStartedAt, educationBannerDismissed }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    autoArchiveStartedAt = (try? container.decodeIfPresent(Date.self, forKey: .autoArchiveStartedAt)) ?? nil
    educationBannerDismissed =
      ((try? container.decodeIfPresent(Bool.self, forKey: .educationBannerDismissed)) ?? nil) ?? false
  }
}

/// A value that decodes to nil instead of throwing when malformed.
private struct Lossy<Value: Decodable>: Decodable {
  let value: Value?

  init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}
