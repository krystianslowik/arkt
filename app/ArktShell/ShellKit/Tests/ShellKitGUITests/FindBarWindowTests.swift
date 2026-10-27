import AppKit
import Carbon.HIToolbox
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// The find bar in a shell window (#134, design/find-in-page direction A): Cmd-F opens it and focuses the field,
/// typing searches after a debounce on an injected sleeper, Return and Cmd-G step, Esc and the close button end the
/// find with `.clear` and give the page its focus back, and each tab has its own bar. Nothing here waits on a clock:
/// the debounce is resumed by hand and the waits take bounded main-actor turns.
@MainActor
final class FindBarWindowTests: XCTestCase {
  private static let link = URL(string: "https://example.com/link")!
  private var harnesses: [EngineHarnessWindow] = []
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for harness in harnesses { harness.controller.window?.orderOut(nil) }
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    harnesses = []
    sets = []
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

    func resumeNext() {
      guard !parked.isEmpty else { return }
      parked.removeFirst().continuation.resume()
    }
  }

  /// One window over two Today tabs whose pages hold `occurrences` copies of the find word.
  @MainActor
  private struct Rig {
    let harness: EngineHarnessWindow
    let sleeper: Sleeper
    let nodes: [UUID]
    var controller: ShellWindowController { harness.controller }
    var engine: InMemoryEngine { harness.engine }
    var presenter: FindBarPresenter { controller.findBar }
    var bar: FindBarView { controller.rootView.card.findBarView! }
    var window: NSWindow { controller.window! }
  }

  private func makeSidebar(occurrences: Int) throws -> (SidebarModel.Sidebar, [UUID]) {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let nodes = try (0..<2).map {
      try sidebar.addTab(url: InMemoryEngine.findPageURL(occurrences: occurrences + $0, link: Self.link),
                         title: "Page \($0)", in: .today(space))
    }
    return (sidebar, nodes)
  }

  private func makeRig(occurrences: Int = 3) throws -> Rig {
    let (sidebar, nodes) = try makeSidebar(occurrences: occurrences)
    let harness = EngineHarnessWindow(sidebar)
    harnesses.append(harness)
    let sleeper = Sleeper()
    harness.controller.findBar.sleep = { try await sleeper.sleep($0) }
    harness.controller.activate(node: nodes[0])
    let window = try XCTUnwrap(harness.controller.window)
    window.contentView?.layoutSubtreeIfNeeded()
    return Rig(harness: harness, sleeper: sleeper, nodes: nodes)
  }

  private func key(_ code: Int, flags: NSEvent.ModifierFlags = [], in window: NSWindow, _ characters: String) throws
    -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
      keyCode: UInt16(code)))
  }

  private func type(_ text: String, into rig: Rig) throws {
    let editor = try XCTUnwrap(rig.window.firstResponder as? NSTextView, "the field is being edited")
    for character in text { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
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

  /// Types `text` and lets the debounce run out.
  private func search(_ text: String, in rig: Rig) async throws {
    try type(text, into: rig)
    await until("the debounce timer is parked") { await rig.sleeper.parkedCount == 1 }
    await rig.sleeper.resumeNext()
    await until("the count for \(text)") { rig.bar.countLabel.stringValue != "" }
  }

  private func open(_ rig: Rig) {
    XCTAssertTrue(rig.controller.engineHost.perform(.find, disposition: .currentTab))
  }

  // MARK: Cmd-F

  func testFindIsClaimedAndEnabledWithAPage() throws {
    let rig = try makeRig()
    XCTAssertEqual(rig.controller.engineHost.claim(.find), CommandClaim(isEnabled: true))
    XCTAssertEqual(rig.controller.engineHost.claim(.findNext), CommandClaim(isEnabled: false), "nothing to find again")
    XCTAssertEqual(rig.controller.engineHost.claim(.findPrevious), CommandClaim(isEnabled: false))
    XCTAssertTrue(rig.engine.executedCommands.isEmpty, "claimed commands never reach the engine")
  }

  func testFindIsDisabledWithoutAPage() throws {
    var sidebar = SidebarModel.Sidebar()
    _ = sidebar.addSpace(title: "Empty")
    let harness = EngineHarnessWindow(sidebar)
    harnesses.append(harness)
    XCTAssertEqual(harness.controller.engineHost.claim(.find), CommandClaim(isEnabled: false))
  }

  func testCmdFOpensTheBarAndFocusesTheField() throws {
    let rig = try makeRig()
    XCTAssertTrue(rig.bar.isHidden, "no bar until Cmd-F")

    open(rig)

    XCTAssertFalse(rig.bar.isHidden)
    XCTAssertTrue(rig.bar.isDescendant(of: rig.controller.rootView.card))
    let editor = try XCTUnwrap(rig.window.firstResponder as? NSTextView)
    XCTAssertTrue(editor.delegate === rig.bar.field, "the field has the keyboard")
  }

  func testTheBarIsA372By36PillAtTheTopTrailingCorner() throws {
    let rig = try makeRig()
    open(rig)
    rig.window.contentView?.layoutSubtreeIfNeeded()
    let card = rig.controller.rootView.card
    XCTAssertEqual(rig.bar.frame.size, CGSize(width: 372, height: 36))
    XCTAssertEqual(rig.bar.frame.maxX, card.bounds.maxX - 12, accuracy: 0.01)
    XCTAssertEqual(rig.bar.frame.maxY, card.bounds.maxY - 12, accuracy: 0.01)
    XCTAssertEqual(rig.bar.surfaceLayer.cornerRadius, 18)
  }

  func testWithTheToolbarOnTheBarSitsBelowIt() throws {
    let rig = try makeRig()
    let card = rig.controller.rootView.card
    card.showsToolbar = true
    open(rig)
    rig.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(rig.bar.frame.maxY, card.bounds.maxY - ContentToolbarView.height - 12, accuracy: 0.01)
  }

  func testASecondCmdFSelectsTheTextSoTypingReplacesIt() async throws {
    let rig = try makeRig()
    open(rig)
    try await search("nee", in: rig)
    XCTAssertEqual(rig.bar.field.stringValue, "nee")
    let editor = try XCTUnwrap(rig.window.firstResponder as? NSTextView)
    editor.setSelectedRange(NSRange(location: 3, length: 0))

    open(rig)

    XCTAssertEqual((rig.window.firstResponder as? NSTextView)?.selectedRange(), NSRange(location: 0, length: 3))
  }

  func testReopeningAfterEscSelectsTheRememberedText() async throws {
    let rig = try makeRig()
    open(rig)
    try await search("nee", in: rig)
    try rig.window.sendEvent(key(kVK_Escape, in: rig.window, "\u{1B}"))

    open(rig)

    XCTAssertEqual(rig.bar.field.stringValue, "nee")
    XCTAssertEqual((rig.window.firstResponder as? NSTextView)?.selectedRange(), NSRange(location: 0, length: 3))
  }

  // MARK: Searching

  func testTypingSearchesAfterTheDebounceAndShowsNOfM() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try type("nee", into: rig)
    await until("the debounce timer is parked") { await rig.sleeper.parkedCount == 1 }
    XCTAssertEqual(rig.bar.countLabel.stringValue, "", "nothing before the debounce ends")

    await rig.sleeper.resumeNext()
    await until("the count") { rig.bar.countLabel.stringValue == "1 of 3" }
    XCTAssertEqual(rig.bar.field.stringValue, "nee")
  }

  func testNoMatchesShowsPlainTextAndDimsTheStepButtons() async throws {
    let rig = try makeRig()
    rig.bar.appearance = NSAppearance(named: .aqua)
    open(rig)
    try await search("zzz", in: rig)
    XCTAssertEqual(rig.bar.countLabel.stringValue, "No matches")
    XCTAssertEqual(rig.bar.countLabel.textColor, ShellTokens.primaryText.resolve(.light).nsColor(), "not red, not an error")
    for button in [rig.bar.previousButton, rig.bar.nextButton] {
      XCTAssertFalse(button.isEnabled)
      XCTAssertEqual(button.alphaValue, 0.35, accuracy: 0.001)
    }
    XCTAssertTrue(rig.bar.closeButton.isEnabled)
  }

  func testMatchesUseTheSecondaryTextAndLiveButtons() async throws {
    let rig = try makeRig()
    rig.bar.appearance = NSAppearance(named: .aqua)
    open(rig)
    try await search("nee", in: rig)
    XCTAssertEqual(rig.bar.countLabel.textColor, ShellTokens.secondaryText.resolve(.light).nsColor())
    XCTAssertTrue(rig.bar.previousButton.isEnabled && rig.bar.nextButton.isEnabled)
    XCTAssertEqual(rig.bar.nextButton.alphaValue, 1)
  }

  // MARK: Stepping

  func testReturnGoesToTheNextMatchAndShiftReturnToThePrevious() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)

    try rig.window.sendEvent(key(kVK_Return, in: rig.window, "\r"))
    XCTAssertEqual(rig.bar.countLabel.stringValue, "2 of 3")
    try rig.window.sendEvent(key(kVK_Return, flags: .shift, in: rig.window, "\r"))
    XCTAssertEqual(rig.bar.countLabel.stringValue, "1 of 3")
    try rig.window.sendEvent(key(kVK_Return, flags: .shift, in: rig.window, "\r"))
    XCTAssertEqual(rig.bar.countLabel.stringValue, "3 of 3", "previous wraps")
  }

  func testCmdGAndShiftCmdGStepThroughTheHostCommands() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    let host = rig.controller.engineHost
    XCTAssertEqual(host.claim(.findNext), CommandClaim(isEnabled: true))

    XCTAssertTrue(host.perform(.findNext, disposition: .currentTab))
    XCTAssertEqual(rig.bar.countLabel.stringValue, "2 of 3")
    XCTAssertTrue(host.perform(.findPrevious, disposition: .currentTab))
    XCTAssertEqual(rig.bar.countLabel.stringValue, "1 of 3")
    XCTAssertTrue(rig.engine.executedCommands.isEmpty)
  }

  func testTheStepButtonsStep() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    rig.bar.nextButton.performClick(nil)
    XCTAssertEqual(rig.bar.countLabel.stringValue, "2 of 3")
    rig.bar.previousButton.performClick(nil)
    XCTAssertEqual(rig.bar.countLabel.stringValue, "1 of 3")
  }

  func testCmdGWithTheBarClosedOpensItOnTheLastText() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    try rig.window.sendEvent(key(kVK_Escape, in: rig.window, "\u{1B}"))
    XCTAssertTrue(rig.bar.isHidden)

    XCTAssertTrue(rig.controller.engineHost.perform(.findNext, disposition: .currentTab))

    XCTAssertFalse(rig.bar.isHidden)
    XCTAssertEqual(rig.bar.field.stringValue, "nee")
    XCTAssertEqual(rig.bar.countLabel.stringValue, "1 of 3")
  }

  // MARK: Closing

  func testEscClosesTheBarEndsTheFindWithActivateAndFocusesThePage() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    let tab = try XCTUnwrap(rig.controller.currentTab)

    try rig.window.sendEvent(key(kVK_Escape, in: rig.window, "\u{1B}"))

    XCTAssertTrue(rig.bar.isHidden)
    XCTAssertEqual(try rig.engine.selectedText(tab), "nee", "activate: the match becomes the page's selection")
    XCTAssertTrue(rig.window.firstResponder === rig.engine.contentView(for: tab), "the page has the keyboard again")
  }

  func testEscFromAStepButtonCloses() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    XCTAssertTrue(rig.window.makeFirstResponder(rig.bar.nextButton))

    try rig.window.sendEvent(key(kVK_Escape, in: rig.window, "\u{1B}"))

    XCTAssertTrue(rig.bar.isHidden)
  }

  func testTheCloseButtonDoesTheSame() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    let tab = try XCTUnwrap(rig.controller.currentTab)
    let card = rig.controller.rootView.card
    let point = try XCTUnwrap(card.superview).convert(NSPoint(x: 12, y: 12), from: rig.bar.closeButton)
    XCTAssertTrue(card.hitTest(point) === rig.bar.closeButton, "the click lands on the button, not on the page")

    rig.bar.closeButton.performClick(nil)

    XCTAssertTrue(rig.bar.isHidden)
    XCTAssertEqual(try rig.engine.selectedText(tab), "nee")
    XCTAssertTrue(rig.window.firstResponder === rig.engine.contentView(for: tab))
  }

  func testClosingWhileTheDebounceRunsSearchesNothing() async throws {
    let rig = try makeRig()
    open(rig)
    try type("nee", into: rig)
    await until("the debounce timer is parked") { await rig.sleeper.parkedCount == 1 }

    try rig.window.sendEvent(key(kVK_Escape, in: rig.window, "\u{1B}"))

    await until("the timer was cancelled") { await rig.sleeper.parkedCount == 0 }
    XCTAssertTrue(rig.bar.isHidden)
  }

  // MARK: One bar per tab

  func testSwitchingTabsHidesTheBarAndKeepsItsTextSwitchingBackShowsIt() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    XCTAssertTrue(rig.controller.engineHost.perform(.findNext, disposition: .currentTab))
    XCTAssertEqual(rig.bar.countLabel.stringValue, "2 of 3")

    rig.controller.activate(node: rig.nodes[1])
    XCTAssertTrue(rig.bar.isHidden, "the other tab has no bar")

    rig.controller.activate(node: rig.nodes[0])
    XCTAssertFalse(rig.bar.isHidden)
    XCTAssertEqual(rig.bar.field.stringValue, "nee")
    XCTAssertEqual(rig.bar.countLabel.stringValue, "2 of 3")
  }

  func testEachTabKeepsItsOwnText() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    rig.controller.activate(node: rig.nodes[1])
    open(rig)
    XCTAssertEqual(rig.bar.field.stringValue, "", "a tab's bar starts empty")
    try await search("fill", in: rig)
    XCTAssertEqual(rig.bar.countLabel.stringValue, "1 of 4")

    rig.controller.activate(node: rig.nodes[0])
    XCTAssertEqual(rig.bar.field.stringValue, "nee")
    rig.controller.activate(node: rig.nodes[1])
    XCTAssertEqual(rig.bar.field.stringValue, "fill")
  }

  func testMovingATabToAnotherWindowClosesItsBar() async throws {
    let (sidebar, nodes) = try makeSidebar(occurrences: 3)
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    sets.append(set)
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    let sleeper = Sleeper()
    first.findBar.sleep = { try await sleeper.sleep($0) }
    second.findBar.sleep = { try await sleeper.sleep($0) }
    first.activate(node: nodes[0])
    let tab = try XCTUnwrap(first.currentTab)
    XCTAssertTrue(first.engineHost.perform(.find, disposition: .currentTab))
    let firstBar = try XCTUnwrap(first.rootView.card.findBarView)
    let editor = try XCTUnwrap(first.window?.firstResponder as? NSTextView)
    for character in "nee" { editor.insertText(String(character), replacementRange: editor.selectedRange()) }
    await until("the debounce timer is parked") { await sleeper.parkedCount == 1 }
    await sleeper.resumeNext()
    await until("the count") { firstBar.countLabel.stringValue == "1 of 3" }
    XCTAssertTrue(first.engineHost.perform(.findNext, disposition: .currentTab))
    XCTAssertEqual(firstBar.countLabel.stringValue, "2 of 3")

    second.activate(node: nodes[0])

    XCTAssertEqual(second.currentTab, tab, "the same page moved")
    XCTAssertTrue(firstBar.isHidden, "the window it left shows no bar")
    XCTAssertFalse(first.findBar.isOpen(tab))
    let secondBar = try XCTUnwrap(second.rootView.card.findBarView)
    XCTAssertTrue(secondBar.isHidden, "the window it came to shows none either")
    XCTAssertFalse(second.findBar.isOpen(tab))

    // The engine ended the find with the move: the same search there starts at the first match again.
    XCTAssertTrue(second.engineHost.perform(.find, disposition: .currentTab))
    let secondEditor = try XCTUnwrap(second.window?.firstResponder as? NSTextView)
    for character in "nee" { secondEditor.insertText(String(character), replacementRange: secondEditor.selectedRange()) }
    await until("the debounce timer is parked") { await sleeper.parkedCount == 1 }
    await sleeper.resumeNext()
    await until("the count") { secondBar.countLabel.stringValue != "" }
    XCTAssertEqual(secondBar.countLabel.stringValue, "1 of 3")
  }

  func testClosingTheTabDropsItsBar() async throws {
    let rig = try makeRig(occurrences: 3)
    open(rig)
    try await search("nee", in: rig)
    let tab = try XCTUnwrap(rig.controller.currentTab)

    rig.engine.closeTab(tab, mode: .skipUnloadHandlers)

    XCTAssertFalse(rig.presenter.isOpen(tab))
    XCTAssertTrue(rig.bar.isHidden)
  }

  // MARK: Motion

  func testOpeningFadesAndRisesAndASecondOpenDoesNotReplayIt() throws {
    let rig = try makeRig()
    rig.bar.reduceMotion = { false }
    open(rig)
    let layer = try XCTUnwrap(rig.bar.layer)
    XCTAssertNotNil(layer.animation(forKey: FindBarView.fadeKey))
    XCTAssertNotNil(layer.animation(forKey: FindBarView.riseKey))
    let fade = try XCTUnwrap(layer.animation(forKey: FindBarView.fadeKey) as? CABasicAnimation)
    XCTAssertEqual(fade.duration, 0.12)
    XCTAssertEqual(rig.bar.alphaValue, 1, "the model value is the end state: nothing waits for the animation")

    layer.removeAllAnimations()
    open(rig)
    XCTAssertNil(layer.animation(forKey: FindBarView.fadeKey), "skipped if it is already open")
    XCTAssertNil(layer.animation(forKey: FindBarView.riseKey))
  }

  func testReduceMotionOpensWithTheFadeOnly() throws {
    let rig = try makeRig()
    rig.bar.reduceMotion = { true }
    open(rig)
    let layer = try XCTUnwrap(rig.bar.layer)
    XCTAssertNotNil(layer.animation(forKey: FindBarView.fadeKey))
    XCTAssertNil(layer.animation(forKey: FindBarView.riseKey), "no movement")
  }

  func testClosingIsInstant() async throws {
    let rig = try makeRig(occurrences: 3)
    rig.bar.reduceMotion = { false }
    open(rig)
    try await search("nee", in: rig)
    rig.bar.layer?.removeAllAnimations()
    try rig.window.sendEvent(key(kVK_Escape, in: rig.window, "\u{1B}"))
    XCTAssertTrue(rig.bar.isHidden)
    XCTAssertTrue(rig.bar.layer?.animationKeys()?.isEmpty ?? true)
  }

  func testNoMatchesNudgesTheFieldOnceAndReduceMotionDoesNot() async throws {
    let rig = try makeRig()
    rig.bar.reduceMotion = { false }
    open(rig)
    try await search("zzz", in: rig)
    let nudge = try XCTUnwrap(rig.bar.field.layer?.animation(forKey: FindBarView.nudgeKey) as? CAKeyframeAnimation)
    XCTAssertEqual(nudge.duration, 0.24)
    XCTAssertEqual(nudge.values as? [Double], [0, -3, 3, -2, 0])

    rig.bar.field.layer?.removeAllAnimations()
    try type("z", into: rig)
    await until("the next timer is parked") { await rig.sleeper.parkedCount == 1 }
    await rig.sleeper.resumeNext()
    await until("the reply") { rig.presenter.pendingSearches == 0 }
    XCTAssertNil(rig.bar.field.layer?.animation(forKey: FindBarView.nudgeKey), "still no matches: no second nudge")

    let quiet = try makeRig()
    quiet.bar.reduceMotion = { true }
    open(quiet)
    try await search("zzz", in: quiet)
    XCTAssertNil(quiet.bar.field.layer?.animation(forKey: FindBarView.nudgeKey))
  }

  // MARK: Light, dark, accessibility

  func testTheSurfaceAndTextFollowLightAndDark() throws {
    let rig = try makeRig()
    open(rig)
    for (name, flavor) in [(NSAppearance.Name.aqua, ThemeFlavor.light), (.darkAqua, .dark)] {
      rig.bar.appearance = NSAppearance(named: name)
      rig.bar.viewDidChangeEffectiveAppearance()
      XCTAssertEqual(rig.bar.surfaceLayer.backgroundColor, BrandTokens.surfaceBrand.resolve(flavor).cgColor, "\(flavor)")
      XCTAssertEqual(rig.bar.surfaceLayer.borderColor, ShellTokens.overlayEdge.resolve(flavor).cgColor, "\(flavor)")
      XCTAssertEqual(rig.bar.field.textColor, ShellTokens.primaryText.resolve(flavor).nsColor(), "\(flavor)")
      XCTAssertEqual(rig.bar.countLabel.textColor, ShellTokens.secondaryText.resolve(flavor).nsColor(), "\(flavor)")
    }
  }

  func testVoiceOverLabels() throws {
    let rig = try makeRig()
    let bar = rig.bar
    XCTAssertEqual(bar.accessibilityLabel(), "Find in page")
    XCTAssertEqual(bar.accessibilityRole(), .group)
    XCTAssertEqual(bar.accessibilityRoleDescription(), "search")
    XCTAssertEqual(bar.field.accessibilityLabel(), "Find in page")
    XCTAssertEqual(bar.field.accessibilitySubrole(), .searchField)
    for (button, label) in [(bar.previousButton, "Previous match"), (bar.nextButton, "Next match"),
                            (bar.closeButton, "Close find bar")] {
      XCTAssertTrue(button.isAccessibilityElement())
      XCTAssertEqual(button.accessibilityRole(), .button)
      XCTAssertEqual(button.accessibilityLabel(), label)
    }
    XCTAssertEqual(bar.accessibilityIdentifier(), AXID.Find.root)
    XCTAssertEqual(bar.field.accessibilityIdentifier(), AXID.Find.field)
    XCTAssertEqual(bar.countLabel.accessibilityIdentifier(), AXID.Find.count)
    XCTAssertEqual(bar.closeButton.accessibilityIdentifier(), AXID.Find.close)
    XCTAssertFalse(bar.glyphView.isAccessibilityElement(), "the magnifier is decoration")
  }

  func testTheCountIsAnnouncedAfterTheFieldSettlesAndOnEveryStep() async throws {
    let rig = try makeRig(occurrences: 3)
    var spoken: [String] = []
    rig.bar.postAnnouncement = { spoken.append($0) }
    open(rig)
    try type("nee", into: rig)
    await until("the debounce timer is parked") { await rig.sleeper.parkedCount == 1 }
    XCTAssertEqual(spoken, [], "not while typing")
    await rig.sleeper.resumeNext()
    await until("the announcement") { !spoken.isEmpty }
    rig.bar.nextButton.performClick(nil)
    XCTAssertEqual(spoken, ["1 of 3", "2 of 3"])
    XCTAssertEqual(rig.bar.countLabel.accessibilityValue() as? String ?? rig.bar.countLabel.stringValue, "2 of 3")
  }

  func testDimmedButtonsReadAsDimmed() async throws {
    let rig = try makeRig()
    open(rig)
    try await search("zzz", in: rig)
    XCTAssertFalse(rig.bar.nextButton.isAccessibilityEnabled())
    XCTAssertTrue(rig.bar.closeButton.isAccessibilityEnabled())
  }

  // MARK: Worst case

  func testALongQueryScrollsInsideTheFieldAndTheCountKeepsItsPlace() async throws {
    let rig = try makeRig()
    open(rig)
    let long = String(repeating: "needle ", count: 40)
    rig.bar.field.stringValue = long
    rig.bar.refreshLayout()
    let before = rig.bar.countLabel.frame
    XCTAssertEqual(rig.bar.frame.size, CGSize(width: 372, height: 36))
    XCTAssertEqual(rig.bar.countLabel.frame, before)
    XCTAssertLessThanOrEqual(rig.bar.field.frame.maxX, rig.bar.countLabel.frame.minX)
    XCTAssertEqual(rig.bar.field.cell?.isScrollable, true)
  }

  func testAHugeCountReadsNineHundredNinetyNinePlus() async throws {
    let (sidebar, nodes) = try makeSidebar(occurrences: 1200)
    let harness = EngineHarnessWindow(sidebar)
    harnesses.append(harness)
    let sleeper = Sleeper()
    harness.controller.findBar.sleep = { try await sleeper.sleep($0) }
    harness.controller.activate(node: nodes[0])
    let rig = Rig(harness: harness, sleeper: sleeper, nodes: nodes)
    open(rig)
    try await search("nee", in: rig)
    XCTAssertEqual(rig.bar.countLabel.stringValue, "1 of 999+")
    rig.window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(rig.bar.frame.width, 372)
    XCTAssertLessThanOrEqual(rig.bar.field.frame.maxX, rig.bar.countLabel.frame.minX)
  }

  func testCmdFInASplitDoesNothingAndTheBarHidesAndComesBack() async throws {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let page = try sidebar.addTab(url: InMemoryEngine.findPageURL(occurrences: 3, link: Self.link), title: "P",
                                  in: .today(space))
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try (0..<2).map { try sidebar.addTab(url: Self.link, title: "L\($0)", in: .split(split)) }
    let harness = EngineHarnessWindow(sidebar)
    harnesses.append(harness)
    let sleeper = Sleeper()
    harness.controller.findBar.sleep = { try await sleeper.sleep($0) }
    harness.controller.activate(node: page)
    let rig = Rig(harness: harness, sleeper: sleeper, nodes: [page])
    open(rig)
    try await search("nee", in: rig)
    XCTAssertFalse(rig.bar.isHidden)

    harness.controller.activate(node: panes[0])
    XCTAssertTrue(rig.bar.isHidden, "no bar over a split")
    XCTAssertTrue(harness.controller.engineHost.perform(.find, disposition: .currentTab),
                  "claimed: nothing falls through to the engine's own find")
    XCTAssertTrue(rig.bar.isHidden, "and nothing opens")
    XCTAssertTrue(harness.engine.executedCommands.isEmpty)

    harness.controller.activate(node: page)
    XCTAssertFalse(rig.bar.isHidden, "the bar comes back when the split ends")
    XCTAssertEqual(rig.bar.field.stringValue, "nee")
  }

  /// Keys the shell owns still reach it while the find field has the keyboard: the window offers a key to its views
  /// (the field editor takes text only), then to the main menu, as AppKit does.
  func testShellKeysStillWorkWhileTheFindFieldHasFocus() throws {
    let rig = try makeRig()
    open(rig)
    XCTAssertTrue(rig.window.firstResponder is NSTextView)
    let saved = NSApp.mainMenu
    defer { NSApp.mainMenu = saved }
    final class Probe: NSObject {
      var hits: [String] = []
      @objc func hit(_ item: NSMenuItem) { hits.append(item.title) }
    }
    let probe = Probe()
    let menu = NSMenu()
    let holder = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
    let sub = NSMenu(title: "Test")
    let items: [(String, String, NSEvent.ModifierFlags)] = [
      ("New Tab", "t", .command), ("Open Location", "l", .command),
      ("Space 1", "1", .control), ("Space 2", "2", .control), ("Space 3", "3", .control),
    ]
    for (title, key, mask) in items {
      let item = NSMenuItem(title: title, action: #selector(Probe.hit(_:)), keyEquivalent: key)
      item.keyEquivalentModifierMask = mask
      item.target = probe
      sub.addItem(item)
    }
    holder.submenu = sub
    menu.addItem(holder)
    NSApp.mainMenu = menu
    let keys: [(Int, CGEventFlags)] = [(kVK_ANSI_T, .maskCommand), (kVK_ANSI_L, .maskCommand),
                                       (kVK_ANSI_1, .maskControl), (kVK_ANSI_2, .maskControl),
                                       (kVK_ANSI_3, .maskControl)]
    for (code, flags) in keys {
      let source = CGEventSource(stateID: .privateState)
      let cg = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: true))
      cg.flags = flags
      let event = try XCTUnwrap(NSEvent(cgEvent: cg))
      _ = rig.window.performKeyEquivalent(with: event) || menu.performKeyEquivalent(with: event)
    }
    XCTAssertEqual(probe.hits, ["New Tab", "Open Location", "Space 1", "Space 2", "Space 3"])
  }

  func testFindIsDisabledWhileASplitShows() throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harnesses.append(harness)
    harness.controller.activate(node: world.panes[0])
    XCTAssertEqual(harness.controller.engineHost.claim(.find), CommandClaim(isEnabled: false),
                   "split panes are out of this change; the bar belongs to a single card")
  }
}
