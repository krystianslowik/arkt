import XCTest

/// Little Arkt end to end (#356, docs/design/little-arkt.md): Opt-Cmd-click on a link opens it in a Little Arkt window
/// (BH-132, GS-028, on by default), Open in moves the page into the Space as a Today row (KB-076, BH-136), Cmd-W closes
/// the window (KB-080), and the chooser's Open in New Window moves the page into a new browser window.
///
/// The Dock menu has no XCUITest handle (it belongs to the Dock process); its rows are covered by
/// `LittleArktMenusTests` in ShellKitGUITests.
final class LittleArktTests: ArktUITestCase {
  /// Opens `/p/alpha` as a Today tab, Opt-Cmd-clicks its link and returns the app and the Little Arkt window.
  @MainActor
  private func openLittleArkt(_ server: FixtureServer) throws -> (XCUIApplication, XCUIElement) {
    let app = try launch(try Sandbox())
    app.activate()
    XCTAssertTrue(waitFor(app, .runningForeground), "the app is frontmost before any key")
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    let source = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    XCTAssertTrue(waitForOutlineRows("the page is a Today row") { source.exists })

    let window = shellWindow(of: app)
    let link = window.webViews.firstMatch.links["Next"]
    XCTAssertTrue(waitFor(link))
    XCTAssertTrue(Waits.until("the fixture link to be interactive") { link.exists && link.isHittable })
    XCUIElement.perform(withKeyModifiers: [.option, .command]) { link.click() }

    let little = app.windows[AXID.LittleArkt.window]
    XCTAssertTrue(waitFor(little), "Opt-Cmd-click opens a Little Arkt window (BH-132)")
    let host = little.descendants(matching: .any)[AXID.LittleArkt.host]
    XCTAssertTrue(waitFor(host))
    return (app, little)
  }

  /// The link opens in Little Arkt, not in the source tab and not as a new Today row (BH-132, GS-028).
  @MainActor
  func test_BH132_GS028_optionCommandClickOpensTheLinkInLittleArkt() async throws {
    let server = try await fixtureServer()
    let (app, _) = try openLittleArkt(server)
    XCTAssertEqual(Shell.todayRows(app).count, 1, "the link gets no Today row")
    let source = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    XCTAssertTrue(source.exists, "the source tab did not navigate")
  }

  /// Open in (Cmd-O): the page becomes the top Today row, selected, and the small window goes (KB-076, BH-136).
  @MainActor
  func test_KB076_BH136_openInMovesThePageIntoTheSpace() async throws {
    let server = try await fixtureServer()
    let (app, little) = try openLittleArkt(server)
    let open = little.buttons[AXID.LittleArkt.open]
    XCTAssertTrue(waitFor(open))
    open.click()
    XCTAssertTrue(waitUntilGone(little), "the Little Arkt window closes")

    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha-next"))
    XCTAssertTrue(waitForOutlineRows("the page as a selected Today row") { row.exists && row.isSelected })
  }

  /// Cmd-W closes the Little Arkt window; the main window keeps its tab (KB-080, BH-138).
  @MainActor
  func test_KB080_commandWClosesTheWindow() async throws {
    let server = try await fixtureServer()
    let (app, little) = try openLittleArkt(server)
    little.click()                                             // key: the window takes Cmd-W
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(waitUntilGone(little), "Cmd-W closes the Little Arkt window")
    XCTAssertEqual(Shell.todayRows(app).count, 1, "the source tab stays")
    XCTAssertTrue(shellWindow(of: app).exists, "the browser window stays")
  }

  /// The chooser lists Open in New Window; it moves the page into a second browser window as a Today row.
  @MainActor
  func test_chooserOpenInNewWindowMovesThePageIntoANewWindow() async throws {
    let server = try await fixtureServer()
    let (app, little) = try openLittleArkt(server)
    let chooser = little.buttons[AXID.LittleArkt.chooser]
    XCTAssertTrue(waitFor(chooser))
    chooser.click()
    let newWindow = app.menuItems["Open in New Window"]
    XCTAssertTrue(waitFor(newWindow), "the chooser lists Open in New Window")
    newWindow.click()
    XCTAssertTrue(waitUntilGone(little), "the Little Arkt window closes")

    let windows = app.windows.matching(identifier: AXID.Shell.window)
    XCTAssertTrue(Waits.until("a second browser window") { windows.count == 2 })
    let rows = Shell.todayRows(app).matching(NSPredicate(format: "label == %@",
                                                         FixtureServer.title(ofPage: "alpha-next")))
    XCTAssertTrue(waitForOutlineRows("the page as a Today row") { rows.count >= 1 })
  }
}
