import XCTest

/// Import from Arc from the empty state and the File menu (plan U13). Counts only: archive assertions never read
/// row titles. Every test checks the Arc copy it launched against: a rendered copy's SHA-256, or the empty
/// directory when the menu must stay disabled.
final class ArcImportTests: ArktUITestCase {
  private static let importMenuTitle = "Import from Arc..."
  private static let importedSheetTitle = "Imported from Arc"

  func test_E_importFromEmptyState() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)

    let importButton = app.buttons[AXID.EmptyState.importFromArc]
    XCTAssertTrue(waitFor(importButton))
    importButton.click()
    dismissImportedSheet(in: app)

    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("2 Space dots") { dots.count == ArcFixture.expected.spaces })
    let tiles = favoriteTiles(app)
    XCTAssertTrue(Waits.until("2 favorite tiles") { tiles.count == ArcFixture.expected.favorites })

    showArchive(in: app)
    XCTAssertTrue(waitForArchiveCount(ArcFixture.expected.archive, in: app))
    try assertArcCopyUnchanged(checksums, in: sandbox)
  }

  func test_E_importFromFileMenu() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)
    try createFirstSpace(in: app)

    let item = try waitForImportMenu(enabled: true, in: app)
    item.click()
    dismissImportedSheet(in: app)

    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("3 Space dots") { dots.count == ArcFixture.expected.spaces + 1 })
    try assertArcCopyUnchanged(checksums, in: sandbox)
  }

  func test_E_reimportIsIdempotent() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)

    let importButton = app.buttons[AXID.EmptyState.importFromArc]
    XCTAssertTrue(waitFor(importButton))
    importButton.click()
    dismissImportedSheet(in: app)

    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("2 Space dots") { dots.count == ArcFixture.expected.spaces })
    let tiles = favoriteTiles(app)
    XCTAssertTrue(Waits.until("2 favorite tiles") { tiles.count == ArcFixture.expected.favorites })
    showArchive(in: app)
    XCTAssertTrue(waitForArchiveCount(ArcFixture.expected.archive, in: app))
    let spacesBefore = dots.count
    let favoritesBefore = tiles.count
    guard let archiveBefore = archiveCount(in: app) else {
      return XCTFail("archive table value was not rows N")
    }
    XCTAssertEqual(archiveBefore, ArcFixture.expected.archive)

    let item = try waitForImportMenu(enabled: true, in: app)
    item.click()
    dismissImportedSheet(in: app)

    XCTAssertEqual(dots.count, spacesBefore)
    XCTAssertEqual(spacesBefore, ArcFixture.expected.spaces)
    XCTAssertTrue(Waits.until("favorite count unchanged") { tiles.count == favoritesBefore })
    XCTAssertTrue(waitForArchiveCount(archiveBefore, in: app))
    XCTAssertEqual(archiveBefore, ArcFixture.expected.archive)
    try assertArcCopyUnchanged(checksums, in: sandbox)
  }

  func test_E_importMenuDisabledWithoutArcData() throws {
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    XCTAssertTrue(waitFor(Shell.element(app, AXID.EmptyState.root)))

    // The availability check is async and the menu returns the cached answer, so a single read can be disabled
    // before the check finishes. The empty-state button is what that check shows; it must not appear.
    let importButton = app.buttons[AXID.EmptyState.importFromArc]
    let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      MainActor.assumeIsolated { importButton.exists }
    }, object: nil)
    appeared.isInverted = true
    let result = XCTWaiter().wait(for: [appeared], timeout: Waits.scaled(2))
    XCTAssertEqual(result, .completed, "Import from Arc appeared with an empty Arc directory")

    let item = try waitForImportMenu(enabled: false, in: app)
    XCTAssertFalse(item.isEnabled)
    app.typeKey(.escape, modifierFlags: [])
    try assertArcCopyUnchanged(nil, in: sandbox)
  }

  /// BH-045: Spaces on one profile show the same Favorites. BH-034: Favorites belong to the profile, so switching
  /// Space does not change them. The second dot must become selected, or a no-op Ctrl-2 would still match.
  func test_BH045_BH034_importedSpacesShareFavorites() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)

    let importButton = app.buttons[AXID.EmptyState.importFromArc]
    XCTAssertTrue(waitFor(importButton))
    importButton.click()
    dismissImportedSheet(in: app)

    let tiles = favoriteTiles(app)
    XCTAssertTrue(Waits.until("2 favorite tiles") { tiles.count == ArcFixture.expected.favorites })
    let labels = tileLabels(tiles)
    XCTAssertEqual(labels.count, ArcFixture.expected.favorites)
    XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })

    app.activate()
    app.typeKey("2", modifierFlags: .control)
    XCTAssertTrue(Waits.until("Space 2 selected") { self.selectedSpaceIndex(in: app) == 1 })
    XCTAssertEqual(tileLabels(tiles), labels)
    try assertArcCopyUnchanged(checksums, in: sandbox)
  }

  // MARK: - Import sheet and menu

  /// File > "Import from Arc...". Reopens the menu while the enabled state is stale: validation returns the cached
  /// availability, and the check that refreshes it applies on the next validation.
  func waitForImportMenu(
    enabled: Bool, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) throws -> XCUIElement {
    app.activate()
    var item = app.menuBars.menuItems[Self.importMenuTitle]
    // One click per opening. A second click before the menu appears would close it again.
    var awaitingMenu = false
    XCTAssertTrue(Waits.until("Import from Arc... isEnabled \(enabled)", file: file, line: line) {
      item = app.menuBars.menuItems[Self.importMenuTitle]
      // `exists` can be true while the menu is closed. Only a hittable item has been validated.
      if item.isHittable {
        awaitingMenu = false
        if item.isEnabled == enabled { return true }
        app.typeKey(.escape, modifierFlags: [])
        return false
      }
      if awaitingMenu || app.menuBars.menuItems["New Tab"].isHittable { return false }
      app.menuBars.menuBarItems["File"].click()
      awaitingMenu = true
      return false
    }, file: file, line: line)
    return item
  }

  func dismissImportedSheet(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let title = Self.importedSheetTitle
    var host: XCUIElement?
    XCTAssertTrue(Waits.until("sheet titled \(title)", file: file, line: line) {
      host = Self.importedSheet(in: app)
      return host != nil
    }, file: file, line: line)
    let ok = host?.buttons["OK"] ?? app.buttons["OK"]
    XCTAssertTrue(waitFor(ok, file: file, line: line), file: file, line: line)
    ok.click()
    if let host {
      XCTAssertTrue(waitUntilGone(host, file: file, line: line), file: file, line: line)
    }
  }

  private static func importedSheet(in app: XCUIApplication) -> XCUIElement? {
    let title = importedSheetTitle
    let named = [app.sheets[title], app.dialogs[title], app.windows[title]]
    if let match = named.first(where: { $0.exists }) { return match }
    if app.staticTexts[title].exists {
      if app.sheets.firstMatch.exists { return app.sheets.firstMatch }
      if app.dialogs.firstMatch.exists { return app.dialogs.firstMatch }
    }
    return nil
  }

  // MARK: - Counts

  func favoriteTiles(_ app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: AXID.Favorites.tile)
  }

  func tileLabels(_ tiles: XCUIElementQuery) -> [String] {
    tiles.allElementsBoundByIndex.map(\.label)
  }

  /// Zero-based index of the selected Space dot, left to right. Nil when none is selected.
  func selectedSpaceIndex(in app: XCUIApplication) -> Int? {
    let dots = Shell.spaceDots(app).allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
    return dots.firstIndex { $0.isSelected }
  }

  func showArchive(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    if app.menuBars.menuItems[Self.importMenuTitle].exists || app.menuBars.menuItems["Show Archive"].exists {
      app.typeKey(.escape, modifierFlags: [])
    }
    app.menuBars.menuBarItems["Window"].click()
    let item = app.menuBars.menuItems["Show Archive"]
    XCTAssertTrue(waitFor(item, file: file, line: line), file: file, line: line)
    item.click()
    XCTAssertTrue(waitFor(app.windows[AXID.Archive.window], file: file, line: line), file: file, line: line)
  }

  /// Count encoded as the archive table accessibility value `rows N`, or nil when the value is not that text.
  /// Out-of-process clients see no `archive.row` children, so this value is the count text the plan asserts.
  func archiveCount(in app: XCUIApplication) -> Int? {
    parsedArchiveCount(archiveTableValue(in: app))
  }

  /// `archive.window`'s `archive.table` accessibility value, and nothing else. Polling `archive.row` or
  /// `archive.footer` from XCTest wedges the runner.
  private func archiveTableValue(in app: XCUIApplication) -> String {
    let table = app.windows[AXID.Archive.window].tables[AXID.Archive.table]
    return (table.value as? String) ?? ""
  }

  private func parsedArchiveCount(_ value: String) -> Int? {
    let prefix = "rows "
    guard value.hasPrefix(prefix) else { return nil }
    return Int(value.dropFirst(prefix.count))
  }

  /// Waits until the archive table value is `rows <count>`. Returns whether it matched; a timeout fails the test.
  func waitForArchiveCount(
    _ count: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    let table = app.windows[AXID.Archive.window].tables[AXID.Archive.table]
    var observed = ""
    return Waits.until("archive table value rows \(count) (saw \(observed))", file: file, line: line) {
      observed = (table.value as? String) ?? ""
      return self.parsedArchiveCount(observed) == count
    }
  }

  /// `checksums` is the rendered copy. Nil means the test launched against an empty Arc directory, which must stay
  /// empty: rendering a copy would enable Import from Arc.
  func assertArcCopyUnchanged(
    _ checksums: ArcFixture.Checksums?, in sandbox: Sandbox,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    if let checksums {
      XCTAssertTrue(try checksums.unchanged(in: sandbox.arcDirectory),
                    "rendered Arc copy must stay untouched", file: file, line: line)
      return
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: sandbox.arcDirectory.path)
    XCTAssertEqual(names, [], "empty Arc directory must stay empty", file: file, line: line)
  }
}
