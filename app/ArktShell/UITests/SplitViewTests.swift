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
    // Added panes are inserted after the focused pane, before the original right pane.
    select(2, in: app)
    XCTAssertTrue(Waits.until("fourth fixture selected") {
      self.panes(app).element(boundBy: 2).webViews.firstMatch.label == FixtureServer.title(ofPage: "fourth")
    })
    // The close shortcut separates the focused page; it must not add an Archive entry.
    app.menuBars.menuBarItems["Window"].click()
    app.menuBars.menuItems["Show Archive"].click()
    let archive = app.windows[AXID.Archive.window]
    XCTAssertTrue(waitFor(archive))
    let before = archive.tables[AXID.Archive.table].tableRows.count
    archive.typeKey("w", modifierFlags: .command)
    app.typeKey("-", modifierFlags: modifiers)
    XCTAssertTrue(Waits.until("three panes after separating") { self.panes(app).count == 3 })
    let separated = app.outlineRows.matching(identifier: AXID.Sidebar.rowPinned)
      .element(matching: NSPredicate(format: "label == %@", FixtureServer.title(ofPage: "fourth")))
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
    // Collect every probe before feature assertions: each menu is dismissed before the next click.
    let control = try XCTUnwrap(Shell.todayRows(app).allElementsBoundByIndex.first)
    let urlBar = Shell.element(app, AXID.Sidebar.urlBar)
    let splitItem = app.menuItems["Separate All Tabs"]
    // Match ToolbarTests, including its hittability check to distinguish the menu bar item.
    let toolbarItems = app.menuItems.matching(NSPredicate(
      format: "title == %@ OR identifier == %@", "Show Toolbar", "Show Toolbar"))
    var snapshots = ""
    var controlOpened = [Bool]()
    var splitOpened = [Bool]()
    var toolbarOpened = [Bool]()
    var dismissed = [Bool]()
    func screenshot(_ method: String, _ target: String, _ stage: String) {
      let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      attachment.name = "\(method) \(target) \(stage)"
      attachment.lifetime = .deleteOnSuccess
      add(attachment)
    }
    func observe(_ condition: @escaping @MainActor () -> Bool) -> Bool {
      let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
      return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
                              timeout: Waits.scaled(3)) == .completed
    }
    for controlClick in [false, true] {
      let method = controlClick ? "control-click" : "right-click"
      func probe(_ target: XCUIElement, name: String, items: XCUIElementQuery, hittable: Bool) -> Bool {
        snapshots += "\n\(method) \(name) before: identifier=\(target.identifier) label=\(target.label) frame=\(target.frame) hittable=\(target.isHittable)\n"
        if controlClick { XCUIElement.perform(withKeyModifiers: .control) { target.click() } }
        else { target.rightClick() }
        screenshot(method, name, "after-click")
        let found = observe {
          items.allElementsBoundByIndex.contains { $0.exists && (!hittable || $0.isHittable) }
        }
        screenshot(method, name, "after-query")
        snapshots += "\(method) \(name) found=\(found) itemCount=\(items.count) menus=\(app.menus.count):\n"
        snapshots += "menu-scoped AX:\n" + app.menus.debugDescription + "\napp AX:\n" + app.debugDescription
        app.typeKey(.escape, modifierFlags: [])
        dismissed.append(observe {
          !items.allElementsBoundByIndex.contains { $0.exists && (!hittable || $0.isHittable) }
        })
        return found
      }
      toolbarOpened.append(probe(urlBar, name: "sidebar-url-bar", items: toolbarItems, hittable: true))
      controlOpened.append(probe(control, name: "today-row", items: app.menuItems.matching(identifier: "Rename"), hittable: false))
      splitOpened.append(probe(splitRow(app), name: "split-row", items: app.menuItems.matching(identifier: "Separate All Tabs"), hittable: false))
    }
    let probe = XCTAttachment(string: snapshots)
    probe.name = "context menu target and accessibility probes"
    probe.lifetime = .deleteOnSuccess
    add(probe)

    // The imported split is pinned: its two panes replace the split as pinned rows, not Today rows.
    let pinned = app.outlineRows.matching(identifier: AXID.Sidebar.rowPinned)
    let before = pinned.count
    let todayBefore = Shell.todayRows(app).count
    XCUIElement.perform(withKeyModifiers: .option) { self.splitRow(app).click() }
    XCTAssertTrue(Waits.until("option-click separates the pinned split") {
      !self.splitRow(app).exists && pinned.count == before && Shell.todayRows(app).count == todayBefore
        && pinned.matching(NSPredicate(format: "label == %@", "Fixture /docs/left")).count == 1
        && pinned.matching(NSPredicate(format: "label == %@", "Fixture /docs/right")).count == 1
    })
    XCTAssertTrue(toolbarOpened.contains(true), "sidebar URL bar menu missing; inspect the paired probes")
    XCTAssertTrue(controlOpened.contains(true), "regular row menu missing; inspect the paired probes")
    XCTAssertTrue(splitOpened.contains(true), "split menu missing; inspect the paired control probes")
    XCTAssertTrue(dismissed.allSatisfy { $0 }, "a context menu did not dismiss")

    // Re-create the split from its focused pinned page to exercise the menu action independently of its probes.
    let current = try XCTUnwrap(pinned.allElementsBoundByIndex.first { $0.isSelected })
    XCUIElement.perform(withKeyModifiers: .option) { current.click() }
    XCTAssertTrue(waitFor(splitRow(app)))
    let count = pinned.count
    guard let method = splitOpened.firstIndex(of: true) else { return }
    if method == 0 { splitRow(app).rightClick() }
    else { XCUIElement.perform(withKeyModifiers: .control) { self.splitRow(app).click() } }
    let actionMethod = method == 0 ? "right-click" : "control-click"
    screenshot(actionMethod, "split-row-action", "after-click")
    let actionItemFound = splitItem.waitForExistence(timeout: Waits.scaled(3))
    screenshot(actionMethod, "split-row-action", "after-query")
    XCTAssertTrue(actionItemFound)
    splitItem.click()
    XCTAssertTrue(Waits.until("context menu separates the pinned split") {
      !self.splitRow(app).exists && pinned.count == count
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
