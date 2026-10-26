import Foundation
import SidebarModel

/// What app code needs from the archive table. `Persistence.ArchiveStore` conforms; CoreBridge tests use fakes.
public protocol ArchiveStoring: Sendable {
  func add(_ items: [ArchivedItem], onConflict policy: ArchiveConflictPolicy) async throws -> Int
  func items(matching filter: ArchiveFilter, limit: Int?) async throws -> ArchivePage
  func remove(_ ids: [NodeID]) async throws
  /// How many stored rows match `filter`, readable or not.
  func count(matching filter: ArchiveFilter) async throws -> Int
  /// Clear Archive (BH-087): deletes every entry. The confirmation is the caller's.
  func removeAll() async throws
}

/// The one-time auto-archive education banner (BH-089): `ArchiveState.educationBannerDismissed`.
/// `Persistence.SettingsStore` conforms.
public protocol ArchiveBannerStoring: Sendable {
  func isEducationBannerDismissed() async throws -> Bool
  func dismissEducationBanner(at date: Date) async throws
}

/// Auto-archive bookkeeping (`ArchiveState`) and the archive settings. `Persistence.SettingsStore` conforms.
public protocol ArchiveStateStoring: Sendable {
  func resolveAutoArchiveStart(now: Date) async throws -> Date
  /// Track D open question 6, decided in Track E: an Arc sidebar import restarts the auto-archive clock.
  func resetAutoArchiveStart(to date: Date) async throws
  func loadArchiveSettings() async throws -> ArchiveSettings
}
