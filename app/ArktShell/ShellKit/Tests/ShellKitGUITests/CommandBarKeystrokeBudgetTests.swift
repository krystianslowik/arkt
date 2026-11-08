import AppKit
import CoreBridge
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The command bar at its worst (#606): 2,000 open tabs across 10 Spaces, every one of them matching each prefix of a
/// 12-character query, typed one character at a time. A keystroke's work (results, pill counts, the rows, and the
/// panel's layout, display and commit) stays under 8 ms of main-thread CPU time; each keystroke is the median of its
/// passes. The first keystroke, which turns the empty state into results and resizes the panel, is reported on its own
/// line and not asserted (see the pull request).
///
/// CPU time, not wall time, so no clock decides the result. It still depends on the machine: a run under `nice` or
/// with the cores saturated lands on slower cores and reads high. The gate follows `CONTRIBUTING.md` section 7: it
/// asserts when its class runs alone (`ARKT_PACING_GATE=1` lifts only this rule), on a machine below its core count
/// in load and not deprioritized; otherwise it prints and attaches its numbers.
@MainActor
final class CommandBarKeystrokeBudgetTests: XCTestCase {
  static let spaceCount = 10
  /// Open tabs listed per Space. A split lists its first pane only, so each Space also holds the split's second pane.
  static let tabsPerSpace = 200
  /// Every title contains it, so every prefix matches all 2,000 tabs and the pills count every one.
  static let query = "quarterly pl"
  static let measuredPasses = 6
  static let budget = 0.008

  private var shell: ShellWindowController!
  private var source: ModelSidebarSource!
  private var bar: CommandBarController { shell.commandBar }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let (source, first) = try Self.worstCaseSidebar()
    self.source = source
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

  /// 10 Spaces of 200 open tabs: long titles in several scripts, long paths, punycode hosts (the shown-host check
  /// decodes them), a folder and a split (the open-tabs walk descends into both).
  static func worstCaseSidebar() throws -> (ModelSidebarSource, NodeID) {
    var sidebar = SidebarModel.Sidebar()
    var first: NodeID?
    let scripts = ["Notes", "Заметки по проекту", "会议记录和计划", "ملاحظات الاجتماع", "Ελληνικές σημειώσεις"]
    for spaceIndex in 0..<spaceCount {
      let space = sidebar.addSpace(title: "Space \(spaceIndex) with a fairly long title for the pills")
      let folder = try sidebar.addFolder(title: "Folder \(spaceIndex)", in: .pinned(space))
      let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
      for index in 0...tabsPerSpace {                  // one more: the split's second pane is not listed
        let host = index % 7 == 0 ? "xn--bcher-kva\(index).example" : "docs-\(index).example-company.com"
        let url = try XCTUnwrap(URL(string: "https://\(host)/team/\(spaceIndex)/reports/quarterly-planning/"
          + String(repeating: "segment/", count: 12) + "page-\(index)?ref=sidebar&id=\(index)"))
        let title = "Quarterly planning \(scripts[index % scripts.count]) \(index) "
          + String(repeating: "and a very long tail of words ", count: 6)
        let location: SidebarModel.Location = switch index % 10 {
        case 0: .folder(folder)
        case 1 where sidebar.children(of: .split(split)).count < 2: .split(split)
        case 2: .pinned(space)
        default: .today(space)
        }
        let node = try sidebar.addTab(url: url, title: title, in: location)
        if first == nil, case .today = location { first = node }
      }
    }
    return (ModelSidebarSource(sidebar: sidebar), try XCTUnwrap(first))
  }

  private func threadCPU() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

  /// One keystroke as AppKit delivers it: the field's text changes and the delegate hears it; then the panel's
  /// layout, display and commit, where the rows are drawn.
  private func type(_ text: String) {
    let field = bar.barView.field
    field.stringValue = text
    bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    bar.panel.contentView?.layoutSubtreeIfNeeded()
    bar.panel.displayIfNeeded()
    CATransaction.flush()
  }

  /// Every row the table holds has its own cell, showing that row's result: rows refreshed in place never leave a row
  /// empty or showing another row's result.
  private func assertRowsShowTheResults(file: StaticString = #filePath, line: UInt = #line) {
    let table = bar.barView.table
    var seen = Set<ObjectIdentifier>()
    var rows = 0
    table.enumerateAvailableRowViews { rowView, row in
      rows += 1
      let cell = rowView.view(atColumn: 0) as? CommandBarCellView
      XCTAssertEqual(cell?.result, bar.results[row], "row \(row)", file: file, line: line)
      if let cell { XCTAssertTrue(seen.insert(ObjectIdentifier(cell)).inserted, "one cell in two rows", file: file, line: line) }
    }
    XCTAssertGreaterThan(rows, 0, file: file, line: line)
  }

  /// Why this run only reports, or nil when it asserts.
  private static func reportsOnly() -> String? {
    let environment = ProcessInfo.processInfo.environment
    guard environment["ARKT_PACING_GATE"] == "1" || PacingEnvironment.gateAsserts(for: Self.self) else {
      return "run in a batch"
    }
    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    if getloadavg(&load, 1) != 1 || load[0] >= Double(cores) {
      return String(format: "load %.2f on %d cores", load[0], cores)
    }
    let nice = getpriority(PRIO_PROCESS, 0)
    if nice > 0 { return "nice \(nice)" }
    return nil
  }

  func testTypedKeystrokesTwoToTwelveOfATwelveCharacterQueryStayUnderEightMilliseconds() throws {
    XCTAssertEqual(Self.query.count, 12)
    let openTabs = bar.openTabsProvider()
    XCTAssertEqual(openTabs.count, Self.spaceCount * Self.tabsPerSpace)
    bar.toggle(.newTab)
    XCTAssertTrue(bar.isVisible)

    var samples = Array(repeating: [Double](), count: Self.query.count)
    for pass in 0...Self.measuredPasses {                 // pass 0 warms the caches and the cells
      type("")
      for length in 1...Self.query.count {
        let start = threadCPU()
        type(String(Self.query.prefix(length)))
        let spent = threadCPU() - start
        if pass > 0 { samples[length - 1].append(spent) }
      }
      assertRowsShowTheResults()
      XCTAssertEqual(bar.barView.pills.counts[.tabs], openTabs.count, "the Tabs pill counts every match")
      XCTAssertEqual(bar.results.filter { $0.rowKind == .openTab }.count, CommandBarResults.maxSwitchResults)
    }

    let medians = samples.map { values in values.sorted()[values.count / 2] }
    for (index, values) in samples.enumerated() {
      print(String(format: "commandbar.keystroke n=%d query=\"%@\" median=%.3f max=%.3f ms", index + 1,
                   String(Self.query.prefix(index + 1)), medians[index] * 1000, (values.max() ?? 0) * 1000))
    }
    let typed = medians.dropFirst()
    let reportsOnly = Self.reportsOnly()
    let summary = String(format: "commandbar.keystroke tabs=%d spaces=%d passes=%d first=%.3f worstTyped=%.3f "
                         + "budget=%.1f ms gate=%@", openTabs.count, Self.spaceCount, Self.measuredPasses,
                         medians[0] * 1000, (typed.max() ?? 0) * 1000, Self.budget * 1000,
                         reportsOnly.map { "reports (\($0))" } ?? "asserts")
    print(summary)
    let attachment = XCTAttachment(string: summary)
    attachment.name = "commandbar.keystroke"
    attachment.lifetime = .keepAlways
    add(attachment)
    guard reportsOnly == nil else { return }
    for (index, median) in typed.enumerated() {
      XCTAssertLessThan(median, Self.budget, "keystroke \(index + 2) over 8 ms of main-thread CPU time")
    }
  }

  // MARK: The open tabs kept between keystrokes

  private func firstTabRow() throws -> (node: NodeID, title: String) {
    let row = try XCTUnwrap(bar.results.first { $0.rowKind == .openTab })
    guard case .switchTo(let node) = row.kind else { throw XCTSkip("not a tab row") }
    return (node, row.title)
  }

  func testATitleChangedWhileTypingShowsOnTheNextKeystroke() throws {
    bar.toggle(.newTab)
    type("qu")
    let first = try firstTabRow()
    source.updateTab(first.node, url: nil, title: "Quarterly review, renamed while the bar is open")
    type("qua")
    XCTAssertEqual(try firstTabRow().title, "Quarterly review, renamed while the bar is open")
  }

  func testATabViewedSinceTheLastShowLeadsTheRecentTabs() throws {
    let tabs = bar.openTabsProvider().map(\.node)
    shell.activate(node: tabs[5])
    shell.activate(node: tabs[9])
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.first { $0.group == .recentTabs }?.kind, .switchTo(tabs[5]))
    bar.hide()
    shell.activate(node: tabs[12])
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.first { $0.group == .recentTabs }?.kind, .switchTo(tabs[9]),
                   "the tab left last leads, not the one the earlier show listed")
  }
}
