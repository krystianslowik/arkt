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
}
