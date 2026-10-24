import XCTest

/// Command bar arrow wrap, Cmd-Enter, Opt-Enter and Switch to Tab (plan U11).
///
/// KB-085 is NEEDS-RUNTIME-CHECK (RT-08). Tests marked [I] assert Arkt's current default. Every Enter in this class
/// goes through `Shell.commitSelectedRow()`, which refuses a row whose value is `Search`. The typed text is only a
/// loopback URL or `Fixture`.
///
/// Sidebar rows are not in the accessibility tree on the macOS 26 runner (#269); assertions that need them go through
/// `waitForOutlineRows`.
final class CommandBarKeyTests: ArktUITestCase {
  private static let pages = ["alpha", "beta", "gamma"]
  /// Query that matches the three open tabs and adds one search row. Never committed.
  private static let query = "Fixture"

  /// PARITY(NEEDS-RUNTIME-CHECK RT-08): Down past the last result wraps to the first, Up from the first wraps to the
  /// last. Arkt's [I] default; Arc's wrap is not confirmed.
  func test_KB085_downWrapsFromLastToFirst() async throws {
    let (_, app) = try await launchWithThreeTabs()
    showFixtureResults(in: app)

    let ordered = try orderedResults(in: app)
    let firstLabel = try XCTUnwrap(ordered.first?.label)
    XCTAssertEqual(Shell.selectedCommandBarRow(app)?.label, Optional(firstLabel), Shell.commandBarRowSummary(app))

    for index in ordered.indices {
      let expected = ordered[(index + 1) % ordered.count].label
      app.typeKey(.downArrow, modifierFlags: [])
      XCTAssertTrue(Waits.until("Down selects \(expected); \(Shell.commandBarRowSummary(app))") {
        Shell.selectedCommandBarRow(app)?.label == expected
      })
    }
    XCTAssertEqual(Shell.selectedCommandBarRow(app)?.label, Optional(firstLabel), "Down once per row wraps to the first")

    let last = ordered[ordered.count - 1]
    app.typeKey(.upArrow, modifierFlags: [])
    XCTAssertTrue(Waits.until("Up from the first selects \(last.label); \(Shell.commandBarRowSummary(app))") {
      let selected = Shell.selectedCommandBarRow(app)
      return selected?.label == last.label && (selected?.value as? String) == "Search"
    })
    XCTAssertTrue(Shell.isCommandBarOpen(app), "wrapping onto the search row does not commit it")
  }

  func test_BH104_BH110_switchToTabRow() async throws {
    let (_, app) = try await launchWithThreeTabs()
    let before = Shell.todayRows(app).count
    showFixtureResults(in: app)

    let title = FixtureServer.title(ofPage: "alpha")
    XCTAssertTrue(Shell.selectCommandBarRow(app, label: title, value: "Switch to Tab"))
    XCTAssertTrue(Shell.commitSelectedRow(app))
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))

    let alpha = Shell.todayRow(app, label: title)
    if waitForOutlineRows("\(alpha) selected", { alpha.exists && alpha.isSelected }) {
      XCTAssertEqual(Shell.todayRows(app).count, before, "switching tabs adds no row")
    }
  }

  /// PARITY(NEEDS-RUNTIME-CHECK RT-08): Cmd-Enter opens the selected result in a new tab, including from Cmd-L.
  /// Arkt's [I] default.
  func test_KB085_cmdEnterOpensURLInNewTab() async throws {
    let (server, app) = try await launchWithThreeTabs()
    try openEditedURLInNewTab("delta", modifiers: .command, server: server, app: app)
  }

  /// PARITY(NEEDS-RUNTIME-CHECK RT-08): Opt-Enter opens the selected result in a new tab, including from Cmd-L.
  /// Arkt's [I] default.
  func test_KB085_optEnterOpensURLInNewTab() async throws {
    let (server, app) = try await launchWithThreeTabs()
    try openEditedURLInNewTab("delta", modifiers: .option, server: server, app: app)
  }

  /// Every Enter in the class uses `Shell.commitSelectedRow()`. On a Search row that helper presses nothing: the bar
  /// stays open and the fixture server sees no further page.
  func test_E_noSearchCommitted() async throws {
    let (server, app) = try await launchWithThreeTabs()
    let pagesBefore = server.requestedPaths.filter { $0.hasPrefix("/p/") }
    showFixtureResults(in: app)

    XCTAssertTrue(Shell.selectCommandBarRow(app, label: Self.query, value: "Search"))
    XCTAssertEqual(Shell.selectedCommandBarRow(app)?.value as? String, Optional("Search"))
    XCTAssertFalse(Shell.commitSelectedRow(app), "refuses to press Enter on a Search row")
    XCTAssertTrue(Shell.isCommandBarOpen(app))
    XCTAssertEqual(Shell.selectedCommandBarRow(app)?.value as? String, Optional("Search"))

    let pagesAfter = server.requestedPaths.filter { $0.hasPrefix("/p/") }
    XCTAssertEqual(pagesAfter, pagesBefore, "no search row was committed: \(server.requestedPaths)")
    for path in server.requestedPaths {
      XCTAssertTrue(path == "/favicon.ico" || path.hasPrefix("/p/"), "unexpected request \(path)")
    }
  }

  // MARK: - Setup

  private func launchWithThreeTabs() async throws -> (FixtureServer, XCUIApplication) {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    openTabs(Self.pages, server: server, in: app)
    return (server, app)
  }

  /// Cmd-T and a loopback URL. Enter is `commitSelectedRow()` on the Open row, never a search row.
  private func openTabs(_ names: [String], server: FixtureServer, in app: XCUIApplication) {
    for name in names {
      XCTAssertTrue(Shell.openCommandBar(app, key: "t"))
      let field = Shell.commandBarField(app)
      field.typeText(server.page(name))
      XCTAssertTrue(Waits.until("selected row is Open for /p/\(name); \(Shell.commandBarRowSummary(app))") {
        (Shell.selectedCommandBarRow(app)?.value as? String) == "Open"
      })
      XCTAssertTrue(Shell.commitSelectedRow(app))
      XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
      XCTAssertTrue(Waits.until("/p/\(name) requested") { server.requestedPaths.contains("/p/\(name)") })
    }
    for name in names {
      let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: name))
      waitForOutlineRows("\(row) to exist") { row.exists }
    }
  }

  /// Cmd-T, type `Fixture`: the open-tab rows (caption "Switch to Tab") plus one search row.
  private func showFixtureResults(in app: XCUIApplication) {
    XCTAssertTrue(Shell.openCommandBar(app, key: "t"))
    Shell.commandBarField(app).typeText(Self.query)
    XCTAssertTrue(Waits.until("three Switch to Tab rows and one Search row; \(Shell.commandBarRowSummary(app))") {
      let values = Shell.commandBarRowsInOrder(app).map { $0.value as? String }
      return values.filter { $0 == "Switch to Tab" }.count == 3 && values.last == "Search"
    })
  }

  private func orderedResults(in app: XCUIApplication) throws -> [XCUIElement] {
    let ordered = Shell.commandBarRowsInOrder(app)
    XCTAssertEqual(ordered.count, 4, Shell.commandBarRowSummary(app))
    return ordered
  }

  /// Cmd-L on alpha, replace the address, then Cmd-Enter or Opt-Enter. The new page is a Today row; alpha stays.
  private func openEditedURLInNewTab(
    _ name: String, modifiers: XCUIElement.KeyModifierFlags, server: FixtureServer, app: XCUIApplication
  ) throws {
    let title = FixtureServer.title(ofPage: "alpha")
    let alpha = Shell.todayRow(app, label: title)
    let rowsVisible = waitForOutlineRows("\(alpha) to exist") { alpha.exists }
    if rowsVisible {
      alpha.click()
      XCTAssertTrue(waitForSelected(alpha))
      XCTAssertTrue(Waits.until("sidebar URL bar shows /p/alpha") {
        (Shell.element(app, AXID.Sidebar.urlBar).value as? String)?.contains("/p/alpha") == true
      })
    }

    XCTAssertTrue(Shell.openCommandBar(app, key: "l"))
    let field = Shell.commandBarField(app)
    if rowsVisible {
      XCTAssertTrue(Waits.until("address field holds /p/alpha") {
        (field.value as? String)?.contains("/p/alpha") == true
      })
    }
    field.typeKey("a", modifierFlags: .command)
    field.typeText(server.page(name))
    XCTAssertTrue(Waits.until("selected row is Open, not Search; \(Shell.commandBarRowSummary(app))") {
      (Shell.selectedCommandBarRow(app)?.value as? String) == "Open"
    })
    XCTAssertTrue(Shell.commitSelectedRow(app, modifiers: modifiers))
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    XCTAssertTrue(Waits.until("/p/\(name) requested") { server.requestedPaths.contains("/p/\(name)") })

    let opened = Shell.todayRow(app, label: FixtureServer.title(ofPage: name))
    if waitForOutlineRows("\(opened) exists and \(alpha) remains", { opened.exists && alpha.exists }) {
      XCTAssertEqual(Shell.todayRows(app).count, Self.pages.count + 1)
    }
  }
}
