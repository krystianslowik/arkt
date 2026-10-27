import XCTest

/// Command bar arrow wrap, Cmd-Enter, Opt-Enter and Switch to Tab (plan U11).
///
/// KB-085 is NEEDS-RUNTIME-CHECK (RT-08). Tests marked [I] assert Arkt's current default. Every Enter in this class
/// goes through `Shell.commitSelectedRow()`, which refuses a row whose value is `Search`. The typed text is only a
/// loopback URL or `Fixture`. What a Search row does on Enter is covered in process (`CommandBarTests`), where the
/// search URL is observed without being loaded.
///
/// Every test proves its behavior from the URL bars, Back state and the fixture server's request log first; the
/// sidebar row checks are one combined `waitForOutlineRows` per test.
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

  /// #371: Cmd-2 selects the Tabs pill (the three open tabs, no Search row) and Cmd-1 goes back to All. The query stays.
  /// Not run in CI on a pull request (section 12); the in-process twin is `CommandBarBehaviourTests`.
  func test_371_commandDigitsPickTheFilterPills() async throws {
    let (_, app) = try await launchWithThreeTabs()
    showFixtureResults(in: app)

    Shell.commandBarField(app).typeKey("2", modifierFlags: .command)
    XCTAssertTrue(Waits.until("only Switch to Tab rows under Tabs; \(Shell.commandBarRowSummary(app))") {
      let values = Shell.commandBarRowsInOrder(app).map { $0.value as? String }
      return values.count == 3 && values.allSatisfy { $0 == "Switch to Tab" }
    })
    XCTAssertEqual(Shell.commandBarField(app).value as? String, Self.query, "a filter does not change the query")

    Shell.commandBarField(app).typeKey("1", modifierFlags: .command)
    XCTAssertTrue(Waits.until("All shows the Search row again; \(Shell.commandBarRowSummary(app))") {
      Shell.commandBarRowsInOrder(app).count == 4
    })
  }

  /// #371: Esc clears the query first and closes the bar on the second press.
  func test_371_escClearsTheQueryThenCloses() async throws {
    let (_, app) = try await launchWithThreeTabs()
    showFixtureResults(in: app)

    Shell.commandBarField(app).typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(Waits.until("the query is cleared and the bar is open") {
      (Shell.commandBarField(app).value as? String)?.isEmpty == true && Shell.isCommandBarOpen(app)
    })
    Shell.commandBarField(app).typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
  }

  /// BH-104 / BH-110: a "Switch to Tab" result shows the open tab instead of loading it again. Shown from gamma, the
  /// alpha row switches: the Toolbar's URL bar shows alpha's address and the fixture server sees no second request
  /// for it. The Toolbar is turned on because the sidebar URL bar shows the host only, the same for every fixture
  /// page. The sidebar rows are one combined check at the end.
  func test_BH104_BH110_switchToTabRow() async throws {
    let (server, app) = try await launchWithThreeTabs()
    let urlBar = showToolbarURLBar(in: app)
    XCTAssertTrue(Waits.until("toolbar URL bar shows /p/gamma") { Self.value(of: urlBar).contains("/p/gamma") })
    let alphaLoads = Self.requests(server, "alpha")
    XCTAssertGreaterThanOrEqual(alphaLoads, 1, "alpha loaded when its tab opened: \(server.requestedPaths)")
    showFixtureResults(in: app)

    let title = FixtureServer.title(ofPage: "alpha")
    XCTAssertTrue(Shell.selectCommandBarRow(app, label: title, value: "Switch to Tab"))
    XCTAssertTrue(Shell.commitSelectedRow(app))
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))

    XCTAssertTrue(Waits.until("toolbar URL bar shows /p/alpha after Switch to Tab") {
      Self.value(of: urlBar).contains("/p/alpha")
    })
    XCTAssertEqual(Self.requests(server, "alpha"), alphaLoads,
                   "Switch to Tab did not load alpha again: \(server.requestedPaths)")

    let alpha = Shell.todayRow(app, label: title)
    let rows = Shell.todayRows(app)
    waitForOutlineRows("\(alpha) selected and still three Today rows") {
      alpha.exists && alpha.isSelected && rows.count == Self.pages.count
    }
  }

  /// PARITY(NEEDS-RUNTIME-CHECK RT-08): Cmd-Enter opens the selected result in a new tab, including from Cmd-L.
  /// Arkt's [I] default.
  func test_KB085_cmdEnterOpensURLInNewTab() async throws {
    let (server, app) = try await launchWithThreeTabs()
    try openEditedURLInNewTab(modifiers: .command, server: server, app: app)
  }

  /// PARITY(NEEDS-RUNTIME-CHECK RT-08): Opt-Enter opens the selected result in a new tab, including from Cmd-L.
  /// Arkt's [I] default.
  func test_KB085_optEnterOpensURLInNewTab() async throws {
    let (server, app) = try await launchWithThreeTabs()
    try openEditedURLInNewTab(modifiers: .option, server: server, app: app)
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

  /// Requests the fixture server has seen for `/p/<name>`.
  private static func requests(_ server: FixtureServer, _ name: String) -> Int {
    server.requestedPaths.filter { $0 == "/p/\(name)" }.count
  }

  private static func value(of element: XCUIElement) -> String { (element.value as? String) ?? "" }

  /// Cmd-Shift-D turns the Toolbar on (a fresh sandbox starts with it off) and returns its URL bar, whose value is the
  /// shown tab's full address.
  private func showToolbarURLBar(in app: XCUIApplication) -> XCUIElement {
    app.typeKey("d", modifierFlags: [.command, .shift])
    XCTAssertTrue(waitFor(Shell.element(app, AXID.Toolbar.root)))
    return Shell.element(app, AXID.Toolbar.urlBar)
  }

  /// With the Toolbar on, from gamma: Cmd-L and Return navigate gamma in place to epsilon, so that tab has Back
  /// history. Cmd-L again (prefilled with epsilon), a new address, then Cmd-Return or Opt-Return. A new tab shows
  /// delta with Back disabled, where in-place navigation would have left Back enabled; switching back to the
  /// epsilon tab finds its Back history intact and loads nothing again. The sidebar rows are one combined
  /// check at the end.
  private func openEditedURLInNewTab(
    modifiers: XCUIElement.KeyModifierFlags, server: FixtureServer, app: XCUIApplication
  ) throws {
    let urlBar = showToolbarURLBar(in: app)
    let back = app.buttons[AXID.Toolbar.back]
    XCTAssertTrue(Waits.until("toolbar URL bar shows /p/gamma") { Self.value(of: urlBar).contains("/p/gamma") })
    XCTAssertTrue(waitForEnabled(back, false), "gamma opened in a new tab has no Back history")

    XCTAssertTrue(Shell.openCommandBar(app, key: "l"))
    let field = Shell.commandBarField(app)
    XCTAssertTrue(Waits.until("Cmd-L prefills /p/gamma") { Self.value(of: field).contains("/p/gamma") })
    field.typeKey("a", modifierFlags: .command)
    field.typeText(server.page("epsilon"))
    XCTAssertTrue(Waits.until("selected row is Open, not Search; \(Shell.commandBarRowSummary(app))") {
      (Shell.selectedCommandBarRow(app)?.value as? String) == "Open"
    })
    XCTAssertTrue(Shell.commitSelectedRow(app))
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    XCTAssertTrue(Waits.until("toolbar URL bar shows /p/epsilon") { Self.value(of: urlBar).contains("/p/epsilon") })
    XCTAssertTrue(waitForEnabled(back, true), "Return from Cmd-L navigated gamma's tab in place")
    let epsilonLoads = Self.requests(server, "epsilon")
    XCTAssertGreaterThanOrEqual(epsilonLoads, 1, "epsilon loaded: \(server.requestedPaths)")

    XCTAssertTrue(Shell.openCommandBar(app, key: "l"))
    XCTAssertTrue(Waits.until("Cmd-L prefills /p/epsilon") { Self.value(of: field).contains("/p/epsilon") })
    field.typeKey("a", modifierFlags: .command)
    field.typeText(server.page("delta"))
    XCTAssertTrue(Waits.until("selected row is Open, not Search; \(Shell.commandBarRowSummary(app))") {
      (Shell.selectedCommandBarRow(app)?.value as? String) == "Open"
    })
    XCTAssertTrue(Shell.commitSelectedRow(app, modifiers: modifiers))
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    XCTAssertTrue(Waits.until("/p/delta requested") { server.requestedPaths.contains("/p/delta") })
    XCTAssertTrue(Waits.until("toolbar URL bar shows /p/delta") { Self.value(of: urlBar).contains("/p/delta") })
    XCTAssertTrue(waitForEnabled(back, false), "delta opened in a new tab, not in epsilon's tab")
    let deltaLoads = Self.requests(server, "delta")

    let epsilonTitle = FixtureServer.title(ofPage: "epsilon")
    XCTAssertTrue(Shell.openCommandBar(app, key: "t"))
    Shell.commandBarField(app).typeText(Self.query)
    XCTAssertTrue(Shell.selectCommandBarRow(app, label: epsilonTitle, value: "Switch to Tab"))
    XCTAssertTrue(Shell.commitSelectedRow(app))
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    XCTAssertTrue(Waits.until("toolbar URL bar shows /p/epsilon again") {
      Self.value(of: urlBar).contains("/p/epsilon")
    })
    XCTAssertTrue(waitForEnabled(back, true), "the previous tab kept its Back history")
    XCTAssertEqual(Self.requests(server, "epsilon"), epsilonLoads,
                   "switching back did not load epsilon again: \(server.requestedPaths)")
    XCTAssertEqual(Self.requests(server, "delta"), deltaLoads, "nothing loaded delta again: \(server.requestedPaths)")

    let rows = Shell.todayRows(app)
    let delta = Shell.todayRow(app, label: FixtureServer.title(ofPage: "delta"))
    let epsilon = Shell.todayRow(app, label: epsilonTitle)
    waitForOutlineRows("four Today rows, \(delta) and \(epsilon) among them") {
      rows.count == Self.pages.count + 1 && delta.exists && epsilon.exists
    }
  }
}
