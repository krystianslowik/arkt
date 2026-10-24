import XCTest

/// Quit inside the autosave debounce, relaunch, and the recovery toasts after a corrupt database (plan U14).
///
/// Sidebar rows are not in the out-of-process accessibility tree (#269), including on this Mac. The row probe
/// does not go through `waitForOutlineRows`: recording that expected failure symbolicates in-process, and that
/// `open` of a test object file does not return on this machine, so the suite never finishes. A missing row is
/// not a failure. The sidebar URL bar (not an outline row) showing the loopback host is what proves the tab is
/// there. When the row is present, its label is the assertion and the URL bar is not consulted.
final class PersistenceTests: ArktUITestCase {
  private static let recreatedPrefix = "Arkt couldn't read its saved sidebar and no backup could be used"
  private static let restoredPrefix = "Arkt couldn't read its saved sidebar and restored it from a backup"

  /// Cmd-Q only after this app is frontmost, then `.notRunning` within `seconds` times the scale. The activation is
  /// what keeps the key off any other process; same order as `ArktUITestCase.quit`.
  private func quit(
    _ app: XCUIApplication, notRunningWithin seconds: TimeInterval,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    app.activate()
    guard waitFor(app, .runningForeground, file: file, line: line) else { return }
    app.typeKey("q", modifierFlags: .command)
    waitFor(app, .notRunning, timeout: seconds, file: file, line: line)
  }

  /// True when the Today row is in the accessibility tree. Otherwise requires the sidebar URL bar to show the
  /// loopback host, which is the tab the row would be (#269). The row wait records nothing on a miss: see the type
  /// comment.
  @discardableResult
  private func expectFixtureAlpha(
    _ app: XCUIApplication, _ what: String, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    let row = Shell.todayRow(app, label: FixtureServer.title(ofPage: "alpha"))
    let rowShown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      MainActor.assumeIsolated { row.exists }
    }, object: nil)
    if XCTWaiter().wait(for: [rowShown], timeout: Waits.scaled(nil)) == .completed { return true }
    let urlBar = Shell.element(app, AXID.Sidebar.urlBar)
    XCTAssertTrue(Waits.until("sidebar URL bar shows the loopback host (\(what))", file: file, line: line) {
      (urlBar.value as? String)?.contains("127.0.0.1") == true
    }, what, file: file, line: line)
    return false
  }

  /// The first launch can raise a notification permission dialog. The runner clicks Don't Allow in the middle of
  /// typing, which closes the command bar. Dismiss it before the address is typed, then come back to this app.
  private func dismissNotificationPermission(_ app: XCUIApplication) {
    let center = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
    let dialog = center.dialogs.firstMatch
    guard dialog.exists else { return }
    let deny = dialog.buttons.matching(NSPredicate(format: "title CONTAINS %@", "Don")).firstMatch
    if deny.exists { deny.click() }
    app.activate()
    _ = waitFor(app, .runningForeground)
  }

  /// Cmd-T and the alpha address. A notification dialog is cleared before Return, and the bar is reopened if that
  /// clearance closed it. Does not wait for the bar to close: the default-debounce test quits on the next line.
  private func openAlpha(
    _ server: FixtureServer, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(Shell.openCommandBar(app, key: "t"), file: file, line: line)
    dismissNotificationPermission(app)
    if !Shell.isCommandBarOpen(app) {
      XCTAssertTrue(Shell.openCommandBar(app, key: "t"), file: file, line: line)
    }
    Shell.submit(server.page("alpha"), in: app)
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
    let database = sandbox.dataDirectory.appendingPathComponent("Arkt.sqlite")
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
    // Far past the row wait, so the debounced write cannot fire. Only the termination flush can save the change.
    sandbox.autosaveDelayMilliseconds = 60_000
    let app = try launch(sandbox)
    XCTAssertEqual(app.launchEnvironment["ARKT_AUTOSAVE_DELAY_MS"], "60000")

    try createFirstSpace(in: app)
    openAlpha(server, in: app)
    XCTAssertTrue(Shell.waitForCommandBar(app, open: false))
    expectFixtureAlpha(app, "Fixture alpha before quit")
    // The flush itself is bounded at 1 s; 5 s times the scale is the bound this wait asserts.
    quit(app, notRunningWithin: 5)

    sandbox.autosaveDelayMilliseconds = nil
    let relaunched = try launch(sandbox)
    XCTAssertNil(relaunched.launchEnvironment["ARKT_AUTOSAVE_DELAY_MS"])
    expectFixtureAlpha(relaunched, "Fixture alpha after relaunch")
  }

  func test_E_quitAtDefaultDebounceKeepsChange() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    XCTAssertNil(app.launchEnvironment["ARKT_AUTOSAVE_DELAY_MS"])

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
