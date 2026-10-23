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

  // #96: Cmd-L on a URL lists it once: no "Search Google" row with the same text, no subtitle repeating it.
  func testCmdLOnAURLShowsOneOpenRow() async throws {
    bar.toggle(.currentTab(URL(string: "https://example.com/a")))
    XCTAssertEqual(bar.results.map(\.kind.name), ["open"])
    XCTAssertEqual(bar.results.first?.subtitle, "")
    XCTAssertEqual(bar.panel.frame.height, CommandBarGeometry.contentHeight(rowCount: 1))
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
    var result: (URL, Bool)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example.com")
    try sendReturn()
    XCTAssertEqual(result?.0.absoluteString, "https://example.com")
    XCTAssertEqual(result?.1, true)
    XCTAssertFalse(bar.isVisible)
  }

  // [I] KB-085: Opt-Enter opens the selected result in a new tab, also from Cmd-L (Chromium omnibox convention).
  func testOptionReturnFromCmdLOpensInANewTab() async throws {
    var result: (URL, Bool)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    try sendReturn(.option)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, true, "new tab, not the current one")
    XCTAssertFalse(bar.isVisible)
  }

  // [I] KB-085: Cmd-Enter opens the selected result in a new tab, also from Cmd-L.
  func testCommandReturnFromCmdLOpensInANewTab() async throws {
    var result: (URL, Bool)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    try sendReturn(.command)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, true)
    XCTAssertFalse(bar.isVisible)
  }

  // [I] A modified Enter on an unedited Cmd-L opens the URL in a new tab instead of reloading (KB-004 is plain Enter).
  func testModifiedReturnOnUneditedCmdLOpensANewTabInsteadOfReloading() async throws {
    var reloaded = false
    var result: (URL, Bool)?
    bar.onReload = { reloaded = true }
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    try sendReturn(.command)
    XCTAssertFalse(reloaded)
    XCTAssertEqual(result?.0.absoluteString, "https://example.com")
    XCTAssertEqual(result?.1, true)
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
    var result: (URL, Bool)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    try sendReturn(.shift)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, false, "plain commit: Cmd-L navigates the current tab")
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
    var result: (URL, Bool)?
    bar.onOpen = { result = ($0, $1) }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    bar.setQueryForTesting("example.org")
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    let handled = bar.control(bar.barView.field, textView: editor,
                              doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
    XCTAssertTrue(handled)
    XCTAssertEqual(result?.0.absoluteString, "https://example.org")
    XCTAssertEqual(result?.1, false, "not an Opt-Return: Cmd-L navigates the current tab")
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
}
