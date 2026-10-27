import AppKit
internal import WebKit
import EngineAPI

/// What the engine keeps of one download: the live WKDownload and what Retry needs.
@MainActor
final class DownloadRecord {
  var download: WKDownload?
  /// The delegate; WKDownload holds it weakly.
  var observer: DownloadObserver?
  var request: URLRequest?
  var resumeData: Data?
  /// The target decided for the item, kept for a resume.
  var target: URL?
  var progressObservation: NSKeyValueObservation?
  /// Speed is the bytes since the last sample over the time since it.
  var lastSample: (date: Date, bytes: Int64)?
  /// The user cancelled or removed it: a failure callback that follows is not an interruption.
  var isEnding = false
}

/// The WKDownloadDelegate of one download, forwarding to the engine.
@MainActor
final class DownloadObserver: NSObject, WKDownloadDelegate {
  let id: DownloadID
  weak var engine: FakeEngine?
  init(id: DownloadID, engine: FakeEngine) { self.id = id; self.engine = engine }

  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
    guard let engine else { completionHandler(nil); return }
    engine.decideDestination(id, response: response, suggestedFilename: suggestedFilename, completion: completionHandler)
  }

  func downloadDidFinish(_ download: WKDownload) { engine?.downloadFinished(id) }

  func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
    engine?.downloadFailed(id, error: error, resumeData: resumeData)
  }
}

/// Downloads through WKDownload (rule 24). WebKit offers no pause and no danger judgement: `pause` and the danger
/// commands do nothing, and every item is `.notDangerous`. Progress is the download's own NSProgress; bytes arrive from
/// the network, so the contract's held response is a loopback server in the GUI tests.
extension FakeEngine {
  public var downloads: [DownloadItem] { downloadItems }

  public func observeDownloads(_ handler: @escaping @MainActor (DownloadEvent) -> Void) -> EngineObservation {
    hub.addDownloadObserver(handler)
  }

  public func startDownload(from url: URL) {
    startDownload(DownloadID(), request: URLRequest(url: url), replacing: nil)
  }

  // MARK: Commands

  public func perform(_ command: DownloadCommand, on id: DownloadID) {
    guard let item = download(id), let record = downloadRecords[id] else { return }
    switch command {
    case .cancel:
      guard item.state.isActive else { return }
      cancelDownload(id)
    case .pause, .keepDangerous, .discardDangerous:
      return                                    // WebKit cannot pause and judges nothing dangerous
    case .resume:
      guard case .interrupted = item.state, item.canResume else { return }
      resumeDownload(id)
    case .open:
      guard item.state == .complete, let target = item.targetPath else { return }
      downloadOpener(target)
    case .showInFinder:
      guard let target = item.targetPath else { return }
      downloadRevealer(target)
    case .retry:
      switch item.state {
      case .interrupted where item.canResume: resumeDownload(id)
      case .interrupted, .cancelled:
        guard let request = record.request else { return }
        startDownload(DownloadID(), request: request, replacing: id)
      default: return
      }
    case .remove:
      if item.state.isActive { cancelDownload(id) }
      removeDownloadItem(id)
    }
  }

  // MARK: Starting

  func adoptDownload(_ download: WKDownload) {
    let id = DownloadID()
    attach(download, to: id, record: DownloadRecord(), request: download.originalRequest)
  }

  private func startDownload(_ id: DownloadID, request: URLRequest, replacing old: DownloadID?) {
    let record = DownloadRecord()
    record.request = request
    // The old row goes when the new one is listed (decideDestination), so a refused panel keeps it.
    pendingReplacement[id] = old                    // nil: no row to replace
    downloadRecords[id] = record
    downloadWebView.startDownload(using: request) { [weak self] download in
      MainActor.assumeIsolated { self?.attach(download, to: id, record: record, request: request) }
    }
  }

  private func attach(_ download: WKDownload, to id: DownloadID, record: DownloadRecord, request: URLRequest?) {
    record.request = request
    record.download = download
    let observer = DownloadObserver(id: id, engine: self)
    record.observer = observer
    download.delegate = observer
    downloadRecords[id] = record
  }

  // MARK: WebKit callbacks

  func decideDestination(_ id: DownloadID, response: URLResponse, suggestedFilename: String,
                         completion: @escaping @MainActor @Sendable (URL?) -> Void) {
    guard let record = downloadRecords[id] else { completion(nil); return }
    if let target = record.target {                // a resume keeps its file
      completion(target)
      return
    }
    let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
    switch downloadSavePreference {
    case .folder(let folder):
      chosen(id, response, name, uniqueTarget(name, in: usableFolder(folder)), completion)
    case .ask:
      guard let chooser = downloadDestinationChooser else {
        chosen(id, response, name, uniqueTarget(name, in: downloadDefaultFolder), completion)
        return
      }
      let request = DownloadDestinationRequest(suggestedFilename: name, directory: downloadDefaultFolder)
      Task { [weak self] in
        let target = await chooser(request)
        guard let self else { completion(nil); return }
        guard let target else {
          self.downloadRecords[id] = nil
          self.pendingReplacement[id] = nil
          completion(nil)                          // the panel was cancelled: the download never lists
          return
        }
        self.chosen(id, response, name, target, completion)
      }
    }
  }

  private func chosen(_ id: DownloadID, _ response: URLResponse, _ name: String, _ target: URL,
                      _ completion: @MainActor @Sendable (URL?) -> Void) {
    guard let record = downloadRecords[id] else { completion(nil); return }
    try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    record.target = target
    let total = response.expectedContentLength > 0 ? response.expectedContentLength : nil
    let item = DownloadItem(
      id: id, url: response.url ?? record.request?.url ?? target, filename: target.lastPathComponent,
      targetPath: target, totalBytes: total, mimeType: response.mimeType ?? "application/octet-stream",
      startTime: downloadClock())
    downloadItems.append(item)
    if let old = pendingReplacement.removeValue(forKey: id) { removeDownloadItem(old) }
    hub.emit(DownloadEvent.downloadCreated(item))
    if let download = record.download {
      record.progressObservation = download.progress.observe(\.completedUnitCount, options: [.new]) { [weak self] _, _ in
        MainActor.assumeIsolated { self?.downloadProgressed(id) }
      }
    }
    completion(target)
  }

  private func downloadProgressed(_ id: DownloadID) {
    guard let record = downloadRecords[id], let progress = record.download?.progress,
          let item = download(id), item.state == .inProgress else { return }
    let received = progress.completedUnitCount
    let now = downloadClock()
    var speed = item.bytesPerSecond
    if let last = record.lastSample, now.timeIntervalSince(last.date) > 0.5 {
      speed = Int64(Double(received - last.bytes) / now.timeIntervalSince(last.date))
      record.lastSample = (now, received)
    } else if record.lastSample == nil {
      record.lastSample = (now, received)
    }
    let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : item.totalBytes
    changeDownload(id) {
      $0.receivedBytes = max($0.receivedBytes, received)
      $0.bytesPerSecond = max(0, speed)
      if let total { $0.totalBytes = total }
    }
  }

  func downloadFinished(_ id: DownloadID) {
    guard let record = downloadRecords[id], let item = download(id), item.state.isActive else { return }
    record.progressObservation = nil
    let size = (try? item.targetPath.map { try FileManager.default.attributesOfItem(atPath: $0.path())[.size] as? Int64 })
      .flatMap { $0 } ?? item.receivedBytes
    let end = downloadClock()
    changeDownload(id) {
      $0.receivedBytes = size
      if $0.totalBytes == nil { $0.totalBytes = size }
      $0.state = .complete; $0.endTime = end; $0.bytesPerSecond = 0
    }
    record.download = nil
  }

  func downloadFailed(_ id: DownloadID, error: any Error, resumeData: Data?) {
    guard let record = downloadRecords[id], let item = download(id), item.state.isActive, !record.isEnding else {
      downloadRecords[id]?.download = nil
      return
    }
    record.progressObservation = nil
    record.resumeData = resumeData
    record.download = nil
    let reason = Self.interruptReason(for: error)
    changeDownload(id) {
      $0.state = .interrupted(reason); $0.canResume = resumeData != nil; $0.bytesPerSecond = 0
    }
  }

  static func interruptReason(for error: any Error) -> DownloadInterruptReason {
    switch (error as? URLError)?.code {
    case .notConnectedToInternet?, .networkConnectionLost?, .dataNotAllowed?: .networkDisconnected
    case .timedOut?: .networkTimeout
    case .cannotFindHost?, .cannotConnectToHost?, .dnsLookupFailed?: .serverUnreachable
    case .secureConnectionFailed?, .serverCertificateUntrusted?, .serverCertificateHasBadDate?,
         .serverCertificateHasUnknownRoot?, .serverCertificateNotYetValid?, .clientCertificateRejected?:
      .serverCertProblem
    case .cancelled?: .userCanceled
    case .noPermissionsToReadFile?, .fileDoesNotExist?, .cannotWriteToFile?, .cannotCreateFile?: .fileAccessDenied
    default: .networkFailed
    }
  }

  // MARK: Internals

  private func cancelDownload(_ id: DownloadID) {
    guard let record = downloadRecords[id], let item = download(id) else { return }
    record.isEnding = true
    record.progressObservation = nil
    record.download?.cancel { _ in }
    record.download = nil
    if let target = item.targetPath {
      try? FileManager.default.removeItem(at: target)
      try? FileManager.default.removeItem(at: target.appendingPathExtension("download"))
    }
    let end = downloadClock()
    changeDownload(id) { $0.state = .cancelled; $0.bytesPerSecond = 0; $0.endTime = end }
  }

  private func resumeDownload(_ id: DownloadID) {
    guard let record = downloadRecords[id], let data = record.resumeData else { return }
    record.resumeData = nil
    record.isEnding = false
    changeDownload(id) { $0.state = .inProgress; $0.endTime = nil }
    downloadWebView.resumeDownload(fromResumeData: data) { [weak self] download in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.attach(download, to: id, record: record, request: record.request)
        record.progressObservation = download.progress.observe(\.completedUnitCount, options: [.new]) { [weak self] _, _ in
          MainActor.assumeIsolated { self?.downloadProgressed(id) }
        }
      }
    }
  }

  private func removeDownloadItem(_ id: DownloadID) {
    guard downloadItems.contains(where: { $0.id == id }) else { return }
    downloadItems.removeAll { $0.id == id }
    downloadRecords[id] = nil
    hub.emit(DownloadEvent.downloadRemoved(id))
  }

  private func changeDownload(_ id: DownloadID, _ mutate: (inout DownloadItem) -> Void) {
    guard let index = downloadItems.firstIndex(where: { $0.id == id }) else { return }
    var item = downloadItems[index]
    mutate(&item)
    guard item != downloadItems[index] else { return }
    downloadItems[index] = item
    hub.emit(DownloadEvent.downloadUpdated(item))
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
}
