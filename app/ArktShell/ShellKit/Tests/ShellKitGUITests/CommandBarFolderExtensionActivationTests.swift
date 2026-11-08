import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@_spi(Smoke) @testable import ShellUI

/// #562: production window wiring, not a synthetic provider or callback installed by the test.
@MainActor
final class CommandBarFolderExtensionActivationTests: XCTestCase {
  private var shells: [ShellWindowController] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for shell in shells { shell.close() }
    shells.removeAll()
  }

  private func shell(engine: InMemoryEngine, source: ModelSidebarSource, node: NodeID) -> ShellWindowController {
    let shell = ShellWindowController(engine: engine, sidebar: source)
    shells.append(shell)
    shell.window?.setFrame(NSRect(x: 100, y: 100, width: 1200, height: 800), display: false)
    // Activate through the sidebar too: `show` alone changes only the content and leaves its initial Space selected.
    shell.activate(node: node)
    shell.commandBar.settings.dismissSearchSuggestionNotice()
    shell.commandBar.dismissFinisher = { $0() }
    shell.commandBar.barView.selectionMotion.drivesFramesItself = false
    shell.commandBar.barView.widthMotion.drivesFramesItself = false
    return shell
  }

  private func choose(_ kind: CommandBarResults.Kind, in bar: CommandBarController) throws {
    let row = try XCTUnwrap(bar.results.firstIndex { $0.kind == kind }, "the real window must forward this provider")
    XCTAssertTrue(bar.results[row].isActionable)
    bar.barView.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    bar.commit()
  }

  func testFolderSelectionRevealsAndExpandsItsAncestorsInItsSpace() throws {
    for inToday in [false, true] {
      var model = SidebarModel.Sidebar()
      let personal = model.addSpace(title: "Personal")
      let work = model.addSpace(title: "Work")
      let first = try model.addTab(url: URL(string: "https://personal.example.test/")!, title: "Personal", in: .today(personal))
      let workTab = try model.addTab(url: URL(string: "https://work.example.test/")!, title: "Work", in: .today(work))
      let outer = try model.addFolder(title: "Outer", in: inToday ? .today(work) : .pinned(work))
      let folder = try model.addFolder(title: "Project notes", in: .folder(outer))
      let untouched = try model.addFolder(title: "Untouched", in: .pinned(work))
      let child = try model.addTab(url: URL(string: "https://child.example.test/")!, title: "Child", in: .folder(folder))
      let source = ModelSidebarSource(sidebar: model)
      let shell = shell(engine: InMemoryEngine(), source: source, node: workTab)
      XCTAssertEqual(shell.currentSpace, work, "collapse setup belongs to the target Space")
      let outline = try XCTUnwrap(shell.sidebarController.currentPage?.outlineController)
      outline.toggleFolder(untouched, animated: false)
      outline.toggleFolder(folder, animated: false)
      outline.toggleFolder(outer, animated: false)
      XCTAssertFalse(outline.isFolderOpen(outer))
      XCTAssertFalse(outline.isFolderOpen(folder))
      XCTAssertFalse(outline.isFolderOpen(untouched), "the unrelated folder starts closed on the Work outline")
      shell.activate(node: first)
      XCTAssertEqual(shell.currentSpace, personal)
      XCTAssertFalse(outline.isFolderOpen(untouched), "switching away preserves the target outline's collapsed state")
      let snapshot = source.sidebar.snapshot(of: outer)
      let bar = shell.commandBar
      bar.show(.newTab)
      bar.setQueryForTesting("project notes")

      try choose(.folder(folder), in: bar)

      XCTAssertFalse(bar.isVisible)
      XCTAssertEqual(shell.currentSpace, work)
      let revealed = try XCTUnwrap(shell.sidebarController.currentPage?.outlineController)
      XCTAssertTrue(revealed === outline, "reveal returns to the outline whose folders were closed during setup")
      XCTAssertTrue(revealed.isFolderOpen(outer))
      XCTAssertTrue(revealed.isFolderOpen(folder))
      XCTAssertFalse(revealed.isFolderOpen(untouched), "reveal must not expand unrelated folders")
      XCTAssertGreaterThanOrEqual(revealed.row(for: folder), 0)
      XCTAssertGreaterThanOrEqual(revealed.row(for: child), 0)
      XCTAssertEqual(source.sidebar.snapshot(of: outer), snapshot, "revealing does not move or duplicate nodes")
      // A later show must collect current source data rather than a cached synthetic folder list.
      source.renameNode(folder, to: "Renamed project")
      bar.show(.newTab)
      bar.setQueryForTesting("renamed project")
      XCTAssertEqual(bar.results.first { $0.kind == .folder(folder) }?.title, "Renamed project")
      source.removeNode(outer)
      // An activation already handed off before removal must not reveal a different node.
      bar.onRevealFolder?(folder)
      XCTAssertEqual(shell.currentSpace, work)
      XCTAssertFalse(revealed.isFolderOpen(untouched))
      bar.setQueryForTesting("renamed project")
      XCTAssertFalse(bar.results.contains { $0.kind == .folder(folder) })
      bar.hide()
    }
  }

  func testExtensionSelectionInvokesTheChosenWindowsExistingAction() throws {
    var model = SidebarModel.Sidebar()
    let space = model.addSpace(title: "Work")
    let first = try model.addTab(url: URL(string: "https://first.example.test/")!, title: "First", in: .today(space))
    let second = try model.addTab(url: URL(string: "https://second.example.test/")!, title: "Second", in: .today(space))
    let source = ModelSidebarSource(sidebar: model)
    let engine = InMemoryEngine()
    let a = shell(engine: engine, source: source, node: first)
    let b = shell(engine: engine, source: source, node: second)
    let aID = try XCTUnwrap(a.engineWindow), bID = try XCTUnwrap(b.engineWindow)
    engine.setExtensionActions([.init(id: "notes-a", name: "Notes extension"),
                                .init(id: "disabled", name: "Notes disabled", isEnabled: false)], in: aID)
    engine.setExtensionActions([.init(id: "notes-b", name: "Notes extension")], in: bID)
    let tabs = engine.tabIDs
    for (host, id, action, other) in [(a, aID, "notes-a", "notes-b"), (b, bID, "notes-b", "notes-a")] {
      let bar = host.commandBar
      bar.show(.newTab)
      bar.setQueryForTesting("notes")
      XCTAssertFalse(bar.results.contains { $0.kind == .extensionAction(other) })
      XCTAssertFalse(bar.results.contains { $0.kind == .extensionAction("disabled") })
      try choose(.extensionAction(action), in: bar)
      XCTAssertFalse(bar.isVisible)
      let invocation = try XCTUnwrap(engine.ranExtensionActions.last)
      XCTAssertEqual(invocation.id, action)
      XCTAssertEqual(invocation.window, id)
      XCTAssertTrue(invocation.anchor.window === host.window, "the existing engine action needs an anchor in its host window")
    }
    XCTAssertEqual(engine.ranExtensionActions.map(\.id), ["notes-a", "notes-b"])
    XCTAssertEqual(engine.tabIDs, tabs, "extension actions must not open a search or duplicate a tab")
  }

  func testFolderProvidersExcludeOtherProfilesAndPrivateSidebarData() throws {
    var model = SidebarModel.Sidebar()
    let own = model.addSpace(title: "Work")
    let foreign = model.addSpace(title: "Other", profile: "other")
    let tab = try model.addTab(url: URL(string: "https://work.example.test/")!, title: "Work", in: .today(own))
    let visible = try model.addFolder(title: "Notes own", in: .pinned(own))
    let hidden = try model.addFolder(title: "Notes foreign", in: .pinned(foreign))
    let shell = shell(engine: InMemoryEngine(), source: ModelSidebarSource(sidebar: model), node: tab)
    let bar = shell.commandBar
    bar.show(.newTab)
    bar.setQueryForTesting("notes")
    XCTAssertTrue(bar.results.contains { $0.kind == .folder(visible) })
    XCTAssertFalse(bar.results.contains { $0.kind == .folder(hidden) })
    bar.onRevealFolder?(hidden)
    XCTAssertEqual(shell.currentSpace, own)
    bar.hide()
    shell.makeIncognito()
    bar.show(.newTab)
    bar.setQueryForTesting("notes")
    XCTAssertFalse(bar.results.contains {
      if case .folder = $0.kind { return true }
      return false
    })
  }

  func testOpenBarFollowsTheWindowsExtensionActionChanges() throws {
    var model = SidebarModel.Sidebar()
    let space = model.addSpace(title: "Work")
    let tab = try model.addTab(url: URL(string: "https://work.example.test/")!, title: "Work", in: .today(space))
    let engine = InMemoryEngine()
    let shell = shell(engine: engine, source: ModelSidebarSource(sidebar: model), node: tab)
    let id = try XCTUnwrap(shell.engineWindow)
    engine.setExtensionActions([.init(id: "notes", name: "Notes original")], in: id)
    let bar = shell.commandBar
    bar.show(.newTab)
    bar.setQueryForTesting("notes")
    XCTAssertEqual(bar.results.first { $0.kind == .extensionAction("notes") }?.title, "Notes original")

    let selected = try XCTUnwrap(bar.results.firstIndex { $0.kind == .extensionAction("notes") })
    bar.barView.table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
    engine.setExtensionActions([.init(id: "notes", name: "Notes renamed"),
                                .init(id: "added", name: "Notes added")], in: id)
    waitUntil("extension changes reach the already open query") {
      bar.results.first { $0.kind == .extensionAction("notes") }?.title == "Notes renamed"
        && bar.results.contains { $0.kind == .extensionAction("added") }
    }
    let retained = bar.barView.table.selectedRow
    let retainedResult = try XCTUnwrap(bar.results.indices.contains(retained) ? bar.results[retained] : nil)
    XCTAssertEqual(retainedResult.kind, .extensionAction("notes"), "a renamed action retains selection by ID")
    engine.setExtensionActions([.init(id: "notes", name: "Notes renamed", isEnabled: false)], in: id)
    waitUntil("disabled and removed actions leave the open query") {
      !bar.results.contains {
        if case .extensionAction = $0.kind { return true }
        return false
      }
    }
    // The real window callback also rechecks a stale action ID before reaching the engine.
    bar.onExtensionAction?("notes")
    bar.onExtensionAction?("added")
    XCTAssertTrue(engine.ranExtensionActions.isEmpty)
    XCTAssertTrue(bar.isVisible)
  }
}
