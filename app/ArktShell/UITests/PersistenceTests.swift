import XCTest

/// Quit inside the autosave debounce, relaunch, and the recovery toasts after a corrupt database (plan U14).
///
/// Sidebar rows are not in the out-of-process accessibility tree on the macOS 26 runner (#269). The `Fixture alpha`
/// row goes through `waitForOutlineRows`, the harness's known-issue wait: an expected failure where the rows are
/// missing, the title assertion where they are exposed. The sidebar URL bar (not an outline row) showing the
/// loopback host is asserted every time as well.
final class PersistenceTests: ArktUITestCase {
  private static let recreatedPrefix = "Arkt couldn't read its saved sidebar and no backup could be used"
  private static let restoredPrefix = "Arkt couldn't read its saved sidebar and restored it from a backup"

  /// The sidebar URL bar shows the loopback host: the shown tab is a fixture page. Needs no outline row.
  private func expectLoopbackURLBar(
    _ app: XCUIApplication, _ what: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let urlBar = Shell.element(app, AXID.Sidebar.urlBar)
    XCTAssertTrue(Waits.until("sidebar URL bar shows the loopback host (\(what))", file: file, line: line) {
      (urlBar.value as? String)?.contains("127.0.0.1") == true
    }, what, file: file, line: line)
  }

  /// The Today row titled `Fixture alpha` (expected failure while #269 hides the rows), then the URL bar.
  private func expectFixtureAlpha(
    _ app: XCUIApplication, _ what: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    waitForOutlineRows("\(row) to exist (\(what))", file: file, line: line) { row.exists }
    expectLoopbackURLBar(app, what, file: file, line: line)
  }

  /// Cmd-T and the alpha address. Does not wait for the bar to close: the default-debounce test quits on the next
  /// line.
  private func openAlpha(
    _ server: FixtureServer, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(Shell.openCommandBar(app, key: "t"), file: file, line: line)
    Shell.submit(server.page("alpha"), in: app)
  }

  private func databaseURL(_ sandbox: Sandbox) -> URL {
    sandbox.dataDirectory.appendingPathComponent("Arkt.sqlite")
  }

  /// Size and modification date of the live database. It uses a rollback journal (`ArktDatabase`), so every
  /// committed write changes `Arkt.sqlite` itself.
  private struct DatabaseStamp: Equatable {
    let size: UInt64
    let modified: Date
  }

  private func databaseStamp(_ sandbox: Sandbox) throws -> DatabaseStamp {
    let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL(sandbox).path)
    guard let size = (attributes[.size] as? NSNumber)?.uint64Value,
          let modified = attributes[.modificationDate] as? Date else {
      throw HarnessError("no size or modification date for \(databaseURL(sandbox).path)")
    }
    return DatabaseStamp(size: size, modified: modified)
  }

  /// New Space, the alpha page, wait for its row, Cmd-Q. A `.created` launch writes no backup.
  private func seedAlpha(_ server: FixtureServer, _ sandbox: Sandbox) throws {
    let app = try launch(sandbox)
    try createFirstSpace(in: app)
    openAlpha(server, in: app)
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    expectFixtureAlpha(app, "Fixture alpha before quit")
    quit(app)
  }

  private func corruptLiveDatabase(_ sandbox: Sandbox, file: StaticString = #filePath, line: UInt = #line) throws {
    let database = databaseURL(sandbox)
    XCTAssertTrue(FileManager.default.fileExists(atPath: database.path), "live database before overwrite",
                  file: file, line: line)
    try Data("not a database".utf8).write(to: database)
  }

  /// The renamed `Arkt-*.sqlite`. A `.tmp` shows up first and is not a backup launch can restore.
  private func waitForBackupFile(_ sandbox: Sandbox, file: StaticString = #filePath, line: UInt = #line) {
    let backups = sandbox.dataDirectory.appendingPathComponent("Backups", isDirectory: true)
    XCTAssertTrue(Waits.until("a backup file in data/Backups", file: file, line: line) {
      let names = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
      return names.contains { $0.hasPrefix("Arkt-") && $0.hasSuffix(".sqlite") }
    }, file: file, line: line)
  }

  @discardableResult
  private func expectPersistentToast(
    _ app: XCUIApplication, prefix: String, file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIElement {
    let toast = Shell.element(app, AXID.Toast.root)
    XCTAssertTrue(Waits.until("persistent toast \(prefix)", file: file, line: line) {
      toast.exists && toast.label.hasPrefix(prefix) && (toast.value as? String) == AXID.Toast.persistent
    }, file: file, line: line)
    return toast
  }

  // MARK: - Quit and relaunch

  func test_E_quitInsideAutosaveDebounceKeepsChange() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    // The longest delay the app accepts (`EnvironmentOverrides.autosaveDelayMilliseconds`, 10 minutes): the debounced
    // write cannot fire during this test, so only the termination flush can save the change.
    sandbox.autosaveDelayMilliseconds = 600_000
    let app = try launch(sandbox)

    try createFirstSpace(in: app)
    openAlpha(server, in: app)
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    // The tab is in the model once the URL bar shows it. No row probe from here to Cmd-Q: its timeout would only
    // move Cmd-Q later.
    expectLoopbackURLBar(app, "alpha before quit")
    let settled = try databaseStamp(sandbox)
    // `SidebarStorageFormat` writes JSON without escaping slashes, so a saved sidebar with this tab would contain its
    // address.
    let onDisk = try Data(contentsOf: databaseURL(sandbox))
    XCTAssertNil(onDisk.range(of: Data(server.page("alpha").utf8)), "the tab was saved before Cmd-Q")
    XCTAssertEqual(try databaseStamp(sandbox), settled, "Arkt.sqlite was written before Cmd-Q")
    // The flush itself is bounded at 1 s; 5 s times the scale is the bound this wait asserts.
    quit(app, timeout: 5)

    sandbox.autosaveDelayMilliseconds = nil
    let relaunched = try launch(sandbox)
    expectFixtureAlpha(relaunched, "Fixture alpha after relaunch")
  }

  func test_E_quitAtDefaultDebounceKeepsChange() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let app = try launch(sandbox)

    try createFirstSpace(in: app)
    openAlpha(server, in: app)
    // Nothing between Enter and Cmd-Q. `quit` still activates this app first, so the key cannot reach another
    // process. On a fast machine the default 500 ms debounce has not fired; on a slow one it may have.
    quit(app)

    let relaunched = try launch(sandbox)
    expectFixtureAlpha(relaunched, "Fixture alpha after relaunch")
  }

  // MARK: - Recovery toasts

  func test_E_corruptDatabaseWithoutBackupShowsRecreatedToast() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    try seedAlpha(server, sandbox)
    try corruptLiveDatabase(sandbox)

    let app = try launch(sandbox)
    expectPersistentToast(app, prefix: Self.recreatedPrefix)
    // The button exposes "Show Files" as its title. Out of process that is not always `label`.
    let action = Shell.element(app, AXID.Toast.action)
    XCTAssertTrue(Waits.until("toast.action Show Files") {
      action.exists && (action.label == "Show Files" || action.title == "Show Files")
    })
    // Never pressed: the action reveals the data folder in Finder.
    XCTAssertTrue(waitFor(Shell.element(app, AXID.EmptyState.root)))

    let corrupt = try FileManager.default.contentsOfDirectory(atPath: sandbox.dataDirectory.path)
      .filter { $0.contains("corrupt") }
      .sorted()
    XCTAssertEqual(corrupt.count, 1, "\(corrupt)")
  }

  func test_E_corruptDatabaseWithBackupShowsRestoredToast() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    try seedAlpha(server, sandbox)

    // An `.opened` launch writes the backup. The window is up before that file exists.
    let opened = try launch(sandbox)
    waitForBackupFile(sandbox)
    quit(opened)

    try corruptLiveDatabase(sandbox)
    let restored = try launch(sandbox)
    expectPersistentToast(restored, prefix: Self.restoredPrefix)
    expectFixtureAlpha(restored, "Fixture alpha restored from the backup")
  }

  func test_E_toastStaysUntilDismissed() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    try seedAlpha(server, sandbox)
    try corruptLiveDatabase(sandbox)
    let app = try launch(sandbox)
    let toast = expectPersistentToast(app, prefix: Self.recreatedPrefix)

    XCTAssertTrue(Shell.openCommandBar(app, key: "t"))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    XCTAssertTrue(toast.exists)
    XCTAssertTrue(toast.label.hasPrefix(Self.recreatedPrefix))
    XCTAssertEqual(toast.value as? String, AXID.Toast.persistent)

    // The one fixed wait in this suite. It asserts an absence: a persistent toast must not disappear, so a
    // predicate that the toast is gone is inverted and a 2 s timeout is the pass. A positive wait cannot assert
    // that something stays.
    let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      MainActor.assumeIsolated { !toast.exists }
    }, object: nil)
    gone.isInverted = true
    XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 2), .completed)
  }
}
