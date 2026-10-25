import AppKit
import EngineAPI
import EngineAPITestSupport
import FakeEngineKit
import XCTest
@testable import ShellUI

@MainActor
final class EmptySpaceContentTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testSettlingOnEmptySpaceDetachesPageAndRestoresSameTabOnReturn() throws {
    let source = StubSidebar()
    let first = source.addSpace(title: "Space 1")
    let empty = source.addSpace(title: "Space 2")
    let url = try XCTUnwrap(URL(string: "about:blank"))
    let node = source.addTab(url: url, title: "Page", in: .today(first))
    let engine = FakeEngine()
    let controller = ShellWindowController(engine: engine, sidebar: source)
    defer { controller.close() }
    controller.rootView.layoutSubtreeIfNeeded()
    controller.pager.reduceMotionForTesting = true
    let tab = try XCTUnwrap(controller.currentTab)
    let page = try XCTUnwrap(engine.contentView(for: tab))
    var hidden: [NodeID] = []
    controller.onTabHidden = { hidden.append($0) }

    controller.sidebarController.goToSpace(at: 1)

    XCTAssertEqual(controller.currentSpace, empty)
    assertEmptyContent(controller)
    XCTAssertNil(page.superview)
    XCTAssertEqual(hidden, [node])
    XCTAssertEqual(engine.tabIDs, [tab], "switching Spaces unloads no tabs")
    XCTAssertTrue(controller.sidebarController.loadedNodes.contains(node))

    controller.sidebarController.goToSpace(at: 0)

    XCTAssertEqual(controller.currentSpace, first)
    XCTAssertEqual(controller.currentTab, tab)
    XCTAssertTrue(controller.rootView.card.contentView === page)
    XCTAssertEqual(controller.visibleNodes, [node])
    XCTAssertEqual(engine.tabIDs, [tab], "returning reuses the page")
    XCTAssertEqual(hidden, [node], "the page is hidden only once")
  }

  func testDirectSwitchToFolderOnlySpaceClearsContentAndCurrentTabNavigationCreatesThere() throws {
    let source = StubSidebar()
    let first = source.addSpace(title: "Space 1")
    let empty = source.addSpace(title: "Space 2")
    source.addFolder(title: "Folder", in: .pinned(empty))
    let url = try XCTUnwrap(URL(string: "about:blank"))
    let node = source.addTab(url: url, title: "Page", in: .today(first))
    let engine = FakeEngine()
    let controller = ShellWindowController(engine: engine, sidebar: source)
    defer { controller.close() }
    let original = try XCTUnwrap(controller.currentTab)

    controller.sidebarController.showSpace(empty)

    assertEmptyContent(controller)
    let destination = try XCTUnwrap(URL(string: "about:blank#new"))
    controller.commandBar.onOpen?(destination, .currentTab)
    let newNode = try XCTUnwrap(controller.sidebarController.current)
    XCTAssertNotEqual(newNode, node)
    XCTAssertEqual(source.spaceID(containing: newNode), empty)
    XCTAssertEqual(source.children(of: .today(empty)), [newNode])
    XCTAssertEqual(controller.engineTab(of: node), original)
    XCTAssertEqual(engine.snapshot(of: original)?.url, url, "Cmd-L must not navigate the old Space's page")
  }

  func testNewSpaceClearsAllSplitPanesAndReturningRestoresThem() throws {
    let source = StubSidebar()
    let first = source.addSpace(title: "Space 1")
    let split = source.addSplit(in: .today(first))
    let url = try XCTUnwrap(URL(string: "about:blank"))
    let panes = (0..<2).map { source.addTab(url: url, title: "Pane \($0)", in: .split(split)) }
    let engine = FakeEngine()
    let controller = ShellWindowController(engine: engine, sidebar: source)
    defer { controller.close() }
    controller.rootView.layoutSubtreeIfNeeded()
    controller.pager.reduceMotionForTesting = true
    controller.activate(node: panes[1])
    let focused = try XCTUnwrap(controller.currentTab)
    let tabs = engine.tabIDs
    let pages = try tabs.map { try XCTUnwrap(engine.contentView(for: $0)) }
    var hidden: [NodeID] = []
    controller.onTabHidden = { hidden.append($0) }

    controller.newSpace(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    XCTAssertNotEqual(controller.currentSpace, first)
    assertEmptyContent(controller)
    XCTAssertFalse(controller.rootView.showsSplit)
    XCTAssertNil(controller.splitState.split)
    XCTAssertTrue(pages.allSatisfy { $0.superview == nil })
    XCTAssertEqual(Set(hidden), Set(panes))
    XCTAssertEqual(hidden.count, panes.count)
    XCTAssertEqual(engine.tabIDs, tabs)

    controller.sidebarController.goToSpace(at: 0)

    XCTAssertTrue(controller.rootView.showsSplit)
    XCTAssertEqual(controller.currentTab, focused)
    XCTAssertEqual(controller.visibleNodes, Set(panes))
    XCTAssertEqual(engine.tabIDs, tabs)
  }

  /// An activation inside an event handler is acknowledged only after that handler returns. Selecting an empty
  /// Space in between must win over the queued acknowledgement, while later engine-initiated activations still work.
  func testQueuedActivationAcknowledgementDoesNotLeaveEmptySpaceButFutureEngineActivationsDo() throws {
    let source = StubSidebar()
    let first = source.addSpace(title: "Space 1")
    let empty = source.addSpace(title: "Space 2")
    let url = try XCTUnwrap(URL(string: "about:blank"))
    let firstNode = source.addTab(url: url, title: "First", in: .today(first))
    let secondNode = source.addTab(url: url, title: "Second", in: .today(first))
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: source)
    defer { controller.close() }
    controller.activate(node: secondNode)
    let secondTab = try XCTUnwrap(controller.currentTab)
    controller.activate(node: firstNode)
    let firstTab = try XCTUnwrap(controller.currentTab)
    let secondPage = try XCTUnwrap(engine.contentView(for: secondTab))
    let tabs = engine.tabIDs
    var acknowledgements: [TabID] = []
    var selectedEmptyBeforeAcknowledgement = false
    let observation = engine.observe { event in
      switch event {
      case .titleChanged(let tab, _) where tab == firstTab:
        controller.activate(node: secondNode)
        controller.sidebarController.showSpace(empty)
        selectedEmptyBeforeAcknowledgement = controller.currentSpace == empty && controller.currentTab == nil
        XCTAssertTrue(acknowledgements.isEmpty, "activation delivery is queued behind this handler")
      case .activeTabChanged(let tab):
        acknowledgements.append(tab)
      default:
        break
      }
    }
    defer { observation.cancel() }

    engine.setDocumentTitle(firstTab, "Queue activation")

    XCTAssertTrue(selectedEmptyBeforeAcknowledgement)
    XCTAssertEqual(acknowledgements, [secondTab], "the old shell activation acknowledgement was delivered")
    XCTAssertEqual(controller.currentSpace, empty, "the late acknowledgement must not undo the Space switch")
    assertEmptyContent(controller)
    XCTAssertNil(secondPage.superview)
    XCTAssertEqual(engine.tabIDs, tabs)

    engine.engineActivate(firstTab)
    XCTAssertEqual(controller.currentSpace, first, "a new engine activation still switches to its Space")
    XCTAssertEqual(controller.currentTab, firstTab)
    controller.sidebarController.showSpace(empty)
    assertEmptyContent(controller)
    engine.engineActivate(secondTab)
    XCTAssertEqual(controller.currentSpace, first)
    XCTAssertEqual(controller.currentTab, secondTab, "the acknowledged tab must not remain permanently suppressed")
    XCTAssertTrue(controller.rootView.card.contentView === secondPage)
  }

  func testHeldArchiveCompletionDoesNotRestoreOldSpacesSuccessorAfterSelectingEmptySpace() throws {
    var world = try EngineWorld.make()
    let empty = world.sidebar.addSpace(title: "Space 2")
    let harness = EngineHarnessWindow(world.sidebar)
    let controller = harness.controller
    defer { controller.close() }
    controller.activate(node: world.today[0])
    let held = try XCTUnwrap(controller.currentTab)
    let successor = world.today[1]
    XCTAssertNil(controller.engineTab(of: successor), "the old Space's successor has not been opened")
    harness.engine.holdClose(held)
    controller.closeTab(nil)
    XCTAssertEqual(harness.engine.snapshot(of: held)?.isClosing, true)
    XCTAssertTrue(harness.archived.isEmpty)

    controller.sidebarController.showSpace(empty)
    XCTAssertEqual(controller.currentSpace, empty)
    assertEmptyContent(controller)

    XCTAssertTrue(harness.engine.answerDialog(held, accept: true))

    XCTAssertEqual(harness.archived, [[world.today[0]]], "the requested archive still completes exactly once")
    XCTAssertNil(harness.source.node(world.today[0]))
    XCTAssertNil(harness.engine.snapshot(of: held))
    XCTAssertNotNil(harness.source.node(successor), "the sibling remains available in its own Space")
    XCTAssertEqual(controller.currentSpace, empty, "a completed close must not change the user's selected Space")
    assertEmptyContent(controller)
    XCTAssertNil(controller.engineTab(of: successor), "the hidden Space's sibling must not be opened by the close")
    XCTAssertTrue(controller.pendingArchives.isEmpty)
    XCTAssertTrue(controller.sidebarController.closingNodes.isEmpty)
  }

  /// The adapter drops events for removed handles and suppresses a return to its already reported active tab.
  /// Omitting both acknowledgements must not leave a request that swallows a later, genuine activation.
  func testRemovedIntermediateActivationDoesNotLeaveSuppressionForLaterEngineSelections() throws {
    let (controller, engine, nodes, tabs, _) = try makeActivationHarness()
    defer { controller.close() }
    let window = try XCTUnwrap(controller.engineWindow)
    controller.tabObservation?.cancel()
    controller.tabObservation = nil

    controller.activate(node: nodes[1])
    controller.activate(node: nodes[0])
    XCTAssertEqual(controller.currentNode, nodes[0])
    engine.closeTab(tabs[1], mode: .skipUnloadHandlers)
    controller.handle(.tabClosed(tabs[1], reason: .client))
    XCTAssertNil(controller.engineTab(of: nodes[1]))
    controller.tabObservation = engine.observe(window: window) { [weak controller] event in
      controller?.handle(event)
    }

    engine.engineActivate(tabs[2])
    XCTAssertEqual(controller.currentNode, nodes[2])
    XCTAssertEqual(controller.visibleNodes, [nodes[2]])
    engine.engineActivate(tabs[0])
    XCTAssertEqual(controller.currentNode, nodes[0], "a suppressed old acknowledgement must not eat a new selection")
    XCTAssertEqual(controller.visibleNodes, [nodes[0]])
    XCTAssertTrue(controller.rootView.card.contentView === engine.contentView(for: tabs[0]))
  }

  /// A genuine engine event queued before a shell request is superseded by that request. It must not discard the
  /// still-valid acknowledgement behind it, nor start a cycle of corrective activations.
  func testEarlierEngineActivationDoesNotDiscardLaterShellAcknowledgementAfterSelectingEmptySpace() throws {
    let scripts: [(earlier: [Int], requests: [Int])] = [([2], [1]), ([2], [1, 2]), ([1, 2], [1]), ([2], [])]
    for (earlier, requests) in scripts {
      let (controller, engine, nodes, tabs, empty) = try makeActivationHarness()
      defer { controller.close() }
      let window = try XCTUnwrap(controller.engineWindow)
      controller.tabObservation?.cancel()
      var delivered: [TabID] = []
      var exceededEventLimit = false
      controller.tabObservation = engine.observe(window: window) { [weak controller] event in
        if case .activeTabChanged(let tab) = event {
          delivered.append(tab)
          guard delivered.count <= 12 else {
            exceededEventLimit = true
            controller?.tabObservation?.cancel()
            return
          }
        }
        controller?.handle(event)
      }
      let observation = engine.observe { event in
        guard case .titleChanged(let tab, _) = event, tab == tabs[0] else { return }
        for index in earlier { engine.engineActivate(tabs[index]) }
        for index in requests { controller.activate(node: nodes[index]) }
        controller.sidebarController.showSpace(empty)
        XCTAssertTrue(delivered.isEmpty, "all activations are still queued behind the title handler")
      }
      defer { observation.cancel() }

      engine.setDocumentTitle(tabs[0], "Queue earlier engine selection")

      XCTAssertFalse(exceededEventLimit, "activation delivery must terminate without corrective activation loops")
      XCTAssertEqual(delivered, (earlier + requests).map { tabs[$0] }, "no corrective activation is sent back")
      XCTAssertEqual(controller.currentSpace, empty)
      assertEmptyContent(controller)
      XCTAssertEqual(engine.activeTab(in: window), (requests.last ?? earlier.last).map { tabs[$0] })
      engine.engineActivate(tabs[0])
      XCTAssertEqual(controller.currentNode, nodes[0], "a subsequent genuine activation is still followed")
      XCTAssertEqual(controller.visibleNodes, [nodes[0]])
    }
  }

  private func makeActivationHarness() throws
    -> (ShellWindowController, InMemoryEngine, [NodeID], [TabID], SpaceID) {
    let source = StubSidebar()
    let first = source.addSpace(title: "Space 1")
    let empty = source.addSpace(title: "Space 2")
    let url = try XCTUnwrap(URL(string: "about:blank"))
    let nodes = [source.addTab(url: url, title: "A", in: .today(first)),
                 source.addTab(url: url, title: "B", in: .pinned(first)),
                 source.addTab(url: url, title: "C", in: .today(first))]
    let engine = InMemoryEngine()
    let controller = ShellWindowController(engine: engine, sidebar: source)
    for node in nodes { controller.activate(node: node) }
    controller.activate(node: nodes[0])
    let tabs = try nodes.map { try XCTUnwrap(controller.engineTab(of: $0)) }
    XCTAssertEqual(controller.currentNode, nodes[0])
    return (controller, engine, nodes, tabs, empty)
  }

  func testAgreedCloseSuccessorDoesNotSuppressTheNextGenuineEngineActivation() async throws {
    let world = try EngineWorld.make()
    let harness = EngineHarnessWindow(world.sidebar)
    let controller = harness.controller
    defer { controller.close() }
    for node in world.today { controller.activate(node: node) }
    controller.activate(node: world.today[1])
    let held = try XCTUnwrap(controller.currentTab)
    let first = try XCTUnwrap(controller.engineTab(of: world.today[0]))
    harness.engine.holdClose(held)
    controller.closeTab(nil)

    XCTAssertTrue(harness.engine.answerDialog(held, accept: true))
    XCTAssertEqual(controller.currentNode, world.today[2])
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
    harness.engine.engineActivate(first)

    XCTAssertEqual(controller.currentNode, world.today[0], "agreement needs no timeout before the next activation")
    XCTAssertEqual(controller.visibleNodes, [world.today[0]])
  }

  private func assertEmptyContent(_ controller: ShellWindowController,
                                  file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(controller.currentTab, file: file, line: line)
    XCTAssertNil(controller.sidebarController.current, file: file, line: line)
    XCTAssertTrue(controller.visibleNodes.isEmpty, file: file, line: line)
    XCTAssertNil(controller.rootView.card.contentView, file: file, line: line)
    XCTAssertNil(controller.urlBar.url, file: file, line: line)
    XCTAssertNil(controller.rootView.card.toolbar.urlBar.url, file: file, line: line)
    XCTAssertFalse(controller.isShowingEmptyState, "a Space exists; this is not first run", file: file, line: line)
  }
}
