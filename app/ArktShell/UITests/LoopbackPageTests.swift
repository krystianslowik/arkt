import XCTest

/// Pages come from the test runner's loopback server and load in the engine (infrastructure, no parity row).
final class LoopbackPageTests: ArktUITestCase {
  func test_E_loopbackPageLoadsInTheEngine() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())

    // Cmd-T on an empty profile creates the first Space, then the tab (decision 3).
    app.typeKey("t", modifierFlags: .command)
    let field = app.textFields["commandBar.field"]
    XCTAssertTrue(waitFor(field))
    field.typeText(server.page("alpha"))
    field.typeKey(.return, modifierFlags: [])

    // The sidebar row takes the page's title once the page has loaded. Until `sidebar.row.today` lands (U4b, #168)
    // the row is found as the title text inside the sidebar outline.
    let title = FixtureServer.title(ofPage: "alpha")
    let row = app.outlines.firstMatch.staticTexts
      .matching(NSPredicate(format: "value == %@ OR label == %@", title, title)).firstMatch
    XCTAssertTrue(waitFor(row))
    XCTAssertTrue(server.requestedPaths.contains("/p/alpha"), "\(server.requestedPaths)")
  }
}
