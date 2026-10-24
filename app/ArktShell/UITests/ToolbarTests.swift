import XCTest

/// The Toolbar toggle, its menu title, the sidebar URL bar context menu, persistence in the defaults suite and
/// Back / Forward state (plan U8). Cmd-[ and Cmd-] (KB-031, KB-032) are deferred to #119.
///
/// Sidebar rows are not in the accessibility tree on the macOS 26 runner (#269); row assertions go through
/// `waitForOutlineRows`.
final class ToolbarTests: ArktUITestCase {
  func test_KB018_BH032_cmdShiftDTogglesToolbar() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    let toolbar = Shell.element(app, AXID.Toolbar.root)
    XCTAssertFalse(toolbar.exists, "a fresh sandbox starts with the Toolbar off")

    app.typeKey("d", modifierFlags: [.command, .shift])
    XCTAssertTrue(waitFor(toolbar))
    let urlBar = Shell.element(app, AXID.Toolbar.urlBar)
    XCTAssertTrue(Waits.until("toolbar URL bar holds /p/alpha") { (urlBar.value as? String)?.contains("/p/alpha") == true })

    app.menuBars.menuBarItems["View"].click()
    XCTAssertTrue(waitFor(app.menuBars.menuItems["Hide Toolbar"]))
    app.typeKey(.escape, modifierFlags: [])

    app.typeKey("d", modifierFlags: [.command, .shift])
    XCTAssertTrue(waitUntilGone(toolbar))
  }

  func test_BH031_GS042_sidebarURLBarContextMenuShowsToolbar() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    let toolbar = Shell.element(app, AXID.Toolbar.root)
    XCTAssertFalse(toolbar.exists)

    let sidebarURLBar = Shell.element(app, AXID.Sidebar.urlBar)
    XCTAssertTrue(waitFor(sidebarURLBar))
    sidebarURLBar.rightClick()
    let item = app.menuItems["Show Toolbar"]
    XCTAssertTrue(waitFor(item))
    item.click()

    XCTAssertTrue(waitFor(toolbar))
  }

  /// The relaunch reuses the sandbox, so the Toolbar being on afterwards comes from the sandbox's defaults suite. That
  /// the first launch of a sandbox has the Toolbar off (the other tests assert it) shows the real
  /// `dev.arkt.ArktShell` domain is not read.
  func test_BH032_toolbarSettingSurvivesRelaunchInSameSuite() throws {
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    try createFirstSpace(in: app)
    let toolbar = Shell.element(app, AXID.Toolbar.root)
    XCTAssertFalse(toolbar.exists, "a fresh sandbox starts with the Toolbar off")
    app.typeKey("d", modifierFlags: [.command, .shift])
    XCTAssertTrue(waitFor(toolbar))

    quit(app)
    let relaunched = try launch(sandbox)

    XCTAssertTrue(waitFor(Shell.element(relaunched, AXID.Toolbar.root)))
  }

  func test_BH032_backForwardEnabledFollowsHistory() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    app.typeKey("d", modifierFlags: [.command, .shift])
    let toolbar = Shell.element(app, AXID.Toolbar.root)
    XCTAssertTrue(waitFor(toolbar))
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    let back = app.buttons[AXID.Toolbar.back]
    let forward = app.buttons[AXID.Toolbar.forward]
    let urlBar = Shell.element(app, AXID.Toolbar.urlBar)
    XCTAssertTrue(Waits.until("toolbar URL bar holds /p/alpha") { (urlBar.value as? String)?.contains("/p/alpha") == true })
    XCTAssertTrue(waitForEnabled(back, false))
    XCTAssertTrue(waitForEnabled(forward, false))

    XCTAssertTrue(Shell.openCommandBar(app, key: "l"))
    Shell.commandBarField(app).typeKey("a", modifierFlags: .command)
    Shell.submit(server.page("beta"), in: app)
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    XCTAssertTrue(Waits.until("toolbar URL bar holds /p/beta") { (urlBar.value as? String)?.contains("/p/beta") == true })
    XCTAssertTrue(waitForEnabled(back, true))
    XCTAssertTrue(waitForEnabled(forward, false))

    back.click()
    XCTAssertTrue(Waits.until("toolbar URL bar holds /p/alpha again") { (urlBar.value as? String)?.contains("/p/alpha") == true })
    XCTAssertTrue(waitForEnabled(forward, true))
    XCTAssertTrue(waitForEnabled(back, false))
    let alpha = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    waitForOutlineRows("\(alpha) to exist after Back") { alpha.exists }

    forward.click()
    XCTAssertTrue(Waits.until("toolbar URL bar holds /p/beta again") { (urlBar.value as? String)?.contains("/p/beta") == true })
    let beta = Shell.todayRow(app, label: FixtureServer.title(ofPage: "beta"))
    waitForOutlineRows("\(beta) to exist after Forward") { beta.exists }
  }
}
