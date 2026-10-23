import AppKit
import XCTest
@testable import ShellUI

/// Space events reach the pager: a Space added after launch (first run: the window starts with no Space), renamed,
/// rethemed, moved or removed.
@MainActor
final class SpaceListChangeTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testAddedSpaceBecomesCurrentOnAnEmptySidebar() throws {
    let stub = StubSidebar()
    let controller = SidebarController(source: stub)
    XCTAssertNil(controller.currentSpace)
    XCTAssertNil(controller.currentPage)
    var changed: [[SpaceID]] = []
    var currentAtCall: [SpaceID?] = []
    controller.onSpacesChanged = { [unowned controller] in
      changed.append($0)
      currentAtCall.append(controller.currentSpace)
    }

    let space = stub.addSpace(title: "Space")
    stub.addTab(url: try XCTUnwrap(URL(string: "https://example.com")), title: "Example", in: .today(space))

    XCTAssertEqual(controller.currentSpace, space)
    let page = try XCTUnwrap(controller.currentPage)
    XCTAssertEqual(page.outlineController.spaceID, space)
    XCTAssertEqual(changed, [[space]])
    XCTAssertEqual(currentAtCall, [space], "onSpacesChanged must fire after the current Space settles")
    XCTAssertEqual(controller.view.spaceDots.titles, ["Space"])
  }

  func testRenameAndThemeChangeRefreshLivePages() throws {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "Old")
    let other = stub.addSpace(title: "Other")
    let controller = SidebarController(source: stub)
    let page = try XCTUnwrap(controller.currentPage)
    XCTAssertEqual(page.flavor, .light)
    var changed: [[SpaceID]] = []
    controller.onSpacesChanged = { changed.append($0) }

    stub.renameSpace(space, to: "New")
    XCTAssertEqual(controller.currentPage?.titleLabel.stringValue, "New")
    XCTAssertEqual(controller.view.spaceDots.titles, ["New", "Other"])
    XCTAssertEqual(changed, [[space, other]])

    stub.setTheme(SpaceThemeInfo(baseColors: [], isDark: true), of: space)
    XCTAssertEqual(controller.currentPage?.flavor, .dark)
    XCTAssertEqual(controller.view.flavor, .dark)
    XCTAssertEqual(changed.count, 2)
  }

  func testRemovingTheLastSpaceClearsTheCurrentSpace() throws {
    let stub = StubSidebar()
    let space = stub.addSpace(title: "Only")
    let controller = SidebarController(source: stub)
    XCTAssertEqual(controller.currentSpace, space)
    var changed: [[SpaceID]] = []
    var currentAtCall: [SpaceID?] = []
    controller.onSpacesChanged = { [unowned controller] in
      changed.append($0)
      currentAtCall.append(controller.currentSpace)
    }

    stub.removeSpace(space)
    XCTAssertNil(controller.currentSpace)
    XCTAssertNil(controller.currentPage)
    XCTAssertNil(controller.view.currentPage)
    XCTAssertEqual(changed, [[]])
    XCTAssertEqual(currentAtCall, [nil], "onSpacesChanged must not see the removed Space as current")
  }

  func testRemovingTheCurrentSpaceSettlesOnTheFirstBeforeNotifying() throws {
    let stub = StubSidebar()
    let first = stub.addSpace(title: "First")
    let second = stub.addSpace(title: "Second")
    let controller = SidebarController(source: stub)
    controller.showSpace(second)
    XCTAssertEqual(controller.currentSpace, second)
    var changed: [[SpaceID]] = []
    var currentAtCall: [SpaceID?] = []
    controller.onSpacesChanged = { [unowned controller] in
      changed.append($0)
      currentAtCall.append(controller.currentSpace)
    }

    stub.removeSpace(second)
    XCTAssertEqual(controller.currentSpace, first)
    XCTAssertEqual(changed, [[first]])
    XCTAssertEqual(currentAtCall, [first])
  }

  /// The Space that slides into the removed one's place becomes current [I].
  func testRemovingTheCurrentSpaceShowsTheNextSpace() throws {
    let stub = StubSidebar()
    let spaces = ["A", "B", "C"].map { stub.addSpace(title: $0) }
    let controller = SidebarController(source: stub)
    controller.showSpace(spaces[1])
    var currentAtCall: [SpaceID?] = []
    controller.onSpacesChanged = { [unowned controller] _ in currentAtCall.append(controller.currentSpace) }

    stub.removeSpace(spaces[1])
    XCTAssertEqual(controller.currentSpace, spaces[2])
    XCTAssertEqual(controller.view.spaceDots.selectedIndex, 1)
    XCTAssertEqual(controller.view.spaceDots.titles, ["A", "C"])
    XCTAssertEqual(currentAtCall, [spaces[2]])
  }

  /// With no Space after it, the one before the removed Space becomes current.
  func testRemovingTheCurrentLastSpaceShowsThePreviousSpace() throws {
    let stub = StubSidebar()
    let spaces = ["A", "B", "C"].map { stub.addSpace(title: $0) }
    let controller = SidebarController(source: stub)
    controller.showSpace(spaces[2])

    stub.removeSpace(spaces[2])
    XCTAssertEqual(controller.currentSpace, spaces[1])
    XCTAssertEqual(controller.view.spaceDots.selectedIndex, 1)
  }

  func testRemovingAnotherSpaceKeepsTheCurrentSpace() throws {
    let stub = StubSidebar()
    let spaces = ["A", "B", "C"].map { stub.addSpace(title: $0) }
    let controller = SidebarController(source: stub)
    controller.showSpace(spaces[2])

    stub.removeSpace(spaces[0])
    XCTAssertEqual(controller.currentSpace, spaces[2])
    XCTAssertEqual(controller.view.spaceDots.selectedIndex, 1)
    XCTAssertEqual(controller.currentPage?.outlineController.spaceID, spaces[2])
  }

  func testMovingASpaceReordersPagesAndDotsAndKeepsTheCurrentSpace() throws {
    let stub = StubSidebar()
    let spaces = ["A", "B", "C"].map { stub.addSpace(title: $0) }
    let controller = SidebarController(source: stub)
    controller.showSpace(spaces[0])
    var changed: [[SpaceID]] = []
    controller.onSpacesChanged = { changed.append($0) }

    stub.moveSpace(spaces[0], to: 3)
    XCTAssertEqual(controller.spaces, [spaces[1], spaces[2], spaces[0]])
    XCTAssertEqual(controller.view.spaceDots.titles, ["B", "C", "A"])
    XCTAssertEqual(controller.currentSpace, spaces[0])
    XCTAssertEqual(controller.view.spaceDots.selectedIndex, 2)
    XCTAssertEqual(controller.currentPage?.outlineController.spaceID, spaces[0])
    XCTAssertEqual(changed, [[spaces[1], spaces[2], spaces[0]]])
  }

  func testRemovingTheCurrentSpaceActivatesTheRestoredTabOfTheNewCurrentSpace() throws {
    let stub = StubSidebar()
    let url = try XCTUnwrap(URL(string: "https://example.com"))
    let first = stub.addSpace(title: "First")
    let pinned = stub.addTab(url: url, title: "Pinned", in: .pinned(first))
    let second = stub.addSpace(title: "Second")
    let other = stub.addTab(url: url, title: "Other", in: .today(second))
    let controller = SidebarController(source: stub)
    controller.activate(node: other)
    XCTAssertEqual(controller.currentSpace, second)
    var activated: [NodeID] = []
    controller.onActivate = { activated.append($0) }

    stub.removeSpace(second)
    XCTAssertEqual(controller.currentSpace, first)
    XCTAssertEqual(activated, [], "activation is deferred out of change delivery")
    let restored = expectation(description: "restored tab activated")
    Task { @MainActor in
      while activated.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
      restored.fulfill()
    }
    wait(for: [restored], timeout: 2)
    XCTAssertEqual(activated, [pinned])
    XCTAssertEqual(controller.current, pinned)
  }

  func testAddingASpaceToAnEmptySidebarActivatesNothing() throws {
    let stub = StubSidebar()
    let controller = SidebarController(source: stub)
    var activated: [NodeID] = []
    controller.onActivate = { activated.append($0) }
    stub.addSpace(title: "Space")
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertEqual(activated, [])
  }
}
