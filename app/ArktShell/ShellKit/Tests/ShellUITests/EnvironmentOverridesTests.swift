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

  // MARK: - First run (onboarding)

  @Test func skipOnboardingOnlyForTheValueOne() {
    #expect(overrides(["ARKT_SKIP_ONBOARDING": "1"]).skipsOnboarding)
    #expect(!overrides([:]).skipsOnboarding)
    #expect(!overrides(["ARKT_SKIP_ONBOARDING": "0"]).skipsOnboarding)
  }

  /// A run that sets it never asks macOS: the check answers the given value and Make default only records the ask.
  @Test func defaultBrowserOverride() {
    #expect(overrides(["ARKT_DEFAULT_BROWSER": "default"]).defaultBrowser == .isDefault)
    #expect(overrides(["ARKT_DEFAULT_BROWSER": "notDefault"]).defaultBrowser == .notDefault)
    #expect(overrides([:]).defaultBrowser == nil)
    #expect(overrides(["ARKT_DEFAULT_BROWSER": "yes"]).defaultBrowser == nil)
  }

  /// A UI-test run never touches the real default browser, whatever it sets.
  @Test func uiTestModeFakesTheDefaultBrowser() {
    #expect(overrides(complete).defaultBrowser == .notDefault)
    var env = complete
    env["ARKT_DEFAULT_BROWSER"] = "default"
    #expect(overrides(env).defaultBrowser == .isDefault)
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

  /// A suite named after the app's own domain or the global domain (in any letter case) would write the real
  /// defaults; a name with a slash or a leading dot could address a file outside the preferences domain.
  @Test func aSuiteThatResolvesToTheRealDefaultsCountsAsMissing() {
    for name in [bundleIdentifier, "NSGlobalDomain", "DEV.ARKT.ArktShell", "nsglobaldomain", "dev/arkt", ".hidden"] {
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
    #expect(EnvironmentOverrides.isUsableSuiteName("dev.arkt.uitest.sandbox", bundleIdentifier: nil))
  }

  /// The defaults system matches domain names without regard to case, so a case variant is the same domain.
  @Test func suiteNamesDifferingOnlyInCaseFromTheRealDomainsAreUnusable() {
    for name in ["DEV.ARKT.ARKTSHELL", "dev.arkt.arktshell", "Dev.Arkt.ArktShell", "NSGLOBALDOMAIN",
                 "nsglobaldomain", "NsGlobalDomain"] {
      #expect(!EnvironmentOverrides.isUsableSuiteName(name, bundleIdentifier: bundleIdentifier), "name \(name)")
    }
    #expect(!EnvironmentOverrides.isUsableSuiteName("nsglobaldomain", bundleIdentifier: nil))
  }

  /// A slash makes the name a path (an absolute one is read as a plist file), and a leading dot names a hidden
  /// file or a relative path such as `..`.
  @Test func suiteNamesThatLookLikePathsAreUnusable() {
    for name in ["/tmp/arkt", "dev/arkt", "../dev.arkt", "dev.arkt/", ".", "..", ".hidden", ".dev.arkt.uitest"] {
      #expect(!EnvironmentOverrides.isUsableSuiteName(name, bundleIdentifier: bundleIdentifier), "name \(name)")
    }
    #expect(EnvironmentOverrides.isUsableSuiteName("dev.arkt.uitest.sandbox.", bundleIdentifier: bundleIdentifier),
            "a dot elsewhere is fine")
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
