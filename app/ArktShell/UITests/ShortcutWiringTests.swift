import XCTest

/// Exercises the actual app composition root and regular window through Settings and keyboard dispatch.
final class ShortcutWiringTests: ArktUITestCase {
  /// OS keyboard delivery must be checked in the running app, whose activation is owned by the UI harness.
  @MainActor
  func testRecorderCapturesSettingsCommandKeysBeforePaneAndCloseRouting() throws {
    let app = try launch(Sandbox())
    try createFirstSpace(in: app)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows[AXID.Settings.window]
    guard waitFor(settings) else { return }
    app.typeKey("4", modifierFlags: .command)
    let recorderID = "settings.shortcuts.record.toggleSidebarVisibility"
    let recorder = settings.buttons.matching(identifier: recorderID).firstMatch
    guard waitFor(recorder) else { return }
    let pane = settings.descendants(matching: .any).matching(identifier: AXID.Settings.tab("shortcuts")).firstMatch
    let search = settings.searchFields.matching(identifier: AXID.Settings.shortcutsSearch).firstMatch
    let newTab = settings.buttons.matching(identifier: "settings.shortcuts.record.newTab").firstMatch
    guard waitFor(search), waitForSelected(pane), waitFor(newTab) else { return }

    for key in ["w", "1", "2", "3", "4", "5", "6", "7"] {
      recorder.click()
      app.typeKey(key, modifierFlags: .command)
      guard waitFor(settings), waitForSelected(pane) else { return }
      let notice = settings.descendants(matching: .any).matching(identifier: "settings.shortcuts.conflict.message").firstMatch
      let expectedOwner = key == "w" ? "Archive Tab" : "Go to Sidebar Item " + key
      guard waitFor(notice) else { return }
      let message = notice.label
      XCTAssertEqual(message, "Command " + key.uppercased() + " is already used by " + expectedOwner +
                     ". This command cannot be changed here; keep the existing shortcut and try another.")
      let use = settings.buttons.matching(identifier: "settings.shortcuts.conflict.use").firstMatch
      XCTAssertFalse(use.isEnabled)
      settings.buttons.matching(identifier: "settings.shortcuts.conflict.keep").firstMatch.click()
      guard waitFor(settings), waitForSelected(pane) else { return }
      // The original binding remains searchable after declining a protected conflict.
      search.click()
      search.typeText("Command S")
      guard Waits.until("prior binding retained", { recorder.exists && !newTab.exists }) else { return }
      search.typeKey("a", modifierFlags: .command)
      search.typeKey(.delete, modifierFlags: [])
      guard Waits.until("shortcut search cleared", { (search.value as? String) == "" && newTab.exists }) else { return }
    }
    recorder.click()
    app.typeKey("y", modifierFlags: [.control, .option])
    guard waitFor(settings), waitForSelected(pane) else { return }
    do {
      let key = "y"
      // The effective-binding search must retain this particular action. A different captured key cannot satisfy it.
      search.click()
      search.typeText("Control Option " + key.uppercased())
      guard Waits.until("effective binding search applied for Control-Option-" + key, {
        recorder.exists && !newTab.exists
      }) else { return }
      search.typeKey("a", modifierFlags: .command)
      search.typeKey(.delete, modifierFlags: [])
      guard Waits.until("shortcut search cleared after recording Control-Option-" + key, {
        (search.value as? String) == "" && newTab.exists
      }) else { return }
    }
    app.typeKey("1", modifierFlags: .command)
    let general = settings.descendants(matching: .any).matching(identifier: AXID.Settings.tab("general")).firstMatch
    guard waitForSelected(general) else { return }
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(waitUntilGone(settings))
  }

  func testSettingsOverrideClearResetAndReloadDriveNewTabCommand() async throws {
    let sandbox = try Sandbox()
    addTeardownBlock { sandbox.remove() }
    let server = try await FixtureServer.start()
    addTeardownBlock { server.stop() }
    var app = try launch(sandbox)
    try createFirstSpace(in: app)

    func loadBarrierPage(_ app: XCUIApplication) -> Bool {
      let readyCount = server.requestedPaths.filter { $0 == "/events/shortcut-key-ready" }.count
      guard Shell.openCommandBar(app, key: "l") else { return false }
      Shell.submit(server.base + "/shortcut-key-barrier", in: app)
      guard Shell.waitForCommandBar(app, open: false) else { return false }
      return Waits.until("the keyboard barrier page installed its handler") {
        server.requestedPaths.filter { $0 == "/events/shortcut-key-ready" }.count > readyCount
      }
    }

    func expectNoNewTab(_ app: XCUIApplication, key: String,
                        modifiers: XCUIElement.KeyModifierFlags, message: String) -> Bool {
      XCTAssertTrue(Shell.isCommandBarClosed(app))
      // Establish page focus before the key under test; do not click or dismiss anything afterward.
      guard waitFor(app.webViews.firstMatch) else { return false }
      app.webViews.firstMatch.click()
      let delivered = server.requestedPaths.filter { $0.hasPrefix("/events/shortcut-key-barrier/") }.count
      app.typeKey(key, modifierFlags: modifiers)
      app.typeKey("z", modifierFlags: [])
      guard Waits.until("a later key reaches the page: " + message, {
        server.requestedPaths.filter { $0.hasPrefix("/events/shortcut-key-barrier/") }.count > delivered
      }) else { return false }
      let closed = Shell.isCommandBarClosed(app)
      XCTAssertTrue(closed, message)
      return closed
    }

    func openRecorder(_ app: XCUIApplication) {
      app.typeKey(",", modifierFlags: .command)
      XCTAssertTrue(waitFor(app.windows[AXID.Settings.window]))
      app.typeKey("4", modifierFlags: .command)
      let recorder = Shell.element(app, "settings.shortcuts.record.newTab")
      XCTAssertTrue(waitFor(recorder))
      recorder.click()
    }
    func closeSettings(_ app: XCUIApplication) {
      app.typeKey(.escape, modifierFlags: [])
      XCTAssertTrue(waitUntilGone(app.windows[AXID.Settings.window]))
    }
    func expectNewTab(_ app: XCUIApplication, key: String, modifiers: XCUIElement.KeyModifierFlags) {
      app.typeKey(key, modifierFlags: modifiers)
      XCTAssertTrue(Shell.waitForCommandBar(app, open: true))
      app.typeKey(.escape, modifierFlags: [])
      XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    }

    openRecorder(app)
    app.typeKey("y", modifierFlags: .control)
    closeSettings(app)
    guard loadBarrierPage(app), waitFor(app.webViews.firstMatch) else { return }
    app.webViews.firstMatch.click()
    let pageCount = server.requestedPaths.filter { $0 == "/events/shortcut-key-page-y" }.count
    expectNewTab(app, key: "y", modifiers: .control)
    XCTAssertEqual(server.requestedPaths.filter { $0 == "/events/shortcut-key-page-y" }.count, pageCount)
    openRecorder(app)
    app.typeKey("k", modifierFlags: [.control, .option])
    closeSettings(app)
    guard loadBarrierPage(app), waitFor(app.webViews.firstMatch) else { return }
    app.webViews.firstMatch.click()
    let beforePageY = server.requestedPaths.filter { $0 == "/events/shortcut-key-page-y" }.count
    app.typeKey("y", modifierFlags: .control)
    guard Waits.until("unassigned Control-Y reached page", {
      server.requestedPaths.filter { $0 == "/events/shortcut-key-page-y" }.count > beforePageY
    }) else { return }
    guard loadBarrierPage(app),
          expectNoNewTab(app, key: "t", modifiers: .command,
                         message: "the old binding no longer dispatches") else { return }
    expectNewTab(app, key: "k", modifiers: [.control, .option])
    quit(app)

    app = try launch(sandbox)
    expectNewTab(app, key: "k", modifiers: [.control, .option])
    openRecorder(app)
    app.typeKey(.delete, modifierFlags: [])
    closeSettings(app)
    guard loadBarrierPage(app),
          expectNoNewTab(app, key: "k", modifiers: [.control, .option],
                         message: "clearing disables the changed binding") else { return }
    quit(app)

    app = try launch(sandbox)
    guard loadBarrierPage(app),
          expectNoNewTab(app, key: "k", modifiers: [.control, .option],
                         message: "the clear survives relaunch") else { return }
    openRecorder(app)
    // Escape exits recording so Reset All can be activated through the Settings UI.
    app.typeKey(.escape, modifierFlags: [])
    let reset = Shell.element(app, AXID.Settings.control("shortcuts", "resetAll"))
    XCTAssertTrue(waitForEnabled(reset))
    reset.click()
    closeSettings(app)
    expectNewTab(app, key: "t", modifiers: .command)
    quit(app)
    app = try launch(sandbox)
    expectNewTab(app, key: "t", modifiers: .command)
  }
}
