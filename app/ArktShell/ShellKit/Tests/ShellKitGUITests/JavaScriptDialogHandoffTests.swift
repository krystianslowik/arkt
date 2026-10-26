import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// A page's pending dialog follows its tab when Tab Handoff moves the tab to another window (#464): the window it
/// left has no panel, the window it reached shows the panel, and the answer reaches the engine once, from there.
@MainActor
final class JavaScriptDialogHandoffTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private struct Scene {
    let engine: InMemoryEngine
    let first: ShellWindowController
    let second: ShellWindowController
    let world: EngineWorld
    let tab: TabID
  }

  /// Two windows; the first shows Today row 0, whose page is `tab`, and has row 1's page too.
  private func makeScene() throws -> Scene {
    let world = try EngineWorld.make()
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    sets.append(set)
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    for controller in [first, second] {
      controller.window?.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 800), display: false)
      controller.window?.orderFront(nil)
      controller.javaScriptDialogs.reduceMotion = { true }
    }
    first.activate(node: world.today[1])           // the window keeps a page when row 0 leaves
    first.activate(node: world.today[0])
    let tab = try XCTUnwrap(first.currentTab)
    return Scene(engine: engine, first: first, second: second, world: world, tab: tab)
  }

  func testEachKindOfDialogMovesItsPanelWithTheTab() throws {
    for kind in [JavaScriptDialog.Kind.alert, .confirm, .prompt] {
      let scene = try makeScene()
      let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: kind, message: "Now?"))
      let oldPanel = try XCTUnwrap(scene.first.javaScriptDialogs.panel(for: scene.tab), "\(kind): up in the first window")

      scene.second.activate(node: scene.world.today[0])

      XCTAssertEqual(scene.second.currentTab, scene.tab, "\(kind): the page moved")
      XCTAssertNil(scene.first.javaScriptDialogs.panel(for: scene.tab), "\(kind): no panel left behind")
      XCTAssertNil(scene.first.javaScriptDialogs.pending[scene.tab])
      XCTAssertNil(oldPanel.panel.parent)
      XCTAssertNil(oldPanel.onAnswer)
      let panel = try XCTUnwrap(scene.second.javaScriptDialogs.panel(for: scene.tab), "\(kind): up in the second window")
      XCTAssertTrue(scene.second.window?.childWindows?.contains(panel.panel) == true)
      XCTAssertEqual(scene.second.javaScriptDialogs.pending[scene.tab]?.id, id)

      panel.view.primaryButton.performClick(nil)

      XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id], "\(kind): answered once")
      XCTAssertNil(scene.second.javaScriptDialogs.panel(for: scene.tab))
      XCTAssertTrue(scene.second.javaScriptDialogs.pending.isEmpty)
    }
  }

  func testAPromptsTypedTextSurvivesTheMove() throws {
    let scene = try makeScene()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .prompt, message: "Name?", defaultPromptText: "Ada"))
    try XCTUnwrap(scene.first.javaScriptDialogs.panel(for: scene.tab)).view.inputView?.field.stringValue = "Grace"

    scene.second.activate(node: scene.world.today[0])

    let panel = try XCTUnwrap(scene.second.javaScriptDialogs.panel(for: scene.tab))
    XCTAssertEqual(panel.inputText, "Grace")
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(scene.engine.dialogAnswers.map(\.userInput), ["Grace"])
  }

  func testTheMovedPanelFollowsTheNewWindowsWidth() throws {
    let scene = try makeScene()
    scene.second.window?.setFrame(NSRect(x: 100, y: 100, width: 420, height: 600), display: false)
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .confirm, message: "Now?"))

    scene.second.activate(node: scene.world.today[0])

    let panel = try XCTUnwrap(scene.second.javaScriptDialogs.panel(for: scene.tab))
    let card = try XCTUnwrap(scene.engine.contentView(for: scene.tab))
    let anchor = try XCTUnwrap(card.window).convertToScreen(card.convert(card.bounds, to: nil))
    XCTAssertEqual(panel.panel.frame.width, min(420, max(260, anchor.width - 2 * DialogPanel.anchorInset)))
  }

  func testTheEndOfAMovedDialogClosesItsPanelInTheNewWindow() throws {
    let scene = try makeScene()
    _ = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .alert, message: "Now?"))
    scene.second.activate(node: scene.world.today[0])
    let panel = try XCTUnwrap(scene.second.javaScriptDialogs.panel(for: scene.tab))

    scene.engine.navigate(scene.tab, to: URL(string: "arkt-test://page/Other")!)

    XCTAssertNil(scene.second.javaScriptDialogs.panel(for: scene.tab))
    XCTAssertNil(panel.panel.parent)
    XCTAssertTrue(scene.engine.dialogAnswers.isEmpty)
  }

  func testMovingTheTabBackBringsThePanelBack() throws {
    let scene = try makeScene()
    let id = try XCTUnwrap(scene.engine.raiseDialog(in: scene.tab, kind: .alert, message: "Now?"))
    scene.second.activate(node: scene.world.today[0])

    scene.first.activate(node: scene.world.today[0])

    XCTAssertNil(scene.second.javaScriptDialogs.panel(for: scene.tab))
    let panel = try XCTUnwrap(scene.first.javaScriptDialogs.panel(for: scene.tab))
    panel.view.primaryButton.performClick(nil)
    XCTAssertEqual(scene.engine.dialogAnswers.map(\.id), [id])
  }
}
