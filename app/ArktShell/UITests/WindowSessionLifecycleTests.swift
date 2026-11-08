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
    // The new window is frontmost. Select Space 1 and its tab there; the other stays in Space 2.
    let frontWindow = windows.element(boundBy: 0)
    let dot = frontWindow.buttons.matching(identifier: AXID.Sidebar.spaceDot)
      .matching(NSPredicate(format: "label == %@", "Space 1")).firstMatch
    XCTAssertTrue(waitFor(dot))
    dot.click()
    XCTAssertTrue(waitForSelected(dot))
    let alphaRow = frontWindow.outlineRows.matching(identifier: AXID.Sidebar.rowToday)
      .matching(NSPredicate(format: "label == %@", alphaTitle)).firstMatch
    XCTAssertTrue(waitFor(alphaRow))
    alphaRow.click()
    XCTAssertTrue(waitForSelected(alphaRow))
    XCTAssertTrue(Waits.until("distinct selected Spaces and tabs") {
      self.hasSelection(windows, space: "Space 1", tab: alphaTitle)
        && self.hasSelection(windows, space: "Space 2", tab: betaTitle)
    })

    app.typeKey("n", modifierFlags: [.command, .shift])
    XCTAssertTrue(Waits.until("private window remains open at capture") { windows.count == 3 })
    let defaults = try XCTUnwrap(UserDefaults(suiteName: sandbox.defaultsSuite))
    var before: [String] = []
    XCTAssertTrue(Waits.until("ordered regular-window state is captured with private window open") {
      before = self.savedSelections(defaults)
      return before.count == 2 && Set(before).count == 2
    })
    quit(app)
    XCTAssertEqual(savedSelections(defaults), before, "quit must preserve the final ordered selections")
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

  /// Read only the ordered selection identities, not frames that may change during termination.
  private func savedSelections(_ defaults: UserDefaults) -> [String] {
    guard let data = defaults.data(forKey: "windowSessions"),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let windows = object["windows"] as? [[String: Any]] else { return [] }
    return windows.compactMap { window in
      guard let space = window["space"], let tab = window["currentTab"],
            let data = try? JSONSerialization.data(withJSONObject: [space, tab], options: [.sortedKeys]),
            let value = String(data: data, encoding: .utf8) else { return nil }
      return value
    }
  }
}
