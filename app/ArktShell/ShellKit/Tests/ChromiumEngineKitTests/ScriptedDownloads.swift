import Foundation
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
@testable import ChromiumEngineKit

// The scripted facade's downloads (#132, contract rule 24): a Swift model of what the real facade reports from
// Chromium's `DownloadManager`. Bytes arrive only when a driver says so. Files are real, in the folder the download
// prefs name (or the default folder, a fresh temporary one), so Open, Remove, Cancel and Discard can be checked on disk.

/// One download as plain values (`ArktDownloadItem`), read when the event was recorded.
final class ScriptedDownloadItem: NSObject, ArktDownloadItem {
  var guid: String
  var url: URL
  var filename: String
  var targetPath: URL?
  var totalBytes: Int64
  var receivedBytes: Int64
  var state: ArktDownloadState
  var interruptReason: Int
  var dangerType: Int
  var mimeType: String
  var startTime: Date
  var endTime: Date?
  var bytesPerSecond: Int64
  var canResume: Bool

  init(guid: String, url: URL, filename: String, targetPath: URL?, totalBytes: Int64, mimeType: String) {
    self.guid = guid; self.url = url; self.filename = filename; self.targetPath = targetPath
    self.totalBytes = totalBytes; self.receivedBytes = 0; self.state = .inProgress; self.interruptReason = 0
    self.dangerType = 0; self.mimeType = mimeType; self.startTime = Date(); self.endTime = nil
    self.bytesPerSecond = 0; self.canResume = false
  }

  func snapshot() -> ScriptedDownloadItem {
    let copy = ScriptedDownloadItem(guid: guid, url: url, filename: filename, targetPath: targetPath,
                                    totalBytes: totalBytes, mimeType: mimeType)
    copy.receivedBytes = receivedBytes; copy.state = state; copy.interruptReason = interruptReason
    copy.dangerType = dangerType; copy.startTime = startTime; copy.endTime = endTime
    copy.bytesPerSecond = bytesPerSecond; copy.canResume = canResume
    return copy
  }

  var type: DownloadDangerType { DownloadDangerType(rawValue: dangerType) }
  var isActive: Bool { state == .inProgress || state == .paused }
}

extension ScriptedFacade {
  var downloads: [any ArktDownloadItem] { scriptedDownloads.map { $0.snapshot() } }

  private func scriptedDownload(_ guid: String) -> ScriptedDownloadItem? {
    scriptedDownloads.first { $0.guid == guid }
  }

  private func record(_ kind: ArktEngineEventKind, _ item: ScriptedDownloadItem) {
    let event = ScriptedEvent(kind, tab: nil, browser: nil)
    event.download = item.snapshot()
    record(event)
  }

  /// Records the item's new values. A change that alters nothing is not reported.
  private func change(_ item: ScriptedDownloadItem, _ mutate: (ScriptedDownloadItem) -> Void) {
    let before = item.snapshot()
    mutate(item)
    guard before.state != item.state || before.receivedBytes != item.receivedBytes
            || before.dangerType != item.dangerType || before.interruptReason != item.interruptReason
            || before.bytesPerSecond != item.bytesPerSecond || before.canResume != item.canResume else { return }
    record(.downloadUpdated, item)
  }

  // MARK: ArktEngine

  func startDownload(from url: URL) {
    _ = beginDownload(url: url, filename: url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent,
                      totalBytes: 0, mimeType: "application/octet-stream")
  }

  func perform(download command: ArktDownloadCommand, on guid: String) {
    guard let item = scriptedDownload(guid) else { return }
    switch command {
    case .cancel:
      guard item.isActive else { return }
      cancel(item)
    case .pause:
      guard item.state == .inProgress else { return }
      change(item) { $0.state = .paused; $0.bytesPerSecond = 0 }
    case .resume:
      guard item.state == .paused || (item.state == .interrupted && item.canResume) else { return }
      change(item) { $0.state = .inProgress; $0.endTime = nil }
    case .open:
      guard item.state == .complete, item.type.canOpen else { return }
      openedDownloads.append(guid)
    case .showInFinder:
      guard item.targetPath != nil else { return }
      revealedDownloads.append(guid)
    case .retry:
      switch item.state {
      case .interrupted where item.canResume:
        change(item) { $0.state = .inProgress; $0.endTime = nil }
      case .interrupted, .cancelled:
        remove(item)
        _ = beginDownload(url: item.url, filename: item.filename, totalBytes: item.totalBytes,
                          mimeType: item.mimeType)
      default:
        return
      }
    case .keepDangerous:
      guard item.type.isHeldForDecision, !item.type.isBlocked else { return }
      change(item) { $0.dangerType = DownloadDangerType.userValidated.rawValue }
    case .discardDangerous:
      guard item.type.isHeldForDecision || item.type.isBlocked else { return }
      deleteFile(of: item)
      remove(item)
    case .remove:
      if item.isActive { cancel(item) }
      remove(item)
    @unknown default:
      return
    }
  }

  // MARK: Drivers: what the network, the disk and the safety check do

  /// A download starts. In the prompting mode with a handler it is listed once the handler answers (never, when it
  /// answers nil). Returns the guid the item will have.
  @discardableResult
  func beginDownload(url: URL, filename: String, totalBytes: Int64, mimeType: String) -> String {
    let guid = UUID().uuidString
    let create: (URL) -> Void = { [unowned self] target in
      try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
      FileManager.default.createFile(atPath: target.path(), contents: Data())
      let item = ScriptedDownloadItem(guid: guid, url: url, filename: target.lastPathComponent, targetPath: target,
                                      totalBytes: totalBytes, mimeType: mimeType)
      scriptedDownloads.append(item)
      record(.downloadCreated, item)
    }
    let name = DownloadFilename.sanitized(filename)
    if downloadPromptsForLocation, let handler = downloadDestinationHandler {
      handler(name, defaultDownloadDirectory) { chosen in
        Task { @MainActor in if let chosen { create(chosen) } }
      }
    } else {
      create(uniqueTarget(name, in: downloadPromptsForLocation ? defaultDownloadDirectory : downloadDirectory))
    }
    return guid
  }

  /// `count` more bytes arrive and are written; the last ones complete the download.
  func deliverDownloadBytes(_ guid: String, _ count: Int64) {
    guard let item = scriptedDownload(guid), item.state == .inProgress, count > 0 else { return }
    let received = min(item.receivedBytes + count, item.totalBytes > 0 ? item.totalBytes : .max)
    if let target = item.targetPath, let handle = try? FileHandle(forWritingTo: target) {
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: Data(count: Int(received - item.receivedBytes)))
      try? handle.close()
    }
    let finished = item.totalBytes > 0 && received >= item.totalBytes
    change(item) {
      $0.receivedBytes = received
      if finished { $0.state = .complete; $0.endTime = Date() }
    }
  }

  /// The connection fails; the partial file is kept only for a download that can resume.
  func interruptDownload(_ guid: String, reason: Int, canResume: Bool = false) {
    guard let item = scriptedDownload(guid), item.isActive else { return }
    if !canResume { deleteFile(of: item) }
    change(item) {
      $0.state = .interrupted; $0.interruptReason = reason; $0.canResume = canResume; $0.bytesPerSecond = 0
      $0.endTime = Date()
    }
  }

  /// The safety check judges the download.
  func markDownloadDangerous(_ guid: String, type: Int) {
    guard let item = scriptedDownload(guid) else { return }
    change(item) { $0.dangerType = type }
  }

  // MARK: Internals

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

  private func cancel(_ item: ScriptedDownloadItem) {
    deleteFile(of: item)
    change(item) { $0.state = .cancelled; $0.bytesPerSecond = 0; $0.endTime = Date() }
  }

  private func remove(_ item: ScriptedDownloadItem) {
    scriptedDownloads.removeAll { $0 === item }
    record(.downloadRemoved, item)
  }

  private func deleteFile(of item: ScriptedDownloadItem) {
    if let target = item.targetPath { try? FileManager.default.removeItem(at: target) }
  }
}

// MARK: - Harness drivers

extension DownloadDrivers {
  /// The scripted facade's drivers: bytes arrive when the check says so.
  @MainActor static func scripted() -> DownloadDrivers {
    func parts(_ engine: any EngineClient) throws -> (ChromiumEngine, ScriptedFacade) {
      let chromium = try ScriptedHarness.chromium(engine)
      return (chromium, ScriptedHarness.scripted(chromium))
    }
    return DownloadDrivers(
      start: { engine, name, size in
        let (chromium, facade) = try parts(engine)
        let guid = facade.beginDownload(url: URL(string: "https://files.test/\(name)")!, filename: name,
                                        totalBytes: size, mimeType: "application/octet-stream")
        let id = DownloadID(guid)
        try await ScriptedWait.until("the download to be listed") { chromium.download(id) != nil }
        return id
      },
      advance: { engine, id, bytes in
        let (chromium, facade) = try parts(engine)
        facade.deliverDownloadBytes(id.rawValue, bytes)
        try await ScriptedHarness.delivered(chromium)
      },
      canPause: true,
      fail: { engine, id, reason in
        let (chromium, facade) = try parts(engine)
        facade.interruptDownload(id.rawValue, reason: reason.rawValue)
        try await ScriptedHarness.delivered(chromium)
      },
      markDangerous: { engine, id, type in
        let (chromium, facade) = try parts(engine)
        facade.markDownloadDangerous(id.rawValue, type: type.rawValue)
        try await ScriptedHarness.delivered(chromium)
      })
  }
}
