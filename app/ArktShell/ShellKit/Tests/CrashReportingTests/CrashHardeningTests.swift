import Foundation
import Synchronization
import Testing
@testable import CrashReporting

/// Review fixes on #457: private storage, the production redaction wiring, the exception hook chain.
struct CrashHardeningTests {
  private let epoch = Date(timeIntervalSince1970: 2_000_000_000)

  // MARK: Permissions

  @Test func theFolderIsOwnerOnlyAndEachFileIsOwnerReadWrite() throws {
    let store = CrashReportStore(directory: CrashFixtures.makeDirectory(), now: { epoch })
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let report = CrashFixtures.stripper.report(from: CrashFixtures.raw(at: epoch), id: "aaaa-1")
    let previous = umask(0)                       // a permissive umask must not widen anything
    defer { umask(previous) }
    try store.save(report)
    #expect(try mode(store.directory) == 0o700)
    let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
    #expect(files == ["aaaa-1.json"], "no temporary file is left behind")
    #expect(try mode(store.directory.appendingPathComponent("aaaa-1.json")) == 0o600)
  }

  private func mode(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? Int)
  }

  // MARK: Redaction wiring

  @Test func aSeededSpaceNameIsStrippedThroughTheProductionRecorder() throws {
    let store = CrashReportStore(directory: CrashFixtures.makeDirectory(), now: { epoch })
    defer { try? FileManager.default.removeItem(at: store.directory) }
    let redactions = CrashRedactions()
    let recorder = CrashReportRecorder.production(
      store: store, homeDirectory: CrashFixtures.home, userName: CrashFixtures.userName, redactions: redactions,
      consent: { (enabled: true, asked: true) }, markAsked: {})
    var raw = CrashFixtures.raw(at: epoch)
    raw.frames = [RawFrame(image: "Img", offset: 1, symbol: "open \(CrashFixtures.spaceName) / \(CrashFixtures.profileName)")]
    #expect(recorder.record(raw)?.frames.first?.symbol?.contains(CrashFixtures.spaceName) == true,
            "nothing is redacted until the app supplies the names")
    redactions.update([CrashFixtures.spaceName, CrashFixtures.profileName])   // what the app does from the sidebar
    let report = try #require(recorder.record(raw))
    let json = try String(decoding: JSONEncoder().encode(report), as: UTF8.self)
    #expect(!json.contains(CrashFixtures.spaceName))
    #expect(!json.contains(CrashFixtures.profileName))
    let onDisk = try String(contentsOf: store.directory.appendingPathComponent("\(report.id).json"), encoding: .utf8)
    #expect(!onDisk.contains(CrashFixtures.spaceName))
  }

  // MARK: Exception hook

  private static let previousCalls = Mutex(0)
  private static let previous: UncaughtHandlerChain.Handler = { _ in previousCalls.withLock { $0 += 1 } }
  private static let other: UncaughtHandlerChain.Handler = { _ in }

  private struct RecordFailure: Error {}

  @Test func installIsIdempotentAndTheChainAlwaysReachesThePreviousHandler() {
    let chain = UncaughtHandlerChain()
    #expect(chain.install(previous: Self.previous))
    #expect(!chain.install(previous: Self.other), "a second install does nothing")
    let before = Self.previousCalls.withLock { $0 }
    let recorded = Mutex(0)
    chain.handle(NSException(name: .genericException, reason: nil)) { recorded.withLock { $0 += 1 } }
    chain.handle(NSException(name: .genericException, reason: nil)) { throw RecordFailure() }
    #expect(recorded.withLock { $0 } == 1)
    #expect(Self.previousCalls.withLock { $0 } - before == 2, "the first previous handler ran, also after a failure")
  }
}
