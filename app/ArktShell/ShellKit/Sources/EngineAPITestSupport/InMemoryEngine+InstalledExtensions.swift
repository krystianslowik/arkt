import EngineAPI
import Foundation

// The installed list, enable / disable, developer mode, Load unpacked and options pages for the in-memory engine
// (#600; the Chromium side is #964). The list is profile-wide and independent of the windows' action lists; the
// install and uninstall drivers keep both in step.

extension InMemoryEngine {
  /// Turning off removes the extension's actions from every window and turning on restores them, each window with
  /// `.extensionActionsChanged`, then `.installedExtensionsChanged`. `canDisable` false answers `.refused`; an id in
  /// `permissionApprovalIDs` answers `.needsPermissionApproval` to turning on.
  public func setExtensionEnabled(_ extensionID: String, enabled: Bool) -> ExtensionEnableResult {
    guard let index = installedExtensions.firstIndex(where: { $0.id == extensionID }) else { return .unknownExtension }
    guard installedExtensions[index].isEnabled != enabled else { return .applied }
    guard installedExtensions[index].canDisable else { return .refused }
    if enabled, permissionApprovalIDs.contains(extensionID) { return .needsPermissionApproval }
    installedExtensions[index].isEnabled = enabled
    moveActions(of: [extensionID], enabled: enabled)
    hub.emit(EngineExtensionEvent.installedExtensionsChanged)
    return .applied
  }

  /// Off turns off every unpacked extension that is on, as Chromium does, and locks it (`canDisable` false) until
  /// developer mode is on again, which turns those back on. One `.installedExtensionsChanged` for each change.
  public func setExtensionDeveloperModeEnabled(_ enabled: Bool) {
    guard enabled != isExtensionDeveloperModeEnabled || !enabled else { return }
    isExtensionDeveloperModeEnabled = enabled
    var changed: [String] = []
    for index in installedExtensions.indices {
      let info = installedExtensions[index]
      if enabled, developerModeDisabledIDs.contains(info.id) {
        installedExtensions[index].isEnabled = true
        installedExtensions[index].canDisable = true
        changed.append(info.id)
      } else if !enabled, info.origin == .unpacked, info.isEnabled {
        installedExtensions[index].isEnabled = false
        installedExtensions[index].canDisable = false
        changed.append(info.id)
      }
    }
    if enabled { developerModeDisabledIDs = [] } else { developerModeDisabledIDs.formUnion(changed) }
    guard !changed.isEmpty else { return }
    moveActions(of: changed, enabled: enabled)
    hub.emit(EngineExtensionEvent.installedExtensionsChanged)
  }

  /// Takes the extensions' actions out of every window (off) or puts the kept ones back (on), reporting
  /// `.extensionActionsChanged` for each window that changed.
  private func moveActions(of extensionIDs: [String], enabled: Bool) {
    var touched: [EngineWindowID] = []
    for id in extensionIDs {
      if enabled {
        for (window, kept) in turnedOffActions.removeValue(forKey: id) ?? [:] where windowIDs.contains(window) {
          actions[window, default: []].append(contentsOf: kept)
          if !touched.contains(window) { touched.append(window) }
        }
      } else {
        for window in windowIDs {
          let kept = actions[window]?.filter { $0.extensionID == id } ?? []
          guard !kept.isEmpty else { continue }
          actions[window]?.removeAll { $0.extensionID == id }
          turnedOffActions[id, default: [:]][window] = kept
          if !touched.contains(window) { touched.append(window) }
        }
      }
    }
    for window in windowIDs where touched.contains(window) { hub.emit(.extensionActionsChanged(window)) }
  }

  /// Answers at once, without a sleep: `.developerModeOff` while developer mode is off; `.failed` with
  /// `unpackedLoadFailure` when it is set; otherwise the folder is listed as an unpacked extension named after the
  /// folder (one entry per folder: loading it again reloads it), `.installedExtensionsChanged` is reported, then
  /// `.loaded`.
  public func loadUnpackedExtension(at folder: URL) async -> UnpackedExtensionResult {
    guard folder.isFileURL, folder.path.hasPrefix("/") else { return .failed(reason: Self.notAFolderReason) }
    guard isExtensionDeveloperModeEnabled else { return .developerModeOff }
    loadedUnpackedFolders.append(folder)
    if let unpackedLoadFailure { return .failed(reason: unpackedLoadFailure) }
    let id = "unpacked-\(folder.standardizedFileURL.path)"
    let entry = InstalledExtensionInfo(id: id, name: folder.lastPathComponent, version: "1.0", origin: .unpacked)
    if let index = installedExtensions.firstIndex(where: { $0.id == id }) {
      installedExtensions[index] = entry
    } else {
      installedExtensions.append(entry)
      knownExtensionIDs.insert(id)
    }
    hub.emit(EngineExtensionEvent.installedExtensionsChanged)
    return .loaded(extensionID: id)
  }

  public func openExtensionOptionsPage(_ extensionID: String) {
    guard installedExtensions.contains(where: { $0.id == extensionID && $0.hasOptionsPage }) else { return }
    openedOptionsPages.append(extensionID)
  }

  /// The reason a URL that is not an absolute file URL fails with.
  public static let notAFolderReason = "Choose a folder on this Mac."

  // MARK: - Test drivers

  /// Test driver: the profile's installed extensions, as a profile on disk would have them. Reports one
  /// `.installedExtensionsChanged`. Each becomes pinnable.
  public func setInstalledExtensions(_ list: [InstalledExtensionInfo]) {
    installedExtensions = list
    knownExtensionIDs.formUnion(list.map(\.id))
    hub.emit(EngineExtensionEvent.installedExtensionsChanged)
  }

  /// Lists an extension `installExtension` installed, unless it is listed already. Returns whether the list changed.
  func listInstalled(_ info: InstalledExtension) -> Bool {
    guard !installedExtensions.contains(where: { $0.id == info.id }) else { return false }
    installedExtensions.append(InstalledExtensionInfo(id: info.id, name: info.name, version: "1.0",
                                                      iconPNG: info.iconPNG))
    return true
  }

  /// Whether the engine refuses to uninstall the extension: listed as one the user may not remove, or set to fail.
  func refusesUninstall(_ extensionID: String) -> Bool {
    failingUninstallIDs.contains(extensionID)
      || installedExtensions.contains { $0.id == extensionID && !$0.canUninstall }
  }
}
