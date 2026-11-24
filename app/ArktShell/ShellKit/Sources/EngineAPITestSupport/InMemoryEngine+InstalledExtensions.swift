import EngineAPI
import Foundation

// The installed list, enable / disable, developer mode, Load unpacked and options pages for the in-memory engine
// (#600; the Chromium side is #964). The list is profile-wide and independent of the windows' action lists; the
// install and uninstall drivers keep both in step.

extension InMemoryEngine {
  public func setExtensionEnabled(_ extensionID: String, enabled: Bool) -> ExtensionEnableResult {
    guard let index = installedExtensions.firstIndex(where: { $0.id == extensionID }) else { return .unknownExtension }
    guard installedExtensions[index].isEnabled != enabled else { return .applied }
    guard installedExtensions[index].canDisable else { return .refused }
    installedExtensions[index].isEnabled = enabled
    hub.emit(EngineExtensionEvent.installedExtensionsChanged)
    return .applied
  }

  public func setExtensionDeveloperModeEnabled(_ enabled: Bool) {
    isExtensionDeveloperModeEnabled = enabled
  }

  /// Answers at once, without a sleep: `.developerModeOff` while developer mode is off; `.failed` with
  /// `unpackedLoadFailure` when it is set; otherwise the folder is listed as an unpacked extension named after the
  /// folder (one entry per folder: loading it again reloads it), `.installedExtensionsChanged` is reported, then
  /// `.loaded`.
  public func loadUnpackedExtension(at folder: URL) async -> UnpackedExtensionResult {
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
