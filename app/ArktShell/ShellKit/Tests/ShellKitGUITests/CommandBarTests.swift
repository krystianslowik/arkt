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
    shell = ShellWindowController(engine: InMemoryEngine())
    let window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1400, height: 900), display: true)
    shell.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    bar = CommandBarController(parent: window)
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
    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let loaded = getloadavg(&load, 1) != 1 || load[0] >= Double(cores)
    let summary = String(format: "commandbar.earliestframe p95=%.2f bound=%.2f load1=%.2f cores=%d asserted=%@",
                         p95 * 1000, bound * 1000, load[0], cores, loaded ? "no" : "yes")
    print(summary)
    let attachment = XCTAttachment(string: summary)
    attachment.name = "commandbar.earliestframe"
    attachment.lifetime = .keepAlways
    add(attachment)
    if loaded {
      print("commandbar.earliestframe skipped: 1-minute load \(load[0]) >= \(cores) active cores")
    } else {
      XCTAssertLessThanOrEqual(p95, bound, "panel missed its earliest possible frame")
    }
  }

  func testGeometryAndDarkSurface() async throws {
    let window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1800, height: 1072), display: true)
    bar.toggle(.newTab)
    let panel = bar.panel
    XCTAssertTrue(panel.isVisible)
    XCTAssertGreaterThan(panel.orderedIndex, -1)
    // The window server may clamp the 1800 x 1072 request to the screen, so expect from the actual frame.
    // Tolerance 1 pt: panel origins snap to backing pixels.
    let parent = window.frame
    XCTAssertEqual(panel.frame.width, min(766, parent.width - 48), accuracy: 1)
    XCTAssertEqual(panel.frame.midX, parent.midX, accuracy: 1)
    XCTAssertEqual(panel.frame.maxY, parent.maxY - 0.34 * parent.height, accuracy: 1)
    XCTAssertEqual(panel.frame.height, CommandBarGeometry.inputHeight)          // empty Cmd-T: input row only
    XCTAssertEqual(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
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

  func testCmdLEditedEnterNavigatesCurrentTab() async throws {
    var result: (URL, Bool)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    bar.commit()
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")            // BH-101
    XCTAssertEqual(result?.1, false)
  }

  func testCmdTEnterOnURLOpensInNewTab() async throws {
    var result: (URL, Bool)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example.com")
    bar.commit()
    XCTAssertEqual(result?.0.absoluteString, "https://example.com")            // KB-001, BH-100
    XCTAssertEqual(result?.1, true)
    XCTAssertFalse(bar.isVisible)
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
    XCTAssertEqual(bar.barView.table.selectedRow, 1)                           // clamps, no wrap (RT-08)
    _ = bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
    _ = bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
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
    cell.title.stringValue = "marker"                              // a reload would reconfigure the cell
    table.selectRowIndexes([1], byExtendingSelection: false)
    bar.toggle(.newTab)
    bar.toggle(.newTab)
    let again = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? CommandBarCellView)
    XCTAssertTrue(again === cell, "no reload: the same cell view")
    XCTAssertEqual(again.title.stringValue, "marker")
    XCTAssertEqual(table.selectedRow, 0, "selection still resets to the first result")
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
}
