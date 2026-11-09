import XCTest

/// A sidebar row's context menu is reachable by title through app-wide accessibility queries (#860), the way the
/// sidebar URL bar's menu is (`ToolbarTests`). The menu hangs off the view it is shown for; it used to be shown for
/// the real outline, which the proxy outline stands in for, so the open menu was on screen but its items were not in
/// the tree.
final class SidebarRowMenuTests: ArktUITestCase {
  /// The first hittable menu item titled `title`: an open context menu's item, not a closed menu bar item.
  private func hittableMenuItem(_ title: String, in app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) -> XCUIElement? {
    let items = app.menuItems.matching(NSPredicate(format: "title == %@", title))
    var item: XCUIElement?
    let found = Waits.until("a hittable \(title) menu item", file: file, line: line) {
      item = items.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
      return item != nil
    }
    return found ? item : nil
  }

  func test_sidebarRowRightClickMenuItemsAreQueryableByTitle() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    let title = FixtureServer.title(ofPage: "alpha")
    let rows = Shell.todayRows(app).matching(NSPredicate(format: "label == %@", title))
    waitForOutlineRows("one \(title) row") { rows.count == 1 }

    rows.element(boundBy: 0).rightClick()
    let duplicate = try XCTUnwrap(hittableMenuItem("Duplicate", in: app), "the row menu's Duplicate item")
    duplicate.click()

    waitForOutlineRows("two \(title) rows after Duplicate") { rows.count == 2 }
  }

  /// Ctrl-click is a secondary click (#277): the same menu, reachable the same way.
  func test_sidebarRowControlClickMenuItemsAreQueryableByTitle() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    waitForOutlineRows("\(row) to exist") { row.exists }

    XCUIElement.perform(withKeyModifiers: .control) { row.click() }
    let archiveBelow = try XCTUnwrap(hittableMenuItem("Archive Below", in: app), "the row menu's Archive Below item")
    XCTAssertTrue(archiveBelow.isHittable)

    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(waitUntilGone(archiveBelow))
  }
}
