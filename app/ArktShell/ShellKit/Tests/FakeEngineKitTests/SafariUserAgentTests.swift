import Testing
@testable import FakeEngineKit

struct SafariUserAgentTests {
  @Test func usesTheGivenSafariVersion() {
    let name = SafariUserAgent.applicationName(safariVersion: "26.1")
    #expect(name == "Version/26.1 Safari/605.1.15")
  }

  @Test func fallsBackWhenTheVersionIsMissingOrMalformed() {
    let fallback = "Version/\(SafariUserAgent.fallbackVersion) Safari/605.1.15"
    #expect(SafariUserAgent.applicationName(safariVersion: nil) == fallback)
    #expect(SafariUserAgent.applicationName(safariVersion: "") == fallback)
    #expect(SafariUserAgent.applicationName(safariVersion: "27.0 beta") == fallback)
    #expect(SafariUserAgent.applicationName(safariVersion: "27..0") == fallback)
  }

  @Test func installedSafariProducesSafariTokens() {
    let name = SafariUserAgent.applicationName()
    #expect(name.contains("Version/"))
    #expect(name.contains("Safari/"))
    #expect(name.range(of: #"^Version/\d+(\.\d+)* Safari/605\.1\.15$"#, options: .regularExpression) != nil, "\(name)")
  }

  @Test func readsTheVersionOfTheInstalledSafari() throws {
    // Every supported macOS ships Safari; the dev engine must find it rather than use the fallback.
    let version = try #require(SafariUserAgent.installedSafariVersion())
    #expect(SafariUserAgent.isValidVersion(version), "\(version)")
  }
}
