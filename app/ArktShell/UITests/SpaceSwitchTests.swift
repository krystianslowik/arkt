import XCTest

/// Space switching by Ctrl-1..9, Cmd-Opt arrows and Space dots, plus the two-finger swipe probe (plan U12).
///
/// Outline rows are not in the out-of-process accessibility tree (#269). The last-active tab check skips in that
/// case; the Space dots and `sidebar.page` do not need the rows.
final class SpaceSwitchTests: ArktUITestCase {
  /// Seeded fixture (`StorableSidebar-synthetic.json`): Alpha, then Beta.
  private let firstSpaceTitle = "Alpha"
  private let secondSpaceTitle = "Beta"
  /// Today row in Alpha, not the tab a fresh visit restores (the first pinned tab).
  private let chosenTabTitle = "My Renamed Tab"

  // MARK: - Keys and dots

  func test_KB035_BH041_ctrlNumberGoesToSpace() async throws {
    let app = try await launchSeeded()
    let first = spaceDot(app, index: 0)
    let second = spaceDot(app, index: 1)
    XCTAssertEqual(first.label, firstSpaceTitle)
    XCTAssertEqual(second.label, secondSpaceTitle)
    XCTAssertTrue(waitForSelected(first))
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))

    typeKey("2", modifiers: .control, in: app)
    XCTAssertTrue(waitForSelected(second))
    XCTAssertTrue(waitForSelected(spacePage(app, title: secondSpaceTitle)))
    XCTAssertFalse(first.isSelected)

    typeKey("1", modifiers: .control, in: app)
    XCTAssertTrue(waitForSelected(first))
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))
    XCTAssertFalse(second.isSelected)

    // Two Spaces: Ctrl-9 is out of range and changes nothing.
    typeKey("9", modifiers: .control, in: app)
    XCTAssertTrue(first.isSelected)
    XCTAssertFalse(second.isSelected)
    XCTAssertTrue(spacePage(app, title: firstSpaceTitle).isSelected)
    XCTAssertEqual(Shell.spaceDots(app).count, 2)
  }

  /// Wrap at the ends is #98 and is not asserted. A further arrow at either end stays put.
  func test_KB033_KB034_cmdOptArrowsMoveBetweenSpaces() async throws {
    let app = try await launchSeeded()
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))

    typeKey(.rightArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(spaceDot(app, index: 1)))
    XCTAssertTrue(waitForSelected(spacePage(app, title: secondSpaceTitle)))

    typeKey(.rightArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(spaceDot(app, index: 1).isSelected)
    XCTAssertFalse(spaceDot(app, index: 0).isSelected)
    XCTAssertTrue(spacePage(app, title: secondSpaceTitle).isSelected)

    typeKey(.leftArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(spaceDot(app, index: 0)))
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))

    typeKey(.leftArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(spaceDot(app, index: 0).isSelected)
    XCTAssertFalse(spaceDot(app, index: 1).isSelected)
    XCTAssertTrue(spacePage(app, title: firstSpaceTitle).isSelected)
  }

  func test_BH035_spaceDotClickSelectsSpace() async throws {
    let app = try await launchSeeded()
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))

    let second = spaceDot(app, index: 1)
    XCTAssertTrue(waitFor(second))
    second.click()
    XCTAssertTrue(waitForSelected(second))
    XCTAssertTrue(waitForSelected(spacePage(app, title: secondSpaceTitle)))
    XCTAssertFalse(spaceDot(app, index: 0).isSelected)
  }

  func test_BH036_switchingBackRestoresLastActiveTab() async throws {
    let app = try await launchSeeded()
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))

    let row = Shell.todayRow(app, label: chosenTabTitle)
    // Missing rows are #269. An expected failure on this wait left the app's event loop unmonitorable, so skip.
    guard rowAppears(row) else {
      throw XCTSkip("#269: outline rows are not in the out-of-process accessibility tree")
    }
    XCTAssertFalse(row.isSelected, "the chosen row must not already be the restored tab")
    row.click()
    XCTAssertTrue(waitForSelected(row))

    typeKey("2", modifiers: .control, in: app)
    XCTAssertTrue(waitForSelected(spacePage(app, title: secondSpaceTitle)))

    typeKey("1", modifiers: .control, in: app)
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))
    XCTAssertTrue(waitForSelected(row))
  }

  /// Probe result: `sidebar.page.scroll(byDeltaX: -400, deltaY: 0)` left the Alpha dot selected. The synthesized
  /// scroll's gesture phase was 0, and `SpacePagerView.scrollWheel` ignores an event with an empty phase.
  func test_GS001_twoFingerSwipeMovesSpace() throws {
    throw XCTSkip("GS-001: XCUITest scroll has no gesture phases; manual check in #26")
  }

  // MARK: - Seeded launch

  private func launchSeeded() async throws -> XCUIApplication {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    try sandbox.seedFromArcFixture(server: server)
    let app = try launch(sandbox)
    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("2 Space dots") { dots.count == ArcFixture.expected.spaces })
    return app
  }

  /// True when `row` appears before the scaled default timeout. Does not record a failure: a missing row is #269,
  /// and the caller skips.
  private func rowAppears(_ row: XCUIElement) -> Bool {
    let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { row.exists } }
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
    return XCTWaiter().wait(for: [expectation], timeout: Waits.scaled(nil)) == .completed
  }

  private func spaceDot(_ app: XCUIApplication, index: Int) -> XCUIElement {
    Shell.spaceDots(app).element(boundBy: index)
  }

  private func spacePage(_ app: XCUIApplication, title: String) -> XCUIElement {
    app.groups.matching(identifier: AXID.Sidebar.page)
      .matching(NSPredicate(format: "label == %@", title))
      .firstMatch
  }

  /// Menu key equivalents reach the app only while it is frontmost.
  private func typeKey(_ key: String, modifiers: XCUIElement.KeyModifierFlags, in app: XCUIApplication) {
    app.activate()
    XCTAssertTrue(waitFor(app, .runningForeground))
    app.typeKey(key, modifierFlags: modifiers)
  }

  private func typeKey(_ key: XCUIKeyboardKey, modifiers: XCUIElement.KeyModifierFlags, in app: XCUIApplication) {
    app.activate()
    XCTAssertTrue(waitFor(app, .runningForeground))
    app.typeKey(key, modifierFlags: modifiers)
  }
}
