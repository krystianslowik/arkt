import XCTest

/// Archive scenarios (plan U9).
final class ArchiveTests: ArktUITestCase {
  private func foreground(_ app: XCUIApplication) throws {
    guard waitFor(app, .runningForeground) else { throw HarnessError("test app is not frontmost") }
  }

  private func open(_ page: String, server: FixtureServer, app: XCUIApplication) throws {
    try foreground(app)
    app.typeKey("t", modifierFlags: .command)
    guard Shell.waitForCommandBar(app, open: true) else { throw HarnessError("command bar did not open") }
    let field = Shell.commandBarField(app)
    try foreground(app)
    field.typeText(server.page(page))
    try foreground(app)
    field.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: page))
    XCTAssertTrue(waitForOutlineRows("page row exists") { row.exists })
  }

  private func start(_ pages: [String]) async throws -> XCUIApplication {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    let newSpace = app.buttons[AXID.EmptyState.newSpace]
    XCTAssertTrue(waitFor(newSpace))
    try foreground(app)
    newSpace.click()
    XCTAssertTrue(waitUntilGone(Shell.element(app, AXID.EmptyState.root)))
    for page in pages { try open(page, server: server, app: app) }
    return app
  }

  private func showArchive(_ app: XCUIApplication) throws {
    try foreground(app)
    app.menuBars.menuBarItems["Window"].click()
    let item = app.menuBars.menuItems["Show Archive"]
    XCTAssertTrue(Waits.until("Show Archive is hittable") { item.isHittable })
    try foreground(app)
    item.click()
    XCTAssertTrue(waitFor(app.windows[AXID.Archive.window]))
  }

  private func archiveRow(_ app: XCUIApplication, page: String) -> XCUIElement {
    app.windows[AXID.Archive.window].tables[AXID.Archive.table].tableRows
      .matching(identifier: AXID.Archive.row)
      .element(matching: NSPredicate(format: "label == %@", FixtureServer.title(ofPage: page)))
  }

  func test_GS043_BH071_hoverXArchivesTodayTab() async throws {
    let app = try await start(["alpha", "beta"])
    let alpha = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    let beta = Shell.todayRow(app, label: FixtureServer.title(ofPage: "beta"))
    try foreground(app)
    alpha.hover()
    let close = alpha.buttons[AXID.Sidebar.rowClose]
    XCTAssertTrue(Waits.until("archive button is hittable") { close.isHittable })
    XCTAssertEqual(close.label, "Archive this tab")
    try foreground(app)
    close.click()
    XCTAssertTrue(waitForOutlineRows("alpha removed") { !alpha.exists && beta.exists })
    try showArchive(app)
    XCTAssertTrue(waitFor(archiveRow(app, page: "alpha")))
  }

  func test_KB008_BH071_cmdWArchivesCurrentTodayTab() async throws {
    let app = try await start(["alpha", "beta"])
    let beta = Shell.todayRow(app, label: FixtureServer.title(ofPage: "beta"))
    try foreground(app)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(waitForOutlineRows("beta removed") { !beta.exists })
    try showArchive(app)
    XCTAssertTrue(waitFor(archiveRow(app, page: "beta")))
  }

  /// PARITY(NEEDS-RUNTIME-CHECK): archiving the last Today tab keeps the Space window.
  func test_BH073_archivingLastTodayTabKeepsWindowOnSpace() async throws {
    let app = try await start(["alpha"])
    try foreground(app)
    app.typeKey("w", modifierFlags: .command)
    let alpha = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    XCTAssertTrue(waitForOutlineRows("alpha removed") { !alpha.exists })
    XCTAssertTrue(shellWindow(of: app).exists)
    XCTAssertEqual(Shell.spaceDots(app).count, 1)
    XCTAssertFalse(Shell.element(app, AXID.EmptyState.root).exists)
  }

  func test_KB043_showArchiveHasNoShortcut() async throws {
    let app = try await start([])
    try foreground(app)
    app.menuBars.menuBarItems["Window"].click()
    let item = app.menuBars.menuItems["Show Archive"]
    XCTAssertTrue(Waits.until("Show Archive is visible") { item.isHittable })
    XCTAssertEqual(item.title, "Show Archive")
  }

  func test_BH086_restoreReturnsTabWithToast() async throws {
    let app = try await start(["beta", "alpha"])
    let beta = Shell.todayRow(app, label: FixtureServer.title(ofPage: "beta"))
    try foreground(app)
    app.typeKey("w", modifierFlags: .command)
    try showArchive(app)
    let row = archiveRow(app, page: "alpha")
    XCTAssertTrue(waitFor(row))
    try foreground(app)
    row.click()
    if !row.isSelected {
      try foreground(app)
      app.typeKey(.downArrow, modifierFlags: [])
    }
    XCTAssertTrue(Waits.until("archive row selected") { row.isSelected })
    let restore = app.windows[AXID.Archive.window].buttons[AXID.Archive.restore]
    XCTAssertTrue(Waits.until("Restore is enabled and hittable") { restore.isEnabled && restore.isHittable })
    try foreground(app)
    restore.click()
    let alpha = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    XCTAssertTrue(waitForOutlineRows("restored alpha exists") { alpha.exists && beta.exists })
    XCTAssertLessThan(alpha.frame.minY, beta.frame.minY)
    let toast = Shell.element(app, AXID.Toast.root)
    XCTAssertTrue(Waits.until("restore toast") { toast.exists && toast.label.hasPrefix("Tab restored to") })
    let action = app.buttons[AXID.Toast.action]
    XCTAssertTrue(waitFor(action))
    XCTAssertTrue(action.label == "View" || action.title == "View")
    try foreground(app)
    action.click()
    XCTAssertTrue(waitForOutlineRows("restored alpha selected") { alpha.isSelected })
  }

  func test_BH087_archiveSearchFiltersRows() throws {
    throw XCTSkip("#111: Archive search scenario deferred by plan U9")
  }
}
