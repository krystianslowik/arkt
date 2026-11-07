import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// KB-055 (#757): in a Little Arkt window an Esc the page did not use stops the page while it loads, as it does in the
/// main window (#614) and as View > Stop and Cmd-. do. The window's own Esc owners keep it first: a page dialog, HTML
/// fullscreen, a sheet and the top bar's Space chooser. The engine reports the unused key through
/// `simulateUnhandledKeyDown`; the window's motion is settled by hand and nothing here waits on a clock.
@MainActor
final class LittleArktEscapeStopTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private let popupURL = URL(string: "arkt-test://page/SignIn")!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets {
      for little in set.littleArkts { little.window.orderOut(nil) }
    }
    sets = []
  }

  /// A Little Arkt popup at rest whose page is still loading (the in-memory engine loads until `finishLoad`).
  private func openPopup() throws -> (InMemoryEngine, LittleArktWindowController, EngineWindowID, TabID) {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { true }
    set.littleArktConfigure = { little in little.drivesDisplayLink = false }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: popupURL, isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    little.finishMotion()
    little.window.contentView?.layoutSubtreeIfNeeded()
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    XCTAssertEqual(little.shownTab, tab, "fixture: the window shows the popup's page")
    XCTAssertEqual(engine.snapshot(of: tab)?.isLoading, true, "fixture: the page is loading")
    return (engine, little, id, tab)
  }

  private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], _ characters: String = "\u{1b}") throws
    -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
      characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
  }

  private func stops(_ engine: InMemoryEngine) -> [EngineCommand] {
    engine.executedCommands.map(\.command).filter { $0 == .stop }
  }

  func testEscOnALoadingPageSendsStop() throws {
    let (engine, _, id, tab) = try openPopup()
    XCTAssertTrue(engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertEqual(engine.executedCommands.map(\.command), [.stop])
    XCTAssertEqual(engine.executedCommands.first?.window, id, "Stop goes to the Little Arkt window")
  }

  func testEscOnAnIdlePageDoesNothingNew() throws {
    let (engine, _, _, tab) = try openPopup()
    engine.finishLoad(tab, title: "Sign in")
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(engine.executedCommands.isEmpty)
  }

  func testOtherKeysAndModifiedEscDoNotStop() throws {
    let (engine, _, _, tab) = try openPopup()
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(36, "\r"), in: tab), "Return")
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(53, flags: .shift), in: tab), "Shift-Esc")
    XCTAssertTrue(engine.executedCommands.isEmpty)
  }

  func testAnEscFromATabThatIsNotShownDoesNotStopTheShownOne() throws {
    let (engine, little, id, tab) = try openPopup()
    let hidden = engine.createTab(url: popupURL, in: id)
    XCTAssertEqual(engine.activeTab(in: id), tab, "fixture: the new tab stays in the background")
    XCTAssertEqual(little.shownTab, tab, "fixture: the window still shows the first page")
    XCTAssertEqual(engine.snapshot(of: hidden)?.isLoading, true, "fixture: the hidden page is loading")
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(53), in: hidden))
    XCTAssertTrue(stops(engine).isEmpty)
  }

  func testAPageDialogKeepsEsc() throws {
    let (engine, little, _, tab) = try openPopup()
    XCTAssertNotNil(engine.raiseDialog(in: tab, kind: .alert, message: "Saved"))
    XCTAssertNotNil(little.javaScriptDialogs.pending[tab], "fixture: the dialog is pending")
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(engine).isEmpty)
  }

  func testHTMLFullscreenKeepsEsc() throws {
    let (engine, _, _, tab) = try openPopup()
    engine.setTabFullscreen(tab, true)
    XCTAssertEqual(engine.snapshot(of: tab)?.isTabFullscreen, true, "fixture: the page is fullscreen")
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(engine).isEmpty)
  }

  func testAnAttachedSheetKeepsEsc() throws {
    let (engine, little, _, tab) = try openPopup()
    let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
                         backing: .buffered, defer: true)
    little.window.beginSheet(sheet)
    defer { little.window.endSheet(sheet) }
    XCTAssertFalse(little.window.sheets.isEmpty, "fixture: the sheet is attached")
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(engine).isEmpty)
  }

  /// The chooser tracks as a menu, so an Esc pressed while it is up closes it. An Esc the page passed on just before
  /// it opened may still arrive while it is up; it stops nothing until the menu closes. The menu is not popped up
  /// here (tracking would block the test), its delegate is told it opened and closed.
  func testTheOpenSpaceChooserKeepsEsc() throws {
    let (engine, little, _, tab) = try openPopup()
    let menu = little.chooserMenu()
    let delegate = try XCTUnwrap(menu.delegate, "the chooser reports when it opens and closes")
    delegate.menuWillOpen?(menu)
    XCTAssertFalse(engine.simulateUnhandledKeyDown(try key(53), in: tab), "while the chooser is open")
    XCTAssertTrue(stops(engine).isEmpty)
    delegate.menuDidClose?(menu)
    XCTAssertTrue(engine.simulateUnhandledKeyDown(try key(53), in: tab), "after it closed")
    XCTAssertEqual(stops(engine), [.stop])
  }

  // MARK: The Chromium engine does not name the tab

  /// `arkt_browser_window.mm` posts the unused key with a nil tab: the Esc is the shown page's when the focus is
  /// inside that page.
  func testANilTabStopsTheShownPageWhenItHasTheFocus() throws {
    let (engine, little, _, tab) = try openPopup()
    let page = try XCTUnwrap(engine.contentView(for: tab))
    XCTAssertTrue(little.window.makeFirstResponder(page), "fixture: the page has the focus")
    XCTAssertTrue(little.engineHost.handleUnhandledKeyDown(try key(53), in: nil))
    XCTAssertEqual(engine.executedCommands.map(\.command), [.stop])
  }

  func testANilTabWithTheFocusOutsideThePageDoesNotStop() throws {
    let (engine, little, _, _) = try openPopup()
    XCTAssertTrue(little.window.makeFirstResponder(nil), "fixture: the page does not have the focus")
    XCTAssertFalse(little.engineHost.handleUnhandledKeyDown(try key(53), in: nil))
    XCTAssertTrue(stops(engine).isEmpty)
  }
}
