import AppKit
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// Services the tests drive by hand: the Arc check, the count stream and the import answer when the test says so.
@MainActor
final class FakeOnboardingServices: OnboardingServices {
  var arcFound: Bool
  var isDefault = false
  var countsToSend: [OnboardingCounts] = [OnboardingCounts(spaces: 2, pinnedTabs: 37, favorites: 12, folders: 9)]
  var countFails = false
  var saved: [OnboardingFlow.Snapshot] = []
  var completed = 0
  var makeDefaultCalls = 0
  /// Spaces the fake import adds, with their themes.
  var importSpaces: [(String, SpaceThemeInfo)] = [
    ("Personal", SpaceThemeInfo(baseColors: [.srgb(hex: 0xF4E4EC), .srgb(hex: 0xEFA8C4)], isDark: false)),
  ]
  var importFails = false
  private var importContinuation: CheckedContinuation<Void, Never>?
  private(set) var importStarted = false
  let sidebar: StubSidebar

  init(sidebar: StubSidebar, arcFound: Bool) {
    self.sidebar = sidebar
    self.arcFound = arcFound
  }

  func checkArc() async -> Bool { arcFound }

  func countArcData() -> AsyncThrowingStream<OnboardingCounts, any Error> {
    let updates = countsToSend, fails = countFails
    return AsyncThrowingStream { continuation in
      for update in updates { continuation.yield(update) }
      if fails { continuation.finish(throwing: CocoaError(.fileReadCorruptFile)) } else { continuation.finish() }
    }
  }

  func importArcData() async -> OnboardingImportResult {
    importStarted = true
    await withCheckedContinuation { importContinuation = $0 }
    if importFails { return .failed }
    let added = importSpaces.map { sidebar.addSpace(title: $0.0, theme: $0.1) }
    return .imported(skipped: 0, addedSpaces: added)
  }

  /// Lets the running import finish.
  func finishImport() {
    importContinuation?.resume()
    importContinuation = nil
  }

  func isDefaultBrowser() -> Bool { isDefault }
  func makeDefaultBrowser() async { makeDefaultCalls += 1 }
  func saveProgress(_ snapshot: OnboardingFlow.Snapshot) { saved.append(snapshot) }
  func markCompleted() { completed += 1 }
}

/// The first run over a real shell window (onboarding spec sections 2, 6, 10 to 13): both branches to the browser,
/// Skip setup, the Name field's Escape, the arrow rules, resume, and no "Arc" in anything VoiceOver reads.
@MainActor
final class OnboardingTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private func makeWindow(_ stub: StubSidebar = StubSidebar(), height: CGFloat = 720) -> ShellWindowController {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: stub)
    controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1120, height: height), display: false)
    controller.rootView.layoutSubtreeIfNeeded()
    return controller
  }

  private func present(_ window: ShellWindowController, _ services: FakeOnboardingServices,
                       mode: OnboardingMode = .firstRun, resume: OnboardingFlow.Snapshot? = nil,
                       extensions: Bool = false) -> OnboardingController {
    let onboarding = window.presentOnboarding(
      services: services, options: .init(mode: mode, includesExtensions: extensions, resume: resume))
    onboarding.view.layoutSubtreeIfNeeded()
    spin(until: { onboarding.flow.conditions.arc != .checking })
    return onboarding
  }

  /// Runs the main run loop until `condition` holds (tasks on the main actor run meanwhile).
  @discardableResult
  private func spin(timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
  }

  /// Presses the primary button and waits for the step to change (Make default answers after the system prompt).
  private func pressPrimaryAndWait(_ onboarding: OnboardingController) {
    let before = onboarding.flow.step
    onboarding.performPrimary()
    spin { onboarding.flow.step != before || !onboarding.view.isDescendant(of: onboarding.view.window?.contentView ?? NSView()) }
  }

  private func settle(_ seconds: TimeInterval = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
  }

  private func stepView(_ onboarding: OnboardingController) throws -> OnboardingStepView {
    try XCTUnwrap(onboarding.view.stepView)
  }

  /// Every label, value and title VoiceOver can read under `element`.
  private func accessibilityStrings(_ element: Any) -> [String] {
    var strings: [String] = []
    if let view = element as? NSView {
      strings += [view.accessibilityLabel(), view.accessibilityValue() as? String, view.accessibilityTitle()]
        .compactMap { $0 }
      if let button = view as? NSButton { strings.append(button.title) }
      for child in view.accessibilityChildren() ?? [] { strings += accessibilityStrings(child) }
    }
    return strings
  }

  // MARK: - Covering the window

  func testCoversTheWindowAndDisablesWindowMenus() throws {
    let window = makeWindow()
    let onboarding = present(window, FakeOnboardingServices(sidebar: window.sidebar as! StubSidebar, arcFound: false))
    XCTAssertTrue(window.isShowingOnboarding)
    XCTAssertTrue(onboarding.view.superview === window.window?.contentView)
    XCTAssertEqual(onboarding.view.frame, window.window?.contentView?.bounds)
    XCTAssertEqual(onboarding.view.accessibilityIdentifier(), AXID.Onboarding.root)
    XCTAssertEqual(onboarding.view.accessibilityLabel(), "Welcome to Arkt")
    XCTAssertTrue(window.rootView.card.isHidden && window.rootView.sidebarContainer.isHidden)
    let item = NSMenuItem(title: "New Tab", action: #selector(ShellWindowController.newTab(_:)), keyEquivalent: "t")
    XCTAssertFalse(window.validateMenuItem(item))
    XCTAssertEqual(try stepView(onboarding).accessibilityIdentifier(), AXID.Onboarding.step("welcome"))
    XCTAssertEqual(try stepView(onboarding).primaryButton?.keyEquivalent, "\r")
    window.close()
  }

  func testWindowIsAtLeast1000By680() throws {
    let window = makeWindow(height: 500)
    window.window?.setFrame(NSRect(x: 0, y: 0, width: 800, height: 500), display: false)
    _ = present(window, FakeOnboardingServices(sidebar: window.sidebar as! StubSidebar, arcFound: false))
    let frame = try XCTUnwrap(window.window?.frame)
    let visible = try XCTUnwrap(window.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
    XCTAssertEqual(frame.width, min(1000, visible.width), accuracy: 1)
    XCTAssertGreaterThanOrEqual(frame.height, min(680, visible.height) - 1)
    window.close()
  }

  // MARK: - Arc found: import, Imported swatch, to the browser

  func testArcBranchImportsAndLandsOnTheFirstImportedSpace() throws {
    let stub = StubSidebar()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: true)
    let onboarding = present(window, services)
    onboarding.performPrimary()                                           // Get started
    XCTAssertEqual(onboarding.flow.step, .importData)
    XCTAssertTrue(spin { onboarding.flow.importPhase == .ready })
    XCTAssertEqual(onboarding.counts.pinnedTabs, 37)
    var step = try stepView(onboarding)
    XCTAssertTrue(step.primaryButton?.isEnabled == true)
    XCTAssertEqual(step.primaryButton?.accessibilityIdentifier(), AXID.Onboarding.importData)
    XCTAssertEqual(onboarding.view.progressLabel.text, "1 of 5")
    XCTAssertFalse(onboarding.view.backButton.isEnabled, "no Back on the first step")

    onboarding.performPrimary()                                           // Import
    XCTAssertTrue(spin { services.importStarted })
    XCTAssertEqual(onboarding.flow.importPhase, .importing)
    XCTAssertFalse(onboarding.view.backButton.isEnabled, "Back is hidden while importing")
    onboarding.performEscape()
    XCTAssertEqual(onboarding.flow.importPhase, .importing, "Escape is ignored while importing")
    step = try stepView(onboarding)
    XCTAssertEqual(step.primaryButton?.isEnabled, false)
    services.finishImport()
    XCTAssertTrue(spin { onboarding.flow.importPhase == .imported(skipped: 0) })
    step = try stepView(onboarding)
    XCTAssertNil(step.secondaryButton, "Imported has Continue only")
    XCTAssertEqual(step.primaryButton?.accessibilityIdentifier(), AXID.Onboarding.continueButton)
    XCTAssertEqual(stub.spaceOrder.count, 1)

    onboarding.performPrimary()                                           // Continue
    XCTAssertEqual(onboarding.flow.step, .theme)
    let theme = try XCTUnwrap(onboarding.theme)
    XCTAssertEqual(theme.selectedTitle, "Imported")
    XCTAssertEqual(theme.placeholder, "Personal")
    step = try stepView(onboarding)
    XCTAssertEqual(step.segment?.isEnabled, false, "Appearance is disabled while Imported is selected")
    XCTAssertEqual(step.swatches?.swatchViews.count, 7)
    step.swatches?.onSelect?(3)                                           // Paper
    XCTAssertEqual(onboarding.theme?.selectedTitle, "Paper")
    onboarding.performEscape()                                            // Skip restores
    XCTAssertEqual(onboarding.flow.step, .defaultBrowser)
    let imported = try XCTUnwrap(stub.spaceOrder.first)
    XCTAssertEqual(stub.space(imported)?.theme, services.importSpaces[0].1, "Skip keeps the imported look")
    XCTAssertEqual(stub.space(imported)?.title, "Personal")

    onboarding.performEscape()                                            // Not now
    XCTAssertEqual(onboarding.flow.step, .tour(tip: 1))
    for _ in 1...5 { onboarding.performPrimary() }
    XCTAssertEqual(onboarding.flow.step, .done)
    XCTAssertTrue(onboarding.view.skipButton.isEnabled == false, "Done shows an empty footer")
    onboarding.performPrimary()                                           // Start browsing
    XCTAssertTrue(spin(timeout: 3) { !window.isShowingOnboarding })
    XCTAssertNil(onboarding.view.superview)
    XCTAssertEqual(services.completed, 1)
    XCTAssertEqual(stub.spaceOrder, [imported], "no Space is added after an import")
    XCTAssertEqual(window.currentSpace, imported)
    let row = try XCTUnwrap(stub.children(of: .today(imported)).first)
    guard case .tab(_, _, let title)? = stub.node(row) else { return XCTFail("a New Tab row") }
    XCTAssertEqual(title, "New Tab")
    XCTAssertEqual(window.rowState(for: row), .current)
    XCTAssertTrue(spin { window.commandBar.isVisible }, "the command bar opens")
    XCTAssertFalse(window.rootView.card.isHidden)
    window.commandBar.hide()
    window.close()
  }

  // MARK: - No Arc: Make it yours first, a fresh Space

  func testNoArcBranchCreatesTheChosenSpace() throws {
    let stub = StubSidebar()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: false)
    let onboarding = present(window, services)
    onboarding.performPrimary()
    XCTAssertEqual(onboarding.flow.step, .theme)
    XCTAssertEqual(onboarding.view.progressLabel.text, "1 of 4")
    XCTAssertEqual(onboarding.theme?.selectedTitle, "Dune")
    XCTAssertEqual(onboarding.theme?.placeholder, "Space 1")
    let step = try stepView(onboarding)
    step.swatches?.onSelect?(3)                                           // Sage
    step.segment?.onChange?(.dark)
    step.nameField?.field.stringValue = "Work"
    step.nameField?.onChange?("Work")
    onboarding.performPrimary()                                           // Continue
    let space = try XCTUnwrap(stub.spaceOrder.first)
    XCTAssertEqual(stub.space(space)?.title, "Work")
    XCTAssertEqual(stub.space(space)?.theme, SpaceThemeCatalog.families[3].dark)
    XCTAssertEqual(onboarding.flow.step, .defaultBrowser)
    onboarding.performBack()                                              // back to Make it yours, then on again
    onboarding.performPrimary()
    XCTAssertEqual(stub.spaceOrder.count, 1, "a second visit edits the same Space")
    window.close()
  }

  func testAlreadyDefaultLeavesTheStepOutAndMakeDefaultAsksTheSystem() throws {
    let stub = StubSidebar()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: false)
    services.isDefault = true
    let onboarding = present(window, services)
    onboarding.performPrimary()
    onboarding.performPrimary()
    XCTAssertEqual(onboarding.flow.step, .tour(tip: 1))
    window.close()

    let other = makeWindow()
    let asking = FakeOnboardingServices(sidebar: other.sidebar as! StubSidebar, arcFound: false)
    let second = present(other, asking)
    second.performPrimary()
    second.performPrimary()
    XCTAssertEqual(second.flow.step, .defaultBrowser)
    second.performPrimary()                                               // Make default
    XCTAssertTrue(spin { second.flow.step == .tour(tip: 1) })
    XCTAssertEqual(asking.makeDefaultCalls, 1)
    other.close()
  }

  // MARK: - Skip setup

  func testSkipSetupCancelKeepsTheStepAndConfirmMakesSpace1InDune() throws {
    let stub = StubSidebar()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: false)
    let onboarding = present(window, services)
    var answers = [false, true]
    onboarding.confirmSkip = { answer in answer(answers.removeFirst()) }
    onboarding.performEscape()                                            // Escape on Welcome asks
    XCTAssertEqual(onboarding.flow.step, .welcome)
    XCTAssertTrue(window.isShowingOnboarding)
    onboarding.performPrimary()
    try stepView(onboarding).swatches?.onSelect?(4)                       // Blossom previewed
    onboarding.view.onSkipSetup?()                                        // confirmed
    XCTAssertTrue(spin { !window.isShowingOnboarding })
    let space = try XCTUnwrap(stub.spaceOrder.first)
    XCTAssertEqual(stub.spaceOrder.count, 1)
    XCTAssertEqual(stub.space(space)?.title, "Space 1")
    XCTAssertEqual(stub.space(space)?.theme, SpaceThemeCatalog.defaultFamily.theme(onboarding.view.appearanceModel.flavor),
                   "a confirmed Skip setup drops the preview")
    XCTAssertEqual(services.completed, 1)
    window.commandBar.hide()
    window.close()
  }

  func testSkipSetupDuringAnImportWaitsAndAddsNoSpace() throws {
    let stub = StubSidebar()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: true)
    let onboarding = present(window, services)
    onboarding.confirmSkip = { answer in answer(true) }
    onboarding.performPrimary()
    XCTAssertTrue(spin { onboarding.flow.importPhase == .ready })
    onboarding.performPrimary()
    XCTAssertTrue(spin { services.importStarted })
    onboarding.view.onSkipSetup?()
    settle(0.2)
    XCTAssertTrue(window.isShowingOnboarding, "the import finishes first")
    XCTAssertTrue(stub.spaceOrder.isEmpty)
    services.finishImport()
    XCTAssertTrue(spin { !window.isShowingOnboarding })
    XCTAssertEqual(stub.spaceOrder.count, 1, "only the imported Space")
    XCTAssertEqual(window.currentSpace, stub.spaceOrder.first)
    window.commandBar.hide()
    window.close()
  }

  func testSkipSetupAfterAFailedImportMakesSpace1() throws {
    let stub = StubSidebar()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: true)
    services.importFails = true
    let onboarding = present(window, services)
    onboarding.confirmSkip = { answer in answer(true) }
    onboarding.performPrimary()
    XCTAssertTrue(spin { onboarding.flow.importPhase == .ready })
    onboarding.performPrimary()
    XCTAssertTrue(spin { services.importStarted })
    services.finishImport()
    XCTAssertTrue(spin { onboarding.flow.importPhase == .failed })
    let step = try stepView(onboarding)
    XCTAssertEqual(step.primaryButton?.accessibilityIdentifier(), AXID.Onboarding.tryAgain)
    XCTAssertEqual(step.secondaryButton?.accessibilityIdentifier(), AXID.Onboarding.startFresh)
    onboarding.view.onSkipSetup?()
    XCTAssertTrue(spin { !window.isShowingOnboarding })
    XCTAssertEqual(stub.spaceOrder.map { stub.space($0)?.title }, ["Space 1"])
    window.commandBar.hide()
    window.close()
  }

  // MARK: - Keyboard

  func testEscapeInTheNameFieldRestoresTheValueItHadOnFocus() throws {
    let window = makeWindow()
    window.showWindow(nil)
    let onboarding = present(window, FakeOnboardingServices(sidebar: window.sidebar as! StubSidebar, arcFound: false))
    onboarding.performPrimary()
    let field = try XCTUnwrap(stepView(onboarding).nameField)
    XCTAssertTrue(window.window?.makeFirstResponder(field.field) == true)
    let editor = try XCTUnwrap(field.field.currentEditor() as? NSTextView)
    editor.insertText("Home", replacementRange: NSRange(location: 0, length: 0))
    XCTAssertEqual(onboarding.theme?.name, "Home")
    editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    XCTAssertEqual(field.field.stringValue, "")
    XCTAssertEqual(onboarding.theme?.name, "")
    XCTAssertEqual(onboarding.flow.step, .theme, "the first Escape only ends editing")
    XCTAssertTrue(window.window?.firstResponder === onboarding.view)
    onboarding.performEscape()                                            // the second Escape skips
    XCTAssertEqual(onboarding.flow.step, .defaultBrowser)
    window.close()
  }

  func testArrowsGoBackAndOnlyReturnAfterABack() throws {
    let window = makeWindow()
    let onboarding = present(window, FakeOnboardingServices(sidebar: window.sidebar as! StubSidebar, arcFound: false))
    onboarding.performPrimary()
    onboarding.performPrimary()
    XCTAssertEqual(onboarding.flow.step, .defaultBrowser)
    onboarding.performRight()
    XCTAssertEqual(onboarding.flow.step, .defaultBrowser, "Right never commits a choice")
    onboarding.view.onKey?(.left)
    XCTAssertEqual(onboarding.flow.step, .theme)
    onboarding.performRight()
    XCTAssertEqual(onboarding.flow.step, .defaultBrowser)
    window.close()
  }

  func testArrowKeysInsideTheSwatchesBelongToTheSwatches() throws {
    let window = makeWindow()
    window.showWindow(nil)
    let onboarding = present(window, FakeOnboardingServices(sidebar: window.sidebar as! StubSidebar, arcFound: false))
    onboarding.performPrimary()
    let swatches = try XCTUnwrap(stepView(onboarding).swatches)
    XCTAssertTrue(window.window?.makeFirstResponder(swatches) == true)
    let right = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.window?.windowNumber ?? 0,
      context: nil, characters: String(UnicodeScalar(NSRightArrowFunctionKey)!),
      charactersIgnoringModifiers: String(UnicodeScalar(NSRightArrowFunctionKey)!), isARepeat: false, keyCode: 124))
    swatches.keyDown(with: right)
    XCTAssertEqual(onboarding.theme?.selectedTitle, "Mist")
    XCTAssertEqual(onboarding.flow.step, .theme)
    window.close()
  }

  // MARK: - Resume and re-entry

  func testResumeStartsAtTheSavedStepAndSavesAsTheUserMovesOn() throws {
    let window = makeWindow()
    let services = FakeOnboardingServices(sidebar: window.sidebar as! StubSidebar, arcFound: false)
    let onboarding = present(window, services,
                             resume: OnboardingFlow.Snapshot(step: "default", imported: false, importSkipped: 0))
    XCTAssertEqual(onboarding.flow.step, .defaultBrowser)
    onboarding.performEscape()
    XCTAssertEqual(services.saved.last?.step, "tour-1")
    window.close()
  }

  func testResumeAfterMakeItYoursEditsTheSpaceItMadeOnBack() throws {
    let stub = StubSidebar()
    let made = stub.addSpace(title: "Work", theme: SpaceThemeCatalog.families[3].dark)   // Sage, before the quit
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: false)
    let onboarding = present(window, services,
                             resume: OnboardingFlow.Snapshot(step: "default", imported: false, importSkipped: 0))
    onboarding.performBack()
    XCTAssertEqual(onboarding.flow.step, .theme)
    XCTAssertEqual(onboarding.theme?.placeholder, "Work")
    XCTAssertEqual(onboarding.theme?.selectedTitle, "Sage")
    onboarding.performPrimary()                                           // Continue
    XCTAssertEqual(stub.spaceOrder, [made], "the resumed run edits the Space it made")
    XCTAssertEqual(stub.space(made)?.title, "Work")
    XCTAssertEqual(stub.space(made)?.theme, SpaceThemeCatalog.families[3].dark)
    window.close()
  }

  func testReentryEditsTheCurrentSpaceAndReturnsWithoutANewTab() throws {
    let stub = StubSidebar.sample()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: false)
    let space = try XCTUnwrap(window.currentSpace)
    let before = stub.children(of: .today(space)).count
    let themeBefore = stub.space(space)?.theme
    let onboarding = present(window, services, mode: .reentry)
    onboarding.performPrimary()
    XCTAssertEqual(onboarding.flow.step, .theme)
    onboarding.performEscape()                                            // Skip restores, nothing changes
    XCTAssertEqual(stub.space(space)?.theme, themeBefore)
    XCTAssertEqual(onboarding.theme?.selectedTitle, "Current", "the sample theme is none of the families")
    while onboarding.flow.step != .done { pressPrimaryAndWait(onboarding) }
    XCTAssertEqual(try stepView(onboarding).primaryButton?.title, "Back to browsing")
    onboarding.performPrimary()
    XCTAssertTrue(spin { !window.isShowingOnboarding })
    XCTAssertEqual(stub.children(of: .today(space)).count, before, "no new tab")
    XCTAssertFalse(window.commandBar.isVisible)
    XCTAssertTrue(services.saved.isEmpty && services.completed == 0)
    window.close()
  }

  // MARK: - Copy and accessibility

  func testNoVisibleStringOrLabelNamesArc() throws {
    let stub = StubSidebar()
    let window = makeWindow(stub)
    let services = FakeOnboardingServices(sidebar: stub, arcFound: true)
    let onboarding = present(window, services)
    onboarding.confirmSkip = { answer in answer(false) }
    var strings = accessibilityStrings(onboarding.view)
    onboarding.performPrimary()
    XCTAssertTrue(spin { onboarding.flow.importPhase == .ready })
    strings += accessibilityStrings(onboarding.view)
    onboarding.performPrimary()
    XCTAssertTrue(spin { services.importStarted })
    strings += accessibilityStrings(onboarding.view)
    services.finishImport()
    XCTAssertTrue(spin { onboarding.flow.importPhase == .imported(skipped: 0) })
    while onboarding.flow.step != .done {
      strings += accessibilityStrings(onboarding.view)
      pressPrimaryAndWait(onboarding)
    }
    strings += accessibilityStrings(onboarding.view)
    XCTAssertGreaterThan(strings.count, 40)
    let word = try Regex("\\bArc\\b")
    for string in strings { XCTAssertNil(string.firstMatch(of: word), string) }
    XCTAssertTrue(strings.contains("Welcome to Arkt"))
    XCTAssertTrue(strings.contains("37 pinned tabs, imported"))
    window.close()
  }

  func testRootValueReadsStepNOfTotal() throws {
    let window = makeWindow()
    let onboarding = present(window, FakeOnboardingServices(sidebar: window.sidebar as! StubSidebar, arcFound: false))
    XCTAssertEqual(onboarding.view.accessibilityValue() as? String, "")
    onboarding.performPrimary()
    XCTAssertEqual(onboarding.view.accessibilityValue() as? String, "Step 1 of 4")
    window.close()
  }

  // MARK: - Layout

  /// Nothing scrolls and nothing overlaps the footer at 1000 x 680 and 1000 x 620 (section 4, compact).
  func testEveryStepFitsAt1000By620() throws {
    for height in [680.0, 620.0] {
      let stub = StubSidebar()
      let window = makeWindow(stub, height: height)
      let services = FakeOnboardingServices(sidebar: stub, arcFound: true)
      let onboarding = window.presentOnboarding(services: services,
                                                options: .init(mode: .firstRun, includesExtensions: true))
      window.window?.setFrame(NSRect(x: 0, y: 0, width: 1000, height: height), display: false)
      onboarding.view.layoutSubtreeIfNeeded()
      spin { onboarding.flow.conditions.arc == .found }
      onboarding.performPrimary()
      spin { onboarding.flow.importPhase == .ready }
      repeat {
        let step = try stepView(onboarding)
        step.layoutSubtreeIfNeeded()
        let footerTop = onboarding.view.backButton.frame.minY
        for button in [step.secondaryButton, step.primaryButton].compactMap({ $0 }) {
          XCTAssertLessThanOrEqual(button.frame.maxY, footerTop, "\(onboarding.flow.step) at \(height)")
        }
        XCTAssertEqual(step.compact, height < 700)
        onboarding.performEscape()
        if onboarding.flow.step == .welcome { onboarding.performPrimary() }
      } while onboarding.flow.step != .done
      window.close()
    }
  }
}
