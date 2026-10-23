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
}
