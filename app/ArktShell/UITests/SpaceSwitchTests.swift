import XCTest

/// Space switching by Ctrl-1..9, Cmd-Opt arrows and Space dots, plus the two-finger swipe probe (plan U12).
///
/// The last-active tab check reads the Today row through the proxy outline (#269); the Space dots and
/// `sidebar.page` do not need the rows.
///
/// Precondition (not set by the harness): the Mac running these tests must not bind Ctrl-1 or Ctrl-2 to Mission
/// Control's "Switch to Desktop 1" / "Switch to Desktop 2" (System Settings > Keyboard > Keyboard Shortcuts > Mission
/// Control). Where they are on, the system takes the key before the app sees it and the Ctrl-N waits time out. The
/// tests do not change OS settings.
///
/// A key that must change nothing is followed by a key that does change the Space, and the test waits for that
/// change before checking. Menu key equivalents run in order, every switch goes through `SpacePagerView.go(to:)`
/// (which stops a running settle), and the arrows count from the Space a running switch heads to; so once the
/// follow-up's Space is selected, the no-op key has been handled and no switch it might have started is pending.
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

    // Two Spaces: Ctrl-9 is out of range and changes nothing. Sync point: Cmd-Opt-Right, which from Alpha (the
    // Space Ctrl-9 must leave current) lands on Beta.
    typeKey("9", modifiers: .control, in: app)
    typeKey(.rightArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(second))
    XCTAssertTrue(waitForSelected(spacePage(app, title: secondSpaceTitle)))
    XCTAssertFalse(first.isSelected)
    // At rest the pager hides every page but the current one, and a hidden page leaves the accessibility tree
    // (`SpacePagerView.updatePageVisibility`); the other page is gone once the settle ends.
    XCTAssertTrue(waitUntilGone(spacePage(app, title: firstSpaceTitle)))
    XCTAssertEqual(Shell.spaceDots(app).count, ArcFixture.expected.spaces)
  }

  /// Wrap at the ends is #98 and is not asserted. A further arrow at either end stays put.
  func test_KB033_KB034_cmdOptArrowsMoveBetweenSpaces() async throws {
    let app = try await launchSeeded()
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))

    typeKey(.rightArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(spaceDot(app, index: 1)))
    XCTAssertTrue(waitForSelected(spacePage(app, title: secondSpaceTitle)))

    // At the last Space a further Right stays put. Sync point: one Left, which lands on Alpha. The arrows count from
    // the target, so a Right that pushed the target past Beta would leave Beta current here.
    typeKey(.rightArrow, modifiers: [.command, .option], in: app)
    typeKey(.leftArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(spaceDot(app, index: 0)))
    XCTAssertTrue(waitForSelected(spacePage(app, title: firstSpaceTitle)))
    XCTAssertFalse(spaceDot(app, index: 1).isSelected)
    XCTAssertTrue(waitUntilGone(spacePage(app, title: secondSpaceTitle)))

    // At the first Space a further Left stays put. Sync point: one Right, which lands on Beta. A Left that pushed the
    // target below Alpha would leave Alpha current here.
    typeKey(.leftArrow, modifiers: [.command, .option], in: app)
    typeKey(.rightArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(spaceDot(app, index: 1)))
    XCTAssertTrue(waitForSelected(spacePage(app, title: secondSpaceTitle)))
    XCTAssertFalse(spaceDot(app, index: 0).isSelected)
    XCTAssertTrue(waitUntilGone(spacePage(app, title: firstSpaceTitle)))
    XCTAssertEqual(Shell.spaceDots(app).count, ArcFixture.expected.spaces)
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
    XCTAssertTrue(waitForOutlineRows("\(row) to exist") { row.exists })
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
