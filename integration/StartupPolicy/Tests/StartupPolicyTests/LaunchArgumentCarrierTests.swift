import Foundation
import Testing

@Suite struct LaunchArgumentCarrierTests {
  let endpoint = "http://127.0.0.1:1234/identity/0123456789abcdef0123456789abcdef"
  var config: [String: String] {
    ["ARKT_UITEST": "1", "ARKT_DATA_DIR": "/synthetic/data", "ARKT_ARC_DIR": "/synthetic/arc",
     "ARKT_DEFAULTS_SUITE": "synthetic.suite", "ARKT_TEST_IDENTITY_ENDPOINT": endpoint]
  }
  func wire(_ pairs: [[String]], version: String = "v1") throws -> String {
    "--arkt-ui-test-config=\(version):" + (try JSONEncoder().encode(pairs)).base64EncodedString()
  }
  func decode(_ args: [String], _ env: [String: String] = [:], required: Bool = true) throws -> [String: String]? {
    try LaunchArgumentCarrier.decode(arguments: args, environment: env, required: required, bundleIdentifier: "org.example.app")
  }

  @Test func roundTripAndOptionalSemantics() throws {
    var values = config
    values["ARKT_SKIP_ONBOARDING"] = ""
    let arg = try LaunchArgumentCarrier.encode(values, bundleIdentifier: "org.example.app")
    #expect(try decode(["app", "--other", arg], ["PRIVATE": "untouched"]) == values)
    let decoded = try decode([arg])
    #expect(try TestIdentity.digest(#require(decoded)) == TestIdentity.digest(values))
    #expect(try decode([arg], values) == values)
    #expect(try decode(["app"], ["ARKT_UITEST": "1"], required: false) == nil)
  }

  @Test func requiresIndependentAuthorityAndRejectsConflicts() throws {
    let arg = try LaunchArgumentCarrier.encode(config, bundleIdentifier: "org.example.app")
    #expect(throws: (any Error).self) { try decode([arg], required: false) }
    for (key, value) in config {
      #expect(throws: (any Error).self) { try decode([arg], [key: value + "x"]) }
    }
    #expect(throws: (any Error).self) { try decode([arg], ["ARKT_SKIP_ONBOARDING": ""]) }
    #expect(throws: (any Error).self) { try decode([arg, arg]) }
    #expect(throws: (any Error).self) { try decode(["--arkt-ui-test-config"]) }
  }

  @Test func rejectsInvalidConfigurations() throws {
    for key in config.keys {
      var values = config
      values.removeValue(forKey: key)
      #expect(throws: (any Error).self) { try LaunchArgumentCarrier.encode(values, bundleIdentifier: "org.example.app") }
      values = config
      values[key] = ""
      #expect(throws: (any Error).self) { try LaunchArgumentCarrier.encode(values, bundleIdentifier: "org.example.app") }
    }
    for (key, value) in [("ARKT_UITEST", "0"), ("ARKT_DEFAULTS_SUITE", "org.example.app"),
                         ("ARKT_DEFAULTS_SUITE", ".hidden"), ("ARKT_TEST_IDENTITY_ENDPOINT", "http://localhost:1234/"),
                         ("ARKT_DATA_DIR", "a\0b"), ("ARKT_DATA_DIR", String(repeating: "x", count: 5000)),
                         ("INJECTED", "value")] {
      var values = config
      values[key] = value
      #expect(throws: (any Error).self) { try LaunchArgumentCarrier.encode(values, bundleIdentifier: "org.example.app") }
    }
  }

  @Test func rejectsMalformedWire() throws {
    let pairs = config.sorted { $0.key < $1.key }.map { [$0.key, $0.value] }
    for arg in [try wire(pairs, version: "v2"), try wire(pairs + [pairs[0]]),
                try wire(pairs + [["UNKNOWN", "x"]]), try wire(pairs + [["ARKT_UITEST"]]),
                "--arkt-ui-test-config=v1:!!!", "--arkt-ui-test-config=v1:",
                "--arkt-ui-test-config-extra=x"] {
      #expect(throws: (any Error).self) { try decode([arg]) }
    }
  }
}
