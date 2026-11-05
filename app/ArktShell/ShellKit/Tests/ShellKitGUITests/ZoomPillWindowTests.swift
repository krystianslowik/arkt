import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The zoom pill in a shell window (#579, design/extensions `surf-zoom`): a user zoom of the page on screen shows it at
/// the top trailing corner of the card, its buttons call the engine, Reset hides it, and the zoom keys stay the
/// engine's page commands. Nothing here waits on a clock: the auto-close sleeper parks until the test resumes it.
@MainActor
final class ZoomPillWindowTests: XCTestCase {
  private var harnesses: [EngineHarnessWindow] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for harness in harnesses { harness.controller.window?.orderOut(nil) }
    harnesses = []
  }

  // MARK: Fixtures

  /// A sleeper whose sleeps end only when the test resumes them (cancellation throws).
  actor Sleeper {
    private struct Parked {
      let id: Int
      let continuation: CheckedContinuation<Void, any Error>
    }

    private var parked: [Parked] = []
    private var nextID = 0

    func sleep(_ duration: Duration) async throws {
      let id = nextID
      nextID += 1
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { parked.append(Parked(id: id, continuation: $0)) }
      } onCancel: {
        Task { await self.cancel(id) }
      }
    }

    private func cancel(_ id: Int) {
      guard let index = parked.firstIndex(where: { $0.id == id }) else { return }
      parked.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    var parkedCount: Int { parked.count }
    /// Every sleep that began, cancelled ones included.
    var startedCount: Int { nextID }

    func resumeNext() {
      guard !parked.isEmpty else { return }
      parked.removeFirst().continuation.resume()
    }
  }

  @MainActor
  private struct Rig {
    let harness: EngineHarnessWindow
    let sleeper: Sleeper
    /// The announcement's delay.
    let speech: Sleeper
    let nodes: [UUID]
    var announcements: [String] { box.announcements }
    let box: Box
    var controller: ShellWindowController { harness.controller }
    var engine: InMemoryEngine { harness.engine }
    var pill: ZoomPillView { controller.rootView.card.zoomPillView! }
    var window: NSWindow { controller.window! }
    var tab: TabID { controller.currentTab! }
  }

  @MainActor
  private final class Box {
    var announcements: [String] = []
  }

  private func makeRig(reduceMotion: Bool = false) throws -> Rig {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let nodes = try (0..<2).map {
      try sidebar.addTab(url: URL(string: "https://example.com/\($0)")!, title: "Page \($0)", in: .today(space))
    }
    let harness = EngineHarnessWindow(sidebar)
    harnesses.append(harness)
    let sleeper = Sleeper()
    let box = Box()
    let speech = Sleeper()
    harness.controller.zoomPill.sleep = { try await sleeper.sleep($0) }
    harness.controller.zoomPill.announceSleep = { try await speech.sleep($0) }
    let pill = try XCTUnwrap(harness.controller.rootView.card.zoomPillView)
    pill.reduceMotion = { reduceMotion }
    pill.postAnnouncement = { box.announcements.append($0) }
    pill.pointerInWindow = { _ in nil }                         // the real pointer never decides a test
    harness.controller.activate(node: nodes[0])
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    return Rig(harness: harness, sleeper: sleeper, speech: speech, nodes: nodes, box: box)
  }

  /// Takes main-actor turns until `condition` holds; bounded, no clock.
  private func until(_ what: String, turns: Int = 5000, file: StaticString = #filePath, line: UInt = #line,
                     _ condition: () async -> Bool) async {
    for _ in 0..<turns {
      if await condition() { return }
      await Task.yield()
    }
    XCTFail("never reached: \(what)", file: file, line: line)
  }

  // MARK: Showing

  func testAUserZoomShowsThePillAtTheTopTrailingCorner() throws {
    let rig = try makeRig()
    XCTAssertTrue(rig.pill.isHidden, "no pill before a zoom change")

    rig.engine.zoomIn(rig.tab)
    rig.window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(rig.pill.isHidden)
    XCTAssertTrue(rig.pill.superview === rig.controller.rootView.card)
    XCTAssertEqual(rig.pill.percentLabel.stringValue, "110%")
    let card = rig.controller.rootView.card
    XCTAssertEqual(rig.pill.frame.height, 36)
    XCTAssertEqual(rig.pill.frame.maxX, card.bounds.maxX - 12, accuracy: 0.01)
    XCTAssertEqual(rig.pill.frame.maxY, card.bounds.maxY - 12, accuracy: 0.01)
    XCTAssertEqual(rig.pill.frame.width, ZoomPillLayout.width(resetWidth: rig.pill.resetWidth), accuracy: 0.01)
    XCTAssertEqual(rig.pill.surfaceLayer.cornerRadius, 18)
  }

  func testAZoomTheEngineMadeOnItsOwnShowsNothing() throws {
    let rig = try makeRig()
    rig.engine.setZoom(rig.tab, percent: 150, userInitiated: false)
    XCTAssertTrue(rig.pill.isHidden, "a site's saved zoom or another tab on the same site does not show the pill")
  }

  func testAZoomOfAnotherTabShowsNothing() throws {
    let rig = try makeRig()
    rig.controller.activate(node: rig.nodes[1])
    let second = rig.tab
    rig.controller.activate(node: rig.nodes[0])
    rig.engine.zoomIn(second)
    XCTAssertTrue(rig.pill.isHidden)
  }

  // MARK: The buttons

  func testMinusPlusAndResetCallTheEngineAndResetHidesThePill() throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)

    rig.pill.zoomInButton.performClick(nil)
    XCTAssertEqual(rig.engine.snapshot(of: rig.tab)?.zoom.percent, 125)
    XCTAssertEqual(rig.pill.percentLabel.stringValue, "125%")
    rig.pill.zoomOutButton.performClick(nil)
    XCTAssertEqual(rig.pill.percentLabel.stringValue, "110%")

    rig.pill.resetButton.performClick(nil)
    XCTAssertEqual(rig.engine.snapshot(of: rig.tab)?.zoom, .default)
    XCTAssertTrue(rig.pill.isHidden, "Reset returns to 100% and hides the pill")
  }

  // MARK: Auto-close

  func testThePillClosesWhenTheTimerEndsAndHoverHoldsIt() async throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)
    await until("the timer is parked") { await rig.sleeper.parkedCount == 1 }

    rig.controller.zoomPill.setHovering(true)
    await until("hover cancelled the timer") { await rig.sleeper.parkedCount == 0 }
    XCTAssertFalse(rig.pill.isHidden)

    rig.controller.zoomPill.setHovering(false)
    await until("leaving armed it again") { await rig.sleeper.parkedCount == 1 }
    await rig.sleeper.resumeNext()
    await until("the pill closed") { rig.pill.isHidden }
  }

  func testAPillThatAppearsUnderTheStillPointerStartsHeldOpen() async throws {
    let rig = try makeRig()
    rig.pill.pointerInWindow = { pill in pill.convert(NSPoint(x: pill.bounds.midX, y: pill.bounds.midY), to: nil) }
    rig.engine.zoomIn(rig.tab)
    for _ in 0..<50 { await Task.yield() }
    let parked = await rig.sleeper.parkedCount
    XCTAssertEqual(parked, 0, "no timer while the pointer is over the pill")
    XCTAssertFalse(rig.controller.zoomPill.isTimerArmed)

    rig.controller.zoomPill.setHovering(false)
    await until("leaving armed the timer") { await rig.sleeper.parkedCount == 1 }
  }

  // MARK: Tabs

  func testSwitchingTabsClosesThePill() throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)
    XCTAssertFalse(rig.pill.isHidden)
    rig.controller.activate(node: rig.nodes[1])
    XCTAssertTrue(rig.pill.isHidden)
    rig.controller.activate(node: rig.nodes[0])
    XCTAssertTrue(rig.pill.isHidden, "it does not come back with the tab")
  }

  func testWithTheFindBarOpenThePillSitsBelowIt() throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)
    XCTAssertTrue(rig.controller.engineHost.perform(.find, disposition: .currentTab))
    rig.window.contentView?.layoutSubtreeIfNeeded()
    let bar = try XCTUnwrap(rig.controller.rootView.card.findBarView)
    XCTAssertFalse(bar.isHidden)
    XCTAssertEqual(rig.pill.frame.maxY, bar.frame.minY - 8, accuracy: 0.01)
    XCTAssertEqual(rig.pill.frame.maxX, bar.frame.maxX, accuracy: 0.01)

    rig.controller.findBar.close()
    XCTAssertTrue(bar.isHidden)
    XCTAssertEqual(rig.pill.frame.maxY, rig.controller.rootView.card.bounds.maxY - 12, accuracy: 0.01,
                   "back in the corner once the bar closes")
  }

  // MARK: Split View

  func testInASplitThePillIsOnTheFocusedPane() throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try (0..<2).map {
      try sidebar.addTab(url: URL(string: "https://example.com/pane\($0)")!, title: "Pane \($0)", in: .split(split))
    }
    let harness = EngineHarnessWindow(sidebar)
    harnesses.append(harness)
    let sleeper = Sleeper()
    harness.controller.zoomPill.sleep = { try await sleeper.sleep($0) }
    harness.controller.rootView.card.zoomPillView?.pointerInWindow = { _ in nil }
    harness.controller.activate(node: panes[0])
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    let tab = try XCTUnwrap(harness.controller.findTarget)

    harness.engine.zoomIn(tab)

    let card = harness.controller.rootView.split.paneCards[0]
    let pill = try XCTUnwrap(card.zoomPillView, "the focused pane's card hosts the pill")
    XCTAssertFalse(pill.isHidden)
    XCTAssertNil(harness.controller.rootView.card.zoomPillView)
    card.layoutSubtreeIfNeeded()
    XCTAssertEqual(pill.frame.maxX, card.bounds.maxX - 12, accuracy: 0.01)
    harness.controller.zoomPill.close()
  }

  // MARK: Keys

  func testTheZoomKeysStayTheEnginesPageCommands() throws {
    let rig = try makeRig()
    let host = rig.controller.engineHost
    for command in [EngineCommand.zoomIn, .zoomOut, .zoomReset] {
      XCTAssertNil(host.claim(command), "the shell does not claim \(command)")
    }
    let item = NSMenuItem(title: "Zoom In", action: #selector(ShellWindow.commandDispatch(_:)), keyEquivalent: "+")
    item.tag = EngineCommand.zoomIn.rawValue
    (rig.window as? ShellWindow)?.commandDispatch(item)
    XCTAssertEqual(rig.engine.executedCommands.map(\.command), [.zoomIn], "Cmd-+ reaches the engine")
  }

  // MARK: Accessibility and motion

  func testVoiceOverReadsThePercentAndTheButtons() async throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)
    rig.engine.zoomIn(rig.tab)
    XCTAssertEqual(rig.pill.accessibilityRole(), .group)
    XCTAssertEqual(rig.pill.accessibilityLabel(), "Zoom")
    XCTAssertEqual(rig.pill.percentLabel.accessibilityValue(), "125%")
    XCTAssertEqual(rig.pill.zoomOutButton.accessibilityLabel(), "Zoom out")
    XCTAssertEqual(rig.pill.zoomInButton.accessibilityLabel(), "Zoom in")
    XCTAssertEqual(rig.pill.resetButton.accessibilityLabel(), "Reset zoom")
    await until("only the last change waits to be spoken") {
      let started = await rig.speech.startedCount
      let parked = await rig.speech.parkedCount
      return started == 2 && parked == 1
    }
    await rig.speech.resumeNext()
    await until("spoken") { !rig.announcements.isEmpty }
    XCTAssertEqual(rig.announcements, ["Zoom 125%"], "a held key speaks where it stopped")

    rig.pill.resetButton.performClick(nil)
    XCTAssertTrue(rig.pill.isHidden)
    await until("the reset waits to be spoken") { await rig.speech.parkedCount == 1 }
    await rig.speech.resumeNext()
    await until("spoken") { rig.announcements.count == 2 }
    XCTAssertEqual(rig.announcements.last, "Zoom 100%", "heard though the pill closed")
  }

  func testTheButtonsNeverTakeTheKeyboardFromThePage() throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)
    for button in [rig.pill.zoomOutButton, rig.pill.zoomInButton, rig.pill.resetButton] as [NSButton] {
      XCTAssertTrue(button.refusesFirstResponder)
      XCTAssertFalse(button.acceptsFirstResponder)
    }
    let page = try XCTUnwrap(rig.engine.contentView(for: rig.tab))
    rig.window.makeFirstResponder(page)
    let before = rig.window.firstResponder
    rig.pill.zoomInButton.performClick(nil)
    XCTAssertTrue(rig.window.firstResponder === before, "the page keeps the keyboard, so the zoom keys keep working")
    XCTAssertEqual(rig.pill.percentLabel.stringValue, "125%")
  }

  func testOnANarrowPaneThePartsThatDoNotFitHide() throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)
    rig.pill.frame = CGRect(x: 0, y: 0, width: 120, height: 36)
    rig.pill.layoutSubtreeIfNeeded()
    XCTAssertTrue(rig.pill.resetButton.isHidden, "Reset goes first")
    XCTAssertFalse(rig.pill.zoomInButton.isHidden)
    XCTAssertFalse(rig.pill.percentLabel.isHidden)
    rig.pill.frame = CGRect(x: 0, y: 0, width: 300, height: 36)
    rig.pill.layoutSubtreeIfNeeded()
    XCTAssertFalse(rig.pill.resetButton.isHidden, "back with room")
  }

  func testTheEntranceFadesAndRisesOnceAndOnlyFadesWithReduceMotion() throws {
    let rig = try makeRig()
    rig.engine.zoomIn(rig.tab)
    XCTAssertNotNil(rig.pill.layer?.animation(forKey: ZoomPillView.fadeKey))
    XCTAssertNotNil(rig.pill.layer?.animation(forKey: ZoomPillView.riseKey))
    rig.pill.layer?.removeAllAnimations()
    rig.engine.zoomIn(rig.tab)
    XCTAssertNil(rig.pill.layer?.animation(forKey: ZoomPillView.fadeKey), "a step does not replay the entrance")

    let calm = try makeRig(reduceMotion: true)
    calm.engine.zoomIn(calm.tab)
    XCTAssertNotNil(calm.pill.layer?.animation(forKey: ZoomPillView.fadeKey))
    XCTAssertNil(calm.pill.layer?.animation(forKey: ZoomPillView.riseKey), "Reduce Motion: the fade only")
  }
}
