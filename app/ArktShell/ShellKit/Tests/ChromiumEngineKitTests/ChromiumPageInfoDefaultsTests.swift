import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Until the engine side of the page info seam lands (#583), ChromiumEngine keeps the `EngineClient` default (#582):
/// no site settings, so the shell offers no page info panel, and rule 26 reports itself not applicable.
@MainActor
struct ChromiumPageInfoDefaultsTests {
  @Test func hasNoSiteSettingsUntilTheFacadeReportsPageInfo() {
    let engine = ChromiumEngine(facade: ScriptedFacade())
    #expect(engine.siteSettings == nil)
  }

  @Test func rule26IsNotApplicable() async throws {
    await #expect(throws: ContractNotApplicable.self) {
      try await EngineContract.pageInfoNamesTheSiteItShows(ScriptedHarness.make())
    }
  }
}
