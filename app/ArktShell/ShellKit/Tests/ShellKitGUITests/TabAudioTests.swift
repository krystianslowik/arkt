import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Tab mute in a real shell window (#364, BH-126): a row whose page plays shows the audio button, a click on it
/// mutes and unmutes the tab through the engine, the pane menu's Mute toggles to Unmute, and the state goes with the
/// page when it closes.
@MainActor
final class TabAudioTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private struct World {
    var sidebar = SidebarModel.Sidebar()
    var space: UUID
    var today: [UUID]
    var split: UUID
    var panes: [UUID]
  }

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { TabAudioTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { ids in _ = source.archive(ids, reason: .manual, at: TabAudioTests.now) }
    }

    var outlineController: SidebarOutlineController? { controller.sidebarController.currentPage?.outlineController }

    func cell(_ id: UUID) throws -> SidebarTabCellView {
      let outline = try XCTUnwrap(controller.sidebarController.view.currentOutline)
      outline.layoutSubtreeIfNeeded()
      let row = try XCTUnwrap(outlineController?.row(for: id))
      return try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarTabCellView)
    }

    func rowView(_ id: UUID) throws -> SidebarRowView {
      let outline = try XCTUnwrap(controller.sidebarController.view.currentOutline)
      outline.layoutSubtreeIfNeeded()
      let row = try XCTUnwrap(outlineController?.row(for: id))
      return try XCTUnwrap(outline.rowView(atRow: row, makeIfNecessary: true) as? SidebarRowView)
    }

    func tab(_ node: UUID) throws -> TabID { try XCTUnwrap(controller.engineTab(of: node)) }

    /// Checks that a click at the button's center lands on it, then clicks it in-process.
    func clickAudio(_ id: UUID) throws {
      let button = try cell(id).audioButton
      XCTAssertFalse(button.isHidden, "the audio button is clickable while shown")
      let content = try XCTUnwrap(button.window?.contentView)
      let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
      let hit = content.hitTest(content.superview?.convert(center, from: nil) ?? center)
      XCTAssertTrue(hit === button, "a click on the audio button goes to the button")
      button.performClick(nil)
    }

    func menuTitles(_ id: UUID) throws -> [String] {
      let outline = try XCTUnwrap(outlineController)
      let row = try XCTUnwrap(outline.row(for: id))
      return try XCTUnwrap(outline.menu(forRow: row)).items.filter { !$0.isAlternate }.map(\.title)
    }

    func menuItem(_ title: String, of id: UUID) throws -> NSMenuItem {
      let outline = try XCTUnwrap(outlineController)
      let row = try XCTUnwrap(outline.row(for: id))
      return try XCTUnwrap(outline.menu(forRow: row)?.items.first { $0.title == title }, "no item \(title)")
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld() throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let today = try (0..<2).map { try sidebar.addTab(url: url("t\($0)"), title: "T\($0)", in: .today(space)) }
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    let panes = try ["l", "r"].map { try sidebar.addTab(url: url($0), title: $0, in: .split(split)) }
    return World(sidebar: sidebar, space: space, today: today, split: split, panes: panes)
  }

  // MARK: Indicator

  func testAPlayingTabShowsTheAudioButtonAndASilentOneDoesNot() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try harness.tab(world.today[0])
    XCTAssertTrue(try harness.cell(world.today[0]).audioButton.isHidden)
    XCTAssertEqual(try harness.cell(world.today[0]).audio, .silent)

    harness.engine.setAudible(tab, true)
    let cell = try harness.cell(world.today[0])
    XCTAssertEqual(cell.audio, .playing)
    XCTAssertFalse(cell.audioButton.isHidden)
    XCTAssertEqual(cell.audioButton.accessibilityLabel(), "Mute")
    XCTAssertEqual(cell.audioButton.toolTip, "Mute this tab")
    XCTAssertLessThanOrEqual(cell.titleField.frame.maxX, cell.audioButton.frame.minX, "the title ends before it")

    harness.engine.setAudible(tab, false)
    XCTAssertEqual(try harness.cell(world.today[0]).audio, .silent)
    harness.controller.close()
  }

  /// The audio button keeps its place when the hover X appears: it sits left of the X's slot.
  func testTheAudioButtonSitsLeftOfTheCloseButtonsSlot() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    harness.engine.setAudible(try harness.tab(world.today[0]), true)
    let cell = try harness.cell(world.today[0])
    cell.layoutSubtreeIfNeeded()
    let before = cell.audioButton.frame
    try harness.rowView(world.today[0]).isHovered = true
    cell.layoutSubtreeIfNeeded()
    XCTAssertEqual(cell.audioButton.frame, before, "no jump on hover")
    XCTAssertLessThanOrEqual(cell.audioButton.frame.maxX, cell.closeButton.frame.minX)
    XCTAssertLessThanOrEqual(cell.titleField.frame.maxX, cell.audioButton.frame.minX)
    harness.controller.close()
  }

  func testAClickOnTheAudioButtonMutesAndAgainUnmutes() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try harness.tab(world.today[0])
    harness.engine.setAudible(tab, true)

    try harness.clickAudio(world.today[0])
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isMuted, true)
    let cell = try harness.cell(world.today[0])
    XCTAssertEqual(cell.audio, .muted)
    XCTAssertEqual(cell.audioButton.accessibilityLabel(), "Unmute")
    XCTAssertEqual(harness.controller.currentTab, tab, "the click does not change the selection")

    try harness.clickAudio(world.today[0])
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isMuted, false)
    XCTAssertEqual(try harness.cell(world.today[0]).audio, .playing)
    harness.controller.close()
  }

  /// A muted tab that stops playing keeps its button, so it can still be unmuted.
  func testAMutedSilentTabKeepsItsButton() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try harness.tab(world.today[0])
    harness.engine.setMuted(tab, muted: true)
    XCTAssertEqual(try harness.cell(world.today[0]).audio, .muted)
    XCTAssertFalse(try harness.cell(world.today[0]).audioButton.isHidden)
    harness.controller.close()
  }

  /// The row's VoiceOver actions offer Mute or Unmute while the button shows.
  func testTheRowOffersMuteAsAnAccessibilityAction() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try harness.tab(world.today[0])
    let outline = try XCTUnwrap(harness.outlineController)
    XCTAssertFalse(outline.accessibilityActions(for: world.today[0]).map(\.name).contains("Mute"))
    harness.engine.setAudible(tab, true)
    XCTAssertTrue(outline.performAccessibilityAction(named: "Mute", on: world.today[0]))
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isMuted, true)
    XCTAssertTrue(outline.accessibilityActions(for: world.today[0]).map(\.name).contains("Unmute"))
    harness.controller.close()
  }

  /// A page that closes takes its sound state with it: the row is silent again.
  func testClosingThePageClearsTheIndicator() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[1])
    harness.controller.activate(node: world.today[0])
    let tab = try harness.tab(world.today[1])
    harness.engine.setAudible(tab, true)
    harness.engine.setMuted(tab, muted: true)
    harness.engine.engineCloseTab(tab, reason: .windowClosing)
    XCTAssertEqual(try harness.cell(world.today[1]).audio, .silent)
    harness.controller.close()
  }

  // MARK: Menus

  func testThePaneMenuMutesAndThenOffersUnmute() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.split)
    let pane = world.panes[0]
    let tab = try harness.tab(pane)
    let mute = try harness.menuItem("Mute", of: pane)
    XCTAssertTrue(mute.isEnabled)
    let target = try XCTUnwrap(mute.target)
    _ = target.perform(try XCTUnwrap(mute.action), with: mute)

    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isMuted, true)
    XCTAssertEqual(try harness.menuTitles(pane).first, "Unmute")
    let unmute = try harness.menuItem("Unmute", of: pane)
    _ = try XCTUnwrap(unmute.target).perform(try XCTUnwrap(unmute.action), with: unmute)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.isMuted, false)
    harness.controller.close()
  }

  func testAPlayingTodayTabsMenuOffersMute() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    XCTAssertFalse(try harness.menuTitles(world.today[0]).contains("Mute"))
    harness.engine.setAudible(try harness.tab(world.today[0]), true)
    XCTAssertTrue(try harness.menuTitles(world.today[0]).contains("Mute"))
    harness.controller.close()
  }
}

extension TabAudioTests {
  /// A row whose cell is reloaded (a new title) keeps its audio button at rest: no fade on a reconfigured cell.
  func testAReloadedPlayingRowKeepsItsButtonWithoutAFade() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let tab = try harness.tab(world.today[0])
    harness.engine.setAudible(tab, true)
    harness.engine.setDocumentTitle(tab, "Retitled")

    let cell = try harness.cell(world.today[0])
    XCTAssertEqual(cell.titleField.stringValue, "Retitled")
    XCTAssertEqual(cell.audio, .playing)
    XCTAssertFalse(cell.audioButton.isHidden)
    XCTAssertEqual(cell.audioButton.alphaValue, 1)
    XCTAssertNil(cell.audioButton.layer?.animation(forKey: "opacity"), "a reconfigured cell does not fade")
    harness.controller.close()
  }

  /// A recycled cell starts silent: reuse clears the previous row's sound.
  func testReuseClearsTheSound() throws {
    let cell = SidebarTabCellView(frame: NSRect(x: 0, y: 0, width: 240, height: 41))
    cell.setAudio(.playing, animated: false)
    XCTAssertFalse(cell.audioButton.isHidden)
    cell.prepareForReuse()
    XCTAssertEqual(cell.audio, .silent)
    XCTAssertTrue(cell.audioButton.isHidden)
  }
}
