import XCTest

/// Exercises the actual app composition root and regular window through Settings and keyboard dispatch.
final class ShortcutWiringTests: ArktUITestCase {
  func testSettingsOverrideClearResetAndReloadDriveNewTabCommand() throws {
    let sandbox = try Sandbox()
    addTeardownBlock { sandbox.remove() }
    var app = try launch(sandbox)
    try createFirstSpace(in: app)

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
    app.typeKey("k", modifierFlags: [.control, .option])
    closeSettings(app)
    app.typeKey("t", modifierFlags: .command)
    XCTAssertTrue(Shell.isCommandBarClosed(app), "the old binding no longer dispatches")
    expectNewTab(app, key: "k", modifiers: [.control, .option])
    quit(app)

    app = try launch(sandbox)
    expectNewTab(app, key: "k", modifiers: [.control, .option])
    openRecorder(app)
    app.typeKey(.delete, modifierFlags: [])
    closeSettings(app)
    app.typeKey("k", modifierFlags: [.control, .option])
    XCTAssertTrue(Shell.isCommandBarClosed(app), "clearing disables the changed binding")
    quit(app)

    app = try launch(sandbox)
    app.typeKey("k", modifierFlags: [.control, .option])
    XCTAssertTrue(Shell.isCommandBarClosed(app), "the clear survives relaunch")
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
