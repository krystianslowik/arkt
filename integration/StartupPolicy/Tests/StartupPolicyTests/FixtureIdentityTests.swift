import Foundation
import Testing

// The actual UI harness error is otherwise coupled to XCTest and AppKit.
struct HarnessError: Error { init(_ message: String) {} }

@Suite struct FixtureIdentityTests {
  @Test func acceptsOnlyTheArmedIdentity() async throws {
    let server = try await FixtureServer.start()
    defer { server.stop() }
    let nonce = "0123456789abcdef0123456789abcdef"
    let otherNonce = "1123456789abcdef0123456789abcdef"
    let environment = ["ARKT_UITEST": "1", "ARKT_DATA_DIR": "/data", "ARKT_ARC_DIR": "/arc",
                       "ARKT_DEFAULTS_SUITE": "suite"]
    let digest = try TestIdentity.digest(environment)
    server.armIdentity(nonce: nonce, digest: digest)
    let wrongNonce = TestIdentity.Request(url: URL(string: "\(server.base)/identity/\(otherNonce)")!,
      report: .init(nonce: otherNonce, pid: 42, required: true, digest: digest))
    await #expect(throws: (any Error).self) { try await TestIdentity.send(wrongNonce) }
    var wrong = environment
    wrong["ARKT_DATA_DIR"] = "/other"
    let wrongDigest = TestIdentity.Request(url: URL(string: "\(server.base)/identity/\(nonce)")!,
      report: .init(nonce: nonce, pid: 42, required: true, digest: try TestIdentity.digest(wrong)))
    await #expect(throws: (any Error).self) { try await TestIdentity.send(wrongDigest) }
    #expect(server.acceptedIdentity == nil)
    let correct = TestIdentity.Request(url: URL(string: "\(server.base)/identity/\(nonce)")!,
      report: .init(nonce: nonce, pid: 42, required: true, digest: digest))
    let invalid = TestIdentity.Request(url: URL(string: "\(server.base)/identity/\(nonce)")!,
      report: .init(nonce: nonce, pid: 0, required: true, digest: digest))
    await #expect(throws: (any Error).self) { try await TestIdentity.send(invalid) }
    var incomplete = URLRequest(url: invalid.url)
    incomplete.httpMethod = "POST"
    incomplete.httpBody = Data("{}".utf8)
    let (_, response) = try await URLSession.shared.data(for: incomplete)
    #expect((response as? HTTPURLResponse)?.statusCode == 403)
    let generic = TestIdentity.Request(url: URL(string: "\(server.base)/p/generic")!, report: correct.report)
    await #expect(throws: (any Error).self) { try await TestIdentity.send(generic) }
    #expect(server.acceptedIdentity == nil)
    try await TestIdentity.send(correct)
    #expect(server.acceptedIdentity == correct.report)
    await #expect(throws: (any Error).self) { try await TestIdentity.send(correct) }
    server.armIdentity(nonce: otherNonce, digest: digest)
    #expect(server.acceptedIdentity == nil)
    await #expect(throws: (any Error).self) { try await TestIdentity.send(correct) }
  }
}
