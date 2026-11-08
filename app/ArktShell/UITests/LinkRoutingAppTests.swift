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
  private func open(_ address: String, sandbox: Sandbox) async throws {
    let url = try XCTUnwrap(URL(string: address))
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.environment = try Self.mergedEnvironment(sandbox: sandbox, extraEnv: [:])
    configuration.arguments = Self.launchArguments
    _ = try await NSWorkspace.shared.open([url], withApplicationAt: Self.appURL(), configuration: configuration)
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
    try await open(address, sandbox: sandbox)
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
