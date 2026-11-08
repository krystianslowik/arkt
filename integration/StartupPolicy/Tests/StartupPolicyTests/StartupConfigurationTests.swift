import Foundation
import Testing

@Suite struct StartupConfigurationTests {
  let values = ["ARKT_UITEST": "1", "ARKT_DATA_DIR": "/synthetic/data", "ARKT_ARC_DIR": "/synthetic/arc",
                "ARKT_DEFAULTS_SUITE": "synthetic.suite", "ARKT_SKIP_ONBOARDING": "",
                "ARKT_TEST_IDENTITY_ENDPOINT": "http://127.0.0.1:1234/identity/0123456789abcdef0123456789abcdef"]

  @Test func mergesOnlyValidatedCarrierAndPreservesUnrelatedValues() throws {
    let arg = try LaunchArgumentCarrier.encode(values, bundleIdentifier: "org.example.app")
    let configuration = try StartupConfiguration.resolve(arguments: [arg], environment: ["PRIVATE": "value"],
                                                          required: true, bundleIdentifier: "org.example.app")
    #expect(configuration.environment == values.merging(["PRIVATE": "value"]) { first, _ in first })
    #expect(configuration.environment["ARKT_DEFAULT_BROWSER"] == nil)
  }

  @Test func noCarrierLeavesEnvironmentUnchanged() throws {
    let environment = ["ARKT_UITEST": "1", "PRIVATE": "value", "ARKT_DEFAULT_BROWSER": ""]
    let configuration = try StartupConfiguration.resolve(arguments: ["app", "--unrelated"], environment: environment,
                                                          required: false, bundleIdentifier: "org.example.app")
    #expect(configuration.environment == environment)
  }

  @Test func explicitCarrierRejectsConflictOmissionAndMissingAuthority() throws {
    let arg = try LaunchArgumentCarrier.encode(values, bundleIdentifier: "org.example.app")
    for environment in [["ARKT_DATA_DIR": "/different"], ["ARKT_DEFAULT_BROWSER": ""]] {
      #expect(throws: (any Error).self) {
        try StartupConfiguration.resolve(arguments: [arg], environment: environment, required: true,
                                         bundleIdentifier: "org.example.app")
      }
    }
    #expect(throws: (any Error).self) {
      try StartupConfiguration.resolve(arguments: [arg], environment: [:], required: false,
                                       bundleIdentifier: "org.example.app")
    }
    #expect(throws: (any Error).self) {
      try StartupConfiguration.resolve(arguments: ["--arkt-ui-test-config=bad"], environment: [:], required: true,
                                       bundleIdentifier: "org.example.app")
    }
  }
}
