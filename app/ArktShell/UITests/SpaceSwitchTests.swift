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

  /// #301: a newly created, empty Space clears the content card without losing the previous Space's live tab.
  @MainActor
  func test_E_issue301_newEmptySpaceClearsContentAndRestoresLiveTab() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    XCTAssertTrue(waitFor(spaceDot(app, index: 0), label: "Space 1"))
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))

    let alpha = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    XCTAssertTrue(waitForOutlineRows("the original tab to be selected") { alpha.exists && alpha.isSelected })
    XCTAssertTrue(Waits.until("the loopback page to load") { server.requestedPaths.contains("/p/alpha") })
    let window = shellWindow(of: app)
    let webView = window.webViews.firstMatch
    let next = webView.links["Next"]
    // Establish the web accessibility query before using its absence to detect stale content.
    XCTAssertTrue(waitFor(webView))
    XCTAssertTrue(Waits.until("the fixture link to be interactive") { next.exists && next.isHittable })
    let initialLoads = server.requestedPaths.filter { $0 == "/p/alpha" }.count

    app.menuBars.menuBarItems["Spaces"].click()
    let newSpace = app.menuBars.menuItems["New Space"]
    XCTAssertTrue(waitFor(newSpace))
    newSpace.click()
    XCTAssertTrue(Waits.until("two Space dots") { Shell.spaceDots(app).count == 2 })
    XCTAssertTrue(waitFor(spaceDot(app, index: 1), label: "Space 2"))
    XCTAssertTrue(waitForSelected(spaceDot(app, index: 1)))
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(waitForSelected(spacePage(app, title: "Space 2")))
    XCTAssertTrue(waitUntilGone(spacePage(app, title: "Space 1")))
    attachSpaceWindow(app, title: "Space 2", name: "issue-301-empty-space-header")
    XCTAssertTrue(waitUntilGone(webView), "an empty Space must not show the previous Space's web content")
    XCTAssertFalse(next.exists)
    XCTAssertEqual(Shell.todayRows(app).count, 0)

    spaceDot(app, index: 0).click()
    XCTAssertTrue(waitForSelected(spacePage(app, title: "Space 1")))
    XCTAssertTrue(waitUntilGone(spacePage(app, title: "Space 2")))
    XCTAssertTrue(waitForSelected(alpha))
    XCTAssertTrue(Waits.until("the original fixture link to return") { next.exists && next.isHittable })
    XCTAssertEqual(Shell.todayRows(app).count, 1)
    XCTAssertEqual(server.requestedPaths.filter { $0 == "/p/alpha" }.count, initialLoads,
                   "restoring the live tab must not reload it")
    attachSpaceWindow(app, title: "Space 1", name: "issue-301-restored-populated-space")

    // Repeat through the keyboard path without relying on system-reserved Ctrl-number shortcuts.
    typeKey(.rightArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(spacePage(app, title: "Space 2")))
    XCTAssertTrue(waitUntilGone(spacePage(app, title: "Space 1")))
    XCTAssertTrue(waitUntilGone(webView))
    XCTAssertFalse(next.exists)
    typeKey(.leftArrow, modifiers: [.command, .option], in: app)
    XCTAssertTrue(waitForSelected(spacePage(app, title: "Space 1")))
    XCTAssertTrue(waitForSelected(alpha))
    XCTAssertTrue(Waits.until("the restored fixture link to be interactive") { next.exists && next.isHittable })
    XCTAssertEqual(server.requestedPaths.filter { $0 == "/p/alpha" }.count, initialLoads)

    // A real link navigation distinguishes a live restored tab from a leftover content snapshot.
    next.click()
    XCTAssertTrue(Waits.until("the restored tab to follow its loopback link") {
      server.requestedPaths.contains("/p/alpha-next")
    })
    let navigated = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha-next"))
    XCTAssertTrue(waitForSelected(navigated))
    XCTAssertEqual(Shell.todayRows(app).count, 1, "the restored tab navigates without creating another tab")
  }

  private func attachSpaceWindow(_ app: XCUIApplication, title: String, name: String) {
    let header = spacePage(app, title: title).descendants(matching: .any)[AXID.Sidebar.spaceTitle]
    XCTAssertTrue(waitFor(header))
    header.hover()
    XCTAssertTrue(waitFor(app.buttons[AXID.Sidebar.spaceRename]))
    XCTAssertTrue(waitFor(app.buttons[AXID.Sidebar.spaceOptions]))
    let attachment = XCTAttachment(screenshot: shellWindow(of: app).screenshot())
    attachment.name = name
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
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
