import XCTest

/// #373: with the Space name field focused, the menu key equivalents still win over the field editor (KB-008 Cmd-W,
/// KB-012 Cmd-D). The reported bug: Cmd-W inserted a stray "w" into the name and archived nothing; Cmd-D did nothing
/// (the private `NSWindow.pinTab:` claimed that selector through the responder chain).
final class SpaceNameFieldShortcutTests: ArktUITestCase {
  private static let spaceTitleText = "Space 1"

  /// The current Space's title element (inside its page group).
  private func titleElement(_ app: XCUIApplication) -> XCUIElement {
    app.groups.matching(identifier: AXID.Sidebar.page)
      .matching(NSPredicate(format: "label == %@", Self.spaceTitleText))
      .firstMatch
      .descendants(matching: .any)[AXID.Sidebar.spaceTitle]
  }

  /// The title string as accessibility reports it while the field is open (the field editor's value wins).
  private func titleText(_ app: XCUIApplication) -> String {
    let element = titleElement(app)
    if let value = element.value as? String, !value.isEmpty { return value }
    return element.label
  }

  /// Clicks the Space title, which opens the rename field with the field editor focused (a short press: a drag
  /// reorders instead). Typing proves the focus and returns the title the field holds. The click leaves the caret
  /// wherever it lands, so the typed letter is appended to the selected name rather than replacing it.
  private func beginRenaming(_ app: XCUIApplication) -> String {
    let header = titleElement(app)
    XCTAssertTrue(waitFor(header))
    header.click()
    app.typeText("Z")
    let typed = titleText(app)
    XCTAssertNotEqual(typed, Self.spaceTitleText, "the rename field editor holds keyboard focus")
    XCTAssertTrue(typed.hasSuffix("Z"), "the typed letter reaches the field editor")
    return typed
  }

  /// Activates the app and types a menu shortcut; menu key equivalents reach it only while frontmost.
  private func pressShortcut(_ key: String, modifiers: XCUIElement.KeyModifierFlags, in app: XCUIApplication) {
    app.activate()
    XCTAssertTrue(waitFor(app, .runningForeground))
    app.typeKey(key, modifierFlags: modifiers)
  }

  /// A launch with one Space and one loaded Today tab.
  private func launchWithOneTab() async throws -> (XCUIApplication, XCUIElement) {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    XCTAssertTrue(waitFor(row))
    XCTAssertEqual(Shell.todayRows(app).count, 1)
    return (app, row)
  }

  func test_KB008_cmdWWithTheSpaceNameFieldFocusedArchivesTheTab() async throws {
    let (app, row) = try await launchWithOneTab()
    let typedTitle = beginRenaming(app)

    pressShortcut("w", modifiers: .command, in: app)

    XCTAssertTrue(waitUntilGone(row), "Cmd-W archives the current tab while the name field is focused")
    XCTAssertEqual(titleText(app), typedTitle, "the field editor never receives the Cmd-W as a typed character")
  }

  func test_KB012_cmdDWithTheSpaceNameFieldFocusedPinsTheTab() async throws {
    let (app, row) = try await launchWithOneTab()
    let typedTitle = beginRenaming(app)

    pressShortcut("d", modifiers: .command, in: app)

    let pinned = app.outlineRows.matching(identifier: AXID.Sidebar.rowPinned)
      .element(matching: NSPredicate(format: "label == %@", FixtureServer.title(ofPage: "alpha")))
    XCTAssertTrue(waitFor(pinned), "Cmd-D pins the current tab while the name field is focused")
    XCTAssertTrue(waitUntilGone(row), "the pinned tab leaves Today")
    XCTAssertEqual(titleText(app), typedTitle, "the field editor never receives the Cmd-D as a typed character")
  }
}
