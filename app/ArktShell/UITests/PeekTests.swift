import XCTest

/// Peek end to end (#348, docs/design/peek.md): a link to another site in a pinned tab opens a Peek over it, every
/// close leaves the source as it was, Open as Tab and Add to Split View move the same page into the sidebar, and the
/// toast's Reopen brings a closed Peek back (BH-144, BH-148 to BH-150, KB-076, KB-079).
///
/// The fixture server's `/x/<name>` page links to `localhost`, another host on the same server, so the click is a
/// link to another site and the Peek rules apply.
final class PeekTests: ArktUITestCase {
  /// Opens `/x/alpha`, pins the tab, clicks its cross-site link and returns the app and the open Peek card.
  @MainActor
  private func openPeek(_ server: FixtureServer) throws -> (XCUIApplication, XCUIElement) {
    let app = try launch(try Sandbox())
    app.activate()
    XCTAssertTrue(waitFor(app, .runningForeground), "the app is frontmost before any key")
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.crossSitePage("alpha"), in: app))
    app.typeKey("d", modifierFlags: .command)                  // Cmd-D pins the shown tab (BH-012)
    let pinned = app.outlineRows.matching(identifier: AXID.Sidebar.rowPinned)
      .element(matching: NSPredicate(format: "label == %@", FixtureServer.title(ofPage: "alpha")))
    XCTAssertTrue(waitFor(pinned), "the page is a pinned tab")

    let window = shellWindow(of: app)
    let link = window.webViews.firstMatch.links["Next"]
    XCTAssertTrue(waitFor(link))
    XCTAssertTrue(Waits.until("the fixture link to be interactive") { link.exists && link.isHittable })
    link.click()

    let card = app.dialogs[AXID.Peek.card]
    XCTAssertTrue(waitFor(card), "the cross-site link opens a Peek (BH-144)")
    XCTAssertTrue(Waits.until("the Peek's title") { card.label.contains(FixtureServer.title(ofPage: "alpha-next")) })
    XCTAssertTrue(waitUntilGone(app.groups[AXID.Content.card]), "the source card leaves the accessibility tree")
    return (app, card)
  }

  /// The Peek's URL is what the source did not navigate to, and the source stays the pinned row (BH-152).
  @MainActor
  func test_BH144_BH152_aCrossSiteLinkOpensAPeekWithoutASidebarRow() async throws {
    let server = try await fixtureServer()
    let (app, card) = try openPeek(server)
    XCTAssertEqual(Shell.todayRows(app).count, 0, "the Peek gets no Today row")

    app.typeKey("w", modifierFlags: .command)                  // KB-078
    XCTAssertTrue(waitUntilGone(card), "Cmd-W closes the Peek")
    XCTAssertTrue(waitFor(app.groups[AXID.Content.card]), "the source card is back in the accessibility tree")
    XCTAssertTrue(waitFor(app.groups[AXID.Content.card].webViews.firstMatch), "with its page")
    let kept = app.outlineRows.matching(identifier: AXID.Sidebar.rowPinned)
      .element(matching: NSPredicate(format: "label == %@", FixtureServer.title(ofPage: "alpha")))
    XCTAssertTrue(waitFor(kept), "the source tab stays open where it was (BH-149)")
  }

  /// The Close control closes the Peek and the toast's Reopen brings it back (BH-149, BH-150, KB-079).
  @MainActor
  func test_BH149_BH150_theCloseControlClosesThePeekAndOffersReopen() async throws {
    let server = try await fixtureServer()
    let (app, card) = try openPeek(server)
    let close = app.buttons[AXID.Peek.close]
    XCTAssertTrue(waitFor(close))
    close.click()
    XCTAssertTrue(waitUntilGone(card))

    let reopen = Shell.element(app, AXID.Toast.action)
    XCTAssertTrue(waitFor(reopen), "the Peek closed toast offers Reopen")
    reopen.click()
    XCTAssertTrue(waitFor(card), "Reopen brings the same Peek back (BH-150, KB-079)")
  }

  /// A click on the scrim, the area around the card, closes the Peek (BH-149, GS-023).
  @MainActor
  func test_BH149_GS023_aClickOnTheScrimClosesThePeek() async throws {
    let server = try await fixtureServer()
    let (app, card) = try openPeek(server)
    let window = shellWindow(of: app)
    // The Peek is inset 56 pt from the content card's sides: 24 pt left of it is the scrim, not the card.
    let origin = window.coordinate(withNormalizedOffset: .zero)
    let scrim = origin.withOffset(CGVector(dx: card.frame.minX - window.frame.minX - 24,
                                           dy: card.frame.midY - window.frame.minY))
    scrim.click()
    XCTAssertTrue(waitUntilGone(card))
  }

  /// Esc closes the Peek when the page does not use it (BH-149, KB-039, KB-078).
  @MainActor
  func test_BH149_KB078_escapeClosesThePeek() async throws {
    let server = try await fixtureServer()
    let (app, card) = try openPeek(server)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(waitUntilGone(card))
  }

  /// Open as Tab (Cmd-O, BH-148, KB-076): the page becomes the top Today row and is selected.
  @MainActor
  func test_BH148_KB076_openAsTabMakesThePageATodayRow() async throws {
    let server = try await fixtureServer()
    let (app, card) = try openPeek(server)
    let expand = app.buttons[AXID.Peek.expand]
    XCTAssertTrue(waitFor(expand))
    expand.click()
    XCTAssertTrue(waitUntilGone(card))

    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha-next"))
    XCTAssertTrue(waitForOutlineRows("the Peek's page as a Today row") { row.exists && row.isSelected })
  }

  /// Add to Split View (BH-148, BH-117): the source and the Peek become a split row.
  @MainActor
  func test_BH148_addToSplitViewMakesASplitRow() async throws {
    let server = try await fixtureServer()
    let (app, card) = try openPeek(server)
    let split = app.buttons[AXID.Peek.split]
    XCTAssertTrue(waitFor(split))
    split.click()
    XCTAssertTrue(waitUntilGone(card))

    let splitRow = app.outlineRows.matching(identifier: AXID.Sidebar.rowSplit).firstMatch
    XCTAssertTrue(waitFor(splitRow), "the sidebar shows a split row")
  }
}
