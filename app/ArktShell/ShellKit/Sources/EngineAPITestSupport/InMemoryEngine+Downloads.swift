import EngineAPI
import Foundation

/// What a scripted download started from, so Retry can start it again.
struct DownloadSpec {
  var url: URL
  var filename: String
  var totalBytes: Int64?
  var mimeType: String
}

/// Downloads of the in-memory engine (rule 24). Bytes arrive only when a test calls `deliverDownloadBytes`, so every
/// state is deterministic. Files are real (in `downloadDefaultFolder`, or the folder the preference names), so the
/// save-location, Open and Remove behaviors can be checked without a mock of the file system.
extension InMemoryEngine {
  public var downloads: [DownloadItem] { downloadItems }

  public func observeDownloads(_ handler: @escaping @MainActor (DownloadEvent) -> Void) -> EngineObservation {
    hub.addDownloadObserver(handler)
  }

  public func startDownload(from url: URL) {
    beginDownload(url: url, filename: url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent,
                  totalBytes: nil)
  }

  // MARK: Commands

  public func perform(_ command: DownloadCommand, on id: DownloadID) {
    guard let item = download(id) else { return }
    switch command {
    case .cancel:
      guard item.state.isActive else { return }
      cancelDownload(id)
    case .pause:
      guard item.state == .inProgress else { return }
      change(id) { $0.state = .paused; $0.bytesPerSecond = 0 }
    case .resume:
      switch item.state {
      case .paused: change(id) { $0.state = .inProgress }
      case .interrupted where item.canResume: change(id) { $0.state = .inProgress; $0.endTime = nil }
      default: return
      }
    case .open:
      guard item.state == .complete, !item.isHeldForDecision else { return }
      openedDownloads.append(id)
    case .showInFinder:
      guard item.targetPath != nil else { return }
      revealedDownloads.append(id)
    case .retry:
      retryDownload(item)
    case .keepDangerous:
      guard item.dangerType.canKeep else { return }
      change(id) { $0.dangerType = .userValidated }
    case .discardDangerous:
      guard item.isHeldForDecision else { return }
      deleteFile(of: item)
      removeItem(id)
    case .remove:
      if item.state.isActive { cancelDownload(id) }
      removeItem(id)
    }
  }

  // MARK: Test drivers: what the network, the disk and the safety check do

  /// The engine starts a download. In `.ask` mode with a chooser the item is listed once the chooser answers (never,
  /// when it answers nil). Returns the id the item will have.
  @discardableResult
  public func beginDownload(url: URL, filename: String, totalBytes: Int64?,
                            mimeType: String = "application/octet-stream") -> DownloadID {
    let id = DownloadID()
    startDownload(id, DownloadSpec(url: url, filename: filename, totalBytes: totalBytes, mimeType: mimeType))
    return id
  }

  /// `count` more bytes arrive (written to the file). The last ones complete the download. Nothing arrives for a
  /// paused or finished download.
  public func deliverDownloadBytes(_ id: DownloadID, _ count: Int64, bytesPerSecond: Int64 = 0) {
    guard let item = download(id), item.state == .inProgress, count > 0 else { return }
    let received = min(item.receivedBytes + count, item.totalBytes ?? .max)
    if let target = item.targetPath, let handle = try? FileHandle(forWritingTo: target) {
      try? handle.seekToEnd()
      try? handle.write(contentsOf: Data(count: Int(received - item.receivedBytes)))
      try? handle.close()
    }
    let finished = item.totalBytes.map { received >= $0 } ?? false
    let end = downloadClock()
    change(id) {
      $0.receivedBytes = received
      $0.bytesPerSecond = finished ? 0 : bytesPerSecond
      if finished { $0.state = .complete; $0.endTime = end }
    }
  }

  /// The connection or the disk fails: the download is interrupted, and can resume when the server allows.
  public func interruptDownload(_ id: DownloadID, reason: DownloadInterruptReason, canResume: Bool = false) {
    guard let item = download(id), item.state.isActive else { return }
    if !canResume { deleteFile(of: item) }
    change(id) { $0.state = .interrupted(reason); $0.canResume = canResume; $0.bytesPerSecond = 0 }
  }

  /// The safety check judges the download.
  public func markDownloadDangerous(_ id: DownloadID, _ type: DownloadDangerType) {
    guard download(id) != nil else { return }
    change(id) { $0.dangerType = type }
  }

  /// Lists `item` as is, with no file and no preference (previews and UI tests that need a shape, such as 50 rows or a
  /// 2.4 GB file).
  public func addScriptedDownload(_ item: DownloadItem) {
    downloadItems.append(item)
    downloadSpecs[item.id] = DownloadSpec(url: item.url, filename: item.filename, totalBytes: item.totalBytes,
                                          mimeType: item.mimeType)
    hub.emit(DownloadEvent.downloadCreated(item))
  }

  /// Changes a listed item as the engine would, and reports it.
  public func updateScriptedDownload(_ id: DownloadID, _ mutate: (inout DownloadItem) -> Void) {
    change(id, mutate)
  }

  // MARK: Internals

  private func startDownload(_ id: DownloadID, _ spec: DownloadSpec) {
    switch downloadSavePreference {
    case .folder(let folder):
      createDownload(id, spec, target: uniqueTarget(spec.filename, in: usableFolder(folder)))
    case .ask:
      guard let chooser = downloadDestinationChooser else {
        createDownload(id, spec, target: uniqueTarget(spec.filename, in: downloadDefaultFolder))
        return
      }
      let request = DownloadDestinationRequest(suggestedFilename: spec.filename, directory: downloadDefaultFolder)
      Task { [weak self] in
        guard let chosen = await chooser(request), let self else { return }
        self.createDownload(id, spec, target: chosen)
      }
    }
  }

  private func usableFolder(_ folder: URL) -> URL {
    var isDirectory: ObjCBool = false
    let usable = FileManager.default.fileExists(atPath: folder.path(), isDirectory: &isDirectory)
      && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: folder.path())
    return usable ? folder : downloadDefaultFolder
  }

  private func uniqueTarget(_ filename: String, in folder: URL) -> URL {
    let base = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    var candidate = folder.appending(path: filename)
    var number = 0
    while FileManager.default.fileExists(atPath: candidate.path()) {
      number += 1
      candidate = folder.appending(path: ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)")
    }
    return candidate
  }

  private func createDownload(_ id: DownloadID, _ spec: DownloadSpec, target: URL) {
    try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: target.path(), contents: Data())
    downloadSpecs[id] = spec
    let item = DownloadItem(id: id, url: spec.url, filename: target.lastPathComponent, targetPath: target,
                            totalBytes: spec.totalBytes, mimeType: spec.mimeType, startTime: downloadClock())
    downloadItems.append(item)
    hub.emit(DownloadEvent.downloadCreated(item))
    if spec.totalBytes == 0 { deliverDownloadBytes(id, 1) }       // an empty file is complete at once
  }

  private func change(_ id: DownloadID, _ mutate: (inout DownloadItem) -> Void) {
    guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }
    var item = downloadItems[index]
    mutate(&item)
    guard item != downloadItems[index] else { return }
    downloadItems[index] = item
    hub.emit(DownloadEvent.downloadUpdated(item))
  }

  private func cancelDownload(_ id: DownloadID) {
    guard let item = download(id) else { return }
    deleteFile(of: item)
    let end = downloadClock()
    change(id) { $0.state = .cancelled; $0.bytesPerSecond = 0; $0.endTime = end }
  }

  private func removeItem(_ id: DownloadID) {
    guard downloadItems.contains(where: { $0.id == id }) else { return }
    downloadItems.removeAll { $0.id == id }
    downloadSpecs[id] = nil
    hub.emit(DownloadEvent.downloadRemoved(id))
  }

  private func deleteFile(of item: DownloadItem) {
    if let target = item.targetPath { try? FileManager.default.removeItem(at: target) }
  }

  private func retryDownload(_ item: DownloadItem) {
    switch item.state {
    case .interrupted where item.canResume:
      change(item.id) { $0.state = .inProgress; $0.endTime = nil }
    case .interrupted, .cancelled:
      guard let spec = downloadSpecs[item.id] else { return }
      let replacement = DownloadID()
      removeItem(item.id)
      startDownload(replacement, spec)
    default:
      return
    }
  }
}

// MARK: - Harness drivers

extension DownloadDrivers {
  /// The in-memory engine's drivers: bytes arrive when the check says so.
  public static func inMemory() -> DownloadDrivers {
    func memory(_ engine: any EngineClient) throws -> InMemoryEngine {
      guard let engine = engine as? InMemoryEngine else {
        throw ContractViolation(description: "the in-memory harness needs an InMemoryEngine, got \(type(of: engine))")
      }
      return engine
    }
    return DownloadDrivers(
      start: { engine, name, size in
        let memory = try memory(engine)
        let id = memory.beginDownload(url: URL(string: "https://files.test/\(name)")!, filename: name,
                                      totalBytes: size)
        try await EngineContract.waitUntil(timeout: .seconds(10)) { memory.download(id) != nil }
        return id
      },
      advance: { engine, id, bytes in try memory(engine).deliverDownloadBytes(id, bytes) },
      canPause: true,
      fail: { engine, id, reason in try memory(engine).interruptDownload(id, reason: reason) },
      markDangerous: { engine, id, type in try memory(engine).markDownloadDangerous(id, type) }
    )
  }
}
