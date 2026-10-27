import Foundation
internal import ArktEngineABI
import EngineAPI

// MARK: - Downloads (#132): NOT YET WIRED
//
// The download model and the shell's Library UI are in this repository (EngineAPI/EngineDownloads.swift); the
// Chromium side is a separate engine-lane task. Until it lands this engine reports no downloads and ignores every
// download command, so the shell's Library button stays idle with the Chromium engine. Every stub below names the
// `download::DownloadItem` or `DownloadManager` call it becomes, and the contract (rule 24, `EngineContract+Downloads`)
// is the acceptance test: the engine-lane task adds the facade script and the `DownloadDrivers`, then removes the rule
// 24 skip in `ChromiumEngineContractTests`.
//
// To wire: a facade event for `DownloadManager::Observer` (created, updated, removed) mapped to `DownloadItem` values
// with `DownloadItem.init(facade:)` (states per `DownloadState`'s documentation), `hub.emit(DownloadEvent...)`, the
// commands below, and the profile prefs `download.prompt_for_download` and `download.default_directory` for
// `downloadSavePreference`, with the target determiner's prompt answered by `downloadDestinationChooser`.

extension ChromiumEngine {
  static var systemDownloadsFolder: URL {
    FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
  }

  /// NOT YET WIRED: the Chromium profile's `DownloadPrefs::DefaultDownloadDirectory`.
  public var downloadDefaultFolder: URL { Self.systemDownloadsFolder }

  /// NOT YET WIRED: the `DownloadManager`'s items (`DownloadManager::GetAllDownloads`).
  public var downloads: [DownloadItem] { [] }

  /// Registers on the hub, so the call is valid and the handler fires once the engine reports downloads.
  public func observeDownloads(_ handler: @escaping @MainActor (DownloadEvent) -> Void) -> EngineObservation {
    hub.addDownloadObserver(handler)
  }

  /// NOT YET WIRED: `DownloadManager::DownloadUrl` with the profile's download params.
  public func startDownload(from url: URL) {}

  /// NOT YET WIRED: each command is a `download::DownloadItem` call (see `DownloadCommand`'s documentation).
  public func perform(_ command: DownloadCommand, on id: DownloadID) {}
}
