import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// The bar is tested against an unmodified shell window; Cmd-T / Cmd-L menu wiring is the coordinator's.
@MainActor
final class CommandBarTests: XCTestCase {
  var shell: ShellWindowController!
  var bar: CommandBarController!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate()
    shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1400, height: 900), display: true)
    shell.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    bar = CommandBarController(parent: window)
    // The geometry tests pin the notice (BH-113) off; the notice tests re-enable it on their own settings.
    bar.settings.dismissSearchSuggestionNotice()
    bar.dismissFinisher = { $0() }                  // the dismiss fade ends at once; its own tests step it by hand
    bar.barView.selectionMotion.drivesFramesItself = false   // no display link: tests step the slide by hand
    bar.prewarm()
    try await Task.sleep(for: .milliseconds(300))   // let the window server settle
  }

  override func tearDown() async throws {
    bar.invalidate()
    shell.close()
  }

  /// Shows the bar and waits for its first presented frame.
  func showAndMeasure() async throws -> Double {
    let frame = expectation(description: "first frame")
    var latency = 0.0
    bar.onFirstFrame = { latency = $0; frame.fulfill() }
    bar.toggle(.newTab)
    await fulfillment(of: [frame], timeout: 1)
    XCTAssertTrue(bar.isVisible)
    bar.toggle(.newTab)   // second Cmd-T closes (KB-003, BH-103)
    XCTAssertFalse(bar.isVisible)
    try await Task.sleep(for: .milliseconds(30))
    return latency
  }

  /// Latency as the plan defines it: show() entry to the first display-link tick's `targetTimestamp`.
  /// Measured decomposition (120 Hz panel): total = vsyncWait + interval, vsyncWait = wall work + phase,
  /// phase in (0, interval]. So total lies in [work + interval, work + 2 * interval]; at 120 Hz the ceiling is
  /// 16.7 ms even with zero work, which makes an absolute "p95 < 16 ms" unattainable by construction.
  /// Gate (coordinator decision, "work + earliest frame"):
  /// - show() work p95 under 4 ms, measured as main-thread CPU time so preemption by a loaded machine
  ///   (a Chromium build) does not count against the shell;
  /// - the panel lands on the earliest possible frame: wall-clock p95 total within wall work p95 + 2 intervals.
  ///   Asserted only when the 1-minute load average is below the active core count: on a saturated machine the
  ///   main run loop misses vsyncs after show() returns (measured at load ~300), which is not the shell's work.
  ///   Under load the numbers are printed and attached, and only that assertion is skipped.
  /// The absolute numbers are always printed.
  func testAppearsUnder16ms() async throws {
    var samples: [Double] = []
    var cpu: [Double] = []
    var wall: [Double] = []
    var interval = 0.0
    for _ in 0..<20 {
      samples.append(try await showAndMeasure())
      cpu.append(bar.lastShowCPUTime)
      wall.append(bar.lastShowWallTime)
      interval = max(interval, bar.lastFrameInterval)
      print(String(format: "commandbar.sample total=%.2f cpu=%.2f wall=%.2f vsyncWait=%.2f interval=%.2f",
                   samples.last! * 1000, cpu.last! * 1000, wall.last! * 1000, bar.lastShowVsyncWait * 1000,
                   bar.lastFrameInterval * 1000))
    }
    XCTAssertTrue(samples.contains(try XCTUnwrap(bar.lastShowLatency)))
    samples.sort(); cpu.sort(); wall.sort()
    let p95Index = Int(Double(samples.count) * 0.95) - 1
    let median = samples[samples.count / 2], p95 = samples[p95Index]
    let cpuP95 = cpu[p95Index], wallP95 = wall[p95Index]
    print("commandbar.screen maxFPS=\(NSScreen.main?.maximumFramesPerSecond ?? 0) interval.ms=\(interval * 1000)")
    print("commandbar.showcpu.ms median=\(cpu[cpu.count / 2] * 1000) p95=\(cpuP95 * 1000) max=\(cpu.last! * 1000)")
    print("commandbar.showwall.ms median=\(wall[wall.count / 2] * 1000) p95=\(wallP95 * 1000) max=\(wall.last! * 1000)")
    print("commandbar.latency.ms median=\(median * 1000) p95=\(p95 * 1000) max=\(samples.last! * 1000) "
      + "min=\(samples.first! * 1000)")
    XCTAssertLessThan(cpuP95, 0.004, "show() main-thread CPU time over budget")

    let bound = wallP95 + 2 * interval + 0.0005
    let notMeasurable = PacingEnvironment.notMeasurableReason()
    let summary = String(format: "commandbar.earliestframe p95=%.2f bound=%.2f asserted=%@",
                         p95 * 1000, bound * 1000, notMeasurable.map { "no (NOT-MEASURABLE: \($0))" } ?? "yes")
    print(summary)
    let attachment = XCTAttachment(string: summary)
    attachment.name = "commandbar.earliestframe"
    attachment.lifetime = .keepAlways
    add(attachment)
    if let notMeasurable {
      print("commandbar.earliestframe skipped: NOT-MEASURABLE (\(notMeasurable))")
    } else {
      XCTAssertLessThanOrEqual(p95, bound, "panel missed its earliest possible frame")
    }
  }

  func testGeometryAndFollowsTheWindowAppearance() async throws {
    let window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1800, height: 1072), display: true)
    bar.toggle(.newTab)
    let panel = bar.panel
    XCTAssertTrue(panel.isVisible)
    XCTAssertGreaterThan(panel.orderedIndex, -1)
    // The window server may clamp the 1800 x 1072 request to the screen, so expect from the actual frame.
    // Tolerance 1 pt: panel origins snap to backing pixels.
    let parent = window.frame
    XCTAssertEqual(panel.frame.width, min(680, parent.width - 48), accuracy: 1)
    XCTAssertEqual(panel.frame.midX, parent.midX, accuracy: 1)
    XCTAssertEqual(panel.frame.maxY, parent.maxY - 0.22 * parent.height, accuracy: 1)
    XCTAssertEqual(panel.frame.height, CommandBarGeometry.inputHeight)          // empty Cmd-T: input row only
    // The surface follows the window behind it, light or dark (the panel no longer forces dark).
    let expected: NSAppearance.Name = ThemeFlavor(appearance: window.effectiveAppearance) == .dark ? .darkAqua : .aqua
    XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), expected)
    if NSApp.isActive { XCTAssertTrue(panel.isKeyWindow) }   // a test runner process may not activate
    XCTAssertTrue(panel.firstResponder === bar.barView.field.currentEditor())
  }

  func testTypingGrowsDownwardWithTopPinned() async throws {
    bar.toggle(.newTab)
    let top = bar.panel.frame.maxY
    bar.setQueryForTesting("example.com")
    XCTAssertEqual(bar.results.map(\.kind.name), ["open", "search"])
    XCTAssertEqual(bar.panel.frame.height, CommandBarGeometry.contentHeight(rowCount: 2))
    XCTAssertEqual(bar.panel.frame.maxY, top, accuracy: 0.5)
    XCTAssertEqual(bar.barView.table.selectedRow, 0)
  }

  func testCmdLPrefillAndUneditedEnterReloads() async throws {
    var reloaded = false
    var opened: URL?
    bar.onReload = { reloaded = true }
    bar.onOpen = { url, _ in opened = url }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    XCTAssertEqual(bar.barView.field.stringValue, "https://example.com")      // KB-002, BH-101
    let editor = try XCTUnwrap(bar.barView.field.currentEditor())
    XCTAssertEqual(editor.selectedRange, NSRange(location: 0, length: 19))     // URL selected
    bar.commit()
    XCTAssertTrue(reloaded)                                                    // KB-004, BH-102
    XCTAssertNil(opened)
    XCTAssertFalse(bar.isVisible)
  }

  // #96: Cmd-L on a URL lists it once: no "Search Google" row with the same text, no subtitle repeating it.
  func testCmdLOnAURLShowsOneOpenRow() async throws {
    bar.toggle(.currentTab(URL(string: "https://example.com/a")))
    XCTAssertEqual(bar.results.map(\.kind.name), ["open"])
    XCTAssertEqual(bar.results.first?.subtitle, "")
    XCTAssertEqual(bar.panel.frame.height, CommandBarGeometry.contentHeight(rowCount: 1))
  }

  func testCmdLEditedEnterNavigatesCurrentTab() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    bar.commit()
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")            // BH-101
    XCTAssertEqual(result?.1, .currentTab)
  }

  func testCmdTEnterOnURLOpensInNewTab() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example.com")
    bar.commit()
    XCTAssertEqual(result?.0.absoluteString, "https://example.com")            // KB-001, BH-100
    XCTAssertEqual(result?.1, .newTab)
    XCTAssertFalse(bar.isVisible)
  }

  // Split View S5 (KB-070): Ctrl-Shift-= opens an empty bar whose Enter opens the result as a new split pane.
  func testNewSplitPaneEnterOpensInANewSplitPane() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.newSplitPane)
    XCTAssertEqual(bar.barView.field.stringValue, "", "no prefill")
    bar.setQueryForTesting("example.com")
    bar.commit()
    XCTAssertEqual(result?.0.absoluteString, "https://example.com")
    XCTAssertEqual(result?.1, .newSplitPane)
    XCTAssertFalse(bar.isVisible)
  }

  // [I] Cmd-Enter in the split pane bar opens a plain new tab, as from Cmd-T and Cmd-L (KB-085).
  func testCommandReturnFromNewSplitPaneOpensInANewTab() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.newSplitPane)
    bar.setQueryForTesting("example.com")
    try sendReturn(.command)
    XCTAssertEqual(result?.1, .newTab)
  }

  func testArrowKeysMoveSelectionAndEnterSearches() async throws {
    var opened: URL?
    bar.onOpen = { url, _ in opened = url }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example.com")
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    XCTAssertTrue(bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    XCTAssertEqual(bar.barView.table.selectedRow, 1)
    _ = bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
    XCTAssertEqual(bar.barView.table.selectedRow, 0)                           // wraps to the first [I] (RT-08)
    _ = bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
    XCTAssertEqual(bar.barView.table.selectedRow, 1)                           // and up wraps to the last
    _ = bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    XCTAssertEqual(opened, URLInputParser.searchURL(for: "example.com"))
  }

  func testEnterOnURLOpensNewTodayTab() async throws {
    // Through the wired controller: Cmd-T + Enter on a URL adds a Today tab and activates it (KB-001, BH-100).
    let sidebar = shell.sidebar
    let space = try XCTUnwrap(shell.sidebarController.currentSpace)
    let before = sidebar.children(of: .today(space)).count
    shell.newTab(nil)
    XCTAssertTrue(shell.commandBar.isVisible)
    shell.commandBar.setQueryForTesting("example.com")
    shell.commandBar.commit()
    let today = sidebar.children(of: .today(space))
    XCTAssertEqual(today.count, before + 1)
    let added = try XCTUnwrap(today.first { id in
      if case .tab(_, let url, _)? = sidebar.node(id) { url.absoluteString == "https://example.com" } else { false }
    })
    XCTAssertEqual(shell.sidebarController.current, added)
    XCTAssertEqual(shell.currentTab.flatMap { shell.engine.snapshot(of: $0)?.url }?.host(), "example.com")
  }

  func testCmdLPrefillsCurrentTabURLAndTogglesClosed() async throws {
    let url = try XCTUnwrap(shell.currentTab.flatMap { shell.engine.snapshot(of: $0)?.url })
    shell.openLocation(nil)
    XCTAssertEqual(shell.commandBar.barView.field.stringValue, url.absoluteString)   // KB-002, BH-101
    shell.openLocation(nil)
    XCTAssertFalse(shell.commandBar.isVisible)                                       // KB-003, BH-103
  }

  /// Regression: titles and the hint were truncated in the live table ("Family Calen...").
  func testCellLabelsAreNotTruncated() throws {
    bar.openTabsProvider = { [.init(node: UUID(), title: "Family Calendar", url: URL(string: "https://example.com")!)] }
    bar.toggle(.newTab)
    bar.panel.displayIfNeeded()
    let cell = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? CommandBarCellView)
    for label in [cell.title, cell.hint] {
      XCTAssertGreaterThanOrEqual(label.frame.width, label.fittingSize.width, label.stringValue)
    }
  }

  func testHideBeforeFirstFrameEndsSignpostAndSkipsLatency() async throws {
    var frames = 0
    bar.onFirstFrame = { _ in frames += 1 }
    bar.show(.newTab)
    XCTAssertTrue(bar.hasOpenSignpost)
    bar.hide()
    XCTAssertFalse(bar.hasOpenSignpost)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(frames, 0, "a hidden bar must not report a first frame")
    XCTAssertNil(bar.lastShowLatency)
  }

  func testDoubleShowKeepsOneSignpostAndOneFrame() async throws {
    var frames = 0
    let frame = expectation(description: "first frame")
    bar.onFirstFrame = { _ in frames += 1; frame.fulfill() }
    bar.show(.newTab)
    bar.show(.currentTab(URL(string: "https://example.com")))
    XCTAssertTrue(bar.hasOpenSignpost)
    await fulfillment(of: [frame], timeout: 1)
    XCTAssertFalse(bar.hasOpenSignpost)
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(frames, 1)
  }

  /// Counts focus restores: key status itself is not observable when the test runner app is inactive.
  final class SpyWindow: NSWindow {
    var makeKeyCalls = 0
    override func makeKey() { makeKeyCalls += 1; super.makeKey() }
  }

  func testResignKeyDoesNotRestoreFocusButEscapeDoes() async throws {
    let parent = SpyWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800), styleMask: [.titled],
                           backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    let spyBar = CommandBarController(parent: parent)
    defer { spyBar.invalidate(); parent.close() }

    spyBar.show(.newTab)
    spyBar.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: spyBar.panel))
    XCTAssertFalse(spyBar.isVisible)
    XCTAssertEqual(parent.makeKeyCalls, 0, "focus moved elsewhere; the bar must not take it back")

    spyBar.show(.newTab)
    let editor = try XCTUnwrap(spyBar.barView.field.currentEditor() as? NSTextView)
    _ = spyBar.control(spyBar.barView.field, textView: editor,
                       doCommandBy: #selector(NSResponder.cancelOperation(_:)))         // Esc, KB-084
    XCTAssertEqual(parent.makeKeyCalls, 1)

    spyBar.toggle(.newTab)
    spyBar.toggle(.newTab)                                                              // Cmd-T closes, KB-003
    XCTAssertEqual(parent.makeKeyCalls, 2)
  }

  func testInvalidateReleasesController() async throws {
    weak var weakBar: CommandBarController?
    autoreleasepool {
      let window = shell.window!
      var local: CommandBarController? = CommandBarController(parent: window)
      local?.prewarm()
      local?.show(.newTab)
      weakBar = local
      local?.invalidate()
      local = nil
    }
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertNil(weakBar, "the display link must not keep the controller alive after invalidate()")
  }

  func testSwitchToTabResult() async throws {
    let node = UUID()
    var switched: UUID?
    bar.openTabsProvider = { [.init(node: node, title: "Example Domain", url: URL(string: "https://example.com")!)] }
    bar.onSwitch = { switched = $0 }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.first?.trailingHint, "Switch to Tab")
    bar.commit()
    XCTAssertEqual(switched, node)
  }

  // C7 phase 3: a warm show with unchanged results keeps the table's cells instead of rebuilding them.
  func testShowWithUnchangedResultsKeepsTheCells() async throws {
    let tabs: [CommandBarResults.OpenTab] = (1...3).map {
      .init(node: UUID(), title: "Tab \($0)", url: URL(string: "https://t\($0).example")!)
    }
    bar.openTabsProvider = { tabs }
    bar.toggle(.newTab)
    let table = bar.barView.table
    XCTAssertGreaterThan(table.numberOfRows, 1)
    let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? CommandBarCellView)
    cell.toolTip = "marker"                                        // a reload would make a new cell view
    table.selectRowIndexes([1], byExtendingSelection: false)
    bar.toggle(.newTab)
    bar.toggle(.newTab)
    let again = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? CommandBarCellView)
    XCTAssertTrue(again === cell, "no reload: the same cell view")
    XCTAssertEqual(again.toolTip, "marker")
    XCTAssertEqual(table.selectedRow, 0, "selection still resets to the first result")
    bar.toggle(.newTab)
  }

  /// #25: `prewarm()` attaches the field editor (`currentEditor() != nil`) before the first `show()`, and a warm show
  /// with row 0 already selected does not emit a redundant `selectionDidChangeNotification`.
  func testWarmShowWithEmptyFieldPrewarmsEditorAndSkipsRedundantSelectionNotification() throws {
    XCTAssertNotNil(bar.barView.field.currentEditor(), "prewarm installs the field editor before the first show")
    let tabs: [CommandBarResults.OpenTab] = [
      .init(node: UUID(), title: "One", url: URL(string: "https://one.example")!),
    ]
    bar.openTabsProvider = { tabs }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.barView.table.selectedRow, 0)
    bar.toggle(.newTab)

    var selectionChanges = 0
    let token = NotificationCenter.default.addObserver(
      forName: NSTableView.selectionDidChangeNotification, object: bar.barView.table, queue: nil
    ) { _ in MainActor.assumeIsolated { selectionChanges += 1 } }
    defer { NotificationCenter.default.removeObserver(token) }

    bar.toggle(.newTab)
    XCTAssertEqual(selectionChanges, 0, "row 0 was already selected")
    bar.toggle(.newTab)
  }

  // Pre-merge review: unchanged results keep the cells, but not across a backing scale change (the shell
  // window moved to a display of another scale): the icons are bitmaps at the old scale.
  func testShowAfterBackingScaleChangeReloadsTheIcons() async throws {
    let tabs: [CommandBarResults.OpenTab] = [.init(node: UUID(), title: "One", url: URL(string: "https://one.example")!)]
    bar.openTabsProvider = { tabs }
    bar.backingScaleOverride = 2
    defer { bar.backingScaleOverride = nil }
    bar.toggle(.newTab)
    let table = bar.barView.table
    func iconPixels() throws -> Int {
      let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? CommandBarCellView)
      let rep = try XCTUnwrap(cell.icon.image?.representations.first as? NSBitmapImageRep)
      return rep.pixelsWide
    }
    XCTAssertEqual(try iconPixels(), Int(CommandBarCellView.iconSize * 2))
    bar.toggle(.newTab)
    bar.backingScaleOverride = 1
    bar.toggle(.newTab)
    XCTAssertEqual(try iconPixels(), Int(CommandBarCellView.iconSize), "same results, new scale: reloaded")
    bar.toggle(.newTab)
  }

  // Changed results still reload.
  func testShowWithChangedResultsReloads() async throws {
    var tabs: [CommandBarResults.OpenTab] = [.init(node: UUID(), title: "One", url: URL(string: "https://one.example")!)]
    bar.openTabsProvider = { tabs }
    bar.toggle(.newTab)
    let table = bar.barView.table
    XCTAssertEqual(table.numberOfRows, 1)
    bar.toggle(.newTab)
    tabs.append(.init(node: UUID(), title: "Two", url: URL(string: "https://two.example")!))
    bar.toggle(.newTab)
    XCTAssertEqual(table.numberOfRows, 2)
    let second = try XCTUnwrap(table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? CommandBarCellView)
    XCTAssertEqual(second.title.stringValue, "Two")
    bar.toggle(.newTab)
  }

  func testEscapeCloses() async throws {
    bar.toggle(.newTab)
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    XCTAssertTrue(bar.control(bar.barView.field, textView: editor,
                              doCommandBy: #selector(NSResponder.cancelOperation(_:))))   // KB-084
    XCTAssertFalse(bar.isVisible)
    XCTAssertEqual(bar.panel.alphaValue, 0, "hidden by alpha; the panel stays ordered in")
  }

  // MARK: - Following the parent window (#97)

  /// Where the bar belongs over the parent's actual frame (the window server may clamp a requested one).
  func expectedFrame() throws -> NSRect {
    let window = try XCTUnwrap(shell.window)
    return CommandBarGeometry.frame(parentFrame: window.frame,
                                    contentHeight: CommandBarGeometry.contentHeight(rowCount: bar.results.count))
  }

  /// Within 1 pt: panel origins snap to backing pixels.
  func isClose(_ a: NSRect, _ b: NSRect) -> Bool {
    abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1
      && abs(a.height - b.height) <= 1
  }

  func barIsOverTheParent() -> Bool { (try? isClose(bar.panel.frame, expectedFrame())) == true }

  func testPrewarmPutsThePanelOnTheParentScreen() throws {
    let window = try XCTUnwrap(shell.window)
    let screen = try XCTUnwrap(window.screen)
    XCTAssertTrue(screen.frame.intersects(bar.panel.frame), "pre-warmed on the parent's display, not off-screen")
    XCTAssertTrue(bar.panel.screen === screen)
  }

  func testOpenBarFollowsTheParentWhenItMoves() throws {
    let window = try XCTUnwrap(shell.window)
    bar.toggle(.newTab)
    window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY + 30))
    waitUntil("the bar over the moved parent") { barIsOverTheParent() }
    bar.toggle(.newTab)
  }

  func testOpenBarFollowsTheParentWhenItResizes() throws {
    let window = try XCTUnwrap(shell.window)
    bar.toggle(.newTab)
    window.setFrame(NSRect(x: 160, y: 120, width: 700, height: 600), display: true)
    waitUntil("the bar over the resized parent") { barIsOverTheParent() }
    XCTAssertEqual(bar.panel.frame.width, min(766, window.frame.width - 48), accuracy: 1)
    bar.toggle(.newTab)
  }

  /// One display in tests: displace the panel and post the parent's screen change, which must put it back.
  func testOpenBarRepositionsWhenTheParentChangesScreen() throws {
    let window = try XCTUnwrap(shell.window)
    bar.toggle(.newTab)
    bar.panel.setFrameOrigin(NSPoint(x: bar.panel.frame.minX - 200, y: bar.panel.frame.minY - 100))
    XCTAssertFalse(barIsOverTheParent())
    NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
    waitUntil("the bar back over the parent") { barIsOverTheParent() }
    bar.toggle(.newTab)
  }

  /// #212: when the open bar's parent moves to a display of another backing scale (didChangeBackingProperties or
  /// didChangeScreen), result icons are re-rendered at the new scale immediately without waiting for the next show,
  /// and the selected row is preserved.
  func testOpenBarReRendersIconsWhenBackingScaleChanges() throws {
    let window = try XCTUnwrap(shell.window)
    let tabs: [CommandBarResults.OpenTab] = [
      .init(node: UUID(), title: "One", url: URL(string: "https://one.example")!),
      .init(node: UUID(), title: "Two", url: URL(string: "https://two.example")!),
    ]
    bar.openTabsProvider = { tabs }
    bar.backingScaleOverride = 2
    defer { bar.backingScaleOverride = nil }
    bar.toggle(.newTab)
    let table = bar.barView.table
    table.selectRowIndexes([1], byExtendingSelection: false)
    func iconPixels() -> Int? {
      guard let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? CommandBarCellView,
            let rep = cell.icon.image?.representations.first as? NSBitmapImageRep else { return nil }
      return rep.pixelsWide
    }
    XCTAssertEqual(iconPixels(), Int(CommandBarCellView.iconSize * 2))

    bar.backingScaleOverride = 1
    NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: window)
    waitUntil("open bar icons re-rendered at 1x on didChangeBackingProperties") {
      iconPixels() == Int(CommandBarCellView.iconSize)
    }
    XCTAssertEqual(table.selectedRow, 1, "scale reload keeps the selected row")

    bar.backingScaleOverride = 2
    NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
    waitUntil("open bar icons re-rendered at 2x on didChangeScreen") {
      iconPixels() == Int(CommandBarCellView.iconSize * 2)
    }
    XCTAssertEqual(table.selectedRow, 1)
    bar.toggle(.newTab)
  }

  /// A closed bar does no work while the parent moves or resizes, but follows the parent on `didChangeScreen` (frame
  /// only, still hidden at alpha 0) so the first show after a display change is not a cross-display move (#212).
  func testClosedBarDoesNotFollowTheParent() throws {
    let window = try XCTUnwrap(shell.window)
    bar.toggle(.newTab)
    bar.toggle(.newTab)
    let before = bar.panel.frame
    var moved = false
    let token = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window,
                                                       queue: .main) { _ in MainActor.assumeIsolated { moved = true } }
    defer { NotificationCenter.default.removeObserver(token) }
    window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY + 30))
    waitUntil("the parent's move notification") { moved }
    XCTAssertEqual(bar.panel.frame, before, "ordinary moves while closed do not touch the panel")

    NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
    waitUntil("closed panel follows parent on didChangeScreen") { barIsOverTheParent() }
    XCTAssertFalse(bar.isVisible)
    XCTAssertEqual(bar.panel.alphaValue, 0)

    bar.toggle(.newTab)
    XCTAssertTrue(barIsOverTheParent())
    bar.toggle(.newTab)
  }

  // C7 fix 2: the panel stays ordered in at alpha 0, so a show is an alpha change plus makeKey.
  func testHiddenPanelStaysOrderedInButIsInert() async throws {
    let panel = bar.panel
    XCTAssertTrue(panel.isVisible, "prewarm orders the panel in once")
    XCTAssertEqual(panel.alphaValue, 0)
    XCTAssertTrue(panel.ignoresMouseEvents, "clicks pass through the hidden panel")
    XCTAssertFalse(panel.canBecomeKey, "a hidden panel never takes key status")
    XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle), "not in the Cmd-` window cycle")
    XCTAssertFalse(panel.isAccessibilityElement(), "VoiceOver does not see the hidden panel")
    XCTAssertTrue((panel.accessibilityChildren() ?? []).isEmpty)

    bar.toggle(.newTab)
    XCTAssertTrue(panel.isVisible)
    XCTAssertEqual(panel.alphaValue, 1)
    XCTAssertFalse(panel.ignoresMouseEvents)
    XCTAssertTrue(panel.canBecomeKey)
    XCTAssertTrue(panel.isAccessibilityElement())
    XCTAssertFalse((panel.accessibilityChildren() ?? []).isEmpty)

    bar.toggle(.newTab)                                                // Cmd-T closes, KB-003
    XCTAssertTrue(panel.isVisible, "closing does not order the panel out")
    XCTAssertEqual(panel.alphaValue, 0)
    XCTAssertTrue(panel.ignoresMouseEvents)
    XCTAssertFalse(panel.isAccessibilityElement())
  }

  // C7 fix 2: the hidden panel stays ordered in, so app reactivation can hand it key status back; the bar
  // passes it to the shell window so typing never lands in an invisible window.
  func testHiddenPanelThatBecomesKeyHandsKeyToTheShellWindow() async throws {
    let parent = SpyWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800), styleMask: [.titled],
                           backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    let spyBar = CommandBarController(parent: parent)
    defer { spyBar.invalidate(); parent.close() }
    spyBar.show(.newTab)
    spyBar.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: spyBar.panel))
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(parent.makeKeyCalls, 0, "a presented bar keeps key status")
    spyBar.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: spyBar.panel))
    XCTAssertFalse(spyBar.isVisible)
    spyBar.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: spyBar.panel))
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(parent.makeKeyCalls, 1, "key goes back to the shell window")
  }

  // C7 fix 2: after the app deactivates (hidesOnDeactivate ordered the panel out), a show orders it back in.
  func testShowOrdersThePanelBackInAfterItWasOrderedOut() async throws {
    bar.panel.orderOut(nil)
    bar.toggle(.newTab)
    XCTAssertTrue(bar.panel.isVisible)
    XCTAssertEqual(bar.panel.alphaValue, 1)
  }

  // Pre-merge review: the always-ordered-in panel stays on the Space it was ordered in on. A show on another
  // Space (a second desktop, a full-screen Space) orders it out and back in, onto the active Space.
  func testShowOnAnotherSpaceReordersThePanelOntoTheActiveSpace() async throws {
    let panel = bar.panel
    panel.isOnActiveSpaceOverride = false
    defer { panel.isOnActiveSpaceOverride = nil }
    let (outs, ins) = (panel.orderOutCount, panel.orderFrontRegardlessCount)
    bar.toggle(.newTab)
    XCTAssertEqual(panel.orderOutCount - outs, 1, "ordered out of the old Space")
    XCTAssertEqual(panel.orderFrontRegardlessCount - ins, 1, "ordered in on the active one")
    XCTAssertTrue(bar.isVisible)
    XCTAssertTrue(panel.isVisible)
    XCTAssertEqual(panel.alphaValue, 1)
    if NSApp.isActive { XCTAssertTrue(panel.isKeyWindow) }   // a test runner process may not activate
    bar.toggle(.newTab)
  }

  // The fast path is untouched: on the active Space a show does not order the panel at all.
  func testShowOnTheActiveSpaceDoesNotReorderThePanel() async throws {
    let panel = bar.panel
    panel.isOnActiveSpaceOverride = true
    defer { panel.isOnActiveSpaceOverride = nil }
    let (outs, ins) = (panel.orderOutCount, panel.orderFrontRegardlessCount)
    bar.toggle(.newTab)
    bar.toggle(.newTab)
    bar.toggle(.newTab)
    XCTAssertEqual(panel.orderOutCount, outs)
    XCTAssertEqual(panel.orderFrontRegardlessCount, ins)
    bar.toggle(.newTab)
  }

  // C7 fix 2: the first frame is measured on the parent window's display link after the show's commit.
  func testFirstFrameIsAfterTheShowCommit() async throws {
    let frame = expectation(description: "first frame")
    bar.onFirstFrame = { _ in frame.fulfill() }
    bar.toggle(.newTab)
    await fulfillment(of: [frame], timeout: 1)
    let latency = try XCTUnwrap(bar.lastShowLatency)
    XCTAssertGreaterThan(latency, 0)
    XCTAssertGreaterThanOrEqual(bar.lastShowCommitDelay, 0, "the show's transaction committed")
    XCTAssertLessThanOrEqual(bar.lastShowCommitDelay, latency)
  }

  // MARK: - Keys and hover (#95; KB-084, KB-085, RT-08). Behaviors marked [I] wait on RT-08.

  /// A key-down delivered in-process to the bar's own panel (no OS-level input).
  func sendKey(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                               windowNumber: bar.panel.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: keyCode))
    bar.panel.sendEvent(event)
  }

  func sendReturn(_ flags: NSEvent.ModifierFlags = []) throws { try sendKey(36, "\r", flags) }

  func tabs(_ count: Int) -> [CommandBarResults.OpenTab] {
    (1...count).map { .init(node: UUID(), title: "Tab \($0)", url: URL(string: "https://t\($0).example")!) }
  }

  func testReturnKeyEventOpensTheSelectedResult() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example.com")
    try sendReturn()
    XCTAssertEqual(result?.0.absoluteString, "https://example.com")
    XCTAssertEqual(result?.1, .newTab)
    XCTAssertFalse(bar.isVisible)
  }

  // [I] KB-085: Opt-Enter opens the selected result in a new tab, also from Cmd-L (Chromium omnibox convention).
  func testOptionReturnFromCmdLOpensInANewTab() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    try sendReturn(.option)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, .newTab, "new tab, not the current one")
    XCTAssertFalse(bar.isVisible)
  }

  // [I] KB-085: Cmd-Enter opens the selected result in a new tab, also from Cmd-L.
  func testCommandReturnFromCmdLOpensInANewTab() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    try sendReturn(.command)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, .newTab)
    XCTAssertFalse(bar.isVisible)
  }

  // [I] A modified Enter on an unedited Cmd-L opens the URL in a new tab instead of reloading (KB-004 is plain Enter).
  func testModifiedReturnOnUneditedCmdLOpensANewTabInsteadOfReloading() async throws {
    var reloaded = false
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onReload = { reloaded = true }
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    try sendReturn(.command)
    XCTAssertFalse(reloaded)
    XCTAssertEqual(result?.0.absoluteString, "https://example.com")
    XCTAssertEqual(result?.1, .newTab)
  }

  // [I] A modified Enter on a "Switch to Tab" result still switches: the tab is already open.
  func testModifiedReturnOnASwitchResultSwitches() async throws {
    let node = UUID()
    var switched: UUID?
    var opened: URL?
    bar.openTabsProvider = { [.init(node: node, title: "Example Domain", url: URL(string: "https://example.com")!)] }
    bar.onSwitch = { switched = $0 }
    bar.onOpen = { url, _ in opened = url }
    bar.toggle(.newTab)
    try sendReturn(.option)
    XCTAssertEqual(switched, node)
    XCTAssertNil(opened)
  }

  // Only Cmd and Opt are taken over: Shift-Return (KB-086, Arc Max, out of scope) reaches the field editor as before.
  func testShiftReturnIsNotTreatedAsANewTabKey() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    try sendReturn(.shift)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, .currentTab, "plain commit: Cmd-L navigates the current tab")
  }

  // [I] RT-08: Enter on an empty query with no results closes the bar and opens nothing.
  func testEnterOnAnEmptyQueryWithNoResultsCloses() async throws {
    var opened = false
    var switched = false
    bar.onOpen = { _, _ in opened = true }
    bar.onSwitch = { _ in switched = true }
    bar.toggle(.newTab)
    XCTAssertTrue(bar.results.isEmpty)
    try sendReturn()
    XCTAssertFalse(bar.isVisible)
    XCTAssertFalse(opened)
    XCTAssertFalse(switched)
  }

  // [I] RT-08: Enter on an empty query switches to the first listed open tab.
  func testEnterOnAnEmptyQuerySwitchesToTheFirstOpenTab() async throws {
    let list = tabs(3)
    var switched: UUID?
    bar.openTabsProvider = { list }
    bar.onSwitch = { switched = $0 }
    bar.toggle(.newTab)
    try sendReturn()
    XCTAssertEqual(switched, list[0].node)
  }

  // KB-084: the Esc key event closes the bar.
  func testEscapeKeyEventCloses() async throws {
    bar.toggle(.newTab)
    try sendKey(53, "\u{1b}")
    XCTAssertFalse(bar.isVisible)
  }

  // [I] KB-085: Down past the last result wraps to the first, Up from the first wraps to the last.
  func testArrowKeyEventsWrap() async throws {
    bar.openTabsProvider = { self.tabs(3) }
    bar.toggle(.newTab)
    let down = String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
    let up = String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)
    try sendKey(125, down, [.function, .numericPad])
    try sendKey(125, down, [.function, .numericPad])
    XCTAssertEqual(bar.barView.table.selectedRow, 2)
    try sendKey(125, down, [.function, .numericPad])
    XCTAssertEqual(bar.barView.table.selectedRow, 0)
    try sendKey(126, up, [.function, .numericPad])
    XCTAssertEqual(bar.barView.table.selectedRow, 2)
  }

  // [I] PageDown / PageUp move by the visible row count and stop at the ends.
  func testPageDownAndPageUpMoveByAPageAndClamp() async throws {
    bar.openTabsProvider = { self.tabs(6) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")                  // open-tab matches plus the search row
    let count = bar.results.count
    XCTAssertGreaterThan(count, 2)
    let pageDown = String(UnicodeScalar(UInt16(NSPageDownFunctionKey))!)
    let pageUp = String(UnicodeScalar(UInt16(NSPageUpFunctionKey))!)
    try sendKey(121, pageDown, [.function])
    XCTAssertEqual(bar.barView.table.selectedRow, min(CommandBarGeometry.maxVisibleRows, count - 1))
    try sendKey(121, pageDown, [.function])
    XCTAssertEqual(bar.barView.table.selectedRow, count - 1, "clamps at the last row")
    try sendKey(116, pageUp, [.function])
    try sendKey(116, pageUp, [.function])
    XCTAssertEqual(bar.barView.table.selectedRow, 0, "clamps at the first row")
    XCTAssertTrue(bar.isVisible)
  }

  /// A pointer move over `row`, delivered in-process to the results view.
  func hover(row: Int) throws {
    bar.panel.displayIfNeeded()
    let table = bar.barView.table
    let rect = table.convert(table.rect(ofRow: row), to: nil)
    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: rect.midX, y: rect.midY),
                                                 modifierFlags: [], timestamp: 0,
                                                 windowNumber: bar.panel.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 0, pressure: 0))
    bar.barView.mouseMoved(with: event)
  }

  // [I] Hover selects the row under the pointer; Enter then opens it.
  func testHoverSelectsTheRowUnderThePointer() async throws {
    let list = tabs(4)
    var switched: UUID?
    bar.openTabsProvider = { list }
    bar.onSwitch = { switched = $0 }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.barView.table.selectedRow, 0)
    try hover(row: 2)
    XCTAssertEqual(bar.barView.table.selectedRow, 2)
    try sendReturn()
    XCTAssertEqual(switched, list[2].node)
  }

  // The results view tracks pointer moves with one tracking area, installed once (not per show).
  func testHoverTrackingIsInstalledOnce() async throws {
    let table = bar.barView.table
    let moved = table.trackingAreas.filter { $0.options.contains(.mouseMoved) && $0.owner === bar.barView }
    XCTAssertEqual(moved.count, 1)
    bar.toggle(.newTab)
    bar.toggle(.newTab)
    bar.toggle(.newTab)
    XCTAssertEqual(table.trackingAreas.filter { $0.owner === bar.barView }.count, 1)
    bar.toggle(.newTab)
  }

  // A pointer move outside any row (the input row) leaves the selection alone.
  func testHoverOutsideTheRowsKeepsTheSelection() async throws {
    bar.openTabsProvider = { self.tabs(3) }
    bar.toggle(.newTab)
    bar.panel.displayIfNeeded()
    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 40, y: bar.panel.frame.height - 10),
                                                 modifierFlags: [], timestamp: 0,
                                                 windowNumber: bar.panel.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 0, pressure: 0))
    bar.barView.mouseMoved(with: event)
    XCTAssertEqual(bar.barView.table.selectedRow, 0)
  }

  // #157 review: a pointer move over a row that scrolled out of view (forwarded from above the clip view) leaves
  // the selection alone; only visible rows select.
  func testHoverOverARowScrolledOutOfViewKeepsTheSelection() async throws {
    bar.openTabsProvider = { self.tabs(6) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")                  // open-tab matches plus the search row
    let table = bar.barView.table
    let last = bar.results.count - 1
    // Results never exceed maxVisibleRows today, so shorten the panel to make the list scroll.
    var frame = bar.panel.frame
    frame.size.height = CommandBarGeometry.contentHeight(rowCount: 3)
    bar.panel.setFrame(frame, display: true)
    bar.panel.layoutIfNeeded()
    table.selectRowIndexes([last], byExtendingSelection: false)
    table.scrollRowToVisible(last)
    bar.panel.displayIfNeeded()
    XCTAssertFalse(table.visibleRect.intersects(table.rect(ofRow: 0)), "row 0 scrolled out of view")
    try hover(row: 0)
    XCTAssertEqual(table.selectedRow, last)
  }

  // #157 review: only an actual Opt-Return makes the insertNewlineIgnoringFieldEditor: fallback open a new tab.
  // Another key bound to that selector commits like Return (Cmd-L: the current tab).
  func testNewlineIgnoringFieldEditorWithoutOptionReturnCommitsInPlace() async throws {
    var result: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    let handled = bar.control(bar.barView.field, textView: editor,
                              doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
    XCTAssertTrue(handled)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, .currentTab, "not an Opt-Return: Cmd-L navigates the current tab")
  }

  // The one rule both Cmd/Opt-Return paths use: Return or keypad Enter with exactly one of the allowed modifiers.
  func testNewTabReturnRule() throws {
    func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
      try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "\r",
                                     charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code))
    }
    let rule = CommandBarController.isReturn(_:withExactly:)
    XCTAssertTrue(rule(try key(36, .option), [.option]))
    XCTAssertTrue(rule(try key(76, .option), [.option]))                    // keypad Enter
    XCTAssertTrue(rule(try key(36, .command), [.command, .option]))
    XCTAssertTrue(rule(try key(36, [.option, .numericPad]), [.option]))     // other flags are ignored
    XCTAssertFalse(rule(try key(36, .command), [.option]))
    XCTAssertFalse(rule(try key(36, [.option, .shift]), [.option]))
    XCTAssertFalse(rule(try key(36, []), [.option]))
    XCTAssertFalse(rule(try key(0, .option), [.option]))                    // not Return
    XCTAssertFalse(rule(nil, [.option]))
  }

  /// The responder in `window` that a nil-targeted action reaches, as AppKit searches one window: the first
  /// responder up its `nextResponder` chain (the window, then its window controller), then the window's delegate.
  func handler(of action: Selector, in window: NSWindow) -> AnyObject? {
    var responder: NSResponder? = window.firstResponder
    while let current = responder {
      if current.responds(to: action) { return current }
      responder = current.nextResponder
    }
    if let delegate = window.delegate, delegate.responds(to: action) { return delegate }
    return nil
  }

  // #95: menu actions (Cmd-T / Cmd-L) reach ShellWindowController through NSApp.sendAction while the bar is key.
  // A nil-targeted action searches the key window (the panel), then the main window (the shell: the panel cannot
  // become main), then the app. The test runner cannot activate itself, so the per-window search is checked
  // directly; when the app is active, the real NSApp.sendAction path runs as well.
  func testMenuActionsReachTheShellWhileTheBarIsKey() async throws {
    let window = try XCTUnwrap(shell.window)
    let panel = shell.commandBar.panel
    for (action, name) in [(#selector(ShellWindowController.newTab(_:)), "Cmd-T"),
                           (#selector(ShellWindowController.openLocation(_:)), "Cmd-L")] {
      shell.newTab(nil)
      XCTAssertTrue(shell.commandBar.isVisible)
      XCTAssertTrue(panel.firstResponder === shell.commandBar.barView.field.currentEditor(), "typing goes to the bar")
      XCTAssertFalse(panel.canBecomeMain, "the shell window stays main")
      XCTAssertNil(handler(of: action, in: panel), "\(name): nothing in the bar's chain takes the action")
      XCTAssertTrue(handler(of: action, in: window) === shell, "\(name): the shell window's chain reaches the controller")
      if NSApp.isActive, NSApp.keyWindow === panel, NSApp.mainWindow === window {
        XCTAssertTrue(NSApp.sendAction(action, to: nil, from: nil))
      } else {
        XCTAssertTrue(NSApp.sendAction(action, to: handler(of: action, in: window), from: nil))
      }
      XCTAssertFalse(shell.commandBar.isVisible, "\(name) closes the open bar (KB-003)")
    }
  }

  // MARK: - #112: action search, site search, Paste and Go, removal, notice, Space refresh

  private func insertTab() throws -> Bool {
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    return bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))
  }

  private func deleteBackward() throws -> Bool {
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    return bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
  }

  /// BH-106 / KB-081: Tab on the bar just opened with Cmd-T enters action search; Enter runs the action.
  func testTabOnTheEmptyCmdTBarEntersActionSearch() async throws {
    var ran: String?
    bar.actionsProvider = { [CommandBarAction(id: "newSpace", title: "New Space"),
                             CommandBarAction(id: "toggleToolbar", title: "Toggle Toolbar")] }
    bar.onAction = { ran = $0 }
    bar.toggle(.newTab)
    XCTAssertTrue(try insertTab())
    XCTAssertEqual(bar.scope, .actions)
    XCTAssertEqual(bar.results.map(\.kind), [.action("newSpace"), .action("toggleToolbar")])
    XCTAssertEqual(bar.barView.field.placeholderAttributedString?.string, "Search actions...")
    XCTAssertFalse(bar.barView.scopeChip.isHidden)
    XCTAssertEqual(bar.barView.scopeChip.stringValue, "Actions")

    bar.setQueryForTesting("tool")
    XCTAssertEqual(bar.results.map(\.kind), [.action("toggleToolbar")])
    bar.commit()
    XCTAssertEqual(ran, "toggleToolbar")
    XCTAssertFalse(bar.isVisible)
  }

  /// KB-081 is about the bar just opened with Cmd-T: Cmd-L (even empty) and a typed query keep Tab unscoped. With
  /// nothing to scope, Tab cycles the filters (the smart Tab rule, #371).
  func testTabOutsideCmdTDoesNotEnterActionSearch() async throws {
    bar.actionsProvider = { [CommandBarAction(id: "newSpace", title: "New Space")] }
    bar.toggle(.currentTab(nil))
    XCTAssertEqual(bar.barView.field.stringValue, "")
    XCTAssertTrue(try insertTab())
    XCTAssertEqual(bar.scope, .normal)
    XCTAssertEqual(bar.filter, .tabs, "cycled")

    bar.toggle(.newTab)
    bar.toggle(.newTab)
    bar.setQueryForTesting("zzz")                          // a query that is no alias
    XCTAssertTrue(try insertTab())
    XCTAssertEqual(bar.scope, .normal)
    XCTAssertEqual(bar.filter, .tabs)
    bar.toggle(.newTab)
  }

  /// BH-107 / KB-082: an alias typed, then Tab, scopes the query to that engine; Enter opens its search URL.
  func testTabOnAnAliasScopesTheQueryToTheEngine() async throws {
    var opened: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { opened = ($0, $1) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("yt")
    XCTAssertTrue(try insertTab())
    XCTAssertEqual(bar.scope, .siteSearch(SiteSearchEngines.seeded[0]))
    XCTAssertEqual(bar.barView.field.stringValue, "")
    XCTAssertEqual(bar.barView.scopeChip.stringValue, "YouTube")
    XCTAssertEqual(bar.barView.field.placeholderAttributedString?.string, "Search YouTube")

    bar.setQueryForTesting("lofi")
    XCTAssertEqual(bar.results.map(\.kind.name), ["siteSearch"])
    bar.commit()
    XCTAssertEqual(opened?.0.absoluteString, "https://www.youtube.com/results?search_query=lofi")
    XCTAssertEqual(opened?.1, .newTab)
    XCTAssertFalse(bar.isVisible)

    bar.toggle(.newTab)                                    // the next open starts unscoped
    XCTAssertEqual(bar.scope, .normal)
    XCTAssertTrue(bar.barView.scopeChip.isHidden)
    bar.toggle(.newTab)
  }

  /// [I] Backspace on the empty scoped field leaves the scope (Chromium omnibox convention; Arc unverified).
  func testBackspaceOnTheEmptyScopedFieldExitsTheScope() async throws {
    bar.actionsProvider = { [CommandBarAction(id: "newSpace", title: "New Space")] }
    bar.toggle(.newTab)
    XCTAssertTrue(try insertTab())
    XCTAssertEqual(bar.scope, .actions)
    XCTAssertTrue(try deleteBackward())
    XCTAssertEqual(bar.scope, .normal)
    XCTAssertTrue(bar.barView.scopeChip.isHidden)
    bar.toggle(.newTab)
  }

  /// BH-108 / GS-035: a URL on the clipboard makes "Paste and Go" the top suggestion; Enter opens it.
  func testPasteAndGoRowOpensTheClipboardURL() async throws {
    var opened: (URL, CommandBarController.OpenTarget)?
    bar.clipboardURLProvider = { URL(string: "https://clip.example/x") }
    bar.onOpen = { opened = ($0, $1) }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.first?.kind, .pasteAndGo(URL(string: "https://clip.example/x")!))
    XCTAssertEqual(bar.results.first?.accessibilityCaption, "Paste and Go")
    bar.commit()
    XCTAssertEqual(opened?.0.absoluteString, "https://clip.example/x")
    XCTAssertEqual(opened?.1, .newTab)
  }

  /// Paste and Go is a new-tab surface: Cmd-L (a prefill or not) never offers it.
  func testCmdLNeverOffersPasteAndGo() async throws {
    bar.clipboardURLProvider = { URL(string: "https://clip.example/x") }
    bar.toggle(.currentTab(nil))
    XCTAssertTrue(bar.results.isEmpty)
    bar.toggle(.newTab)
  }

  /// The pasteboard read behind the provider: URLs only, never plain text or a schemeless host.
  func testPasteboardURLReadsURLsOnly() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("CommandBarTests.\(UUID().uuidString)"))
    XCTAssertNil(CommandBarController.pasteboardURL(pasteboard))
    pasteboard.clearContents()
    pasteboard.setString("just some words", forType: .string)
    XCTAssertNil(CommandBarController.pasteboardURL(pasteboard))
    pasteboard.clearContents()
    pasteboard.setString("example.com", forType: .string)
    XCTAssertNil(CommandBarController.pasteboardURL(pasteboard), "a schemeless host is not Paste and Go")
    pasteboard.clearContents()
    pasteboard.setString("https://clip.example/a", forType: .string)
    XCTAssertEqual(CommandBarController.pasteboardURL(pasteboard)?.absoluteString, "https://clip.example/a")
    pasteboard.clearContents()
    pasteboard.setString("https://clip.example/b", forType: .URL)
    XCTAssertEqual(CommandBarController.pasteboardURL(pasteboard)?.absoluteString, "https://clip.example/b")
  }

  /// BH-109 / KB-083: Cmd-Opt-Delete removes the selected suggestion; it stays hidden for the session.
  func testCommandOptionDeleteRemovesTheSelectedSuggestion() async throws {
    var removed: CommandBarResults.Result?
    let list = tabs(3)
    bar.openTabsProvider = { list }
    bar.onRemoveSuggestion = { removed = $0 }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.map(\.title), ["Tab 1", "Tab 2", "Tab 3"])
    bar.barView.table.selectRowIndexes([1], byExtendingSelection: false)
    try sendKey(51, "\u{7f}", [.command, .option])
    XCTAssertEqual(removed?.title, "Tab 2")
    XCTAssertEqual(bar.results.map(\.title), ["Tab 1", "Tab 3"])
    XCTAssertEqual(bar.barView.table.selectedRow, 1, "the next suggestion takes the removed row's place")

    bar.setQueryForTesting("Tab")                          // session exclusion survives retypes
    XCTAssertFalse(bar.results.contains { $0.title == "Tab 2" })

    bar.setQueryForTesting("example.com")                  // the typed URL row is not removable
    bar.barView.table.selectRowIndexes([0], byExtendingSelection: false)
    try sendKey(51, "\u{7f}", [.command, .option])
    XCTAssertEqual(bar.results.map(\.kind.name), ["open", "search"])
    bar.toggle(.newTab)
  }

  /// BH-109: the hovered removable row shows an X that removes it; other rows show none.
  func testHoverCloseButtonRemovesTheSuggestion() async throws {
    var removed: String?
    let list = tabs(2)
    bar.openTabsProvider = { list }
    bar.onRemoveSuggestion = { removed = $0.title }
    bar.toggle(.newTab)
    try hover(row: 1)
    let cell = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 1, makeIfNecessary: false)
                             as? CommandBarCellView)
    XCTAssertFalse(cell.closeButton.isHidden)
    cell.closeButton.performClick(nil)
    XCTAssertEqual(removed, "Tab 2")
    XCTAssertEqual(bar.results.map(\.title), ["Tab 1"])

    bar.setQueryForTesting("example.com")                  // rows: open (not removable), search (removable)
    try hover(row: 0)
    let openCell = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 0, makeIfNecessary: false)
                                 as? CommandBarCellView)
    XCTAssertTrue(openCell.closeButton.isHidden)
    try hover(row: 1)
    let searchCell = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: 1, makeIfNecessary: false)
                                   as? CommandBarCellView)
    XCTAssertFalse(searchCell.closeButton.isHidden)
    bar.toggle(.newTab)
  }

  /// BH-113: the notice appears with the first search row, the X dismisses it, and it never comes back.
  func testNoticeShowsWithSearchRowsAndDismissalSticks() async throws {
    let settings = CommandBarSettings.ephemeral()
    bar.settings = settings
    bar.toggle(.newTab)
    XCTAssertFalse(bar.isNoticeVisible, "no search row on an empty query")
    bar.setQueryForTesting("hello")
    XCTAssertTrue(bar.isNoticeVisible)
    XCTAssertFalse(bar.barView.noticeView.isHidden)
    XCTAssertEqual(bar.barView.noticeLabel.stringValue,
                   "We talk to your search engine to help us suggest results.")

    XCTAssertNotNil(bar.barView.noticeDismissButton.image, "the notice's X draws a glyph")
    bar.barView.noticeDismissButton.performClick(nil)
    XCTAssertTrue(settings.searchSuggestionNoticeDismissed)
    XCTAssertFalse(bar.isNoticeVisible)
    XCTAssertTrue(bar.barView.noticeView.isHidden)

    bar.setQueryForTesting("world")
    XCTAssertFalse(bar.isNoticeVisible, "dismissed for good")
    bar.toggle(.newTab)
  }

  /// BH-113: the notice takes its height out of the panel; dismissing shrinks it back, top pinned.
  func testNoticeAddsItsHeightToThePanel() async throws {
    bar.settings = CommandBarSettings.ephemeral()
    bar.toggle(.newTab)
    bar.setQueryForTesting("hello")
    let top = bar.panel.frame.maxY
    XCTAssertEqual(bar.panel.frame.height,
                   CommandBarGeometry.contentHeight(rowCount: 1, showsNotice: true), accuracy: 1)
    bar.dismissNotice()
    XCTAssertEqual(bar.panel.frame.height,
                   CommandBarGeometry.contentHeight(rowCount: 1, showsNotice: false), accuracy: 1)
    XCTAssertEqual(bar.panel.frame.maxY, top, accuracy: 1, "the top edge stays pinned")
    bar.toggle(.newTab)
  }

  /// `searchSuggestEnabled` off: no search row, no notice (no engine round trip).
  func testSuggestionsOffHidesTheSearchRowAndTheNotice() async throws {
    bar.settings = CommandBarSettings.ephemeral()
    bar.settings.setSearchSuggestionsEnabled(false)
    bar.toggle(.newTab)
    bar.setQueryForTesting("hello")
    XCTAssertTrue(bar.results.isEmpty)
    XCTAssertFalse(bar.isNoticeVisible)
    bar.toggle(.newTab)
  }

  /// BH-111: switching the Space while the bar is open refreshes the suggestions for it (current Space first).
  func testSpaceSwitchRefreshesTheOpenBarSuggestions() async throws {
    let sidebar = shell.sidebar
    let current = try XCTUnwrap(shell.sidebarController.currentSpace)
    let other = try sidebar.addSpace(title: "Other")
    let otherTab = try sidebar.addTab(url: URL(string: "https://other.example")!, title: "Other Tab",
                                      in: .today(other))
    shell.newTab(nil)
    XCTAssertTrue(shell.commandBar.isVisible)
    func firstSwitchNode() -> NodeID? {
      guard case .switchTo(let node) = shell.commandBar.results.first?.kind else { return nil }
      return node
    }
    XCTAssertEqual(sidebar.spaceID(containing: try XCTUnwrap(firstSwitchNode())), current)
    shell.sidebarController.showSpace(other)
    XCTAssertEqual(sidebar.spaceID(containing: try XCTUnwrap(firstSwitchNode())), other)
    XCTAssertEqual(shell.commandBar.results.first?.title, "Other Tab")
    XCTAssertEqual(otherTab, firstSwitchNode())
    shell.commandBar.hide()
  }

  /// BH-110: with the bar open and key, a click on a sidebar row reaches the row (the centered panel is not in
  /// its way), activates it, and closes the bar (the click hands key status back to the shell window).
  func testSidebarClickWorksWhileTheBarIsOpen() async throws {
    let sidebar = shell.sidebar
    let space = try XCTUnwrap(shell.sidebarController.currentSpace)
    let target = try sidebar.addTab(url: URL(string: "https://click.example")!, title: "Click Target",
                                    in: .today(space))
    shell.newTab(nil)
    XCTAssertTrue(shell.commandBar.isVisible)

    let outline = try XCTUnwrap(shell.sidebarController.view.currentOutline)
    let content = try XCTUnwrap(shell.window?.contentView)
    content.layoutSubtreeIfNeeded()
    let outlineController = try XCTUnwrap(shell.sidebarController.currentPage?.outlineController)
    let row = outlineController.row(for: target)
    XCTAssertGreaterThanOrEqual(row, 0)
    // A runner screen smaller than the 1400 x 900 frame shrinks the window; the row must be on screen to be hit.
    outline.scrollRowToVisible(row)
    content.layoutSubtreeIfNeeded()
    let rowView = try XCTUnwrap(outline.rowView(atRow: row, makeIfNecessary: true))
    let point = rowView.convert(NSPoint(x: 10, y: rowView.bounds.midY), to: content)
    let hit = content.hitTest(point)
    let diagnostics = "window \(shell.window?.frame ?? .zero), content \(content.bounds), point \(point), "
      + "row \(row) of \(outline.numberOfRows), outline visible \(outline.visibleRect), "
      + "sidebar \(shell.sidebarController.view.frame), pager \(shell.sidebarController.view.pager.frame), "
      + "content flipped \(content.isFlipped), row rect \(outline.rect(ofRow: row)), outline frame \(outline.frame), "
      + "clip bounds \(outline.enclosingScrollView?.contentView.bounds ?? .zero), scroll frame \(outline.enclosingScrollView?.frame ?? .zero), "
      + "hit frame \(hit?.frame ?? .zero), pager hidden \(shell.sidebarController.view.pager.isHidden) "
      + "alpha \(shell.sidebarController.view.pager.alphaValue) strip \(shell.sidebarController.view.pager.strip.frame) "
      + "pages \(shell.sidebarController.view.pager.pages.map(\.frame)) index \(shell.sidebarController.view.pager.index) "
      + "pagerHit \(String(describing: shell.sidebarController.view.pager.hitTest(shell.sidebarController.view.convert(point, from: content)).map { type(of: $0) })) "
      + "sidebarSubviews \(shell.sidebarController.view.subviews.map { "\(type(of: $0)) \($0.frame) hidden=\($0.isHidden)" })"
    XCTAssertTrue(hit?.isDescendant(of: outline) ?? false,
                  "the click lands on the sidebar row, not the bar (hit: \(hit.map { String(describing: type(of: $0)) } ?? "nil"); \(diagnostics))")

    // The click's two effects, as AppKit delivers them: the shell window goes key and the row activates.
    shell.commandBar.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification,
                                                     object: shell.commandBar.panel))
    shell.sidebarController.activate(node: target)
    XCTAssertEqual(shell.sidebarController.current, target, "the click activated the row (BH-110)")
    XCTAssertFalse(shell.commandBar.isVisible, "the bar resigned")
  }
}
