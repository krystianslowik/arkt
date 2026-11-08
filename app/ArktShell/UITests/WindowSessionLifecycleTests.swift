import Foundation
import XCTest

/// A bounded restore round trip through the actual app and isolated defaults. Loopback pages identify selected tabs.
/// This does not prove the timing of quit capture: ordinary state changes may already have saved the same value.
@MainActor
final class WindowSessionLifecycleTests: ArktUITestCase {
  func test_E_relaunchRestoresDistinctRegularWindowsWithPrivateWindowOpen() async throws {
    try await exerciseRelaunch(restores: true)
  }

  func test_F_disabledRestorePreservesSavedCollectionAtLaunch() async throws {
    try await exerciseRelaunch(restores: false)
  }

  private func exerciseRelaunch(restores: Bool) async throws {
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
    if !restores {
      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows[AXID.Settings.window]
      guard waitFor(settings) else { return }
      app.typeKey("1", modifierFlags: .command)
      let opening = Shell.element(app, AXID.Settings.control("general", "whenArktOpens"))
      guard waitForEnabled(opening) else { return }
      opening.click()
      let fresh = app.menuItems["Open a new window"]
      guard waitFor(fresh) else { return }
      fresh.click()
      guard waitFor(opening, value: "Open a new window") else { return }
      app.typeKey(.escape, modifierFlags: [])
      guard waitUntilGone(settings) else { return }
    }
    var firstReport: WindowSessionObservation.Report?
    XCTAssertTrue(Waits.until("two raw regular-window entries while Incognito remains open") {
      guard windows.count == 3,
            windows.allElementsBoundByIndex.filter({ window in
              window.descendants(matching: .any).matching(identifier: AXID.Incognito.label).firstMatch.exists
            }).count == 1,
            let report = self.observation(app) else { return false }
      firstReport = report
      return (try? self.savedWindows(report.current).count) == 2
    })
    let first = try XCTUnwrap(firstReport)
    let beforeWindows = try savedWindows(first.current)
    XCTAssertEqual(beforeWindows.count, 2, "check raw entries before reading any selection fields")
    guard beforeWindows.count == 2 else { return }
    let before = try selectedIdentities(beforeWindows)
    XCTAssertEqual(Set(before).count, 2)
    quit(app)
    let alphaRequests = server.requestedPaths.filter { $0 == "/p/session-alpha" }.count
    let betaRequests = server.requestedPaths.filter { $0 == "/p/session-beta" }.count

    let reopened = try launch(sandbox)
    var secondReport: WindowSessionObservation.Report?
    XCTAssertTrue(Waits.until("new launch completed its window decision") {
      guard let report = self.observation(reopened), report.launchID != first.launchID,
            report.launchComplete else { return false }
      secondReport = report
      return true
    })
    let completedLaunch = try XCTUnwrap(secondReport)
    let initial = completedLaunch.initial
    let afterWindows = try savedWindows(initial)
    XCTAssertEqual(afterWindows.count, 2, "quit cannot append an empty private-window entry")
    guard afterWindows.count == 2 else { return }
    XCTAssertEqual(try selectedIdentities(afterWindows), before, "quit must preserve the final ordered selections")
    let restored = reopened.windows.matching(identifier: AXID.Shell.window)
    if !restores {
      // This launch-specific latch follows creation of the fallback window. Inspect before any further UI action.
      XCTAssertEqual(restored.count, 1, "disabled restore opens one fresh regular window")
      XCTAssertEqual(completedLaunch.current, initial,
                     "creating the disabled-launch fallback must not replace the saved collection")
      return
    }
    // AX enumeration order is not window creation order; ordered identity is checked in the stored collection above.
    XCTAssertTrue(Waits.until("both distinct window selections restored") {
      restored.count == 2 && self.hasSelection(restored, space: "Space 1", tab: alphaTitle)
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

  private func observation(_ app: XCUIApplication) -> WindowSessionObservation.Report? {
    let element = app.staticTexts.matching(identifier: "arkt.ui-test.window-session-observation").firstMatch
    guard element.exists, let text = element.value as? String else { return nil }
    return try? WindowSessionObservation.Report.decode(text)
  }

  private func savedWindows(_ value: WindowSessionObservation.RawValue) throws -> [[String: Any]] {
    guard case .data(let data) = value else { throw ObservationError.notData }
    let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try XCTUnwrap(object["windows"] as? [[String: Any]])
  }

  private enum ObservationError: Error { case notData }

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
