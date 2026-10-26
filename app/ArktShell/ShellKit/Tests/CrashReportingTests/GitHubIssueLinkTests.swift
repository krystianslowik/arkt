import Foundation
import Testing
@testable import CrashReporting

/// The prefilled GitHub issue (#129): opening a URL is the only hand-off, so it must fit URL length limits; a long
/// stack is cut and the issue says so.
struct GitHubIssueLinkTests {
  private func report(frames: Int) -> CrashReport {
    let raw = (0..<frames).map {
      RawFrame(image: "ArktShell", offset: 4096 + $0, symbol: "ArktShell.SomeLongTypeName.someFairlyLongMethodName\($0)(argument:)")
    }
    return CrashFixtures.stripper.report(from: CrashFixtures.raw(frames: raw), id: "33333333-3333-3333-3333-333333333333")
  }

  private func query(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
  }

  @Test func pointsAtTheNewIssueFormOfTheProjectRepository() throws {
    let link = GitHubIssueLink.make(for: report(frames: 3))
    let components = try #require(URLComponents(url: link.url, resolvingAgainstBaseURL: false))
    #expect(components.scheme == "https")
    #expect(components.host == "github.com")
    #expect(components.path == "/krystianslowik/arkt/issues/new")
  }

  @Test func theBodyCarriesTheAllowedFieldsAndTheStack() throws {
    let link = GitHubIssueLink.make(for: report(frames: 3))
    let body = try #require(query(link.url, "body"))
    #expect(body.contains("33333333-3333-3333-3333-333333333333"))
    #expect(body.contains("EXC_BAD_ACCESS (SIGSEGV)"))
    #expect(body.contains("0.1.0"))
    #expect(body.contains("arm64"))
    #expect(body.contains("142.0.7444.0"))
    #expect(body.contains("someFairlyLongMethodName0"))
    #expect(try #require(query(link.url, "title")).contains("33333333"))
    #expect(!link.truncated)
    #expect(link.shownFrames == 3 && link.totalFrames == 3)
    #expect(!body.contains("truncated"))
  }

  @Test func aShortReportIsNeverTruncated() {
    let link = GitHubIssueLink.make(for: report(frames: 20))
    #expect(!link.truncated)
    #expect(link.url.absoluteString.count <= GitHubIssueLink.defaultMaxLength)
  }

  @Test func aLongStackIsCutToFitAndTheBodySaysSo() throws {
    let long = report(frames: CrashReportStripper.maximumFrames)
    let link = GitHubIssueLink.make(for: long, maxLength: 3_000)
    #expect(link.url.absoluteString.count <= 3_000)
    #expect(link.truncated)
    #expect(link.shownFrames < link.totalFrames)
    #expect(link.shownFrames > 0)
    let body = try #require(query(link.url, "body"))
    #expect(body.contains("Stack truncated: showing \(link.shownFrames) of \(link.totalFrames) frames"))
    #expect(body.contains("someFairlyLongMethodName0("), "the top of the stack is kept")
    #expect(!body.contains("someFairlyLongMethodName\(link.totalFrames - 1)("), "the bottom is what goes")
  }

  @Test func theLengthLimitHoldsAtEveryBudget() {
    let long = report(frames: 200)
    for limit in stride(from: 1_200, through: 8_000, by: 350) {
      let link = GitHubIssueLink.make(for: long, maxLength: limit)
      #expect(link.url.absoluteString.count <= limit, "limit \(limit)")
    }
  }

  @Test func theDefaultLimitIsSafeForBrowsersAndGitHub() {
    #expect(GitHubIssueLink.defaultMaxLength <= 8_000)
    let link = GitHubIssueLink.make(for: report(frames: CrashReportStripper.maximumFrames))
    #expect(link.url.absoluteString.count <= GitHubIssueLink.defaultMaxLength)
  }

  @Test func reservedCharactersInSymbolsSurviveTheTripThroughTheURL() throws {
    let raw = [RawFrame(image: "Img", offset: 1, symbol: "a&b=c+d#e?f %20 <T> [x]")]
    let report = CrashFixtures.stripper.report(from: CrashFixtures.raw(frames: raw), id: "x")
    let body = try #require(query(GitHubIssueLink.make(for: report).url, "body"))
    #expect(body.contains("a&b=c+d#e?f %20 <T> [x]"))
  }
}
