import XCTest

/// The first launch on an empty data folder (infrastructure, no parity row).
final class LaunchTests: ArktUITestCase {
  func test_E_launchOnEmptyDataFolderShowsWindowAndQuitsCleanly() throws {
    let sandbox = try Sandbox()
    let app = try launch(sandbox)

    XCTAssertTrue(shellWindow(of: app).exists)

    quit(app)
    XCTAssertEqual(app.state, .notRunning)

    // The app got only sandbox paths; the real data folder is never read here, only proven unused.
    let env = app.launchEnvironment
    XCTAssertEqual(env["ARKT_UITEST"], "1")
    XCTAssertEqual(env["ARKT_DATA_DIR"], sandbox.dataDirectory.path)
    XCTAssertEqual(env["ARKT_ARC_DIR"], sandbox.arcDirectory.path)
    XCTAssertEqual(env["ARKT_DEFAULTS_SUITE"], sandbox.defaultsSuite)
    for path in sandbox.handedOutPaths {
      XCTAssertTrue(path.hasPrefix(sandbox.root.path + "/"), path)
    }

    let files = FileManager.default
    let database = sandbox.dataDirectory.appendingPathComponent("Arkt.sqlite")
    XCTAssertTrue(files.fileExists(atPath: database.path), "no Arkt.sqlite in the sandbox data folder")

    let backups = sandbox.dataDirectory.appendingPathComponent("Backups", isDirectory: true)
    let backupEntries = (try? files.contentsOfDirectory(atPath: backups.path)) ?? []
    XCTAssertEqual(backupEntries, [], "Backups must be empty or missing after a first launch")
  }

  func test_E_sandboxGuardAndExtraEnvRestrictions() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).path

    for path in sandbox.handedOutPaths {
      XCTAssertNoThrow(try Sandbox.checkSafe(path, root: sandbox.root.path, under: temp))
    }
    // A path under temp that is outside the sandbox root (or a prefix sibling without a trailing `/`) is refused.
    XCTAssertThrowsError(try Sandbox.checkSafe(temp + "/other/data", root: sandbox.root.path, under: temp))
    XCTAssertThrowsError(try Sandbox.checkSafe(sandbox.root.path, root: sandbox.root.path, under: temp))
    XCTAssertThrowsError(try Sandbox.checkSafe(sandbox.root.path + "-sibling/data", root: sandbox.root.path, under: temp))
    XCTAssertThrowsError(try Sandbox.checkSafe(sandbox.dataDirectory.path, root: "/Users/someone/arkt-uitest-1", under: temp))
    XCTAssertThrowsError(try Sandbox.checkSafe(
      sandbox.root.path + "/Library/Application Support/Arkt", root: sandbox.root.path, under: temp))
    XCTAssertThrowsError(try Sandbox.checkSafe(sandbox.root.path + "/Arc/data", root: sandbox.root.path, under: temp))

    // `extraEnv` cannot override any key owned by `Sandbox`.
    for key in ["ARKT_UITEST", "ARKT_DATA_DIR", "ARKT_ARC_DIR", "ARKT_DEFAULTS_SUITE"] {
      XCTAssertThrowsError(try Self.mergedEnvironment(sandbox: sandbox, extraEnv: [key: "override"]))
      XCTAssertThrowsError(try launch(sandbox, extraEnv: [key: "override"]))
    }
    sandbox.autosaveDelayMilliseconds = 250
    XCTAssertThrowsError(try Self.mergedEnvironment(sandbox: sandbox, extraEnv: ["ARKT_AUTOSAVE_DELAY_MS": "10"]))

    let merged = try Self.mergedEnvironment(sandbox: sandbox, extraEnv: ["ARKT_UITEST_TIMEOUT_SCALE": "2"])
    XCTAssertEqual(merged["ARKT_DATA_DIR"], sandbox.dataDirectory.path)
    XCTAssertEqual(merged["ARKT_UITEST_TIMEOUT_SCALE"], "2")
  }

  func test_E_arcFixtureRenderRewritesURLsAndMatchesExpectedCounts() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let base = "http://127.0.0.1:54321"
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: base)
    XCTAssertTrue(try checksums.unchanged(in: sandbox.arcDirectory))

    let sidebarText = try String(
      contentsOf: sandbox.arcDirectory.appendingPathComponent("StorableSidebar.json"), encoding: .utf8)
    let archiveText = try String(
      contentsOf: sandbox.arcDirectory.appendingPathComponent("StorableArchiveItems.json"), encoding: .utf8)
    XCTAssertTrue(sidebarText.contains("\(base)/articles/one"))
    XCTAssertTrue(archiveText.contains("\(base)/manual"))
    XCTAssertFalse(sidebarText.contains(ArcFixture.placeholderOrigin))
    XCTAssertFalse(archiveText.contains(ArcFixture.placeholderOrigin))

    XCTAssertEqual(ArcFixture.expected.spaces, 2)
    XCTAssertEqual(ArcFixture.expected.tabs, 9)
    XCTAssertEqual(ArcFixture.expected.folders, 1)
    XCTAssertEqual(ArcFixture.expected.splits, 1)
    XCTAssertEqual(ArcFixture.expected.favorites, 2)
    XCTAssertEqual(ArcFixture.expected.archive, 7)
  }

  func test_E_seededLaunchShowsImportedSpaces() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try sandbox.seedFromArcFixture(server: server)
    let app = try launch(sandbox)

    let dots = app.buttons.matching(identifier: AXID.Sidebar.spaceDot)
    XCTAssertTrue(Waits.until("2 Space dots", { dots.count == ArcFixture.expected.spaces }))
    let rows = app.outlineRows
    waitForOutlineRows("current Space page has rows") { rows.count > 0 }
    XCTAssertTrue(Waits.until("fixture page requested from loopback server", { !server.requestedPaths.isEmpty }))
    let unexpected = server.requestedPaths.filter { !ArcFixture.fixturePaths.contains($0) }
    XCTAssertEqual(unexpected, [], "server saw non-fixture paths: \(unexpected)")

    quit(app)
    XCTAssertTrue(try checksums.unchanged(in: sandbox.arcDirectory), "rendered Arc copy must stay untouched")
  }
}
