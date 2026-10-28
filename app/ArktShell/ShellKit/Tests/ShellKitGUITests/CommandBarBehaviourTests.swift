import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// The hybrid command bar's behaviour (#371, design/command-bar/README.md): filters (Cmd-1 to Cmd-4, Tab, Shift-Tab),
/// the smart Tab rule, Esc clearing before closing, Cmd-Shift-V, the empty state's groups, the selection slide and
/// the fades. Motion is stepped on injected clocks and finishers; nothing here waits on a clock.
@MainActor
final class CommandBarBehaviourTests: XCTestCase {
  var shell: ShellWindowController!
  var bar: CommandBarController!
  var window: NSWindow!
  var announcements: [String] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1280, height: 800), display: true)
    shell.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    bar = CommandBarController(parent: window)
    bar.settings.dismissSearchSuggestionNotice()
    bar.announce = { [unowned self] in announcements.append($0) }
    bar.dismissFinisher = { _ in }            // the fade is ended by hand where a test looks at it
    bar.barView.selectionMotion.drivesFramesItself = false   // no display link: tests step the slide by hand
    bar.prewarm()
    announcements = []
  }

  override func tearDown() async throws {
    bar.invalidate()
    shell.close()
  }

  // MARK: Helpers

  private func tabs(_ count: Int) -> [CommandBarResults.OpenTab] {
    (1...count).map { .init(node: UUID(), title: "Tab \($0)", url: URL(string: "https://t\($0).example")!) }
  }

  private func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                               windowNumber: bar.panel.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code))
    bar.panel.sendEvent(event)
  }

  private func command(_ digit: Int) throws {
    let codes: [Int: UInt16] = [1: 18, 2: 19, 3: 20, 4: 21]
    try key(try XCTUnwrap(codes[digit]), String(digit), [.command])
  }

  private func selector(_ action: Selector) -> Bool {
    bar.control(bar.barView.field, textView: NSTextView(), doCommandBy: action)
  }

  private func tab() -> Bool { selector(#selector(NSResponder.insertTab(_:))) }
  private func backtab() -> Bool { selector(#selector(NSResponder.insertBacktab(_:))) }
  private func escape() -> Bool { selector(#selector(NSResponder.cancelOperation(_:))) }

  /// Three tabs, an action and a search that all match "Tab".
  private func showMixed(query: String = "Tab") {
    bar.openTabsProvider = { [self] in tabs(3) }
    bar.actionsProvider = { [CommandBarAction(id: "tabAction", title: "Tab Action")] }
    bar.toggle(.newTab)
    if !query.isEmpty { bar.setQueryForTesting(query) }
  }

  private func kinds() -> [String] { bar.results.map(\.kind.name) }

  // MARK: Filters

  func testCommandDigitsPickThePillsAndFilterTheRows() throws {
    showMixed()
    XCTAssertEqual(kinds(), ["switch", "switch", "switch", "search", "action"])
    try command(2)
    XCTAssertEqual(bar.filter, .tabs)
    XCTAssertEqual(kinds(), ["switch", "switch", "switch"])
    XCTAssertEqual(bar.barView.pills.selected, .tabs)
    try command(4)
    XCTAssertEqual(kinds(), ["action"])
    try command(3)
    XCTAssertEqual(kinds(), ["noMatch"], "History has no source yet: the empty row")
    XCTAssertEqual(bar.results.first?.title, "No History match Tab")
    try command(1)
    XCTAssertEqual(kinds(), ["switch", "switch", "switch", "search", "action"])
  }

  func testTheQueryAndTheCountsSurviveAFilterChange() throws {
    showMixed()
    try command(2)
    XCTAssertEqual(bar.barView.field.stringValue, "Tab")
    XCTAssertEqual(bar.barView.pills.counts[.all], 5, "counts are of the unfiltered rows")
    XCTAssertEqual(bar.barView.pills.counts[.tabs], 3)
    XCTAssertEqual(bar.barView.pills.counts[.actions], 1)
  }

  func testTheFilterAnnouncesItsNameAndCount() throws {
    showMixed()
    try command(2)
    try command(3)
    XCTAssertEqual(announcements, ["Tabs, 3 results", "History, 0 results"])
    try command(4)
    XCTAssertEqual(announcements.last, "Actions, 1 result")
  }

  func testTheSelectedPillSaysSoToVoiceOver() throws {
    showMixed()
    try command(2)
    let labels = bar.barView.pills.subviews.map { $0.accessibilityLabel() ?? "" }
    XCTAssertEqual(labels[1], "Tabs, 3 results, selected")
    XCTAssertEqual(labels[0], "All, 5 results")
  }

  func testAFilterResetsToAllOnEveryOpen() throws {
    showMixed()
    try command(2)
    bar.hide()
    bar.toggle(.newTab)
    XCTAssertEqual(bar.filter, .all)
    XCTAssertEqual(bar.barView.pills.selected, .all)
  }

  func testTabCyclesTheFiltersWhenNothingScopes() throws {
    showMixed()
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.filter, .tabs)
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.filter, .history)
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.filter, .actions)
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.filter, .all, "wraps")
    XCTAssertEqual(bar.scope, .normal)
  }

  func testShiftTabGoesBack() throws {
    showMixed()
    XCTAssertTrue(backtab())
    XCTAssertEqual(bar.filter, .actions, "wraps backward from All")
    XCTAssertTrue(backtab())
    XCTAssertEqual(bar.filter, .history)
  }

  func testEnteringAScopeResetsTheFilter() throws {
    bar.actionsProvider = { [CommandBarAction(id: "a", title: "A")] }
    bar.toggle(.newTab)
    try command(3)
    XCTAssertTrue(tab())                                   // empty new-tab bar: a Tab key cap shows, action search
    XCTAssertEqual(bar.scope, .actions)
    XCTAssertEqual(bar.filter, .all)
    XCTAssertEqual(bar.barView.pills.selected, .all)
  }

  func testClickingAPillPicksIt() throws {
    showMixed()
    bar.barView.pills.onSelect?(.actions)
    XCTAssertEqual(bar.filter, .actions)
    let pill = try XCTUnwrap(bar.barView.pills.subviews.first { $0.accessibilityIdentifier() == "commandBar.filter.tabs" })
    XCTAssertTrue(pill.accessibilityPerformPress(), "VoiceOver can press it")
    XCTAssertEqual(bar.filter, .tabs)
  }

  func testNoFilterKeyWorksInsideAScope() throws {
    bar.actionsProvider = { [CommandBarAction(id: "a", title: "A")] }
    bar.toggle(.newTab)
    XCTAssertTrue(tab())                                   // empty new-tab bar: action search
    XCTAssertEqual(bar.scope, .actions)
    XCTAssertTrue(tab())
    XCTAssertTrue(backtab())
    try command(2)
    XCTAssertEqual(bar.filter, .all)
    XCTAssertEqual(bar.scope, .actions)
  }

  func testTheEmptyRowIsNotSelected() throws {
    showMixed()
    try command(3)
    XCTAssertEqual(bar.barView.table.selectedRow, -1)
    XCTAssertTrue(bar.barView.selectionIndicator.isHidden, "no fill or tick on a row that does nothing")
  }

  func testTheEmptyRowDoesNothingOnReturn() throws {
    var opened = false
    bar.onOpen = { _, _ in opened = true }
    showMixed()
    try command(3)
    bar.commit()
    XCTAssertTrue(bar.isVisible, "nothing to run: the bar stays")
    XCTAssertFalse(opened)
  }

  func testAFilterRowCountFitsThePanel() throws {
    showMixed()
    try command(3)
    XCTAssertEqual(bar.panel.frame.height, CommandBarGeometry.contentHeight(rowCount: 1))
  }

  // MARK: The smart Tab rule

  func testTabOnTheEmptyNewTabBarEntersActionSearch() throws {
    bar.actionsProvider = { [CommandBarAction(id: "newSpace", title: "New Space")] }
    bar.toggle(.newTab)
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.scope, .actions)
    XCTAssertEqual(bar.filter, .all)
  }

  func testTabOnAnEmptyCmdLBarCyclesTheFilters() throws {
    bar.actionsProvider = { [CommandBarAction(id: "newSpace", title: "New Space")] }
    bar.toggle(.currentTab(nil))
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.scope, .normal)
    XCTAssertEqual(bar.filter, .tabs)
  }

  func testTabOnATypedAliasScopesToTheSiteBecauseItsRowShowsTheTabKeyCap() throws {
    bar.toggle(.newTab)
    bar.setQueryForTesting("yt")
    XCTAssertEqual(bar.results.first?.rowKind, .siteSearch, "the alias row leads")
    XCTAssertTrue(bar.results[0].showsTabKeyCap)
    XCTAssertEqual(bar.barView.hintStrip.hints.items.last, CommandBarHints.Item(keyCaps: ["tab"], caption: "Search site"))
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.scope, .siteSearch(SiteSearchEngines.seeded[0]))
    XCTAssertEqual(bar.barView.field.stringValue, "")
    XCTAssertEqual(bar.filter, .all, "Tab scoped; it did not cycle")
  }

  func testTabOnASiteNameRowScopesOnlyWhileThatRowIsSelected() throws {
    bar.toggle(.newTab)
    bar.setQueryForTesting("git")                          // matches GitHub by name; the search row leads
    let siteRow = try XCTUnwrap(bar.results.firstIndex { $0.rowKind == .siteSearch })
    XCTAssertGreaterThan(siteRow, 0)
    XCTAssertEqual(bar.results[siteRow].title, "Search GitHub for git")
    XCTAssertTrue(tab(), "the selected row is the search row: no Tab key cap, so Tab cycles")
    XCTAssertEqual(bar.filter, .tabs)
    bar.setFilter(.all)
    try key(125, "\u{F701}")                              // Down, once per row above the site row
    for _ in 1..<siteRow { try key(125, "\u{F701}") }
    XCTAssertEqual(bar.barView.table.selectedRow, siteRow)
    XCTAssertTrue(tab())
    XCTAssertEqual(bar.scope, .siteSearch(SiteSearchEngines.seeded[2]))
  }

  func testReturnOnAWholeAliasScopesLikeTab() throws {
    var opened: URL?
    bar.onOpen = { url, _ in opened = url }
    bar.toggle(.newTab)
    bar.setQueryForTesting("yt")
    bar.commit()
    XCTAssertEqual(bar.scope, .siteSearch(SiteSearchEngines.seeded[0]))
    XCTAssertNil(opened, "nothing to search for yet")
    XCTAssertTrue(bar.isVisible)
  }

  func testReturnOnASiteNameRowSearchesTheSite() throws {
    var opened: URL?
    bar.onOpen = { url, _ in opened = url }
    bar.toggle(.newTab)
    bar.setQueryForTesting("git")
    let siteRow = try XCTUnwrap(bar.results.firstIndex { $0.rowKind == .siteSearch })
    for _ in 0..<siteRow { try key(125, "\u{F701}") }
    bar.commit()
    XCTAssertEqual(opened?.absoluteString, "https://github.com/search?q=git")
  }

  func testTheCaretIsMustard() throws {
    bar.toggle(.newTab)
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    XCTAssertEqual(editor.insertionPointColor, ShellTokens.commandBarTick.resolve(bar.flavor).nsColor())
  }

  func testTheHintStripOnAnEmptyNewTabBarAdvertisesActionSearch() throws {
    bar.actionsProvider = { [CommandBarAction(id: "a", title: "A")] }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.barView.hintStrip.hints.items.last,
                   CommandBarHints.Item(keyCaps: ["tab"], caption: "Actions"))
    bar.setQueryForTesting("zzz")
    XCTAssertFalse(bar.barView.hintStrip.hints.items.contains { $0.keyCaps == ["tab"] }, "Tab cycles: no Tab item")
  }

  func testTheHintStripShowsFilterAndPasteAndGo() throws {
    showMixed()
    let hints = bar.barView.hintStrip.hints
    XCTAssertEqual(hints.items.map(\.caption), ["Move", "Filter"])
    XCTAssertEqual(hints.items[1].keyCaps, [CommandBarKeyCaps.command, "1\u{2013}4"])
    XCTAssertEqual(hints.trailing?.text, "Paste and Go")
    XCTAssertEqual(hints.trailing?.keyCaps, [CommandBarKeyCaps.command, CommandBarKeyCaps.shift, "V"])
  }

  func testTheHintStripShowsItsRightHandLineWholeInTheEmptyStateAndInSearch() throws {
    bar.actionsProvider = { [CommandBarAction(id: "a", title: "A")] }
    bar.toggle(.newTab)                                    // Move, Open, Filter, Tab, and the long empty-state line
    bar.barView.layoutSubtreeIfNeeded()
    XCTAssertTrue(bar.barView.hintStrip.trailingLineFits, "the empty-state line is not cut off")
    bar.setQueryForTesting("git")
    bar.barView.layoutSubtreeIfNeeded()
    XCTAssertTrue(bar.barView.hintStrip.trailingLineFits)
  }

  func testTheClipboardIsReadOnceForAShowNotOnEveryReload() throws {
    var reads = 0
    bar.clipboardURLProvider = { reads += 1; return URL(string: "https://clip.example") }
    showMixed(query: "")
    try command(2)
    try command(1)
    XCTAssertTrue(escape())
    bar.setQueryForTesting("x")
    bar.setQueryForTesting("")
    XCTAssertEqual(reads, 1, "one pasteboard read for the whole show")
    bar.hide()
    bar.toggle(.newTab)
    XCTAssertEqual(reads, 2, "and a fresh one for the next show")
  }

  func testThePillCountsCoverEveryMatchNotJustTheRowsShown() throws {
    bar.openTabsProvider = { [self] in tabs(9) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("Tab")
    XCTAssertEqual(bar.results.filter { $0.rowKind == .openTab }.count, 6)
    XCTAssertEqual(bar.barView.pills.counts[.tabs], 9)
    XCTAssertEqual(bar.barView.pills.counts[.all], 10)
  }

  func testANarrowWindowKeepsTheQueryFieldWideAndHidesThePills() throws {
    window.minSize = NSSize(width: 320, height: 200)       // the shell's own minimum would hold the window wider
    window.setFrame(NSRect(x: 100, y: 100, width: 420, height: 700), display: true)
    showMixed()
    bar.barView.layoutSubtreeIfNeeded()
    XCTAssertGreaterThanOrEqual(bar.barView.field.frame.width, CommandBarView.minimumFieldWidth)
    XCTAssertTrue(bar.barView.pills.isHidden,
                  "the pills give way; Cmd-1 to Cmd-4 still filter (window \(window.frame), bar \(bar.panel.frame), pills \(bar.barView.pills.frame), field \(bar.barView.field.frame))")
    try command(2)
    XCTAssertEqual(bar.filter, .tabs)
    window.setFrame(NSRect(x: 100, y: 100, width: 1280, height: 800), display: true)
    bar.hide()
    showMixed()
    bar.barView.layoutSubtreeIfNeeded()
    XCTAssertFalse(bar.barView.pills.isHidden)
  }

  // MARK: Esc

  func testEscClearsTheQueryFirstAndClosesOnTheSecondPress() throws {
    showMixed()
    XCTAssertTrue(escape())
    XCTAssertTrue(bar.isVisible, "the first Esc only clears")
    XCTAssertEqual(bar.barView.field.stringValue, "")
    XCTAssertEqual(bar.barView.field.currentEditor()?.string, "")
    XCTAssertEqual(bar.results.first?.group, .recentTabs, "the empty state is back")
    XCTAssertTrue(escape())
    XCTAssertFalse(bar.isVisible)
  }

  func testEscOnAnEmptyScopedFieldCloses() throws {
    bar.actionsProvider = { [CommandBarAction(id: "a", title: "A")] }
    bar.toggle(.newTab)
    XCTAssertTrue(tab())
    XCTAssertTrue(escape())
    XCTAssertFalse(bar.isVisible)
  }

  func testEscKeepsTheSelectedFilterWhileClearing() throws {
    showMixed()
    try command(2)
    XCTAssertTrue(escape())
    XCTAssertEqual(bar.filter, .tabs)
  }

  // MARK: Cmd-Shift-V

  func testCommandShiftVOpensTheClipboardURLFromAnyState() throws {
    var opened: (URL, CommandBarController.OpenTarget)?
    bar.clipboardURLProvider = { URL(string: "https://clip.example/x") }
    bar.onOpen = { opened = ($0, $1) }
    showMixed()                                            // a typed query: the Paste and Go row is not showing
    try key(9, "v", [.command, .shift])
    XCTAssertEqual(opened?.0.absoluteString, "https://clip.example/x")
    XCTAssertEqual(opened?.1, .newTab)
    XCTAssertFalse(bar.isVisible)
  }

  func testCommandShiftVWithNothingOnTheClipboardKeepsTheBar() throws {
    var opened = false
    bar.onOpen = { _, _ in opened = true }
    showMixed()
    try key(9, "v", [.command, .shift])
    XCTAssertFalse(opened)
    XCTAssertTrue(bar.isVisible)
  }

  func testCmdLLeavesPasteAndGoOutOfTheHintStrip() throws {
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    XCTAssertNil(bar.barView.hintStrip.hints.trailing)
  }

  func testCommandShiftVIsNotOfferedFromCmdL() throws {
    var opened = false
    bar.clipboardURLProvider = { URL(string: "https://clip.example/x") }
    bar.onOpen = { _, _ in opened = true }
    bar.toggle(.currentTab(nil))
    try key(9, "v", [.command, .shift])
    XCTAssertFalse(opened)
  }

  // MARK: Empty state

  func testTheEmptyStateGroupsClipboardRecentTabsAndActions() throws {
    let all = tabs(6)
    bar.clipboardURLProvider = { URL(string: "https://arkt.dev/changelog") }
    bar.recentTabsProvider = { all }
    bar.openTabsProvider = { all }
    bar.actionsProvider = { [CommandBarAction(id: "newSpace", title: "New Space"),
                             CommandBarAction(id: "b", title: "B"), CommandBarAction(id: "c", title: "C")] }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.map(\.group),
                   [.clipboard] + Array(repeating: .recentTabs, count: 4) + [.actions, .actions])
    XCTAssertEqual(bar.barView.table.selectedRow, 0, "Paste and Go is selected first")
    XCTAssertEqual(bar.barView.groupHeaders, [0: "Clipboard", 1: "Recent tabs", 5: "Actions"])
    XCTAssertEqual(bar.panel.frame.height,
                   CommandBarGeometry.contentHeight(rowCount: 7, headerCount: 3,
                                                    maxRows: CommandBarGeometry.maxEmptyStateRows))
  }

  func testGroupHeadersMakeTheirRowsTallerAndTheIndicatorSkipsThem() throws {
    let all = tabs(2)
    bar.recentTabsProvider = { all }
    bar.openTabsProvider = { all }
    bar.toggle(.newTab)
    let table = bar.barView.table
    XCTAssertEqual(table.rect(ofRow: 0).height, 40 + 26)
    XCTAssertEqual(table.rect(ofRow: 1).height, 40)
    let indicator = bar.barView.selectionIndicator
    XCTAssertEqual(indicator.frame.height, 40, "the fill covers the row, not its header")
    XCTAssertEqual(indicator.frame.minY, table.rect(ofRow: 0).minY + 26)
    table.selectRowIndexes([1], byExtendingSelection: false)
    XCTAssertEqual(indicator.frame, table.rect(ofRow: 1))
  }

  func testTheHeaderIsDrawnInTheFirstRowOfAGroupAndNoOtherRow() throws {
    let all = tabs(2)
    bar.recentTabsProvider = { all }
    bar.openTabsProvider = { all }
    bar.toggle(.newTab)
    bar.barView.layoutSubtreeIfNeeded()
    let first = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? CommandBarCellView)
    let second = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? CommandBarCellView)
    XCTAssertEqual(first.header.stringValue, "Recent tabs")
    XCTAssertFalse(first.header.isHidden)
    XCTAssertTrue(second.header.isHidden)
    first.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(first.header.frame.maxY, 26, "the header sits in the top 26 pt")
    XCTAssertGreaterThanOrEqual(first.title.frame.minY, 26, "the row's content is below it")
  }

  func testWithNothingOnTheClipboardTheFirstRecentTabLeads() throws {
    let all = tabs(2)
    bar.recentTabsProvider = { all }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.first?.group, .recentTabs)
    XCTAssertEqual(bar.barView.table.selectedRow, 0)
  }

  func testARecentTabSaysWhenItWasViewed() throws {
    let viewed = Date().addingTimeInterval(-12 * 60)
    let all = [CommandBarResults.OpenTab(node: UUID(), title: "Tab", url: URL(string: "https://t.example")!,
                                         lastViewed: viewed)]
    bar.recentTabsProvider = { all }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.first?.timeText, "12 min")
    let cell = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? CommandBarCellView)
    XCTAssertEqual(cell.hint.stringValue, "12 min")
    XCTAssertEqual(bar.results.first?.accessibilityCaption, "Switch to Tab", "VoiceOver still hears the action")
  }

  func testTheWindowsRecentTabsAreTheViewedOnesNewestFirstWithoutTheTabOnScreen() throws {
    let sidebar = shell.sidebar
    let current = try XCTUnwrap(shell.sidebarController.currentSpace)
    let other = try sidebar.addSpace(title: "Other")
    let second = try sidebar.addTab(url: URL(string: "https://second.example")!, title: "Second", in: .today(current))
    let third = try sidebar.addTab(url: URL(string: "https://third.example")!, title: "Third", in: .today(current))
    let elsewhere = try sidebar.addTab(url: URL(string: "https://else.example")!, title: "Elsewhere", in: .today(other))
    shell.activate(node: elsewhere)                        // viewed in another Space
    shell.activate(node: second)
    shell.activate(node: third)                            // the tab on screen

    let recents = shell.commandBar.recentTabsProvider()
    XCTAssertFalse(recents.contains { $0.node == third }, "the tab on screen is not offered")
    XCTAssertEqual(recents.prefix(2).map(\.node), [second, elsewhere], "viewed tabs, newest first, across Spaces")
    XCTAssertNotNil(recents.first?.lastViewed)
    let firstUnviewed = recents.firstIndex { $0.lastViewed == nil } ?? recents.count
    XCTAssertTrue(recents[firstUnviewed...].allSatisfy { $0.lastViewed == nil }, "then the ones never shown")
    let times = recents[..<firstUnviewed].compactMap(\.lastViewed)
    XCTAssertEqual(times, times.sorted(by: >), "viewed tabs are newest first")
  }

  // MARK: Screenshots

  /// The pull request's screenshots: the empty state with its groups, and a query with a site-search row showing the
  /// Tab key cap, each in both appearances, with synthetic titles. Only with `ARKT_COMMAND_BAR_SNAPSHOT_DIR` set.
  func testRenderTheStatesForTheScreenshots() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["ARKT_COMMAND_BAR_SNAPSHOT_DIR"] != nil)
    let now = Date()
    let pages: [(String, String, TimeInterval)] = [
      ("krystianslowik/arkt - Pull requests", "https://github.com/krystianslowik/arkt/pulls", 12 * 60),
      ("Cycle 42 - Linear", "https://linear.app/cycle-42", 3600),
      ("Q4 roadmap", "https://docs.example.com/q4", 3 * 3600),
      ("WWDC session: AppKit 120Hz", "https://youtube.com/watch?v=synthetic", 30 * 3600),
    ]
    let all = pages.map { page in
      CommandBarResults.OpenTab(node: UUID(), title: page.0, url: URL(string: page.1)!,
                                lastViewed: now.addingTimeInterval(-page.2))
    }
    bar.recentTabsProvider = { all }
    bar.openTabsProvider = { all }
    bar.clipboardURLProvider = { URL(string: "https://arkt.dev/changelog") }
    bar.actionsProvider = { [CommandBarAction(id: "newSpace", title: "New Space",
                                              keyCaps: [CommandBarKeyCaps.command, CommandBarKeyCaps.shift, "N"]),
                             CommandBarAction(id: "copyURL", title: "Copy URL",
                                              keyCaps: [CommandBarKeyCaps.command, CommandBarKeyCaps.shift, "C"])] }
    for (name, flavor) in [(NSAppearance.Name.darkAqua, "dark"), (.aqua, "light")] {
      window.appearance = NSAppearance(named: name)
      for (state, query, filter) in [("empty", "", CommandBarFilter.all), ("site", "git", .all), ("tabs", "linear", .tabs)] {
        bar.toggle(.newTab)
        if !query.isEmpty { bar.setQueryForTesting(query) }
        if filter != .all { bar.setFilter(filter) }
        if state == "site" {                                // the site row selected, its Tab key cap showing
          let row = try XCTUnwrap(bar.results.firstIndex { $0.rowKind == .siteSearch })
          bar.barView.table.selectRowIndexes([row], byExtendingSelection: false)
        }
        bar.barView.selectionMotion.settleNow()
        bar.barView.layoutSubtreeIfNeeded()
        bar.barView.displayIfNeeded()
        let rep = try XCTUnwrap(bar.barView.bitmapImageRepForCachingDisplay(in: bar.barView.bounds))
        bar.barView.cacheDisplay(in: bar.barView.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["ARKT_COMMAND_BAR_SNAPSHOT_DIR"],
           let data = rep.representation(using: .png, properties: [:]) {
          try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(state)-\(flavor).png"))
        }
        bar.hide()
      }
    }
  }

  // MARK: Selection slide

  func testMovingTheSelectionSlidesTheFillByATransformAndSettles() throws {
    let all = tabs(4)
    bar.openTabsProvider = { all }
    var clock = 100.0
    bar.barView.selectionMotion.now = { clock }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.barView.selectionMotion.reduceMotion = { false }
    bar.toggle(.newTab)
    let indicator = bar.barView.selectionIndicator
    XCTAssertEqual(indicator.layer?.transform.m42, 0, "at rest on row 0")
    bar.barView.table.selectRowIndexes([2], byExtendingSelection: false)
    XCTAssertEqual(indicator.frame, bar.barView.table.rect(ofRow: 2), "the frame is the target row at once")
    let start = try XCTUnwrap(indicator.layer?.transform.m42)
    XCTAssertEqual(abs(start), 80, accuracy: 0.5, "drawn two rows behind it")
    clock += 0.05
    bar.barView.selectionMotion.presentFrame()
    let mid = try XCTUnwrap(indicator.layer?.transform.m42)
    XCTAssertLessThan(abs(mid), abs(start))
    XCTAssertGreaterThan(abs(mid), 0)
    clock += 2
    bar.barView.selectionMotion.presentFrame()
    XCTAssertEqual(indicator.layer?.transform.m42, 0, "settled on its row")
    XCTAssertFalse(bar.barView.selectionMotion.isRunning)
  }

  /// The fill is drawn behind the target while it slides: at the start of a move down it is still on the old row,
  /// and it ends on the new one. Rendered, so the direction of the transform is checked, not assumed.
  func testTheSlideRendersTheFillOnTheOldRowFirstAndTheNewRowAtTheEnd() throws {
    let all = tabs(4)
    bar.openTabsProvider = { all }
    var clock = 100.0
    bar.barView.selectionMotion.now = { clock }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.barView.selectionMotion.reduceMotion = { false }
    window.appearance = NSAppearance(named: .darkAqua)
    bar.toggle(.newTab)
    let view = bar.barView
    let table = view.table

    func pixel(row: Int) throws -> NSColor {
      view.layoutSubtreeIfNeeded()
      view.displayIfNeeded()
      let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: rep)
      let rect = view.convert(view.selectionRect(ofRow: row), from: table)
      let scale = CGFloat(rep.pixelsWide) / view.bounds.width
      // Mid-row, left of the trailing group and right of the text: bare fill or bare surface.
      return try XCTUnwrap(rep.colorAt(x: Int((rect.midX + 40) * scale), y: Int(rect.midY * scale))?.usingColorSpace(.sRGB))
    }
    func differ(_ a: NSColor, _ b: NSColor) -> Bool {
      abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) > 0.02
    }

    let fill = try pixel(row: 0)                           // at rest on row 0: the selected fill
    table.selectRowIndexes([2], byExtendingSelection: false)
    XCTAssertFalse(differ(try pixel(row: 0), fill), "the fill is still on the old row at the start of the move")
    XCTAssertTrue(differ(try pixel(row: 2), fill), "and not yet on the new one")
    clock += 2
    bar.barView.selectionMotion.presentFrame()
    XCTAssertFalse(differ(try pixel(row: 2), fill), "settled on the new row")
    XCTAssertTrue(differ(try pixel(row: 0), fill))
  }

  func testAKeyRepeatMidFlightRetargetsFromWhereTheFillIs() throws {
    let all = tabs(5)
    bar.openTabsProvider = { all }
    var clock = 100.0
    bar.barView.selectionMotion.now = { clock }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.barView.selectionMotion.reduceMotion = { false }
    bar.toggle(.newTab)
    let table = bar.barView.table
    let indicator = bar.barView.selectionIndicator
    table.selectRowIndexes([1], byExtendingSelection: false)
    clock += 0.04
    bar.barView.selectionMotion.presentFrame()
    let drawnY = indicator.frame.minY + (indicator.layer?.transform.m42 ?? 0)
    table.selectRowIndexes([2], byExtendingSelection: false)
    let after = indicator.frame.minY + (indicator.layer?.transform.m42 ?? 0)
    XCTAssertEqual(after, drawnY, accuracy: 0.5, "no jump: the next move starts where the fill was")
    XCTAssertGreaterThan(drawnY, table.rect(ofRow: 0).minY)
    XCTAssertLessThan(drawnY, table.rect(ofRow: 1).minY)
  }

  func testReduceMotionMovesTheFillInstantly() throws {
    let all = tabs(4)
    bar.openTabsProvider = { all }
    bar.barView.selectionMotion.reduceMotion = { true }
    bar.toggle(.newTab)
    bar.barView.table.selectRowIndexes([3], byExtendingSelection: false)
    XCTAssertEqual(bar.barView.selectionIndicator.layer?.transform.m42, 0)
    XCTAssertFalse(bar.barView.selectionMotion.isRunning)
  }

  func testNewResultsDoNotSlideTheFill() throws {
    let all = tabs(4)
    bar.openTabsProvider = { all }
    bar.barView.selectionMotion.reduceMotion = { false }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.toggle(.newTab)
    bar.barView.table.selectRowIndexes([3], byExtendingSelection: false)
    bar.barView.selectionMotion.settleNow()
    bar.setQueryForTesting("Tab 1")                        // new rows, selection back on row 0
    XCTAssertFalse(bar.barView.selectionMotion.isRunning)
    XCTAssertEqual(bar.barView.selectionIndicator.layer?.transform.m42, 0)
  }

  func testArrowKeysDriveTheSlide() throws {
    let all = tabs(4)
    bar.openTabsProvider = { all }
    bar.barView.selectionMotion.reduceMotion = { false }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.toggle(.newTab)
    try key(125, "\u{F701}")
    XCTAssertEqual(bar.barView.table.selectedRow, 1)
    XCTAssertTrue(bar.barView.selectionMotion.isRunning)
    bar.hide()
    XCTAssertFalse(bar.barView.selectionMotion.isRunning, "closing ends the motion")
  }

  // MARK: Fades

  func testShowingFadesTheBarAndTheScrimIn() throws {
    bar.openTabsProvider = { [self] in tabs(2) }
    bar.toggle(.newTab)
    let fade = try XCTUnwrap(bar.barView.layer?.animation(forKey: "commandBar.fade") as? CABasicAnimation)
    XCTAssertEqual(fade.keyPath, "opacity")
    XCTAssertEqual(fade.fromValue as? Float, 0)
    XCTAssertEqual(fade.toValue as? Float, 1)
    XCTAssertEqual(fade.duration, 0.1)
    XCTAssertNotNil(bar.scrim.layer?.animation(forKey: "commandBar.fade"))
    XCTAssertEqual(bar.panel.alphaValue, 1)
    XCTAssertEqual(bar.barView.layer?.opacity, 1, "fully laid out: the model is already visible")
    XCTAssertEqual(bar.barView.layer?.transform.m11, 1, "no scale")
  }

  func testDismissingFadesOutAndTheEndOfTheFadeSetsAlphaZero() throws {
    var end: (@MainActor () -> Void)?
    bar.dismissFinisher = { end = $0 }
    bar.openTabsProvider = { [self] in tabs(2) }
    bar.toggle(.newTab)
    bar.hide()
    let fade = try XCTUnwrap(bar.barView.layer?.animation(forKey: "commandBar.fade") as? CABasicAnimation)
    XCTAssertEqual(fade.toValue as? Float, 0)
    XCTAssertEqual(fade.duration, 0.1)
    XCTAssertFalse(bar.panel.isPresented, "inert at once")
    XCTAssertEqual(bar.panel.accessibilityChildren()?.count, 0)
    XCTAssertEqual(bar.panel.alphaValue, 1, "still fading")
    XCTAssertFalse(bar.scrim.isPresented)
    try XCTUnwrap(end)()
    XCTAssertEqual(bar.panel.alphaValue, 0)
  }

  func testAShowDuringTheFadeOutCancelsItsEnd() throws {
    var end: (@MainActor () -> Void)?
    bar.dismissFinisher = { end = $0 }
    bar.openTabsProvider = { [self] in tabs(2) }
    bar.toggle(.newTab)
    bar.hide()
    bar.toggle(.newTab)
    try XCTUnwrap(end)()
    XCTAssertEqual(bar.panel.alphaValue, 1, "the old fade's end does not hide a bar that is back")
    XCTAssertTrue(bar.isVisible)
  }

  func testAShowDuringTheFadeOutStartsFromWhereTheLayerIsDrawn() throws {
    bar.dismissFinisher = { _ in }
    bar.openTabsProvider = { [self] in tabs(2) }
    bar.toggle(.newTab)
    bar.hide()
    bar.toggle(.newTab)
    let fade = try XCTUnwrap(bar.barView.layer?.animation(forKey: "commandBar.fade") as? CABasicAnimation)
    XCTAssertEqual(fade.toValue as? Float, 1)
    XCTAssertEqual(fade.fromValue as? Float, bar.barView.layer?.presentation()?.opacity ?? 0, "no jump to 0")
  }

  func testTheFadesRunWithReduceMotionToo() throws {
    bar.barView.selectionMotion.reduceMotion = { true }
    bar.openTabsProvider = { [self] in tabs(2) }
    bar.toggle(.newTab)
    XCTAssertNotNil(bar.barView.layer?.animation(forKey: "commandBar.fade"))
  }

  func testNothingTheBarAnimatesIsAFrameOrALayoutChange() throws {
    bar.openTabsProvider = { [self] in tabs(3) }
    bar.toggle(.newTab)
    var keyPaths: Set<String> = []
    for layer in [bar.barView.layer, bar.scrim.layer, bar.barView.selectionIndicator.layer].compactMap({ $0 }) {
      for key in layer.animationKeys() ?? [] {
        if let animation = layer.animation(forKey: key) as? CABasicAnimation, let keyPath = animation.keyPath {
          keyPaths.insert(keyPath)
        }
      }
    }
    XCTAssertTrue(keyPaths.isSubset(of: ["opacity", "transform.translation.y"]), "\(keyPaths)")
  }
}
