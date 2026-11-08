import Foundation
import Testing

@Suite struct IdentityTests {
  let environment = ["ARKT_UITEST": "1", "ARKT_DATA_DIR": "/data", "ARKT_ARC_DIR": "/arc",
                     "ARKT_DEFAULTS_SUITE": "suite", "ARKT_SKIP_ONBOARDING": "1",
                     "ARKT_DEFAULT_BROWSER": "notDefault"]
  let nonce = "0123456789abcdef0123456789abcdef"

  @Test func digestUsesExactlyTheWhitelist() throws {
    let original = try TestIdentity.digest(environment)
    #expect(try TestIdentity.digest(Dictionary(uniqueKeysWithValues: environment.reversed())) == original)
    var changed = environment
    changed["UNRELATED"] = "ignored"
    #expect(try TestIdentity.digest(changed) == original)
    for key in TestIdentity.keys {
      changed = environment
      changed[key] = "different"
      #expect(try TestIdentity.digest(changed) != original)
    }
    for key in TestIdentity.keys.prefix(4) {
      changed = environment
      changed.removeValue(forKey: key)
      #expect(throws: (any Error).self) { try TestIdentity.digest(changed) }
    }
    changed = environment
    changed.removeValue(forKey: "ARKT_SKIP_ONBOARDING")
    #expect(try TestIdentity.digest(changed) != original)
  }

  @Test func validatesReportAndEndpoint() throws {
    let digest = try TestIdentity.digest(environment)
    #expect(TestIdentity.Report(nonce: nonce, pid: 42, required: true, digest: digest).isValid)
    #expect(!TestIdentity.Report(nonce: "bad", pid: 42, required: true, digest: digest).isValid)
    #expect(!TestIdentity.Report(nonce: nonce, pid: 0, required: true, digest: digest).isValid)
    #expect(!TestIdentity.Report(nonce: nonce, pid: 42, required: false, digest: digest).isValid)
    #expect(!TestIdentity.Report(nonce: nonce, pid: 42, required: true, digest: "").isValid)
    #expect(TestIdentity.endpoint("http://127.0.0.1:1234/identity/\(nonce)") != nil)
    for bad in ["http://localhost:1234/identity/\(nonce)", "http://127.0.0.1:1234/identity/../\(nonce)",
                "http://user@127.0.0.1:1234/identity/\(nonce)", "http://127.0.0.1:1234/identity/\(nonce)#x",
                "http://127.0.0.1:0/identity/\(nonce)", "https://127.0.0.1:1234/identity/\(nonce)",
                "http://127.0.0.1:1234/identity/\(nonce)?x=1", "http://127.0.0.1:1234/identity/%30\(nonce.dropFirst())"] {
      #expect(TestIdentity.endpoint(bad) == nil)
    }
    #expect(TestIdentity.acknowledged(status: 204, redirected: false))
    #expect(!TestIdentity.acknowledged(status: 200, redirected: false))
    #expect(!TestIdentity.acknowledged(status: 204, redirected: true))
  }

  @Test func absentRequestPreservesNormalLaunch() throws {
    #expect(try TestIdentity.request(environment: [:], required: false, pid: 1) == nil)
    #expect(throws: (any Error).self) {
      try TestIdentity.request(environment: ["ARKT_TEST_IDENTITY_ENDPOINT": "bad"], required: true, pid: 1)
    }
    var requested = environment
    requested[TestIdentity.endpointKey] = "http://127.0.0.1:1234/identity/\(nonce)"
    #expect(throws: (any Error).self) { try TestIdentity.request(environment: requested, required: false, pid: 1) }
    #expect(throws: (any Error).self) { try TestIdentity.request(environment: requested, required: true, pid: 0) }
  }
}
