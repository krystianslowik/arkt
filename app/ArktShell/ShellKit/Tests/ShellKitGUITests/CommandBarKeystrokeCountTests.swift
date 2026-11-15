import AppKit
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The command bar's keystroke work, counted instead of timed (#839), so CI catches the two biggest regressions #606
/// fixed on any machine: 2,000 open tabs that all match every prefix of a 12-character query, typed one character at a
/// time. `CommandBarKeystrokeBudgetTests` times the same keystrokes, but only asserts in a quiet run of its own.
@MainActor
final class CommandBarKeystrokeCountTests: XCTestCase {
  private var shell: ShellWindowController!
  private var bar: CommandBarController { shell.commandBar }
  private var query: String { CommandBarKeystrokeBudgetTests.query }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let (source, first) = try CommandBarKeystrokeBudgetTests.worstCaseSidebar()
    shell = ShellWindowController(engine: InMemoryEngine(), sidebar: source)
    let window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1400, height: 900), display: false)
    shell.showWindow(nil)
    shell.activate(node: first)
    bar.clipboardURLProvider = { nil }                 // never reads the system pasteboard
    bar.settings.dismissSearchSuggestionNotice()
    bar.dismissFinisher = { $0() }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.barView.widthMotion.drivesFramesItself = false
    window.contentView?.layoutSubtreeIfNeeded()
  }

  override func tearDown() async throws {
    bar.invalidate()
    shell?.close()
    shell = nil
  }

  /// One keystroke as AppKit delivers it: the field's text changes and the delegate hears it; then the panel's
  /// layout and display, where the table asks for the rows it shows.
  private func type(_ text: String) {
    let field = bar.barView.field
    field.stringValue = text
    bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    bar.panel.contentView?.layoutSubtreeIfNeeded()
    bar.panel.displayIfNeeded()
  }

  /// The tab rows built while `body` runs.
  private func tabRowsBuilt(_ body: () -> Void) -> Int {
    let counter = CommandBarResults.TabRowCounter()
    CommandBarResults.$tabRowCounter.withValue(counter) { body() }
    return counter.value
  }

  private func openTheBar() {
    XCTAssertEqual(bar.openTabsProvider().count,
                   CommandBarKeystrokeBudgetTests.spaceCount * CommandBarKeystrokeBudgetTests.tabsPerSpace)
    bar.toggle(.newTab)
    XCTAssertTrue(bar.isVisible)
  }

  /// A row is built only for a tab the list shows; the other matches are counted, not built. A second pass that built
  /// a row for every match cost 27 ms a keystroke (#606).
  func testAKeystrokeBuildsOnlyTheTabRowsTheListShows() {
    openTheBar()
    for length in 1...query.count {
      let text = String(query.prefix(length))
      let built = tabRowsBuilt { type(text) }
      XCTAssertEqual(built, CommandBarResults.maxSwitchResults, "keystroke \(length), \"\(text)\"")
      XCTAssertEqual(bar.barView.pills.counts[.tabs], bar.openTabsProvider().count, "the Tabs pill counts every match")
    }
  }

  /// A typed keystroke refreshes the rows on screen in place: a reload takes every row view out of the window and
  /// builds it again (#606). The first keystroke, which turns the empty state into results, is not counted.
  func testTypedKeystrokesTwoToTwelveDoNotReloadTheTable() {
    let table = bar.barView.table
    let before = table.reloadDataCount
    table.reloadData()
    XCTAssertEqual(table.reloadDataCount, before + 1, "the counter counts reloads")

    openTheBar()
    type(String(query.prefix(1)))
    let afterFirst = table.reloadDataCount
    for length in 2...query.count {
      type(String(query.prefix(length)))
      XCTAssertEqual(table.reloadDataCount - afterFirst, 0, "keystroke \(length) reloaded the table")
    }
    XCTAssertEqual(bar.results.filter { $0.rowKind == .openTab }.count, CommandBarResults.maxSwitchResults)
  }
}
