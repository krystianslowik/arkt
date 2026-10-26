import AppKit
import Archive
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Clear Today Tabs with several windows (#429): a Today tab shown in another window stays, and Undo restores exactly
/// the archived set.
@MainActor
final class ClearTodayWindowsTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  /// What the app's archive coordinator holds, so Undo can bring rows back.
  private var archivedItems: [ArchivedItem] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private func makeSet() throws -> (set: ShellWindowSet, source: ModelSidebarSource, world: EngineWorld) {
    let world = try EngineWorld.make()
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.configure = { [unowned self] controller in
      controller.onArchive = { [unowned self] ids in
        archivedItems += source.archive(ids, reason: .manual, at: EngineWorld.now)
      }
      controller.onReopenArchived = { [unowned self] id in
        guard let index = archivedItems.lastIndex(where: { $0.id == id }),
              let space = source.spaceOrder.first,
              let restored = try? source.restore(archivedItems.remove(at: index), fallbackSpace: space) else {
          return nil
        }
        return restored.nodeID
      }
    }
    sets.append(set)
    return (set, source, world)
  }

  func testClearKeepsTheTabsEveryWindowShows() throws {
    let (set, source, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    first.activate(node: world.today[0])
    second.activate(node: world.today[1])
    let before = source.children(of: .today(world.space))
    XCTAssertGreaterThan(before.count, 2)

    XCTAssertEqual(first.currentSpace, world.space)
    XCTAssertEqual(first.visibleNodes, [world.today[0]])
    XCTAssertEqual(second.visibleNodes, [world.today[1]])
    first.clearTodayTabs(nil)

    XCTAssertEqual(Set(source.children(of: .today(world.space))), [world.today[0], world.today[1]])
    XCTAssertNotNil(second.engineTab(of: world.today[1]), "the other window keeps its page")
  }

  func testUndoRestoresExactlyTheArchivedSetAcrossWindows() throws {
    let (set, source, world) = try makeSet()
    let first = set.openWindow(opensFirstTab: false)
    let second = set.openWindow(opensFirstTab: false)
    first.activate(node: world.today[0])
    second.activate(node: world.today[1])
    let before = source.children(of: .today(world.space))

    first.clearTodayTabs(nil)
    XCTAssertEqual(Set(source.children(of: .today(world.space))), [world.today[0], world.today[1]])
    first.toasts.performActionForTesting()

    XCTAssertEqual(source.children(of: .today(world.space)), before)
  }
}
