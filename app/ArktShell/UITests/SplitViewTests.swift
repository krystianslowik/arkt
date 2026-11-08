import XCTest

/// Split View wiring through the real app and synthetic loopback pages (plan U15).
final class SplitViewTests: ArktUITestCase {
  private let splitID = "split.container"
  private let paneID = "split.pane"
  private let rowID = "sidebar.row.split"
  private let modifiers: XCUIElement.KeyModifierFlags = [.control, .shift]

  private func panes(_ app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: paneID)
  }

  private func splitRow(_ app: XCUIApplication) -> XCUIElement {
    app.outlineRows.matching(identifier: rowID).firstMatch
  }

  private func startSplit() async throws -> (XCUIApplication, Sandbox, FixtureServer) {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    do { try sandbox.seedFromArcFixture(server: server) } catch {
      sandbox.remove()
      throw error
    }
    let app = try launch(sandbox)
    let row = splitRow(app)
    XCTAssertTrue(waitFor(row))
    row.click()
    XCTAssertTrue(Waits.until("two split panes") { self.panes(app).count == 2 })
    return (app, sandbox, server)
  }

  private func select(_ index: Int, in app: XCUIApplication) {
    app.typeKey("\(index + 1)", modifierFlags: modifiers)
    XCTAssertTrue(Waits.until("pane \(index + 1) selected") {
      self.panes(app).element(boundBy: index).isSelected
    })
  }

  private func add(_ name: String, server: FixtureServer, app: XCUIApplication, count: Int) {
    app.typeKey("=", modifierFlags: modifiers)
    XCTAssertTrue(Shell.waitForCommandBar(app, open: true))
    Shell.submit(server.page(name), in: app)
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    XCTAssertTrue(Waits.until("\(count) split panes") { self.panes(app).count == count })
  }

  func test_BH115_BH125_KB074_splitShowsPanesAndFocus() async throws {
    let (app, _, server) = try await startSplit()
    XCTAssertTrue(Shell.element(app, splitID).exists)
    XCTAssertEqual(panes(app).allElementsBoundByIndex.filter(\.isSelected).count, 1)
    select(1, in: app)
    XCTAssertTrue(Shell.openCommandBar(app, key: "l"))
    Shell.submit(server.page("focus"), in: app)
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    app.typeKey("d", modifierFlags: [.command, .shift])
    let toolbar = panes(app).element(boundBy: 1).descendants(matching: .any)
      .matching(identifier: AXID.Toolbar.urlBar).firstMatch
    XCTAssertTrue(Waits.until("focused pane URL") { (toolbar.value as? String)?.contains("/p/focus") == true })
    let divider = app.descendants(matching: .any).matching(identifier: "split.divider").firstMatch
    XCTAssertTrue(waitFor(divider))
    let before = String(describing: divider.value)
    let destination = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .withOffset(CGVector(dx: 0, dy: 35))
    divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.3, thenDragTo: destination)
    XCTAssertTrue(Waits.until("divider accessibility value changes") { String(describing: divider.value) != before })
  }

  func test_KB070_BH116_addPaneAndFullSplitToast() async throws {
    let (app, _, server) = try await startSplit()
    add("third", server: server, app: app, count: 3)
    add("fourth", server: server, app: app, count: 4)
    app.typeKey("=", modifierFlags: modifiers)
    let toast = Shell.element(app, AXID.Toast.root)
    XCTAssertTrue(Waits.until("full split toast") { toast.exists && toast.label.contains("Cannot Add New Pane") })
    XCTAssertEqual(panes(app).count, 4)
  }

  func test_KB071_KB072_KB073_BH122_BH128_paneKeys() async throws {
    let (app, _, server) = try await startSplit()
    add("third", server: server, app: app, count: 3)
    add("fourth", server: server, app: app, count: 4)
    for index in 0..<4 { select(index, in: app) }
    app.typeKey("]", modifierFlags: modifiers)
    XCTAssertTrue(Waits.until("focus wraps to first pane") { self.panes(app).element(boundBy: 0).isSelected })
    app.typeKey("[", modifierFlags: modifiers)
    XCTAssertTrue(Waits.until("previous focus wraps to fourth pane") { self.panes(app).element(boundBy: 3).isSelected })
    // The close shortcut separates the focused page; it must not add an Archive entry.
    app.menuBars.menuBarItems["Window"].click()
    app.menuBars.menuItems["Show Archive"].click()
    let archive = app.windows[AXID.Archive.window]
    XCTAssertTrue(waitFor(archive))
    let before = archive.tables[AXID.Archive.table].tableRows.count
    archive.typeKey("w", modifierFlags: .command)
    app.typeKey("-", modifierFlags: modifiers)
    XCTAssertTrue(Waits.until("three panes after separating") { self.panes(app).count == 3 })
    let separated = Shell.todayRow(app, label: FixtureServer.title(ofPage: "fourth"))
    XCTAssertTrue(waitFor(separated))
    separated.click()
    app.typeKey("d", modifierFlags: [.command, .shift])
    let url = Shell.element(app, AXID.Toolbar.urlBar)
    XCTAssertTrue(Waits.until("separated page URL") { (url.value as? String)?.contains("/p/fourth") == true })
    app.menuBars.menuBarItems["Window"].click()
    app.menuBars.menuItems["Show Archive"].click()
    XCTAssertTrue(waitFor(archive))
    XCTAssertEqual(archive.tables[AXID.Archive.table].tableRows.count, before)
    let archived = archive.tables[AXID.Archive.table].tableRows.matching(identifier: AXID.Archive.row)
      .element(matching: NSPredicate(format: "label == %@", FixtureServer.title(ofPage: "fourth")))
    XCTAssertFalse(archived.exists)
  }

  func test_BH121_GS033_sidebarSplitRow() async throws {
    let (app, _, _) = try await startSplit()
    let row = splitRow(app)
    let before = Shell.todayRows(app).count
    XCUIElement.perform(withKeyModifiers: .option) { row.click() }
    XCTAssertTrue(Waits.until("option-click separates the split") {
      !self.splitRow(app).exists && Shell.todayRows(app).count == before + 2
    })
    // Re-create a split from the current plain tab, then exercise its context menu.
    let current = Shell.todayRows(app).allElementsBoundByIndex.first { $0.isSelected }
    let tab = try XCTUnwrap(current)
    XCUIElement.perform(withKeyModifiers: .option) { tab.click() }
    XCTAssertTrue(waitFor(splitRow(app)))
    let count = Shell.todayRows(app).count
    let control = try XCTUnwrap(Shell.todayRows(app).allElementsBoundByIndex.first)
    let splitItem = app.menuItems["Separate All Tabs"]
    let controlItem = app.menuItems["Archive Below"]
    var snapshots = ""
    var splitOpened = [Bool]()
    for controlClick in [false, true] {
      let method = controlClick ? "control-click" : "right-click"
      func click(_ target: XCUIElement) {
        if controlClick { XCUIElement.perform(withKeyModifiers: .control) { target.click() } }
        else { target.rightClick() }
      }
      click(control)
      let controlOpened = controlItem.waitForExistence(timeout: Waits.scaled(3))
      snapshots += "\n\(method) regular row menu=\(controlOpened):\n" + app.debugDescription
      app.typeKey(.escape, modifierFlags: [])
      XCTAssertTrue(Waits.until("regular menu dismissed") { !controlItem.exists })
      click(splitRow(app))
      let opened = splitItem.waitForExistence(timeout: Waits.scaled(3))
      splitOpened.append(opened)
      snapshots += "\n\(method) split row menu=\(opened):\n" + app.debugDescription
      app.typeKey(.escape, modifierFlags: [])
      XCTAssertTrue(Waits.until("split menu dismissed") { !splitItem.exists })
    }
    let probe = XCTAttachment(string: snapshots)
    probe.name = "regular and split row context menu accessibility probes"
    probe.lifetime = .deleteOnSuccess
    add(probe)
    XCTAssertTrue(splitOpened.contains(true), "split menu missing; inspect the paired control probes")
    guard let method = splitOpened.firstIndex(of: true) else { return }
    if method == 0 { splitRow(app).rightClick() }
    else { XCUIElement.perform(withKeyModifiers: .control) { self.splitRow(app).click() } }
    XCTAssertTrue(splitItem.waitForExistence(timeout: Waits.scaled(3)))
    let item = splitItem
    item.click()
    XCTAssertTrue(Waits.until("context menu separates the split") {
      !self.splitRow(app).exists && Shell.todayRows(app).count == count + 2
    })
  }

  func test_GS011_BH117_dragTabOntoPageSplits() async throws {
    let server = try await fixtureServer()
    let app = try launch(try Sandbox())
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("alpha"), in: app))
    XCTAssertTrue(Shell.openInNewTab(server.page("beta"), in: app))
    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    XCTAssertTrue(waitFor(row))
    let card = app.groups[AXID.Content.card]
    XCTAssertTrue(waitFor(card))
    let target = card.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      .press(forDuration: 0.3, thenDragTo: target)
    XCTAssertTrue(waitFor(Shell.element(app, splitID)))
    XCTAssertEqual(panes(app).count, 2)
  }

  func test_BH123_splitSurvivesRelaunchAndArchive() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("first"), in: app))
    let first = Shell.todayRow(app, label: FixtureServer.title(ofPage: "first"))
    XCTAssertTrue(waitFor(first))
    XCUIElement.perform(withKeyModifiers: .option) { first.click() }
    XCTAssertTrue(Waits.until("two Today split panes") { self.panes(app).count == 2 })
    add("archive", server: server, app: app, count: 3)
    quit(app)
    let relaunched = try launch(sandbox)
    let row = splitRow(relaunched)
    XCTAssertTrue(waitFor(row))
    row.click()
    XCTAssertTrue(Waits.until("split survives relaunch") { self.panes(relaunched).count == 3 })
    // The newly added pane was focused before quitting and is restored as focused.
    let selected = try XCTUnwrap(panes(relaunched).allElementsBoundByIndex.first { $0.isSelected })
    XCTAssertTrue(Waits.until("added page title restored") {
      selected.webViews.firstMatch.label.contains(FixtureServer.title(ofPage: "archive"))
    })
    relaunched.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(Waits.until("Cmd-W removes one pane") { self.panes(relaunched).count == 2 })
    relaunched.menuBars.menuBarItems["Window"].click()
    relaunched.menuBars.menuItems["Show Archive"].click()
    let archive = relaunched.windows[AXID.Archive.window]
    XCTAssertTrue(waitFor(archive))
    let archived = archive.tables[AXID.Archive.table].tableRows.matching(identifier: AXID.Archive.row)
      .element(matching: NSPredicate(format: "label == %@", FixtureServer.title(ofPage: "archive")))
    XCTAssertTrue(waitFor(archived))
  }
}
