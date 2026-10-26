import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import FakeEngineKit

/// FakeEngine asks its window host about link clicks in a page (#313), as the Chromium engine does through its
/// navigation throttle: a cancel leaves the page where it was, a navigate lets the link load.
@MainActor
final class FakeEngineLinkActivationTests: XCTestCase {
  private final class Host: EngineWindowHosting {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                          backing: .buffered, defer: true)
    let cardView = NSView()
    var forward: EngineCommandForwarding?
    var onCloseRequested: (@MainActor () -> Void)?
    var decision: EngineLinkDecision = .cancel
    var activations: [EngineLinkActivation] = []
    func claim(_ command: EngineCommand) -> CommandClaim? { nil }
    func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool { false }
    func decideLinkActivation(_ activation: EngineLinkActivation) -> EngineLinkDecision {
      activations.append(activation)
      return decision
    }
  }

  private var server: LoopbackServer!

  override func setUp() async throws {
    _ = NSApplication.shared
    server = try await LoopbackServer.start(routes: [
      "/a": .init(mime: "text/html", body: Data("""
        <!doctype html><title>A</title><a id="out" href="/b">B</a>
        """.utf8)),
      "/b": .init(mime: "text/html", body: Data("<!doctype html><title>B</title>".utf8)),
    ])
  }

  override func tearDown() async throws { server.stop() }

  private func page(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(server.port)\(path)")! }

  private func clickLink(decision: EngineLinkDecision) async throws -> (FakeEngine, Host, TabID) {
    let engine = FakeEngine()
    let host = Host()
    host.decision = decision
    let tab = engine.createTab(url: page("/a"), in: engine.createWindow(host: host))
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.title == "A" }
    await engine.runScript("document.getElementById('out').click()", in: tab)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { !host.activations.isEmpty }
    return (engine, host, tab)
  }

  func testACancelledLinkLeavesThePageAndReportsTheActivation() async throws {
    let (engine, host, tab) = try await clickLink(decision: .cancel)
    let activation = try XCTUnwrap(host.activations.first)
    XCTAssertEqual(activation.url, page("/b"))
    XCTAssertEqual(activation.sourceTab, tab)
    XCTAssertEqual(activation.sourceURL, page("/a"))
    XCTAssertEqual(activation.disposition, .currentTab)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(engine.snapshot(of: tab)?.url, page("/a"))
  }

  func testANavigateAnswerLoadsTheLink() async throws {
    let (engine, _, tab) = try await clickLink(decision: .navigate)
    try await EngineContract.waitUntil(timeout: .seconds(10)) { engine.snapshot(of: tab)?.title == "B" }
    XCTAssertEqual(engine.snapshot(of: tab)?.url, page("/b"))
  }
}
