import Foundation
import Testing

// `EnvironmentOverrides` is the app target's file (`App/EnvironmentOverrides.swift`), compiled here through the
// symlink next to this file: the app has no test target, and the parsing is pure.

@Suite struct EnvironmentOverridesTests {
  private let bundleIdentifier = "dev.arkt.ArktShell"

  private func overrides(_ environment: [String: String]) -> EnvironmentOverrides {
    EnvironmentOverrides(environment: environment)
  }

  private var complete: [String: String] {
    [
      "ARKT_UITEST": "1",
      "ARKT_DATA_DIR": "/tmp/arkt-uitest/data",
      "ARKT_ARC_DIR": "/tmp/arkt-uitest/arc",
      "ARKT_DEFAULTS_SUITE": "dev.arkt.uitest.sandbox",
    ]
  }

  // MARK: - Strict UI-test mode

  @Test func uiTestModeOnlyForTheValueOne() {
    #expect(overrides(["ARKT_UITEST": "1"]).isUITest)
    #expect(!overrides([:]).isUITest)
    #expect(!overrides(["ARKT_UITEST": "0"]).isUITest)
    #expect(!overrides(["ARKT_UITEST": "true"]).isUITest)
    #expect(!overrides(["ARKT_UITEST": ""]).isUITest)
  }

  @Test func everyOverrideMissingIsReportedInKeyOrder() {
    #expect(overrides(["ARKT_UITEST": "1"]).missingUITestOverrides(bundleIdentifier: bundleIdentifier)
      == ["ARKT_DATA_DIR", "ARKT_ARC_DIR", "ARKT_DEFAULTS_SUITE"])
  }

  @Test func nothingMissingWhenEveryOverrideIsSet() {
    #expect(overrides(complete).missingUITestOverrides(bundleIdentifier: bundleIdentifier).isEmpty)
  }

  @Test func onlyTheMissingKeyIsReported() {
    var environment = complete
    environment["ARKT_ARC_DIR"] = nil
    #expect(overrides(environment).missingUITestOverrides(bundleIdentifier: bundleIdentifier) == ["ARKT_ARC_DIR"])
  }

  @Test func anEmptyValueCountsAsMissing() {
    var environment = complete
    environment["ARKT_DATA_DIR"] = ""
    #expect(overrides(environment).missingUITestOverrides(bundleIdentifier: bundleIdentifier) == ["ARKT_DATA_DIR"])
  }

  /// A suite named after the app's own domain or the global domain would write the real defaults.
  @Test func aSuiteThatResolvesToTheRealDefaultsCountsAsMissing() {
    for name in [bundleIdentifier, "NSGlobalDomain"] {
      var environment = complete
      environment["ARKT_DEFAULTS_SUITE"] = name
      #expect(overrides(environment).missingUITestOverrides(bundleIdentifier: bundleIdentifier)
        == ["ARKT_DEFAULTS_SUITE"])
    }
  }

  // MARK: - Defaults suite

  @Test func suiteNameIsReadWhenSet() {
    #expect(overrides(complete).defaultsSuiteName == "dev.arkt.uitest.sandbox")
    #expect(overrides([:]).defaultsSuiteName == nil)
    #expect(overrides(["ARKT_DEFAULTS_SUITE": ""]).defaultsSuiteName == nil)
  }

  @Test func usableSuiteNames() {
    #expect(EnvironmentOverrides.isUsableSuiteName("dev.arkt.uitest.sandbox", bundleIdentifier: bundleIdentifier))
    #expect(!EnvironmentOverrides.isUsableSuiteName(bundleIdentifier, bundleIdentifier: bundleIdentifier))
    #expect(!EnvironmentOverrides.isUsableSuiteName("NSGlobalDomain", bundleIdentifier: bundleIdentifier))
    #expect(!EnvironmentOverrides.isUsableSuiteName("", bundleIdentifier: bundleIdentifier))
  }

  // MARK: - Autosave delay

  @Test func autosaveDelayParsesMilliseconds() {
    #expect(overrides(["ARKT_AUTOSAVE_DELAY_MS": "0"]).autosaveDelay == .zero)
    #expect(overrides(["ARKT_AUTOSAVE_DELAY_MS": "250"]).autosaveDelay == .milliseconds(250))
    #expect(overrides(["ARKT_AUTOSAVE_DELAY_MS": "600000"]).autosaveDelay == .milliseconds(600_000))
  }

  @Test func autosaveDelayIsNilWhenUnsetOrInvalid() {
    for value in ["600001", "-1", "abc", "", " 250", "2.5"] {
      #expect(overrides(["ARKT_AUTOSAVE_DELAY_MS": value]).autosaveDelay == nil, "value \(value)")
    }
    #expect(overrides([:]).autosaveDelay == nil)
  }
}
