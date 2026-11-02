import Foundation
internal import ArktEngineABI
import EngineAPI

// MARK: - Downloads (#132)
//
// The facade (`arkt_engine.h`, "Downloads") observes the profile's `DownloadManager` and reports `DownloadCreated`,
// `DownloadUpdated` and `DownloadRemoved` as plain snapshots. This file keeps the list from those events, so `downloads`
// agrees with the last event a handler saw, and turns the shell's commands into facade calls. The facade executes; the
// gates (what may be opened, kept or discarded) are decided here from the shell's own `DownloadItem` rules.

extension ChromiumEngine {
  static var systemDownloadsFolder: URL {
    FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
  }

  /// `DownloadPrefs::GetDefaultDownloadDirectory()`.
  public var downloadDefaultFolder: URL { facade.defaultDownloadDirectory }

  public var downloads: [DownloadItem] { downloadOrder.compactMap { downloadTable[$0] } }

  public func download(_ id: DownloadID) -> DownloadItem? { downloadTable[id] }

  public func observeDownloads(_ handler: @escaping @MainActor (DownloadEvent) -> Void) -> EngineObservation {
    hub.addDownloadObserver(handler)
  }

  /// `DownloadManager::DownloadUrl`; the item arrives as a `DownloadCreated` event.
  public func startDownload(from url: URL) { facade.startDownload(from: url) }

  public func perform(_ command: DownloadCommand, on id: DownloadID) {
    guard let item = downloadTable[id] else { return }
    let guid = id.rawValue
    switch command {
    case .cancel:
      guard item.state.isActive else { return }
      facade.perform(download: .cancel, on: guid)
    case .pause:
      guard item.state == .inProgress else { return }
      facade.perform(download: .pause, on: guid)
    case .resume:
      switch item.state {
      case .paused: facade.perform(download: .resume, on: guid)
      case .interrupted where item.canResume: facade.perform(download: .resume, on: guid)
      default: return
      }
    case .open:
      guard item.canBeOpened else { return }
      facade.perform(download: .open, on: guid)
    case .showInFinder:
      guard item.targetPath != nil else { return }
      facade.perform(download: .showInFinder, on: guid)
    case .retry:
      switch item.state {
      case .cancelled, .interrupted: facade.perform(download: .retry, on: guid)
      default: return
      }
    case .keepDangerous:
      guard item.dangerType.canKeep else { return }
      facade.perform(download: .keepDangerous, on: guid)
    case .discardDangerous:
      guard item.isHeldForDecision else { return }
      facade.perform(download: .discardDangerous, on: guid)
    case .remove:
      facade.perform(download: .remove, on: guid)
    }
  }

  // MARK: Save location

  /// Pushes the shell's choice to the profile's prefs. A folder that is missing or not writable is replaced by the
  /// default folder here, because Chromium would create a missing one instead of falling back.
  func applySavePreference(_ preference: DownloadSavePreference) {
    switch preference {
    case .ask:
      facade.downloadPromptsForLocation = true
      installDestinationHandler()
    case .folder(let folder):
      facade.downloadPromptsForLocation = false
      facade.downloadDirectory = Self.usableFolder(folder) ?? downloadDefaultFolder
      facade.downloadDestinationHandler = nil
    }
  }

  private static func usableFolder(_ folder: URL) -> URL? {
    var isDirectory: ObjCBool = false
    let usable = FileManager.default.fileExists(atPath: folder.path(), isDirectory: &isDirectory)
      && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: folder.path())
    return usable ? folder : nil
  }

  /// Answers Chromium's save panel with the shell's chooser. Without a chooser the download goes to the default folder
  /// under its suggested name.
  func installDestinationHandler() {
    facade.downloadDestinationHandler = { [weak self] suggested, directory, answer in
      MainActor.assumeIsolated {
        guard let chooser = self?.downloadDestinationChooser else {
          answer(directory.appending(path: DownloadFilename.sanitized(suggested)))
          return
        }
        let request = DownloadDestinationRequest(suggestedFilename: suggested, directory: directory)
        Task { @MainActor in answer(await chooser(request)) }
      }
    }
  }

  // MARK: Events

  func downloadCreated(_ event: any ArktEngineEvent) {
    guard let facadeItem = event.download else { return }
    let item = DownloadItem(facade: facadeItem)
    guard downloadTable[item.id] == nil else { return downloadUpdated(event) }
    downloadTable[item.id] = item
    downloadOrder.append(item.id)
    hub.emit(DownloadEvent.downloadCreated(item))
  }

  /// A change the shell already has (Chromium also reports the "opened" flag and history writes) is not repeated, so
  /// completion is reported once. An update for a download not listed yet lists it.
  func downloadUpdated(_ event: any ArktEngineEvent) {
    guard let facadeItem = event.download else { return }
    let item = DownloadItem(facade: facadeItem)
    guard let known = downloadTable[item.id] else { return downloadCreated(event) }
    guard item != known else { return }
    downloadTable[item.id] = item
    hub.emit(DownloadEvent.downloadUpdated(item))
  }

  func downloadRemoved(_ event: any ArktEngineEvent) {
    guard let guid = event.download?.guid else { return }
    let id = DownloadID(guid)
    guard downloadTable.removeValue(forKey: id) != nil else { return }
    downloadOrder.removeAll { $0 == id }
    hub.emit(DownloadEvent.downloadRemoved(id))
  }
}
