import XCTest

/// Exercises the real app composition and the approved Spaces and Profiles routing entry points.
final class LinkRoutingSettingsTests: ArktUITestCase {
  func testFreshRoutingControlsAreAvailableAndSettingsKeyboardNavigationWorks() throws {
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    app.typeKey(",", modifierFlags: [.command])
    let settings = app.windows[AXID.Settings.window]
    XCTAssertTrue(waitFor(settings))
    app.typeKey("2", modifierFlags: [.command])
    let destination = Shell.element(app, AXID.Settings.control("spaces", "linksFromOtherApps"))
    let add = Shell.element(app, AXID.Settings.control("spaces", "addRoute"))
    XCTAssertTrue(waitFor(destination))
    XCTAssertTrue(waitFor(add))
    XCTAssertTrue(destination.isEnabled)
    XCTAssertEqual(destination.label, "Links from other apps open in")
    XCTAssertEqual(destination.value as? String, "Little Arkt")
    XCTAssertTrue(add.isEnabled)
    XCTAssertEqual(add.label, "Add Route")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(waitUntilGone(settings))
  }
}
