import XCTest

/// Handles and actions on the shell shared by the scenario tests: the command bar and the sidebar rows. Everything
/// waits on accessibility state (plan, Rules: "No sleeps").
@MainActor
enum Shell {
  /// Any element with this identifier, whatever its role.
  static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  static func commandBar(_ app: XCUIApplication) -> XCUIElement { element(app, AXID.CommandBar.root) }

  static func commandBarField(_ app: XCUIApplication) -> XCUIElement { app.textFields[AXID.CommandBar.field] }

  static func isCommandBarOpen(_ app: XCUIApplication) -> Bool {
    let bar = commandBar(app)
    return bar.exists && (bar.value as? String) == AXID.CommandBar.open
  }

  /// A hidden panel may leave the accessibility tree, so "closed" is either an absent root or the `closed` value.
  static func isCommandBarClosed(_ app: XCUIApplication) -> Bool {
    let bar = commandBar(app)
    return !bar.exists || (bar.value as? String) == AXID.CommandBar.closed
  }

  @discardableResult
  static func waitForCommandBar(
    _ app: XCUIApplication, open: Bool, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    Waits.until("command bar \(open ? AXID.CommandBar.open : AXID.CommandBar.closed)", file: file, line: line) {
      open ? isCommandBarOpen(app) : isCommandBarClosed(app)
    }
  }

  /// Presses Cmd plus `key` ("t" or "l") and waits until the command bar is open and its field exists.
  @discardableResult
  static func openCommandBar(
    _ app: XCUIApplication, key: String, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    app.typeKey(key, modifierFlags: .command)
    guard waitForCommandBar(app, open: true, file: file, line: line) else { return false }
    let field = commandBarField(app)
    return Waits.until("\(field) to exist", file: file, line: line) { field.exists }
  }

  /// Types `text` into the open command bar's field and presses Return.
  static func submit(_ text: String, in app: XCUIApplication) {
    let field = commandBarField(app)
    field.typeText(text)
    field.typeKey(.return, modifierFlags: [])
  }

  /// Cmd-T, the address, Return; waits until the command bar has closed.
  @discardableResult
  static func openInNewTab(
    _ url: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    guard openCommandBar(app, key: "t", file: file, line: line) else { return false }
    submit(url, in: app)
    return waitForCommandBar(app, open: false, file: file, line: line)
  }

  /// Every `sidebar.row.today` row.
  static func todayRows(_ app: XCUIApplication) -> XCUIElementQuery {
    app.outlineRows.matching(identifier: AXID.Sidebar.rowToday)
  }

  /// The Today row with this label.
  static func todayRow(_ app: XCUIApplication, label: String) -> XCUIElement {
    todayRows(app).element(matching: NSPredicate(format: "label == %@", label))
  }

  static func spaceDots(_ app: XCUIApplication) -> XCUIElementQuery {
    app.buttons.matching(identifier: AXID.Sidebar.spaceDot)
  }

  /// Result rows of the open command bar (`commandBar.row`). Scoped to the results table: a whole-app
  /// `descendants` query also walks the web view and can stall the test.
  static func commandBarRows(_ app: XCUIApplication) -> XCUIElementQuery {
    app.tables[AXID.CommandBar.results].tableRows.matching(identifier: AXID.CommandBar.row)
  }

  /// Result rows from top to bottom. Screen frames use a top-left origin, so a smaller `minY` is higher.
  static func commandBarRowsInOrder(_ app: XCUIApplication) -> [XCUIElement] {
    commandBarRows(app).allElementsBoundByIndex
      .filter(\.exists)
      .sorted { lhs, rhs in
        if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
        return lhs.frame.minX < rhs.frame.minX
      }
  }

  /// The one selected result row, or nil when selection is missing or ambiguous.
  static func selectedCommandBarRow(_ app: XCUIApplication) -> XCUIElement? {
    let selected = commandBarRowsInOrder(app).filter(\.isSelected)
    guard selected.count == 1 else { return nil }
    return selected[0]
  }

  /// Labels, captions and selection, for a failure message. Empty when the bar shows no rows.
  static func commandBarRowSummary(_ app: XCUIApplication) -> String {
    let rows = commandBarRowsInOrder(app)
    if rows.isEmpty { return "no command bar rows" }
    return rows.map { row in
      let value = (row.value as? String) ?? String(describing: row.value ?? "nil")
      return "\(row.label)=\(value)\(row.isSelected ? " selected" : "")"
    }.joined(separator: " | ")
  }

  /// Whether a command bar row's label is for the page titled `title`: a row reads "<title>, <host>, <kind>, <k> of
  /// <n>" (#371), with the middle parts left out when a row has no host.
  static func rowLabel(_ label: String, isFor title: String) -> Bool {
    label == title || label.hasPrefix(title + ", ")
  }

  /// Moves Down until the selected row has this title and value. Does not press Enter.
  @discardableResult
  static func selectCommandBarRow(
    _ app: XCUIApplication, label: String, value: String,
    file: StaticString = #filePath, line: UInt = #line
  ) -> Bool {
    let present = Waits.until(
      "command bar row \(label) value \(value); \(commandBarRowSummary(app))", file: file, line: line
    ) {
      commandBarRowsInOrder(app).contains { rowLabel($0.label, isFor: label) && ($0.value as? String) == value }
    }
    guard present else { return false }
    let count = max(commandBarRowsInOrder(app).count, 1)
    for _ in 0..<count {
      if let selected = selectedCommandBarRow(app),
         rowLabel(selected.label, isFor: label), (selected.value as? String) == value {
        return true
      }
      let before = selectedCommandBarRow(app)?.label
      app.typeKey(.downArrow, modifierFlags: [])
      let moved = Waits.until(
        "selection to leave \(before ?? "none"); \(commandBarRowSummary(app))", file: file, line: line
      ) {
        let now = selectedCommandBarRow(app)
        if let nowLabel = now?.label, rowLabel(nowLabel, isFor: label), (now?.value as? String) == value { return true }
        return now?.label != before
      }
      if !moved { return false }
    }
    XCTFail("could not select \(label) (\(value)); \(commandBarRowSummary(app))", file: file, line: line)
    return false
  }

  /// Presses Return (or Cmd-Return / Opt-Return) on the selected result. Refuses a `Search` row: Enter is not
  /// pressed and this returns false, so a search is never committed. Callers that mean to commit assert true.
  @discardableResult
  static func commitSelectedRow(
    _ app: XCUIApplication,
    modifiers: XCUIElement.KeyModifierFlags = [],
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> Bool {
    guard let selected = selectedCommandBarRow(app) else {
      XCTFail("no selected command bar row; \(commandBarRowSummary(app))", file: file, line: line)
      return false
    }
    guard let caption = selected.value as? String else {
      XCTFail("selected command bar row has no caption; \(commandBarRowSummary(app))", file: file, line: line)
      return false
    }
    // A Search row would open a search engine. Never press Enter on it (plan U11, Rules: "No network").
    guard caption != "Search" else { return false }
    commandBarField(app).typeKey(.return, modifierFlags: modifiers)
    return true
  }
}

extension ArktUITestCase {
  /// Presses "New Space" in the empty state and waits until the first Space exists.
  func createFirstSpace(in app: XCUIApplication) throws {
    let newSpace = app.buttons[AXID.EmptyState.newSpace]
    XCTAssertTrue(waitFor(newSpace))
    newSpace.click()
    XCTAssertTrue(waitUntilGone(Shell.element(app, AXID.EmptyState.root)))
    let dots = Shell.spaceDots(app)
    XCTAssertTrue(Waits.until("one Space dot") { dots.count == 1 })
  }
}
