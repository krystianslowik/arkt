import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// A delegate that records every seam, as the app's composition root will implement them.
@MainActor
final class RecordingDelegate: ChromiumEmbedderDelegate {
  var log: [String] = []
  var failStart = false
  var hosts: [StubWindowHost] = []
  var started: ChromiumEngine?

  struct Failure: Error {}

  func start(engine: ChromiumEngine) async throws {
    started = engine
    log.append("start")
    try await Task.sleep(for: .milliseconds(20))
    if failStart { throw Failure() }
  }

  func startFailed(_ error: any Error) {
    log.append("startFailed modal=\(NSApp?.modalWindow != nil) mode=\(RunLoop.current.currentMode?.rawValue ?? "none")")
  }

  func host(for request: EngineWindowRequest, in engine: ChromiumEngine) -> any EngineWindowHosting {
    log.append("host \(request.kind)")
    let host = StubWindowHost()
    hosts.append(host)
    return host
  }

  func engineWillBeginTerminating() { log.append("willBegin") }
  func engineDidCancelTerminating() { log.append("didCancel") }

  func engineWillTerminate() async {
    try? await Task.sleep(for: .milliseconds(20))
    log.append("flushed")
  }
}

/// The typed embedder (Decision 1, 2 and 13). The embedder is a process-wide singleton, so these run one at a time.
@MainActor
@Suite(.serialized)
struct ArktShellEmbedderTests {
  @Test func theHookFindsTheEmbedderByName() throws {
    let found: AnyClass = try #require(NSClassFromString("ArktShellEmbedder"))
    #expect(ChromiumEmbedding.embedderClassName == "ArktShellEmbedder")
    #expect(class_conformsToProtocol(found, ArktEngineEmbedder.self))
    let embedder = try #require(found as? any ArktEngineEmbedder.Type)
    #expect(embedder.sharedEmbedder() === ArktShellEmbedder.shared)
  }

  @Test func readyAfterTheShellStartedThenWindowRequestsReachTheDelegate() async throws {
    let delegate = RecordingDelegate()
    ChromiumEmbedding.install(delegate)
    let facade = ScriptedFacade()
    ArktShellEmbedder.shared.engineDidStart(facade)
    let engine = try #require(ChromiumEmbedding.engine)
    #expect(!facade.ready, "embedderReady waits for the shell's start")
    try await EngineContract.waitUntil(timeout: .seconds(5)) { facade.ready }
    #expect(delegate.started === engine && delegate.log == ["start"])

    facade.hostProvider = { ArktShellEmbedder.shared.host(for: $0) }
    facade.openEngineWindow(ScriptedRequest(kind: .startupURL, initialURL: URL(string: "arkt-test://page.test/S")))
    #expect(delegate.log.last == "host startupURL")
    try await EngineContract.waitUntil(timeout: .seconds(5)) { engine.windowIDs.count == 1 }
    #expect(engine.host(of: engine.windowIDs[0]) === delegate.hosts.first)

    let other = try #require(ChromiumEmbedding.makeEngine())
    #expect(other !== engine && other.windowIDs.isEmpty, "a further instance lists none of the first one's windows")
  }

  @Test func aFailedStartReportsEmbedderFailedFromARunLoopCallout() async throws {
    let delegate = RecordingDelegate()
    delegate.failStart = true
    ChromiumEmbedding.install(delegate)
    let facade = ScriptedFacade()
    ArktShellEmbedder.shared.engineDidStart(facade)
    try await EngineContract.waitUntil(timeout: .seconds(5)) { facade.failed }
    #expect(!facade.ready)
    try await EngineContract.waitUntil(timeout: .seconds(5)) { delegate.log.count == 2 }
    #expect(delegate.log.last?.hasPrefix("startFailed") == true)
  }

  @Test func quitSeamsReachTheDelegateAndTheCompletionWaitsForTheFlush() async throws {
    let delegate = RecordingDelegate()
    ChromiumEmbedding.install(delegate)
    let embedder = ArktShellEmbedder.shared
    embedder.engineWillBeginTerminating()
    embedder.engineDidCancelTerminating()
    var completed = false
    embedder.engineWillTerminate { completed = true }
    #expect(!completed)
    try await EngineContract.waitUntil(timeout: .seconds(5)) { completed }
    #expect(delegate.log == ["willBegin", "didCancel", "flushed"])
  }
}
