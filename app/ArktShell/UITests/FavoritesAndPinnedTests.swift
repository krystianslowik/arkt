import XCTest

/// Favorites close and pinned rows (plan U10).
///
/// Archive rows, the archive footer and sidebar outline rows are read once. Polling those queries inside an
/// expectation never returns. A one-shot that finds no `favorites.tile` or `sidebar.row.pinned` is the #269 gap
/// and is skipped, not waited on. The sidebar URL bar shows only the host, so the full address is the Toolbar's.
final class FavoritesAndPinnedTests: ArktUITestCase {
  private let mailTitle = "Example Mail"
  private let mailPath = "/mail"
  private let wikiTitle = "Example Wiki"
  private let wikiPath = "/wiki"
  /// Seeded archive (`ArcFixture.expected.archive`), as `ArchiveWindowController.countText` prints it.
  private let seededArchiveFooter = "7 items"

  func test_BH048_GS043_favoriteXClosesPageKeepsTile() async throws {
    let (server, app) = try await launchSeeded()
    let tile = try favoriteTile(app, title: mailTitle)
    let urlBar = try showToolbarURLBar(in: app)
    try activate(tile, path: mailPath, server: server, urlBar: urlBar, app: app)
    XCTAssertEqual(tile.value as? String, AXID.Favorites.loaded)
    let titles = archiveTitles(shown: tile.label, original: mailTitle, path: mailPath)

    try foreground(app)
    let close = try hoverClose(on: tile, identifier: AXID.Favorites.tileClose, in: app)
    try foreground(app)
    click(close)

    try assertUnloaded(tile, path: mailPath, urlBar: urlBar)
    try assertNotArchived(titles, in: app)
  }

  func test_BH048_cmdWOnFavoriteDoesNotArchive() async throws {
    let (server, app) = try await launchSeeded()
    let tile = try favoriteTile(app, title: mailTitle)
    let urlBar = try showToolbarURLBar(in: app)
    try activate(tile, path: mailPath, server: server, urlBar: urlBar, app: app)
    XCTAssertEqual(tile.value as? String, AXID.Favorites.loaded)
    let titles = archiveTitles(shown: tile.label, original: mailTitle, path: mailPath)

    try foreground(app)
    app.typeKey("w", modifierFlags: .command)

    try assertUnloaded(tile, path: mailPath, urlBar: urlBar)
    try assertNotArchived(titles, in: app)
  }

  func test_BH067_cmdWOnPinnedTabKeepsPin() async throws {
    let (server, app) = try await launchSeeded()
    let urlBar = try showToolbarURLBar(in: app)
    let row = try pinnedWiki(in: app, server: server, urlBar: urlBar)
    let titles = archiveTitles(shown: row.label, original: wikiTitle, path: wikiPath)

    try foreground(app)
    app.typeKey("w", modifierFlags: .command)

    try assertKept(row, path: wikiPath, urlBar: urlBar)
    try assertNotArchived(titles, in: app)
  }

  /// PARITY(NEEDS-RUNTIME-CHECK RT-17). #85 decides the final rule; this test does not change the pinned close.
  func test_BH070_pinnedHoverXCloseAndKeepPinned() async throws {
    let (server, app) = try await launchSeeded()
    let urlBar = try showToolbarURLBar(in: app)
    let row = try pinnedWiki(in: app, server: server, urlBar: urlBar)
    let titles = archiveTitles(shown: row.label, original: wikiTitle, path: wikiPath)

    try foreground(app)
    let close = try hoverClose(on: row, identifier: AXID.Sidebar.rowClose, in: app)
    XCTAssertEqual(close.label, "Close and Keep Pinned")
    try foreground(app)
    click(close)

    try assertKept(row, path: wikiPath, urlBar: urlBar)
    try assertNotArchived(titles, in: app)
  }

  // MARK: - Launch

  private func launchSeeded() async throws -> (FixtureServer, XCUIApplication) {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    try sandbox.seedFromArcFixture(server: server)
    let app = try launch(sandbox)
    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("2 Space dots") { dots.count == ArcFixture.expected.spaces })
    return (server, app)
  }

  /// Cmd-Shift-D. Returns the Toolbar address once, so later reads stay on that element.
  private func showToolbarURLBar(in app: XCUIApplication) throws -> XCUIElement {
    try foreground(app)
    app.typeKey("d", modifierFlags: [.command, .shift])
    let toolbar = app.toolbars[AXID.Toolbar.root]
    XCTAssertTrue(waitFor(toolbar))
    let scoped = toolbar.buttons[AXID.Toolbar.urlBar]
    if scoped.exists { return scoped }
    let shipped = Shell.element(app, AXID.Toolbar.urlBar)
    if shipped.exists { return shipped }
    XCTFail("toolbar URL bar is not in the tree")
    throw HarnessError("no toolbar URL bar")
  }

  // MARK: - Favorites

  /// The tile titled `title`, from one read of the grid. No wait: a missing tile is the #269 gap.
  private func favoriteTile(_ app: XCUIApplication, title: String) throws -> XCUIElement {
    let grid = app.groups[AXID.Favorites.grid]
    guard grid.exists else {
      throw XCTSkip("#269: favorites.grid is not in the out-of-process tree")
    }
    let tiles = grid.buttons.matching(identifier: AXID.Favorites.tile)
    let count = tiles.count
    guard count > 0 else {
      throw XCTSkip("#269: favorites.tile is not in the out-of-process tree")
    }
    for index in 0..<count {
      let tile = tiles.element(boundBy: index)
      if tile.label == title { return tile }
    }
    let labels = (0..<count).map { tiles.element(boundBy: $0).label }
    XCTFail("no favorite titled \(title); saw \(labels)")
    throw HarnessError("missing favorite \(title)")
  }

  private func activate(
    _ tile: XCUIElement, path: String, server: FixtureServer, urlBar: XCUIElement, app: XCUIApplication
  ) throws {
    try foreground(app)
    tile.click()
    XCTAssertTrue(Waits.until("server log shows \(path)") { server.requestedPaths.contains(path) })
    try waitForURL(contains: path, urlBar: urlBar)
  }

  private func assertUnloaded(_ tile: XCUIElement, path: String, urlBar: XCUIElement) throws {
    try waitForURL(leaves: path, urlBar: urlBar)
    XCTAssertTrue(tile.exists, "the favorite tile was removed")
    XCTAssertEqual(tile.value as? String, AXID.Favorites.unloaded)
  }

  // MARK: - Pinned

  /// Beta's pinned tab, from one read of the outline. No wait on the rows: none at all is the #269 gap.
  private func pinnedWiki(in app: XCUIApplication, server: FixtureServer, urlBar: XCUIElement) throws -> XCUIElement {
    let dot = Shell.spaceDots(app).element(boundBy: 1)
    XCTAssertTrue(waitFor(dot))
    try foreground(app)
    dot.click()
    XCTAssertTrue(waitForSelected(dot))
    XCTAssertTrue(waitForSelected(spacePage(app, title: "Beta")))

    let rows = app.outlineRows.matching(identifier: AXID.Sidebar.rowPinned)
    let count = rows.count
    guard count > 0 else {
      throw XCTSkip("#269: sidebar.row.pinned is not in the out-of-process tree")
    }
    let loadedTitle = "Fixture \(wikiPath)"
    var row: XCUIElement?
    var labels: [String] = []
    for index in 0..<count {
      let candidate = rows.element(boundBy: index)
      let label = candidate.label
      labels.append(label)
      if label == wikiTitle || label == loadedTitle { row = candidate }
    }
    guard let row else {
      XCTFail("no pinned row \(wikiTitle); saw \(labels)")
      throw HarnessError("missing pinned row")
    }
    try foreground(app)
    row.click()
    let path = wikiPath
    XCTAssertTrue(Waits.until("server log shows \(path)") { server.requestedPaths.contains(path) })
    try waitForURL(contains: path, urlBar: urlBar)
    return row
  }

  private func assertKept(_ row: XCUIElement, path: String, urlBar: XCUIElement) throws {
    try waitForURL(leaves: path, urlBar: urlBar)
    XCTAssertTrue(row.exists, "the pinned row was removed")
  }

  // MARK: - Hover close

  /// One read of the hover X after `hover()`, then one more if the first mouse-entered has not been published yet.
  /// Not an expectation: polling a close button that is still absent never returns.
  private func hoverClose(on host: XCUIElement, identifier: String, in app: XCUIApplication) throws -> XCUIElement {
    host.hover()
    let nested = host.buttons[identifier]
    if nested.exists { return nested }
    host.hover()
    if nested.exists { return nested }
    let top = app.buttons[identifier]
    if top.exists { return top }
    XCTFail("\(identifier) is not shown after hover")
    throw HarnessError("missing \(identifier)")
  }

  private func click(_ button: XCUIElement) {
    if button.isHittable {
      button.click()
    } else {
      button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }
  }

  // MARK: - Address and archive

  private func waitForURL(
    contains path: String, urlBar: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    XCTAssertTrue(Waits.until("toolbar URL shows \(path)", file: file, line: line) {
      (urlBar.value as? String)?.contains(path) == true
    }, file: file, line: line)
  }

  private func waitForURL(
    leaves path: String, urlBar: XCUIElement, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    XCTAssertTrue(Waits.until("toolbar URL leaves \(path)", file: file, line: line) {
      (urlBar.value as? String)?.contains(path) != true
    }, file: file, line: line)
  }

  private func archiveTitles(shown: String, original: String, path: String) -> [String] {
    var titles: [String] = []
    for title in [shown, original, "Fixture \(path)"] where !title.isEmpty && !titles.contains(title) {
      titles.append(title)
    }
    return titles
  }

  /// Window > Show Archive, then one read of the footer and the row titles. Neither is polled.
  private func assertNotArchived(
    _ titles: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    try foreground(app)
    app.menuBars.menuBarItems["Window"].click()
    let item = app.menuBars.menuItems["Show Archive"]
    XCTAssertTrue(Waits.until("Show Archive is hittable", file: file, line: line) { item.isHittable },
                  file: file, line: line)
    try foreground(app)
    item.click()
    let window = app.windows[AXID.Archive.window]
    XCTAssertTrue(waitFor(window, file: file, line: line), file: file, line: line)
    let clear = window.buttons[AXID.Archive.clear]
    guard clear.exists else {
      XCTFail("Clear Archive is not in the archive window", file: file, line: line)
      return
    }
    XCTAssertTrue(waitForEnabled(clear, file: file, line: line), "archive list did not load", file: file, line: line)

    let footerElement = window.staticTexts[AXID.Archive.footer]
    let footer = footerElement.exists ? ((footerElement.value as? String) ?? footerElement.label) : ""
    let table = window.tables[AXID.Archive.table]
    let tableValue = (table.value as? String) ?? ""
    let labels = table.tableRows.matching(identifier: AXID.Archive.row).allElementsBoundByIndex.map(\.label)
    let count = footer.isEmpty ? tableValue : footer
    XCTAssertEqual(count, seededArchiveFooter, "archive count \(count); table \(tableValue); rows \(labels)",
                   file: file, line: line)
    XCTAssertFalse(labels.isEmpty, "archive row query returned nothing; footer was \(footer)", file: file, line: line)
    for title in titles {
      XCTAssertFalse(labels.contains(title), "archive lists \(title): \(labels)", file: file, line: line)
    }
  }

  private func spacePage(_ app: XCUIApplication, title: String) -> XCUIElement {
    app.groups.matching(identifier: AXID.Sidebar.page)
      .matching(NSPredicate(format: "label == %@", title))
      .firstMatch
  }

  private func foreground(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
    app.activate()
    guard waitFor(app, .runningForeground, file: file, line: line) else {
      throw HarnessError("test app is not frontmost")
    }
  }
}
