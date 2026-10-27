import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// A site's permission requests as panels over its page (#400): shown only while the tab is on screen, one per tab,
/// answered once, protected from an early press for 0.5 s on an injected clock, and taken down with no answer when the
/// engine ends them.
@MainActor
final class PermissionPresenterTests: XCTestCase {
  private var window: NSWindow!
  private var page: NSView!
  private var engine: InMemoryEngine!
  private var tab: TabID!
  private var engineWindow: EngineWindowID!
  private var presenter: PermissionPresenter!
  private var observation: EngineObservation?
  private var shown = true
  private var windowVisible = true
  /// A view the presenter points at instead of the page, for a page not yet laid out.
  private var anchorOverride: NSView?
  /// Whether the panel's window counts as on screen (not occluded, on this Space).
  private var onScreen = true
  /// The input protection's clock, in seconds.
  private var now: TimeInterval = 100

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 500), styleMask: [.titled],
                      backing: .buffered, defer: false)
    page = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    window.contentView = page
    window.orderFront(nil)
    engine = InMemoryEngine()
    engineWindow = engine.createWindow(host: StubWindowHost())
    tab = engine.createTab(url: URL(string: "arkt-test://example.com/Permission")!, in: engineWindow)
    engine.activateTab(tab)
    presenter = PermissionPresenter(engine: engine, anchor: { [unowned self] _ in anchorOverride ?? (shown ? page : nil) },
                                    windowIsVisible: { [unowned self] _ in windowVisible })
    presenter.reduceMotion = { true }
    presenter.clock = { [unowned self] in now }
    presenter.isOnScreen = { [unowned self] in onScreen }
    observation = engine.observe { [unowned self] in presenter.handle($0) }
  }

  override func tearDown() async throws {
    observation?.cancel()
    presenter.closeAll()
    window.orderOut(nil)
  }

  private func panel() throws -> DialogPanel { try XCTUnwrap(presenter.panel(for: tab)) }

  func testAnAskShowsAPanelAnchoredAtThePagesTopLeadingCornerWithTheEnginesStrings() throws {
    let id = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let panel = try panel()
    XCTAssertEqual(presenter.pending[tab]?.id, id)
    XCTAssertTrue(window.childWindows?.contains(panel.panel) == true)
    let anchor = window.convertToScreen(page.convert(page.bounds, to: nil))
    XCTAssertEqual(panel.panel.frame, panel.frame(anchoredTo: anchor))
    XCTAssertEqual(panel.content.title, "example.com wants to")
    XCTAssertEqual(panel.content.listItems, ["Know your location"])
    XCTAssertEqual(panel.view.primaryButton.title, "Allow while visiting the site")
  }

  func testThePanelDoesNotTakeKeyFocusFromThePage() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.camera]))
    XCTAssertFalse(try panel().panel.isKeyWindow)
  }

  func testEachAnswerReachesTheEngineOnceAndTakesThePanelDown() throws {
    let cases: [(String, (DialogPanel) -> Void, PermissionChoice)] = [
      ("allow", { $0.view.primaryButton.performClick(nil) }, .allow),
      ("allow this time", { $0.view.secondaryButton?.performClick(nil) }, .allowThisTime),
      ("block", { $0.view.cancelButton?.performClick(nil) }, .block),
    ]
    for (name, press, choice) in cases {
      let id = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.microphone]))
      now += 1                                                           // past the input protection
      press(try panel())
      XCTAssertEqual(engine.permissionAnswers.last?.id, id, name)
      XCTAssertEqual(engine.permissionAnswers.last?.choice, choice, name)
      XCTAssertNil(presenter.panel(for: tab), name)
      XCTAssertTrue(presenter.pending.isEmpty, name)
    }
    XCTAssertEqual(engine.permissionAnswers.count, 3)
  }

  func testEscapeDismissesWithoutChoosing() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.notifications]))
    XCTAssertTrue(try panel().view.escape())
    XCTAssertEqual(engine.permissionAnswers.map(\.choice), [.dismiss])
    XCTAssertNil(presenter.panel(for: tab))
  }

  // MARK: Input protection

  func testPressesAreIgnoredForHalfASecondAndWorkAfter() throws {
    let id = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let panel = try panel()
    for press in [{ panel.view.primaryButton.performClick(nil) }, { panel.view.secondaryButton?.performClick(nil) },
                  { panel.view.cancelButton?.performClick(nil) }] {
      press()
    }
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "a press at 0 s answers nothing")
    now += 0.49
    panel.view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "a press at 0.49 s answers nothing")
    XCTAssertNotNil(presenter.panel(for: tab))
    now += 0.02
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.permissionAnswers.map(\.id), [id], "a press at 0.51 s answers")
  }

  func testReturnIsIgnoredDuringTheProtectionAndPressesNothingAfter() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let view = try panel().view
    for button in [view.primaryButton, view.secondaryButton, view.cancelButton].compactMap({ $0 }) {
      XCTAssertEqual(button.keyEquivalent, "", "no button is the Return default")
    }
    XCTAssertFalse(view.performKeyEquivalent(with: key("\r")), "Return does nothing, protected or not")
    now += 1
    XCTAssertFalse(view.performKeyEquivalent(with: key("\r")))
    XCTAssertTrue(engine.permissionAnswers.isEmpty)
  }

  func testEscapeIsNotHeldBackByTheProtection() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    XCTAssertTrue(try panel().view.escape())
    XCTAssertEqual(engine.permissionAnswers.map(\.choice), [.dismiss])
  }

  func testEachNewPanelStartsItsOwnProtection() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    now += 1
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.camera]))             // a later ask replaces the panel
    try panel().view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "the second panel is protected from its own start")
    now += 0.6
    try panel().view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.permissionAnswers.count, 1)
  }

  func testAPanelForAPageNotLaidOutYetWaitsForItsBoundsAndProtectsFromWhenItShows() throws {
    let fresh = NSView(frame: .zero)
    page.addSubview(fresh)
    anchorOverride = fresh
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    XCTAssertNil(presenter.panel(for: tab), "never presented with empty bounds")
    now += 5                                                              // the layout arrives late
    fresh.frame = NSRect(x: 0, y: 0, width: 400, height: 300)            // the page view's own frame change
    let panel = try panel()
    panel.view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "a click at the moment it shows answers nothing")
    now += 0.49
    panel.view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "a click 0.49 s after it shows answers nothing")
    now += 0.02
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.permissionAnswers.count, 1)
  }

  func testAPanelPlacedWithEmptyBoundsHoldsItsProtectionUntilItIsLaidOut() throws {
    let panel = DialogPanel(content: .permissionRequest(
      PermissionRequest(id: PermissionRequestID(), tab: tab, origin: "example.com", kinds: [.camera],
                        title: "example.com wants to", items: ["Use your camera"], allowTitle: "Allow",
                        allowThisTimeTitle: nil, blockTitle: "Block")))
    panel.reduceMotion = { true }
    panel.clock = { [unowned self] in now }
    panel.isOnScreen = { true }
    var answers = 0
    panel.onAnswer = { _ in answers += 1 }
    panel.show(over: window, anchoredTo: .zero)
    defer { panel.close(keyboard: true) }
    now += 5
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(answers, 0, "empty bounds: not on screen, so protected however long it waits")
    panel.reposition(anchoredTo: window.frame)
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(answers, 0, "just laid out")
    now += 0.51
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(answers, 1)
  }

  func testTheProtectionIsCountedFromTheEndOfTheEntranceUnlessReduceMotion() throws {
    presenter.reduceMotion = { false }
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let panel = try panel()
    now += 0.6                                                            // past 0.5 s, inside 0.16 + 0.5 s
    panel.view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "the 0.16 s entrance is not part of the 0.5 s")
    now += 0.1
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.permissionAnswers.count, 1)
  }

  func testAnOccludedPanelIsProtectedFromTheMomentItBecomesVisible() throws {
    onScreen = false
    let id = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let panel = try panel()
    now += 5                                                              // shown long after it was placed
    panel.view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "occluded: nothing answers")
    onScreen = true
    presenter.refresh()
    panel.view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "a click right after it becomes visible is ignored")
    now += 0.2
    onScreen = false                                                      // another Space, then back
    presenter.refresh()
    now += 5
    onScreen = true
    presenter.refresh()
    panel.view.primaryButton.performClick(nil)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "every return to visible restarts the protection")
    now += 0.51
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(engine.permissionAnswers.map(\.id), [id])
  }

  private func key(_ characters: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 36)!
  }

  // MARK: Ends

  func testTheEnginesEndTakesThePanelDownWithoutAnAnswer() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let panel = try panel()
    engine.navigate(tab, to: URL(string: "arkt-test://example.com/Other")!)
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertNil(panel.panel.parent)
    XCTAssertTrue(engine.permissionAnswers.isEmpty)
    XCTAssertTrue(presenter.pending.isEmpty)
  }

  func testAClosedTabLeavesNoPanel() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.notifications]))
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertTrue(presenter.pending.isEmpty)
  }

  func testATabSwitchedAwayEndsItsPromptAndGetsANewOneBack() throws {
    let other = engine.createTab(url: URL(string: "arkt-test://example.com/Other")!, in: engineWindow)
    let first = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let firstPanel = try panel()

    engine.activateTab(other)
    XCTAssertNil(presenter.panel(for: tab), "hidden: no panel")
    XCTAssertNil(firstPanel.panel.parent)
    XCTAssertTrue(engine.permissionAnswers.isEmpty, "hiding is not an answer")

    engine.activateTab(tab)
    let back = try XCTUnwrap(presenter.pending[tab])
    XCTAssertNotEqual(back.id, first, "a new request for the same ask")
    XCTAssertNotNil(presenter.panel(for: tab))
    XCTAssertFalse(firstPanel === presenter.panel(for: tab))
  }

  func testAnAskOfATabOffScreenWaitsForAPageViewAndLeavesWithIt() throws {
    shown = false
    let id = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.camera]))
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertEqual(presenter.pending[tab]?.id, id)
    shown = true
    presenter.layoutDidFinish()
    XCTAssertNotNil(presenter.panel(for: tab), "the next layout finds the page view")
    shown = false
    presenter.refresh()
    XCTAssertNil(presenter.panel(for: tab))
    XCTAssertTrue(engine.permissionAnswers.isEmpty)
  }

  func testAMinimizedWindowShowsTheAskWhenItComesBack() throws {
    windowVisible = false
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    XCTAssertNil(presenter.panel(for: tab))
    windowVisible = true
    NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
    XCTAssertNotNil(presenter.panel(for: tab))
  }

  // MARK: Worst case, motion, light and dark, VoiceOver

  func testTheWorstCaseAskKeepsEveryAnswerInsideThePanel() throws {
    page.setFrameSize(NSSize(width: 300, height: 500))
    let longOrigin = String(repeating: "very-long-subdomain.", count: 6) + "example.com"
    let request = PermissionRequest(
      id: PermissionRequestID(), tab: tab, origin: longOrigin, kinds: Array(repeating: .other, count: 8),
      title: "\(longOrigin) wants to", items: (1..<9).map { "Use a permission with a rather long description \($0)" },
      allowTitle: "Allow while visiting the site", allowThisTimeTitle: "Allow this time", blockTitle: "Never allow")
    presenter.handle(.permissionRequested(request))
    let panel = try panel()
    XCTAssertEqual(panel.panel.frame.width, 276, "the narrow page: width minus the 12 pt inset on each side")
    for button in [panel.view.primaryButton, panel.view.secondaryButton, panel.view.cancelButton].compactMap({ $0 }) {
      XCTAssertLessThanOrEqual(button.frame.maxX, panel.view.bounds.width)
      XCTAssertLessThanOrEqual(button.frame.maxY, panel.view.bounds.height)
      XCTAssertGreaterThan(button.frame.width, 200, "stacked buttons are full width")
    }
    XCTAssertLessThan(panel.view.primaryButton.frame.minY, panel.view.secondaryButton?.frame.minY ?? 0)
    XCTAssertLessThan(panel.view.secondaryButton?.frame.minY ?? 0, panel.view.cancelButton?.frame.minY ?? 0)
  }

  func testReduceMotionPanelFadesWithoutTravel() throws {
    presenter.reduceMotion = { false }
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let moving = try panel().container.layer
    XCTAssertNotNil(moving?.animation(forKey: "dialogFade"))
    XCTAssertNotNil(moving?.animation(forKey: "dialogTransform"), "the usual entrance travels")
    presenter.closeAll()
    engine.withdrawPermission(in: tab)

    presenter.reduceMotion = { true }
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let still = try panel().container.layer
    XCTAssertNotNil(still?.animation(forKey: "dialogFade"), "Reduce Motion keeps the fade")
    XCTAssertNil(still?.animation(forKey: "dialogTransform"), "Reduce Motion has no travel")
  }

  func testLightAndDarkResolveDifferentColors() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.geolocation]))
    let view = try panel().view
    var colors: [NSColor] = []
    for name in [NSAppearance.Name.aqua, .darkAqua] {
      view.appearance = NSAppearance(named: name)
      view.viewDidChangeEffectiveAppearance()
      view.updateLayer()
      colors.append(view.titleField.textColor ?? .clear)
    }
    XCTAssertNotEqual(colors[0], colors[1], "the title follows the appearance")
  }

  func testVoiceOverHearsTheTitleTheWantsAndEveryAnswer() throws {
    _ = try XCTUnwrap(engine.askPermission(in: tab, kinds: [.camera, .microphone]))
    let panel = try panel()
    XCTAssertEqual(panel.content.announcement, "example.com wants to: Use your camera, Use your microphone")
    XCTAssertEqual(panel.panel.accessibilitySubrole(), .dialog)
    XCTAssertEqual(panel.panel.accessibilityLabel(), "example.com wants to")
    XCTAssertEqual(panel.view.accessibilityLabel(), "example.com wants to")
    XCTAssertEqual(panel.view.accessibilityHelp(), "Use your camera, Use your microphone")
    XCTAssertEqual(panel.view.primaryButton.accessibilityLabel(), "Allow while visiting the site")
    XCTAssertEqual(panel.view.secondaryButton?.accessibilityLabel(), "Allow this time")
    XCTAssertEqual(panel.view.cancelButton?.accessibilityLabel(), "Never allow")
  }
}
