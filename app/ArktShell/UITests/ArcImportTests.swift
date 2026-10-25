import XCTest

/// Import from Arc from the empty state and the File menu (plan U13). Counts only: archive assertions never read
/// row titles. Every test checks the Arc copy it launched against: a rendered copy's SHA-256, or the empty
/// directory when the menu must stay disabled.
final class ArcImportTests: ArktUITestCase {
  private static let importMenuTitle = "Import Browser Data..."
  private static let importedSheetTitle = "Import complete"

  func test_E_importFromEmptyState() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)

    let importButton = app.buttons[AXID.EmptyState.importFromArc]
    XCTAssertTrue(waitFor(importButton))
    importButton.click()
    dismissImportedSheet(in: app, requiring: Self.firstImportLines)

    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("2 Space dots") { dots.count == ArcFixture.expected.spaces })
    let tiles = favoriteTiles(app)
    XCTAssertTrue(Waits.until("2 favorite tiles") { tiles.count == ArcFixture.expected.favorites })

    showArchive(in: app)
    XCTAssertTrue(waitForArchiveRows(ArcFixture.expected.archive, in: app))
    try assertArcCopyUnchanged(checksums, in: sandbox)
  }

  func test_E_importFromFileMenu() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)
    // The empty state shows Import from Arc once the availability check found Arc's sidebar file, so the menu
    // validates against that answer, not the launch default.
    XCTAssertTrue(waitFor(app.buttons[AXID.EmptyState.importFromArc]))
    try createFirstSpace(in: app)

    let item = openImportMenuItem(in: app)
    XCTAssertTrue(item.isEnabled, "Import from Arc... is disabled with Arc data present")
    item.click()
    dismissImportedSheet(in: app, requiring: Self.firstImportLines)

    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("3 Space dots") { dots.count == ArcFixture.expected.spaces + 1 })
    try assertArcCopyUnchanged(checksums, in: sandbox)
  }

  /// The second import writes nothing: its sheet reports 0 new Spaces, 0 Favorites added and 0 new archived items
  /// (the coordinator's counts of what it wrote), and the sidebar and the Archive still hold the first import's
  /// counts. The Archive window is first opened after the re-import, so the first page it applies is the count
  /// after both imports; a stale page from before the re-import cannot satisfy the wait.
  func test_E_reimportIsIdempotent() async throws {
    let server = try await fixtureServer()
    let sandbox = try Sandbox()
    let checksums = try ArcFixture.render(into: sandbox.arcDirectory, base: server.base)
    let app = try launch(sandbox)

    let importButton = app.buttons[AXID.EmptyState.importFromArc]
    XCTAssertTrue(waitFor(importButton))
    importButton.click()
    dismissImportedSheet(in: app, requiring: Self.firstImportLines)

    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("2 Space dots") { dots.count == ArcFixture.expected.spaces })
    let tiles = favoriteTiles(app)
    XCTAssertTrue(Waits.until("2 favorite tiles") { tiles.count == ArcFixture.expected.favorites })

    let item = openImportMenuItem(in: app)
    XCTAssertTrue(item.isEnabled, "Import from Arc... is disabled after the first import finished")
    item.click()
    // The sheet appears after the import applied, so the counts read after it are the final ones.
    dismissImportedSheet(in: app, requiring: ["0 new Spaces", "0 favorites added", "0 new archived items"])

    XCTAssertEqual(dots.count, ArcFixture.expected.spaces)
    XCTAssertEqual(tiles.count, ArcFixture.expected.favorites)
    showArchive(in: app)
    XCTAssertTrue(waitForArchiveRows(ArcFixture.expected.archive, in: app))
    try assertArcCopyUnchanged(checksums, in: sandbox)
  }

  /// With an empty Arc directory the availability check can only answer false, and the launch default is false,
  /// so the menu item the app validates is disabled whichever answer it read; the empty state offers no import.
  func test_E_importMenuDisabledWithoutArcData() throws {
    let sandbox = try Sandbox()
    let app = try launch(sandbox)
    XCTAssertTrue(waitFor(app.buttons[AXID.EmptyState.newSpace]))

    let item = openImportMenuItem(in: app)
    XCTAssertFalse(item.isEnabled, "Import from Arc... is enabled with an empty Arc directory")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(Waits.until("File menu closed") { !item.isHittable })
    XCTAssertFalse(app.buttons[AXID.EmptyState.importFromArc].exists,
                   "Import from Arc appeared with an empty Arc directory")
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
    dismissImportedSheet(in: app, requiring: Self.firstImportLines)

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

  /// The summary lines a first import into an empty profile shows (`ArcImportSummary.lines`), as line prefixes.
  static var firstImportLines: [String] {
    let expected = ArcFixture.expected
    return ["\(counted(expected.spaces, "Space")), ", "\(counted(expected.favorites, "favorite")) added",
            "\(expected.archive) new archived \(expected.archive == 1 ? "item" : "items")"]
  }

  private static func counted(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }

  /// Opens File once and returns "Import from Arc..." when the open menu shows it. AppKit validated the item as the
  /// menu opened, so its enabled state is the app's answer at that moment. Callers act on it (click, or Escape).
  func openImportMenuItem(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
    app.activate()
    app.menuBars.menuBarItems["File"].click()
    let item = app.menuBars.menuItems[Self.importMenuTitle]
    // `exists` can be true while the menu is closed; a hittable item is on screen in the open menu.
    XCTAssertTrue(Waits.until("File menu shows \(Self.importMenuTitle)", file: file, line: line) { item.isHittable },
                  file: file, line: line)
    return item
  }

  /// Waits for the "Imported from Arc" sheet, checks that its text has a line starting with each of `lines` (the
  /// coordinator's counts of what this import wrote), and closes it with OK.
  func dismissImportedSheet(
    in app: XCUIApplication, requiring lines: [String], file: StaticString = #filePath, line: UInt = #line
  ) {
    let title = Self.importedSheetTitle
    var found: XCUIElement?
    XCTAssertTrue(Waits.until("sheet titled \(title)", file: file, line: line) {
      found = Self.importedSheet(in: app)
      return found != nil
    }, file: file, line: line)
    guard let host = found else { return }
    var shown: [String] = []
    XCTAssertTrue(Waits.until("sheet lines \(lines) (shown: \(shown))", file: file, line: line) {
      shown = host.staticTexts.allElementsBoundByIndex.flatMap { text -> [String] in
        let strings = [(text.value as? String) ?? "", text.label]
        return strings.flatMap { $0.components(separatedBy: "\n") }
      }
      return lines.allSatisfy { prefix in shown.contains { $0.hasPrefix(prefix) } }
    }, file: file, line: line)
    let ok = host.buttons["OK"]
    XCTAssertTrue(waitFor(ok, file: file, line: line), file: file, line: line)
    ok.click()
    XCTAssertTrue(waitUntilGone(host, file: file, line: line), file: file, line: line)
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

  /// Tiles in the Favorites grid. Scoped to `favorites.grid`: a whole-app `descendants` query also walks the web
  /// view and can stall a wait (#289).
  func favoriteTiles(_ app: XCUIApplication) -> XCUIElementQuery {
    app.groups[AXID.Favorites.grid].buttons.matching(identifier: AXID.Favorites.tile)
  }

  func tileLabels(_ tiles: XCUIElementQuery) -> [String] {
    tiles.allElementsBoundByIndex.map(\.label)
  }

  /// Zero-based index of the selected Space dot, left to right. Nil when none is selected.
  func selectedSpaceIndex(in app: XCUIApplication) -> Int? {
    let dots = Shell.spaceDots(app).allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
    return dots.firstIndex { $0.isSelected }
  }

  /// Window > Show Archive: one click on the menu, one on the item once the open menu shows it.
  func showArchive(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    app.menuBars.menuBarItems["Window"].click()
    let item = app.menuBars.menuItems["Show Archive"]
    XCTAssertTrue(Waits.until("Window menu shows Show Archive", file: file, line: line) { item.isHittable },
                  file: file, line: line)
    item.click()
    XCTAssertTrue(waitFor(app.windows[AXID.Archive.window], file: file, line: line), file: file, line: line)
  }

  /// The Archive's rows (`archive.row`), scoped to its table. The table publishes one proxy row per loaded item
  /// from the page it applied, so the count is the number of items listed; titles are never read.
  func archiveRows(_ app: XCUIApplication) -> XCUIElementQuery {
    app.windows[AXID.Archive.window].tables[AXID.Archive.table].tableRows.matching(identifier: AXID.Archive.row)
  }

  /// Waits until the Archive lists `count` rows. Returns whether it did; a timeout fails the test.
  func waitForArchiveRows(
    _ count: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    let rows = archiveRows(app)
    var observed = 0
    return Waits.until("\(count) archive rows (saw \(observed))", file: file, line: line) {
      observed = rows.count
      return observed == count
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
