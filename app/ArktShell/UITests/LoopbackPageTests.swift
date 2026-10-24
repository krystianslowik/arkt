import XCTest

/// Pages come from the test runner's loopback server and load in the engine (infrastructure, no parity row).
final class LoopbackPageTests: ArktUITestCase {
  func test_E_loopbackPageLoadsInTheEngine() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())

    // Cmd-T on an empty profile creates the first Space, then the tab (decision 3).
    app.typeKey("t", modifierFlags: .command)
    let field = app.textFields[AXID.CommandBar.field]
    XCTAssertTrue(waitFor(field))
    field.typeText(server.page("alpha"))
    field.typeKey(.return, modifierFlags: [])

    // The sidebar row (`sidebar.row.today`, U4b #168) takes the page's title once the page has loaded.
    let title = FixtureServer.title(ofPage: "alpha")
    let row = app.outlineRows[AXID.Sidebar.rowToday].firstMatch
    XCTAssertTrue(Waits.until("/p/alpha requested from the loopback server", { server.requestedPaths.contains("/p/alpha") }),
                  "\(server.requestedPaths)")
    waitForOutlineRows("\(row) label \(title)") { row.exists && row.label == title }
  }
}
