import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Little Arkt (#314): popups open in a small window with the brand frame, "Open in" moves the page into the main
/// window as the first Today tab without a reload, the window closes through the engine, several windows cascade, and
/// Reduce Motion only fades.
@MainActor
final class LittleArktWindowTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private let popupURL = URL(string: "arkt-test://page/SignIn")!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets {
      for controller in set.controllers { controller.window?.orderOut(nil) }
      for little in set.littleArkts { little.window.orderOut(nil) }
    }
    sets = []
  }

  private func makeSet(reduceMotion: Bool = false) throws
    -> (set: ShellWindowSet, engine: InMemoryEngine, world: EngineWorld) {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { reduceMotion }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return (set, engine, world)
  }

  private func popupRequest(bounds: CGRect? = nil) -> EngineWindowRequest {
    EngineWindowRequest(kind: .page, bounds: bounds, profile: EngineProfileID("default"), initialURL: popupURL,
                        isPopup: true)
  }

  private func openPopup(_ engine: InMemoryEngine, _ set: ShellWindowSet, bounds: CGRect? = nil) throws
    -> (LittleArktWindowController, EngineWindowID, TabID) {
    let id = try XCTUnwrap(engine.openEngineWindow(popupRequest(bounds: bounds)))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    return (little, id, tab)
  }

  // MARK: Open

  func testAPagePopupOpensInALittleArktWindowNotABrowserWindow() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()

    let (little, _, tab) = try openPopup(engine, set)

    XCTAssertEqual(set.controllers.count, 1, "no second browser window")
    XCTAssertTrue(little.window.isVisible)
    XCTAssertEqual(little.window.accessibilityLabel(), LittleArktCopy.windowDescription)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    XCTAssertTrue(page.isDescendant(of: little.card), "the page is mounted in the card")
    XCTAssertEqual(little.topBar.hostLabel.stringValue, "page")
    XCTAssertEqual(little.topBar.openButton.title, "Open as Tab", "a popup's action is the quiet Open as Tab")
    XCTAssertFalse(little.topBar.usesAccent)
    XCTAssertEqual(little.topBar.chooserButton.title, "", "the chevron segment draws no title")
    XCTAssertTrue(little.topBar.lockView.isHidden, "no lock for a page that is not https")
  }

  func testANormalExtensionWindowStaysABrowserWindow() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    _ = try XCTUnwrap(engine.openEngineWindow(EngineWindowRequest(kind: .extension, profile: EngineProfileID("d"))))
    XCTAssertTrue(set.littleArkts.isEmpty)
    XCTAssertEqual(set.controllers.count, 2)
  }

  func testTheWindowHasTheBrandFrameTopBarAndCard() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let (little, _, _) = try openPopup(engine, set)
    little.finishMotion()
    little.window.contentView?.layoutSubtreeIfNeeded()
    let bounds = try XCTUnwrap(little.window.contentView?.bounds)
    XCTAssertEqual(little.card.frame, LittleArktLayout.cardFrame(in: bounds))
    XCTAssertEqual(little.topBar.frame, LittleArktLayout.topBarFrame(in: bounds))
    XCTAssertTrue(CATransform3DIsIdentity(little.contentLayer?.transform ?? CATransform3DMakeScale(2, 2, 1)))
  }

  func testARequestedPageFrameIsHonoured() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
    let page = CGRect(x: visible.midX - 250, y: visible.midY - 200, width: 500, height: 400).integral
    let (little, _, _) = try openPopup(engine, set, bounds: page)
    XCTAssertEqual(little.window.frame, LittleArktLayout.frame(forRequestedPage: page, in: visible))
  }

  func testTheChooserOpensBelowTheChevron() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let (little, _, _) = try openPopup(engine, set)
    little.window.contentView?.layoutSubtreeIfNeeded()
    let chevron = little.topBar.chooserButton
    let origin = LittleArktWindowController.menuOrigin(below: chevron)
    let inWindow = chevron.convert(origin, to: nil)
    let chevronInWindow = chevron.convert(chevron.bounds, to: nil)
    XCTAssertEqual(inWindow.y, chevronInWindow.minY - 4, accuracy: 0.5, "the menu starts below the chevron")
  }

  // MARK: Cascade

  func testSeveralWindowsCascadeFromTheTopRight() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let visible = try XCTUnwrap(NSScreen.main?.visibleFrame)
    let (first, _, _) = try openPopup(engine, set)
    let (second, _, _) = try openPopup(engine, set)
    let expected = LittleArktLayout.placement(size: LittleArktLayout.defaultSize, frontmost: nil, in: visible)
    XCTAssertEqual(first.window.frame, expected)
    XCTAssertEqual(second.window.frame, expected.offsetBy(dx: -28, dy: -28))
  }

  // MARK: Open in

  func testOpenInMovesThePageToTheTopOfTodaySelected() throws {
    let (set, engine, _) = try makeSet()
    let main = set.openWindow()
    let (little, littleWindow, tab) = try openPopup(engine, set)
    let view = try XCTUnwrap(engine.contentView(for: tab))
    let space = try XCTUnwrap(main.currentSpace)

    little.openIn()
    waitUntil("the page is in the main window") { main.currentTab == tab }

    XCTAssertEqual(engine.snapshot(of: tab)?.window, main.engineWindow)
    XCTAssertTrue(engine.contentView(for: tab) === view, "the same page view, not a reload")
    XCTAssertTrue(view.isDescendant(of: main.rootView.card))
    let firstToday = main.sidebar.children(of: .today(space)).first
    XCTAssertEqual(firstToday.flatMap { main.tabsByNode[$0] }, tab)
    waitUntil("the emptied Little Arkt window closes") { !little.window.isVisible }
    XCTAssertFalse(engine.windowIDs.contains(littleWindow))
    XCTAssertTrue(set.littleArkts.isEmpty)
  }

  func testOpenInWithoutAMainWindowOpensOne() throws {
    let (set, engine, _) = try makeSet()
    let (little, _, tab) = try openPopup(engine, set)
    XCTAssertTrue(set.controllers.isEmpty)

    little.openIn()

    waitUntil("a main window opened") { !set.controllers.isEmpty }
    let main = try XCTUnwrap(set.controllers.first)
    waitUntil("the page is in the new main window") { main.currentTab == tab }
    XCTAssertEqual(engine.snapshot(of: tab)?.window, main.engineWindow)
  }

  // MARK: Close

  func testTheCloseButtonAsksTheEngineAndTheWindowGoes() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let (little, id, _) = try openPopup(engine, set)

    little.window.performClose(nil)

    waitUntil("the window closed") { !little.window.isVisible }
    XCTAssertFalse(engine.windowIDs.contains(id))
    XCTAssertTrue(set.littleArkts.isEmpty)
  }

  func testThePageClosingItsPopupFadesTheWindowOut() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let (little, id, _) = try openPopup(engine, set)

    engine.closeWindow(id)                                  // window.close() in the page

    XCTAssertEqual(little.lastTransition, .fadeOut)
    waitUntil("the faded window closed") { !little.window.isVisible }
  }

  func testCommandWClosesTheLittleArktWindow() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let (little, id, _) = try openPopup(engine, set)
    little.closeTab(nil)
    waitUntil("the window closed") { !engine.windowIDs.contains(id) }
  }

  // MARK: Motion

  func testTheAppearIsSpringDrivenOnTheContentLayerOnly() throws {
    let (set, engine, _) = try makeSet()
    _ = set.openWindow()
    let (little, _, _) = try openPopup(engine, set)
    let frame = little.window.frame
    XCTAssertEqual(little.lastTransition, .appear)
    XCTAssertTrue(little.isAnimating)
    little.finishMotion()
    XCTAssertEqual(little.window.frame, frame, "the window frame never animates")
    XCTAssertEqual(little.window.alphaValue, 1, "opacity is the window's, so its shadow fades with it")
    XCTAssertTrue(CATransform3DIsIdentity(little.contentLayer?.transform ?? CATransform3DMakeScale(2, 2, 1)))
  }

  func testReduceMotionAppearOnlyFades() throws {
    let (set, engine, _) = try makeSet(reduceMotion: true)
    _ = set.openWindow()
    let (little, _, _) = try openPopup(engine, set)
    XCTAssertTrue(CATransform3DIsIdentity(little.contentLayer?.transform ?? CATransform3DMakeScale(2, 2, 1)),
                  "no lift and no scale under Reduce Motion")
    XCTAssertLessThan(little.window.alphaValue, 1)
    little.finishMotion()
    XCTAssertEqual(little.window.alphaValue, 1)
  }

  func testAnOpenInDuringTheAppearPicksUpFromTheCurrentScene() throws {
    let (set, engine, _) = try makeSet()
    let main = set.openWindow()
    let (little, _, tab) = try openPopup(engine, set)
    XCTAssertTrue(little.isAnimating)
    little.openIn()
    XCTAssertEqual(little.lastTransition, .fadeOut)
    waitUntil("the page is in the main window") { main.currentTab == tab }
  }
}
