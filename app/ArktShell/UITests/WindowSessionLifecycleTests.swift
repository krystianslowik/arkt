import Foundation
import XCTest

/// Uses the actual app, isolated defaults and Cmd-Q; the loopback pages identify the selected tab in each window.
@MainActor
final class WindowSessionLifecycleTests: ArktUITestCase {
  func test_E_cleanQuitRestoresDistinctRegularWindowsWithPrivateWindowOpen() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    try createFirstSpace(in: app)
    XCTAssertTrue(Shell.openInNewTab(server.page("session-alpha"), in: app))
    let alphaTitle = FixtureServer.title(ofPage: "session-alpha")
    XCTAssertTrue(waitForSelected(Shell.todayRow(app, label: alphaTitle)))

    app.menuBars.menuBarItems["Spaces"].click()
    let newSpace = app.menuBars.menuItems["New Space"]
    XCTAssertTrue(waitFor(newSpace))
    newSpace.click()
    XCTAssertTrue(Waits.until("second Space") { Shell.spaceDots(app).count == 2 })
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(Shell.openInNewTab(server.page("session-beta"), in: app))
    let betaTitle = FixtureServer.title(ofPage: "session-beta")
    XCTAssertTrue(waitForSelected(Shell.todayRow(app, label: betaTitle)))

    app.typeKey("n", modifierFlags: .command)
    let windows = app.windows.matching(identifier: AXID.Shell.window)
    XCTAssertTrue(Waits.until("two regular windows") { windows.count == 2 })
    // Identify the new window by its absent selection rather than relying on accessibility enumeration order.
    let newWindows = windows.allElementsBoundByIndex.filter { window in
      let row = window.outlineRows.matching(identifier: AXID.Sidebar.rowToday)
        .matching(NSPredicate(format: "label == %@", betaTitle)).firstMatch
      return row.exists && !row.isSelected
    }
    XCTAssertEqual(newWindows.count, 1)
    let newWindow = try XCTUnwrap(newWindows.first)
    let dot = newWindow.buttons.matching(identifier: AXID.Sidebar.spaceDot)
      .matching(NSPredicate(format: "label == %@", "Space 1")).firstMatch
    XCTAssertTrue(waitFor(dot))
    dot.click()
    XCTAssertTrue(waitForSelected(dot))
    let alphaRow = newWindow.outlineRows.matching(identifier: AXID.Sidebar.rowToday)
      .matching(NSPredicate(format: "label == %@", alphaTitle)).firstMatch
    XCTAssertTrue(waitFor(alphaRow))
    alphaRow.click()
    XCTAssertTrue(waitForSelected(alphaRow))
    XCTAssertTrue(Waits.until("distinct selected Spaces and tabs") {
      self.hasSelection(windows, space: "Space 1", tab: alphaTitle)
        && self.hasSelection(windows, space: "Space 2", tab: betaTitle)
    })

    app.typeKey("n", modifierFlags: [.command, .shift])
    XCTAssertTrue(Waits.until("one identified Incognito window remains open at capture") {
      windows.count == 3 && windows.allElementsBoundByIndex.filter { window in
        let label = window.descendants(matching: .any).matching(identifier: AXID.Incognito.label).firstMatch
        return label.exists && label.label == "Incognito"
      }.count == 1
    })
    let defaults = try XCTUnwrap(UserDefaults(suiteName: sandbox.defaultsSuite))
    var beforeWindows: [[String: Any]] = []
    XCTAssertTrue(Waits.until("ordered regular-window state is captured with private window open") {
      guard let saved = self.savedWindows(defaults) else { return false }
      beforeWindows = saved
      return saved.count == 2
    })
    XCTAssertEqual(beforeWindows.count, 2, "check raw entries before reading any selection fields")
    let before = try selectedIdentities(beforeWindows)
    XCTAssertEqual(Set(before).count, 2)
    quit(app)
    let afterWindows = try XCTUnwrap(savedWindows(defaults))
    XCTAssertEqual(afterWindows.count, 2, "quit cannot append an empty private-window entry")
    XCTAssertEqual(try selectedIdentities(afterWindows), before, "quit must preserve the final ordered selections")
    let alphaRequests = server.requestedPaths.filter { $0 == "/p/session-alpha" }.count
    let betaRequests = server.requestedPaths.filter { $0 == "/p/session-beta" }.count

    let reopened = try launch(sandbox)
    let restored = reopened.windows.matching(identifier: AXID.Shell.window)
    XCTAssertTrue(Waits.until("both distinct window selections restored") {
      restored.count >= 2 && self.hasSelection(restored, space: "Space 1", tab: alphaTitle)
        && self.hasSelection(restored, space: "Space 2", tab: betaTitle)
    })
    XCTAssertTrue(Waits.until("both selected pages requested after relaunch") {
      server.requestedPaths.filter { $0 == "/p/session-alpha" }.count > alphaRequests
        && server.requestedPaths.filter { $0 == "/p/session-beta" }.count > betaRequests
    })
  }

  private func hasSelection(_ windows: XCUIElementQuery, space: String, tab: String) -> Bool {
    windows.allElementsBoundByIndex.contains { window in
      let dot = window.buttons.matching(identifier: AXID.Sidebar.spaceDot)
        .matching(NSPredicate(format: "label == %@", space)).firstMatch
      let row = window.outlineRows.matching(identifier: AXID.Sidebar.rowToday)
        .matching(NSPredicate(format: "label == %@", tab)).firstMatch
      return dot.exists && dot.isSelected && row.exists && row.isSelected
    }
  }

  private func savedWindows(_ defaults: UserDefaults) -> [[String: Any]]? {
    guard let data = defaults.data(forKey: "windowSessions"),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let windows = object["windows"] as? [[String: Any]] else { return nil }
    return windows
  }

  /// Every raw entry must have a selection; none may disappear when projecting the ordered identities.
  private func selectedIdentities(_ windows: [[String: Any]]) throws -> [String] {
    try windows.map { window in
      let space = try XCTUnwrap(window["space"])
      let tab = try XCTUnwrap(window["currentTab"])
      let data = try JSONSerialization.data(withJSONObject: [space, tab], options: [.sortedKeys])
      return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
  }
}
