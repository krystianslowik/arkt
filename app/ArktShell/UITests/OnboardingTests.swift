import XCTest

/// The first run end to end (onboarding spec, #310), like U7: both branches through the accessibility identifiers to
/// the browser, Make it yours after an import ("Imported" selected, Skip restores it), the Skip setup alert (cancel,
/// confirm, confirm during an import), Escape in the Name field, the arrow rules, and no "Arc" in anything the
/// flow shows. The default browser is never touched (`Sandbox` sets `ARKT_DEFAULT_BROWSER=notDefault`).
final class OnboardingTests: ArktUITestCase {
  private typealias ID = AXID.Onboarding

  private func onboardingSandbox() throws -> Sandbox {
    let sandbox = try Sandbox()
    sandbox.showsOnboarding = true
    return sandbox
  }

  private func button(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.buttons[identifier]
  }

  /// Presses a button once it exists and is enabled.
  private func press(_ app: XCUIApplication, _ identifier: String, file: StaticString = #filePath,
                     line: UInt = #line) {
    let element = button(app, identifier)
    guard waitForEnabled(element, file: file, line: line) else { return }
    element.click()
  }

  /// Import now opens the browser data import in place of the step (#514): its consent, then progress, then a result.
  /// Import there runs what is ticked; Continue on the result returns to the step's Imported state.
  private func runImportHandOff(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
    let primary = button(app, AXID.BrowserDataImport.primary)
    XCTAssertTrue(Waits.until("the consent's Import") { primary.exists && primary.isEnabled && primary.label == "Import" },
                  file: file, line: line)
    try assertNoArc(app)
    primary.click()
    XCTAssertTrue(Waits.until("the result's Continue") { primary.exists && primary.label == "Continue" },
                  file: file, line: line)
    try assertNoArc(app)
    primary.click()
  }

  private func step(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    Shell.element(app, ID.step(identifier))
  }

  private func swatch(_ app: XCUIApplication, _ title: String) -> XCUIElement {
    app.radioButtons.matching(NSPredicate(format: "identifier == %@ AND label == %@", ID.swatch, title)).firstMatch
  }

  /// Every label, title and string value under the flow's root.
  private func visibleStrings(_ app: XCUIApplication) -> [String] {
    let root = Shell.element(app, ID.root)
    var strings = [root.label]
    for element in root.descendants(matching: .any).allElementsBoundByIndex {
      strings.append(element.label)
      strings.append(element.title)
      if let value = element.value as? String { strings.append(value) }
    }
    return strings.filter { !$0.isEmpty }
  }

  private func assertNoArc(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
    let word = try Regex("\\bArc\\b")
    for string in visibleStrings(app) {
      XCTAssertNil(string.firstMatch(of: word), "\"\(string)\" names Arc", file: file, line: line)
    }
  }

  // MARK: - Arc found

  func test_onboarding_arcBranchImportsAndLandsInTheBrowser() async throws {
    let server = try await fixtureServer()
    let sandbox = try onboardingSandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)

    XCTAssertTrue(waitFor(step(app, "welcome")))
    XCTAssertEqual(Shell.element(app, ID.root).label, "Welcome to Arkt")
    try assertNoArc(app)
    press(app, ID.getStarted)

    XCTAssertTrue(waitFor(step(app, "import")))
    XCTAssertTrue(waitForEnabled(button(app, ID.importData)), "Import is enabled once the count pass finished")
    let pinned = Shell.element(app, ID.countPinnedTabs)
    XCTAssertTrue(pinned.label.hasSuffix("pinned tabs") || pinned.label.hasSuffix("pinned tab"), pinned.label)
    XCTAssertEqual(Shell.element(app, ID.countSpaces).label, "\(ArcFixture.expected.spaces) Spaces")
    XCTAssertEqual(Shell.element(app, ID.progress).label, "1 of 5")
    try assertNoArc(app)
    press(app, ID.importData)
    try runImportHandOff(app)

    XCTAssertTrue(waitFor(button(app, ID.continueButton)))
    XCTAssertTrue(Shell.element(app, ID.countSpaces).label.hasSuffix(", imported"))
    XCTAssertFalse(button(app, ID.startFresh).exists, "Imported has Continue only")
    try assertNoArc(app)
    press(app, ID.continueButton)

    // Make it yours after an import: "Imported" leads and is selected; Skip keeps the imported look.
    XCTAssertTrue(waitFor(step(app, "theme")))
    let imported = swatch(app, "Imported")
    XCTAssertTrue(waitFor(imported))
    XCTAssertEqual(imported.value as? Int, 1, "Imported is selected")
    XCTAssertFalse(Shell.element(app, ID.appearanceDark).isEnabled, "Appearance is disabled while Imported is selected")
    swatch(app, "Sage").click()
    XCTAssertTrue(Waits.until("Sage selected") { self.swatch(app, "Sage").value as? Int == 1 })
    try assertNoArc(app)
    press(app, ID.skip)
    XCTAssertTrue(waitFor(step(app, "default")))
    press(app, ID.back)
    XCTAssertTrue(waitFor(step(app, "theme")))
    XCTAssertTrue(Waits.until("Imported selected again") { self.swatch(app, "Imported").value as? Int == 1 },
                  "Skip restored what the step opened with")
    press(app, ID.continueButton)

    press(app, ID.notNow)
    for _ in 1...5 { press(app, ID.next) }
    XCTAssertTrue(waitFor(step(app, "done")))
    try assertNoArc(app)
    press(app, ID.startBrowsing)

    XCTAssertTrue(waitUntilGone(Shell.element(app, ID.root)))
    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("\(ArcFixture.expected.spaces) Space dots") { dots.count == ArcFixture.expected.spaces },
                  "the import's Spaces, no fresh one")
    XCTAssertTrue(Shell.waitForCommandBar(app, open: true))
    XCTAssertTrue(Shell.todayRow(app, label: "New Tab").exists || waitFor(Shell.todayRow(app, label: "New Tab")))
    XCTAssertTrue(try checksums.unchanged(in: sandbox.arcDirectory), "the Arc copy is only read")
  }

  // MARK: - No Arc

  func test_onboarding_noArcBranchKeysAndSkipSetup() throws {
    let app = try launch(try onboardingSandbox())
    XCTAssertTrue(waitFor(step(app, "welcome")))
    app.typeKey(.return, modifierFlags: [])                       // Return is Get started

    XCTAssertTrue(waitFor(step(app, "theme")))
    XCTAssertEqual(Shell.element(app, ID.progress).label, "1 of 4")
    XCTAssertEqual(swatch(app, "Dune").value as? Int, 1)

    // Escape in the Name field ends editing and restores the value it had on focus; a second Escape skips.
    let name = app.textFields[ID.name]
    name.click()
    name.typeText("Home")
    XCTAssertTrue(Waits.until("typed") { (name.value as? String) == "Home" })
    name.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(Waits.until("restored") { (name.value as? String) != "Home" })
    XCTAssertTrue(step(app, "theme").exists, "the first Escape stays on the step")

    // Right never commits a choice; Left goes back; Right returns only to a step left with Back.
    app.typeKey(.rightArrow, modifierFlags: [])
    XCTAssertTrue(step(app, "theme").exists)
    app.typeKey(.escape, modifierFlags: [])                       // Skip
    XCTAssertTrue(waitFor(step(app, "default")))
    app.typeKey(.leftArrow, modifierFlags: [])
    XCTAssertTrue(waitFor(step(app, "theme")))
    app.typeKey(.rightArrow, modifierFlags: [])
    XCTAssertTrue(waitFor(step(app, "default")))

    // Skip setup asks first; Cancel returns to the same step.
    press(app, ID.skipSetup)
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(waitFor(sheet))
    XCTAssertTrue(sheet.staticTexts["Skip setup?"].exists)
    sheet.buttons["Cancel"].click()
    XCTAssertTrue(waitUntilGone(sheet))
    XCTAssertTrue(step(app, "default").exists)
    try assertNoArc(app)

    press(app, ID.skipSetup)
    XCTAssertTrue(waitFor(sheet))
    sheet.buttons["Skip setup"].click()
    XCTAssertTrue(waitUntilGone(Shell.element(app, ID.root)))
    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("one Space dot") { dots.count == 1 })
    XCTAssertEqual(dots.firstMatch.label, "Space 1", "the Space Make it yours created, no second one")
  }

  /// A confirmed Skip setup during (or right after) an import adds no Space: the browser opens on the imported ones.
  func test_onboarding_skipSetupDuringImportAddsNoSpace() async throws {
    let server = try await fixtureServer()
    let sandbox = try onboardingSandbox()
    _ = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)
    press(app, ID.getStarted)
    press(app, ID.importData)
    let primary = button(app, AXID.BrowserDataImport.primary)
    XCTAssertTrue(Waits.until("the consent's Import") { primary.exists && primary.isEnabled && primary.label == "Import" })
    primary.click()
    press(app, ID.skipSetup)
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(waitFor(sheet))
    sheet.buttons["Skip setup"].click()
    XCTAssertTrue(waitUntilGone(Shell.element(app, ID.root)))
    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("\(ArcFixture.expected.spaces) Space dots") { dots.count == ArcFixture.expected.spaces })
  }

  // MARK: - Help > Welcome to Arkt

  func test_onboarding_doesNotShowAgainAndHelpReopensIt() throws {
    let sandbox = try onboardingSandbox()
    var app = try launch(sandbox)
    press(app, ID.skipSetup)
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(waitFor(sheet))
    sheet.buttons["Skip setup"].click()
    XCTAssertTrue(waitUntilGone(Shell.element(app, ID.root)))
    quit(app)

    app = try launch(sandbox)
    XCTAssertTrue(Waits.until("one Space dot") { Shell.spaceDots(app).count == 1 })
    XCTAssertFalse(Shell.element(app, ID.root).exists, "a finished first run does not show again")
    app.menuBars.menuBarItems["Help"].click()
    app.menuBars.menuItems["Welcome to Arkt"].click()
    XCTAssertTrue(waitFor(step(app, "welcome")))
  }
}
