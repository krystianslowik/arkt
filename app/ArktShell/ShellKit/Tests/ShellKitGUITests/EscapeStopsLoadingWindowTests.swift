import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// KB-055 (#614): an Esc the page did not use stops the page while it loads, as Cmd-. does (KB-054). Esc keeps its
/// other owners first: an open Peek, find bar, command bar, page dialog, HTML fullscreen or sheet. The engine reports
/// the unused key through `simulateUnhandledKeyDown`; nothing here waits on a clock.
@MainActor
final class EscapeStopsLoadingWindowTests: XCTestCase {
  private var harnesses: [EngineHarnessWindow] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for harness in harnesses {
      harness.controller.commandBar.hide()
      harness.controller.close()
    }
    harnesses = []
  }

  /// A window showing the first Today tab, which is still loading (the in-memory engine loads until `finishLoad`).
  private func makeWindow() throws -> (EngineHarnessWindow, EngineWorld, TabID) {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    harnesses.append(harness)
    harness.controller.activate(node: world.today[0])
    harness.controller.window?.contentView?.layoutSubtreeIfNeeded()
    let tab = try XCTUnwrap(harness.controller.currentTab)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isLoading, true, "fixture: the page is loading")
    return (harness, world, tab)
  }

  private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], _ characters: String = "\u{1b}") throws
    -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
      characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
  }

  private func stops(_ harness: EngineHarnessWindow) -> [EngineCommand] {
    harness.engine.executedCommands.map(\.command).filter { $0 == .stop }
  }

  func testEscOnALoadingPageSendsStop() throws {
    let (harness, _, tab) = try makeWindow()
    XCTAssertTrue(harness.engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertEqual(harness.engine.executedCommands.map(\.command), [.stop])
    XCTAssertEqual(harness.engine.executedCommands.first?.window, harness.controller.engineWindow)
  }

  func testEscOnAnIdlePageDoesNothingNew() throws {
    let (harness, _, tab) = try makeWindow()
    harness.engine.finishLoad(tab, title: "T0")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(harness.engine.executedCommands.isEmpty)
  }

  func testOtherKeysAndModifiedEscDoNotStop() throws {
    let (harness, _, tab) = try makeWindow()
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(36, "\r"), in: tab), "Return")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53, flags: .shift), in: tab), "Shift-Esc")
    XCTAssertTrue(harness.engine.executedCommands.isEmpty)
  }

  func testAnEscFromATabThatIsNotShownDoesNotStopTheShownOne() throws {
    let (harness, world, _) = try makeWindow()
    harness.controller.activate(node: world.today[1])
    let hidden = try XCTUnwrap(harness.controller.engineTab(of: world.today[0]))
    XCTAssertNotEqual(hidden, harness.controller.currentTab)
    XCTAssertEqual(harness.engine.snapshot(of: hidden)?.window, harness.controller.engineWindow,
                   "fixture: the hidden tab is still in the window, so its Esc reaches the host")
    XCTAssertEqual(harness.engine.snapshot(of: hidden)?.isLoading, true, "fixture: the hidden page is loading")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53), in: hidden))
    XCTAssertTrue(stops(harness).isEmpty)
  }

  func testAnOpenFindBarKeepsEsc() throws {
    let (harness, _, tab) = try makeWindow()
    XCTAssertTrue(harness.controller.engineHost.perform(.find, disposition: .currentTab))
    XCTAssertTrue(harness.controller.findBar.isOpen(tab), "fixture: the find bar is open")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(harness).isEmpty)
  }

  func testAnOpenCommandBarKeepsEsc() throws {
    let (harness, _, tab) = try makeWindow()
    harness.controller.commandBar.show(.newTab)
    XCTAssertTrue(harness.controller.commandBar.isVisible, "fixture: the command bar is open")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(harness).isEmpty)
  }

  func testAPageDialogKeepsEsc() throws {
    let (harness, _, tab) = try makeWindow()
    XCTAssertNotNil(harness.engine.raiseDialog(in: tab, kind: .alert, message: "Saved"))
    XCTAssertNotNil(harness.controller.javaScriptDialogs.pending[tab], "fixture: the dialog is pending")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(harness).isEmpty)
  }

  func testHTMLFullscreenKeepsEsc() throws {
    let (harness, _, tab) = try makeWindow()
    harness.engine.setTabFullscreen(tab, true)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isTabFullscreen, true, "fixture: the page is fullscreen")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(harness).isEmpty)
  }

  func testAnAttachedSheetKeepsEsc() throws {
    let (harness, _, tab) = try makeWindow()
    let window = try XCTUnwrap(harness.controller.window)
    let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
                         backing: .buffered, defer: true)
    window.beginSheet(sheet)
    defer { window.endSheet(sheet) }
    XCTAssertFalse(window.sheets.isEmpty, "fixture: the sheet is attached")
    XCTAssertFalse(harness.engine.simulateUnhandledKeyDown(try key(53), in: tab))
    XCTAssertTrue(stops(harness).isEmpty)
  }
}
