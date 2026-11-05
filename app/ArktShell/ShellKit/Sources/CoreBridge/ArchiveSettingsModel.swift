import Archive
import Foundation
import ShellUI
import os

/// The archive thresholds the app runs with (#448): "Archive Today tabs after" for the Default profile and "Archive
/// Little Arkt windows after". Settings changes them here; `onChange` hears each change at once (the auto-archive
/// timer applies it from its next tick) and the change is stored in the background, one field per write, so the two
/// rows never overwrite each other. Until `load()` finishes the values are the defaults (12 hours, 6 hours).
///
/// Only the Default profile is edited until a profile detail pane exists; the BH-083 "all profiles or only this one"
/// prompt needs two profiles, which #101 brings.
@MainActor
public final class ArchiveSettingsModel {
  /// The settings in effect: the stored ones once loaded, with every change made here.
  public private(set) var settings = ArchiveSettings()
  /// Hears every change made here and the loaded settings, on the main actor.
  public var onChange: (@MainActor (ArchiveSettings) -> Void)?

  private let state: any ArchiveStateStoring
  private let now: @MainActor () -> Date
  /// Changes made since the model was created; a load or store answer older than the latest change is not applied.
  private var generation = 0
  private var saving: Task<Void, Never>?
  /// Writes not finished yet; a load answer is not applied while one runs (the write's answer is newer).
  private var pendingSaves = 0
  private static let log = Logger(subsystem: ShellSignposts.subsystem, category: "archive-settings")

  public init(state: any ArchiveStateStoring, now: @escaping @MainActor () -> Date = { Date() }) {
    self.state = state
    self.now = now
  }

  /// "Archive Today tabs after": the Default profile's threshold (BH-080, BH-083).
  public var tabThreshold: AutoArchiveThreshold { settings.tabThreshold(forProfile: ArchiveSettings.defaultProfile) }

  /// "Archive Little Arkt windows after" (BH-137): 6 hours unless changed.
  public var littleArktThreshold: AutoArchiveThreshold { settings.littleArcThreshold }

  /// Reads the stored settings. A failed read keeps the defaults; a change made before the answer arrives is kept
  /// (its own write brings the rest of the stored settings).
  public func load() async {
    let started = generation
    do {
      let loaded = try await state.loadArchiveSettings()
      guard generation == started, pendingSaves == 0 else { return }
      adopt(loaded)
    } catch {
      Self.log.error("archive settings not loaded \(String(describing: type(of: error)), privacy: .public)")
    }
  }

  public func setTabThreshold(_ threshold: AutoArchiveThreshold) {
    guard threshold != tabThreshold else { return }
    change { $0.setTabThreshold(threshold, forProfile: ArchiveSettings.defaultProfile, scope: .thisProfile) }
  }

  public func setLittleArktThreshold(_ threshold: AutoArchiveThreshold) {
    guard threshold != littleArktThreshold else { return }
    change { $0.littleArcThreshold = threshold }
  }

  /// Returns when every change made so far is stored (or failed to store).
  public func flush() async { await saving?.value }

  /// The Settings window's Archive rows, as pop-up titles.
  public var settingsRows: SettingsArchiveRows {
    SettingsArchiveRows(
      tabsAfter: { [weak self] in (self?.tabThreshold ?? .tabsDefault).settingsTitle },
      setTabsAfter: { [weak self] title in
        AutoArchiveThreshold(settingsTitle: title).map { self?.setTabThreshold($0) }
      },
      littleArktAfter: { [weak self] in (self?.littleArktThreshold ?? .littleArcDefault).settingsTitle },
      setLittleArktAfter: { [weak self] title in
        AutoArchiveThreshold(settingsTitle: title).map { self?.setLittleArktThreshold($0) }
      })
  }

  private func change(_ edit: @escaping @Sendable (inout ArchiveSettings) -> Void) {
    generation += 1
    let current = generation
    var updated = settings
    edit(&updated)
    adopt(updated)
    let (state, date, previous) = (state, now(), saving)
    pendingSaves += 1
    saving = Task { [weak self] in
      await previous?.value                       // writes land in the order they were made
      let stored: ArchiveSettings?
      do {
        stored = try await state.updateArchiveSettings(at: date, edit)
      } catch {
        stored = nil
        Self.log.error("archive settings not saved \(String(describing: type(of: error)), privacy: .public)")
      }
      guard let self else { return }
      self.pendingSaves -= 1
      // The stored value carries fields this model had not loaded yet; a newer change keeps its own.
      if let stored, self.generation == current { self.adopt(stored) }
    }
  }

  private func adopt(_ new: ArchiveSettings) {
    guard new != settings else { return }
    settings = new
    onChange?(new)
  }
}

extension AutoArchiveThreshold {
  /// The Settings pop-up's title ("1 hour" to "30 days", "Never"; `SettingsWindowController.archiveAfterTitles`).
  public var settingsTitle: String {
    switch self {
    case .oneHour: "1 hour"
    case .sixHours: "6 hours"
    case .twelveHours: "12 hours"
    case .twentyFourHours: "24 hours"
    case .sevenDays: "7 days"
    case .thirtyDays: "30 days"
    case .never: "Never"
    }
  }

  public init?(settingsTitle: String) {
    guard let match = Self.allCases.first(where: { $0.settingsTitle == settingsTitle }) else { return nil }
    self = match
  }
}
