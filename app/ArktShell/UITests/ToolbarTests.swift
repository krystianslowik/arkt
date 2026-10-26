import XCTest

/// The Toolbar toggle, its menu title, the sidebar URL bar context menu, persistence in the defaults suite and
/// Back / Forward state (plan U8). Cmd-[ and Cmd-] (KB-031, KB-032) are deferred to #119.
///
/// Row assertions go through `waitForOutlineRows`.
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

  /// #307: Arkt > Settings... (Cmd-,) opens the Settings window on General; Cmd-3 shows Appearance; flipping Show
  /// Toolbar there shows the Toolbar in the browser window; Escape closes Settings.
  func test_KB066_settingsShowToolbarFlipsTheToolbar() throws {
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    let toolbar = Shell.element(app, AXID.Toolbar.root)
    XCTAssertFalse(toolbar.exists, "a fresh sandbox starts with the Toolbar off")

    app.typeKey(",", modifierFlags: [.command])
    let settings = app.windows[AXID.Settings.window]
    XCTAssertTrue(waitFor(settings))
    app.typeKey("3", modifierFlags: [.command])
    let showToolbar = Shell.element(app, AXID.Settings.control("appearance", "showToolbar"))
    XCTAssertTrue(waitFor(showToolbar))
    showToolbar.click()

    XCTAssertTrue(waitFor(toolbar))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(waitUntilGone(settings))
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
    // The View menu in the menu bar has an item with the same title; only the context menu's item can be hit.
    let items = app.menuItems.matching(NSPredicate(format: "title == %@ OR identifier == %@", "Show Toolbar", "Show Toolbar"))
    var item: XCUIElement?
    XCTAssertTrue(Waits.until("a hittable Show Toolbar menu item") {
      item = items.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
      return item != nil
    })
    item?.click()

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
