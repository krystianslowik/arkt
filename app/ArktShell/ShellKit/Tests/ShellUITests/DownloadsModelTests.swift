import EngineAPI
import EngineAPITestSupport
import Foundation
import Testing
@testable import ShellUI

/// The Downloads model over the in-memory engine: the ring's state, what the popover lists, Cancel, Clear List, the
/// VoiceOver announcements and the save location.
@MainActor
struct DownloadsModelTests {
  private func url(_ name: String) -> URL { URL(string: "https://files.example/\(name)")! }

  private func make(settings: AppSettings? = nil) -> (InMemoryEngine, DownloadsModel) {
    let engine = InMemoryEngine()
    return (engine, DownloadsModel(engine: engine, settings: settings))
  }

  @discardableResult
  private func start(_ engine: InMemoryEngine, _ name: String, total: Int64 = 400) -> DownloadID {
    engine.beginDownload(url: url(name), filename: name, totalBytes: total)
  }

  // MARK: Ring

  @Test func `an engine with no downloads is idle`() {
    let (_, model) = make()
    #expect(model.ringState == .idle && model.items.isEmpty && model.activeItems.isEmpty)
  }

  @Test func `the ring is the whole's progress over the downloads that know their size`() {
    let (engine, model) = make()
    let first = start(engine, "a.bin"), second = start(engine, "b.bin")
    let unknown = engine.beginDownload(url: url("c.bin"), filename: "c.bin", totalBytes: nil)
    engine.deliverDownloadBytes(first, 100)
    engine.deliverDownloadBytes(second, 300)
    engine.deliverDownloadBytes(unknown, 50)
    #expect(model.ringState == .active(fraction: 0.5))
  }

  @Test func `a ring with no known size has no fraction`() {
    let (engine, model) = make()
    engine.beginDownload(url: url("c.bin"), filename: "c.bin", totalBytes: nil)
    #expect(model.ringState == .active(fraction: nil))
  }

  @Test func `finishing turns the ring into done until the library is opened`() {
    let (engine, model) = make()
    let id = start(engine, "a.bin")
    engine.deliverDownloadBytes(id, 400)
    #expect(model.ringState == .done)
    model.markSeen()
    #expect(model.ringState == .idle)
  }

  @Test func `a failure or a held file needs attention`() {
    let (engine, model) = make()
    let failed = start(engine, "a.bin")
    engine.interruptDownload(failed, reason: .networkDisconnected)
    #expect(model.ringState == .attention)
    model.markSeen()
    let held = start(engine, "b.dmg")
    engine.markDownloadDangerous(held, .dangerousFile)
    engine.deliverDownloadBytes(held, 400)
    #expect(model.ringState == .attention, "a finished, held file is not a silent success")
  }

  @Test func `a download the user cancelled leaves no dot`() {
    let (engine, model) = make()
    let id = start(engine, "a.bin")
    model.cancel(id)
    #expect(model.items.isEmpty && model.ringState == .idle)
  }

  // MARK: Lists

  @Test func `recent lists the newest first and at most the limit`() {
    let (engine, model) = make()
    let ids = (1...8).map { start(engine, "f\($0).bin") }
    let recent = model.recent(limit: 6)
    #expect(recent.map(\.id) == Array(ids.reversed().prefix(6)))
    #expect(model.recent().count == 6 && model.newestFirst.count == 8)
  }

  @Test func `clear list removes finished rows and keeps active and held ones, and the files stay`() throws {
    let (engine, model) = make()
    let done = start(engine, "done.bin"), failed = start(engine, "failed.bin"), active = start(engine, "active.bin")
    let held = start(engine, "held.dmg")
    engine.deliverDownloadBytes(done, 400)
    engine.interruptDownload(failed, reason: .networkFailed, canResume: true)
    engine.markDownloadDangerous(held, .dangerousFile)
    engine.deliverDownloadBytes(held, 400)                       // finished, but still held for a decision
    let file = try #require(engine.download(done)?.targetPath)
    model.clearList()
    #expect(Set(model.items.map(\.id)) == [active, held])
    #expect(FileManager.default.fileExists(atPath: file.path()), "Clear List leaves the file on disk")
  }

  @Test func `commands reach the engine`() {
    let (engine, model) = make()
    let id = start(engine, "a.bin")
    model.pause(id)
    #expect(engine.download(id)?.state == .paused)
    model.resume(id)
    #expect(engine.download(id)?.state == .inProgress)
    model.showInFinder(id)
    #expect(engine.revealedDownloads == [id])
    engine.deliverDownloadBytes(id, 400)
    model.open(id)
    #expect(engine.openedDownloads == [id])
    let held = start(engine, "h.dmg")
    engine.markDownloadDangerous(held, .dangerousFile)
    model.keep(held)
    #expect(engine.download(held)?.dangerType == .userValidated)
    let bad = start(engine, "b.dmg")
    engine.markDownloadDangerous(bad, .dangerousContent)
    model.discard(bad)
    #expect(engine.download(bad) == nil)
    model.remove(id)
    #expect(engine.download(id) == nil)
  }

  @Test(arguments: DownloadDangerType.all)
  func `the model opens a file only when its danger type is openable`(_ type: DownloadDangerType) {
    let (engine, model) = make()
    let id = start(engine, "a.bin", total: 10)
    engine.deliverDownloadBytes(id, 10)
    engine.markDownloadDangerous(id, type)
    model.open(id)
    let openable: Set<DownloadDangerType> = [.notDangerous, .userValidated, .allowlistedByPolicy, .deepScannedSafe]
    #expect(engine.openedDownloads == (openable.contains(type) ? [id] : []), "\(type)")
  }

  @Test func `retry of a failed row replaces it`() {
    let (engine, model) = make()
    let id = start(engine, "a.bin")
    engine.interruptDownload(id, reason: .networkDisconnected)
    model.retry(id)
    #expect(engine.download(id) == nil && model.activeItems.count == 1)
    #expect(model.ringState == .active(fraction: 0))
  }

  // MARK: Observers

  @Test func `observers hear created, updated and removed, and stop when cancelled`() {
    let (engine, model) = make()
    var log: [String] = []
    let observation = model.addObserver { change in
      switch change {
      case .created: log.append("created")
      case .updated: log.append("updated")
      case .removed: log.append("removed")
      case .seen: log.append("seen")
      }
    }
    let id = start(engine, "a.bin")
    engine.deliverDownloadBytes(id, 10)
    model.remove(id)
    #expect(log == ["created", "updated", "updated", "removed"], "an active row is cancelled, then removed: \(log)")
    observation.cancel()
    let count = log.count
    start(engine, "b.bin")
    #expect(log.count == count)
    _ = observation
  }

  @Test func `opening the library tells observers once, and only when something was unseen`() {
    let (engine, model) = make()
    var seen = 0
    let observation = model.addObserver { if case .seen = $0 { seen += 1 } }
    model.markSeen()
    #expect(seen == 0)
    let id = start(engine, "a.bin")
    engine.deliverDownloadBytes(id, 400)
    model.markSeen()
    model.markSeen()
    #expect(seen == 1)
    _ = observation
  }

  // MARK: Throttling

  /// A model with a clock and a scheduler the test steps by hand.
  @MainActor private final class Stepper {
    var now: CFTimeInterval = 0
    var scheduled: [(due: CFTimeInterval, action: @MainActor () -> Void)] = []
    /// Runs everything that is due at `now`; `run()` runs everything.
    func runDue() {
      let due = scheduled.filter { $0.due <= now }
      scheduled.removeAll { $0.due <= now }
      for item in due { item.action() }
    }
    func run() { let all = scheduled; scheduled = []; for item in all { item.action() } }
  }

  private func throttled() -> (InMemoryEngine, DownloadsModel, Stepper) {
    let (engine, model) = make()
    let stepper = Stepper()
    model.clock = { stepper.now }
    model.scheduler = { delay, action in stepper.scheduled.append((stepper.now + delay, action)) }
    return (engine, model, stepper)
  }

  @Test func `a thousand progress updates reach observers at most about ten times a second`() {
    let (engine, model, stepper) = throttled()
    let id = engine.beginDownload(url: url("a.bin"), filename: "a.bin", totalBytes: 1_000_000)
    var heard: [DownloadItem] = []
    let observation = model.addObserver { if case .updated(let item) = $0 { heard.append(item) } }
    for _ in 0..<1_000 {
      stepper.now += 0.001                                    // 1 ms per update: a second of traffic
      stepper.runDue()
      engine.deliverDownloadBytes(id, 100)
    }
    stepper.now += 0.2
    stepper.runDue()                                          // the last coalesced value lands
    #expect(heard.count <= 12, "\(heard.count) deliveries for 1000 updates")
    #expect(heard.count >= 2)
    #expect(heard.last?.receivedBytes == 100_000, "the latest value is what lands")
    #expect(model.item(id)?.receivedBytes == 100_000, "the model itself is never behind")
    let bytes = heard.map(\.receivedBytes)
    #expect(bytes == bytes.sorted(), "never backwards")
    _ = observation
  }

  @Test func `a state change is never delayed and carries the latest bytes`() {
    let (engine, model, stepper) = throttled()
    let id = engine.beginDownload(url: url("a.bin"), filename: "a.bin", totalBytes: 100)
    var heard: [DownloadItem] = []
    let observation = model.addObserver { if case .updated(let item) = $0 { heard.append(item) } }
    engine.deliverDownloadBytes(id, 10)                       // delivered at once
    stepper.now += 0.01
    engine.deliverDownloadBytes(id, 10)                       // coalesced
    #expect(heard.count == 1)
    engine.perform(.pause, on: id)
    #expect(heard.last?.state == .paused && heard.last?.receivedBytes == 20, "pause is immediate and current")
    engine.interruptDownload(id, reason: .networkFailed)
    #expect(heard.last?.state == .interrupted(.networkFailed))
    stepper.run()
    #expect(heard.last?.state == .interrupted(.networkFailed), "a stale coalesced value never lands after it")
    _ = observation
  }

  @Test func `a removed download leaves nothing pending`() {
    let (engine, model, stepper) = throttled()
    let id = engine.beginDownload(url: url("a.bin"), filename: "a.bin", totalBytes: 100)
    var updates = 0
    let observation = model.addObserver { if case .updated = $0 { updates += 1 } }
    engine.deliverDownloadBytes(id, 10)
    stepper.now += 0.01
    engine.deliverDownloadBytes(id, 10)
    let before = updates
    model.remove(id)
    stepper.run()
    #expect(model.items.isEmpty)
    #expect(updates <= before + 1, "only the cancel from remove, never the stale progress")
    _ = observation
  }

  // MARK: Announcements

  @Test func `progress is announced at 25, 50 and 75 percent, once each, and at the end`() {
    let (engine, model) = make()
    var spoken: [String] = []
    model.onAnnouncement = { spoken.append($0) }
    let id = start(engine, "a.bin", total: 400)
    for _ in 0..<100 { engine.deliverDownloadBytes(id, 4) }      // a hundred ticks, a quarter at a time announced
    #expect(spoken == ["a.bin, 25 percent", "a.bin, 50 percent", "a.bin, 75 percent", "a.bin finished"], "\(spoken)")
  }

  @Test func `a failure is announced once`() {
    let (engine, model) = make()
    var spoken: [String] = []
    model.onAnnouncement = { spoken.append($0) }
    let id = start(engine, "a.bin")
    engine.interruptDownload(id, reason: .networkDisconnected)
    #expect(spoken == ["a.bin failed"])
  }

  // MARK: Location

  @Test func `a missing folder is reported once and the file goes to the default folder`() {
    let (engine, model) = make()
    var notices: [String] = []
    model.onNotice = { notices.append($0) }
    engine.downloadSavePreference = .folder(engine.downloadDefaultFolder.appending(path: "gone-\(UUID().uuidString)"))
    start(engine, "a.bin")
    let name = engine.downloadDefaultFolder.lastPathComponent
    #expect(notices == ["Saved to \(name). The chosen folder is unavailable."], "\(notices)")
  }

  @Test func `the saved location reaches the engine at once and on every change`() {
    let settings = AppSettings.ephemeral()
    let (engine, model) = make(settings: settings)
    defer { withExtendedLifetime(model) {} }
    #expect(engine.downloadSavePreference == .folder(engine.downloadDefaultFolder))
    let folder = URL(filePath: "/tmp/arkt-chosen", directoryHint: .isDirectory)
    settings.downloadLocation = DownloadLocationSetting(asksWhereToSave: false, folder: folder)
    #expect(engine.downloadSavePreference == .folder(folder))
    settings.downloadLocation = DownloadLocationSetting(asksWhereToSave: true, folder: folder)
    #expect(engine.downloadSavePreference == .ask)
  }
}
