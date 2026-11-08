import AppKit
import XCTest

/// Real Settings, persisted routing and application-open delivery in the sandboxed Debug app.
final class LinkRoutingAppTests: ArktUITestCase {
  @MainActor
  private func choose(_ title: String, from control: XCUIElement, in app: XCUIApplication) {
    XCTAssertTrue(waitFor(control))
    XCTAssertTrue(waitForEnabled(control))
    control.click()
    let item = app.menuItems[title]
    XCTAssertTrue(waitFor(item))
    item.click()
  }

  @MainActor
  private func configureRouting(_ app: XCUIApplication) throws {
    try createFirstSpace(in: app)
    app.menuBars.menuBarItems["Spaces"].click()
    let newSpace = app.menuBars.menuItems["New Space"]
    XCTAssertTrue(waitFor(newSpace))
    newSpace.click()
    XCTAssertTrue(Waits.until("two Space dots") { Shell.spaceDots(app).count == 2 })
    XCTAssertTrue(waitForSelected(Shell.spaceDots(app).element(boundBy: 1)))
    app.typeKey(.return, modifierFlags: [])

    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows[AXID.Settings.window]
    XCTAssertTrue(waitFor(settings))
    app.typeKey("2", modifierFlags: .command)
    let defaultControl = Shell.element(app, AXID.Settings.control("spaces", "linksFromOtherApps"))
    choose("Space 2", from: defaultControl, in: app)
    let add = Shell.element(app, AXID.Settings.control("spaces", "addRoute"))
    XCTAssertTrue(waitForEnabled(add))
    add.click()
    let literal = app.textFields["settings.route.literal"]
    XCTAssertTrue(waitFor(literal))
    literal.typeText("/routing/routed-")
    choose("Space 1", from: Shell.element(app, "settings.route.destination"), in: app)
    let save = Shell.element(app, "settings.route.save")
    XCTAssertTrue(waitFor(save))
    save.click()
    XCTAssertTrue(waitUntilGone(literal))
    // A rendered Edit button confirms the route was accepted by the shared editor before adding another.
    XCTAssertTrue(waitFor(Shell.element(app, "settings.spaces.route.0.edit")))
    let addSecond = Shell.element(app, AXID.Settings.control("spaces", "addRoute"))
    XCTAssertTrue(waitForEnabled(addSecond))
    addSecond.click()
    let secondLiteral = app.textFields["settings.route.literal"]
    XCTAssertTrue(waitFor(secondLiteral))
    secondLiteral.typeText("/routing/little-")
    let secondSave = Shell.element(app, "settings.route.save")
    XCTAssertTrue(waitFor(secondSave))
    secondSave.click()
    XCTAssertTrue(waitUntilGone(secondLiteral))
    XCTAssertTrue(waitFor(Shell.element(app, "settings.spaces.route.1.edit")))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(waitUntilGone(settings))
  }

  /// Target the same validated bundle used by `launch`; never consult or modify the default browser.
  @MainActor
  private func open(_ address: String, sandbox: Sandbox, server: FixtureServer, cold: Bool) async throws -> NSRunningApplication {
    let url = try XCTUnwrap(URL(string: address))
    let applicationURL = Self.appURL().standardizedFileURL.resolvingSymlinksInPath()
    var bundleIdentifier: String?
    if cold {
      _ = try Self.makeApplication() // Repeat bundle validation and the no-running-instance preflight.
      guard let bundle = Bundle(url: applicationURL),
            bundle.object(forInfoDictionaryKey: "ArktRequireUITestOverrides") as? String == "YES",
            let identifier = bundle.bundleIdentifier, !identifier.isEmpty else {
        throw HarnessError("cold OS open requires the mandatory UI-test startup guard")
      }
      bundleIdentifier = identifier
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.allowsRunningApplicationSubstitution = false
    // Use the normal cold URL-open path after the no-running-instance preflight, without forcing another instance.
    // Exact bundle, PID, ACK and sole-instance checks below still reject unintended reuse or environment loss.
    configuration.createsNewApplicationInstance = false
    var environment = try Self.mergedEnvironment(sandbox: sandbox, extraEnv: [:])
    if cold {
      let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
      server.armIdentity(nonce: nonce, digest: try TestIdentity.digest(environment))
      environment[TestIdentity.endpointKey] = "\(server.base)/identity/\(nonce)"
    }
    configuration.environment = environment
    configuration.arguments = Self.launchArguments
    if cold {
      let keys = Set(TestIdentity.keys + [TestIdentity.endpointKey])
      let carrierValues = environment.filter { keys.contains($0.key) }
      configuration.arguments.append(try LaunchArgumentCarrier.encode(carrierValues, bundleIdentifier: bundleIdentifier))
    }
    let opened = try await NSWorkspace.shared.open([url], withApplicationAt: applicationURL,
                                                   configuration: configuration)
    guard opened.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == applicationURL,
          opened.processIdentifier > 0 else {
      let returnedBundle = opened.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path ?? "nil"
      let acceptedPID = server.acceptedIdentity.map { String($0.pid) } ?? "none"
      let reports = server.requestedPaths.filter { $0.hasPrefix("/identity/") }.count
      throw HarnessError("OS open returned an unexpected application identity: "
        + "pid=\(opened.processIdentifier), terminated=\(opened.isTerminated), "
        + "finishedLaunching=\(opened.isFinishedLaunching), bundle=\(returnedBundle), "
        + "expectedBundle=\(applicationURL.path), acceptedPID=\(acceptedPID), identityRequests=\(reports)")
    }
    if cold {
      guard Waits.until("cold process identity report", { server.acceptedIdentity != nil }),
            let report = server.acceptedIdentity, report.pid == opened.processIdentifier,
            let bundleID = opened.bundleIdentifier, bundleID == bundleIdentifier else {
        throw HarnessError("cold process identity was not established")
      }
      let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      guard instances.count == 1, instances[0].processIdentifier == report.pid,
            instances[0].bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == applicationURL else {
        throw HarnessError("cold process is not the sole instance of the validated bundle")
      }
    }
    return opened
  }

  /// Observe the loaded app profile without editing it or changing the active Space.
  @MainActor
  private func verifyPersistedProfile(_ app: XCUIApplication) throws {
    guard Waits.until("cold profile: two Spaces", { Shell.spaceDots(app).count == 2 }) else {
      throw HarnessError("cold profile does not contain the configured Spaces")
    }
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows[AXID.Settings.window]
    guard waitFor(settings) else { throw HarnessError("cold profile Settings unavailable") }
    app.typeKey("2", modifierFlags: .command)
    let control = Shell.element(app, AXID.Settings.control("spaces", "linksFromOtherApps"))
    guard Waits.until("cold profile: routing settings", {
      control.value as? String == "Space 2"
        && Shell.element(app, "settings.spaces.route.0.edit").exists
        && Shell.element(app, "settings.spaces.route.1.edit").exists
    }) else { throw HarnessError("cold profile routing settings differ from configured profile") }
    for (index, literal, destination) in [(0, "/routing/routed-", "Space 1"),
                                           (1, "/routing/little-", "Little Arkt")] {
      Shell.element(app, "settings.spaces.route.\(index).edit").click()
      let field = app.textFields["settings.route.literal"]
      let condition = Shell.element(app, "settings.route.condition")
      let target = Shell.element(app, "settings.route.destination")
      guard waitFor(field), field.value as? String == literal,
            condition.value as? String == "Contains", target.value as? String == destination else {
        throw HarnessError("cold profile route \(index) differs from configured profile")
      }
      Shell.element(app, "settings.route.cancel").click()
      guard waitUntilGone(field) else { throw HarnessError("cold profile route inspection did not close") }
    }
    app.typeKey(.escape, modifierFlags: [])
    guard waitUntilGone(settings) else { throw HarnessError("cold profile Settings did not close") }
  }

  @MainActor
  private func expectSpacePage(_ name: String, index: Int, server: FixtureServer, app: XCUIApplication) {
    let target = Shell.spaceDots(app).element(boundBy: index)
    XCTAssertTrue(waitForSelected(target))
    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: name))
    XCTAssertTrue(waitForOutlineRows("fixture in destination Space") { row.exists && row.isSelected })
    XCTAssertTrue(Waits.until("routed fixture requested") { server.requestedPaths.contains("/routing/\(name)") })
  }

  @MainActor
  private func expectLittlePage(_ name: String, server: FixtureServer, app: XCUIApplication) {
    let little = app.windows[AXID.LittleArkt.window]
    XCTAssertTrue(waitFor(little))
    XCTAssertTrue(waitFor(little.descendants(matching: .any)[AXID.LittleArkt.host]))
    XCTAssertTrue(waitFor(little.webViews.staticTexts[FixtureServer.title(ofPage: name)]))
    XCTAssertTrue(Waits.until("Little Arkt fixture requested") { server.requestedPaths.contains("/routing/\(name)") })
  }

  @MainActor
  private func exerciseOpen(cold: Bool, destination: Destination) async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    try configureRouting(app)
    XCTAssertTrue(waitForSelected(Shell.spaceDots(app).element(boundBy: 1)))
    if destination == .defaultSpace {
      Shell.spaceDots(app).element(boundBy: 0).click()
      XCTAssertTrue(waitForSelected(Shell.spaceDots(app).element(boundBy: 0)))
    }
    if cold { quit(app) }

    let name = "\(destination.rawValue)-\(cold ? "cold" : "warm")"
    let address = "\(server.base)/routing/\(name)"
    // Cold opens start the validated bundle with the same sandbox, without an XCUIApplication launch first.
    let opened = try await open(address, sandbox: sandbox, server: server, cold: cold)
    if cold {
      try verifyPersistedProfile(app)
      guard !opened.isTerminated else { throw HarnessError("cold process exited during profile inspection") }
    }
    switch destination {
    case .routed: expectSpacePage(name, index: 0, server: server, app: app)
    case .little: expectLittlePage(name, server: server, app: app)
    case .defaultSpace: expectSpacePage(name, index: 1, server: server, app: app)
    }
  }

  private enum Destination: String { case routed, little, defaultSpace = "default" }

  func testWarmRouteToSpace() async throws { try await exerciseOpen(cold: false, destination: .routed) }
  func testWarmRouteToLittleArkt() async throws { try await exerciseOpen(cold: false, destination: .little) }
  func testWarmDefaultToSpace() async throws { try await exerciseOpen(cold: false, destination: .defaultSpace) }
  func testColdRouteToSpace() async throws { try await exerciseOpen(cold: true, destination: .routed) }
  func testColdRouteToLittleArkt() async throws { try await exerciseOpen(cold: true, destination: .little) }
  func testColdDefaultToSpace() async throws { try await exerciseOpen(cold: true, destination: .defaultSpace) }
}
