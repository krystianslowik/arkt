import AppKit
import Archive
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import Motion
@testable import ShellUI

/// The close (X) on each split pane (#388, BH-121): shown on hover or keyboard focus, closes only its pane (a Today
/// pane is archived and goes on the reopen stack), and the panes left reflow on an interruptible spring; with one pane
/// left the split ends and that page grows into the single card. Reduce Motion: frames change at once under a fade.
@MainActor
final class SplitPaneCloseTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private var windows: [NSWindow] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for window in windows { window.close() }
    windows = []
  }

  // MARK: Container

  /// A 1010 x 600 container in its own window (on screen when `onScreen`, so the display link ticks).
  private func makeContainer(width: CGFloat = 1010, onScreen: Bool = false,
                             reduceMotion: Bool = true) -> SplitContainerView {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    windows.append(window)
    let container = SplitContainerView()
    container.reduceMotion = { reduceMotion }
    container.frame = NSRect(x: 0, y: 0, width: width, height: 600)
    window.contentView = NSView(frame: container.frame)
    window.contentView?.addSubview(container)
    if onScreen { window.orderFrontRegardless() }
    return container
  }

  private func page() -> NSView {
    let view = NSView(frame: .zero)
    view.wantsLayer = true
    return view
  }

  private func show(_ container: SplitContainerView, _ panes: [NSView?], animated: Bool = false) {
    container.show(panes: panes, axis: .sideBySide,
                   factors: Array(repeating: 1 / Double(panes.count), count: panes.count), animated: animated)
    container.layoutSubtreeIfNeeded()
  }

  private func hover(_ card: ContentCardView, entered: Bool) throws {
    let window = try XCTUnwrap(card.window)
    let event = try XCTUnwrap(NSEvent.enterExitEvent(
      with: entered ? .mouseEntered : .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    if entered { card.mouseEntered(with: event) } else { card.mouseExited(with: event) }
  }

  func testEveryPaneHasAHiddenCloseButtonThatTakesNoClicks() throws {
    let container = makeContainer()
    show(container, [page(), page()])
    for card in container.paneCards {
      let button = try XCTUnwrap(card.closeButton)
      XCTAssertFalse(button.isHidden, "in the accessibility tree and the key loop")
      XCTAssertFalse(button.isRevealed)
      XCTAssertEqual(button.alphaValue, 0)
      let center = card.convert(NSPoint(x: button.frame.midX, y: button.frame.midY), to: card.superview)
      XCTAssertFalse(card.hitTest(center) === button, "clicks reach the page while the X is not shown")
    }
  }

  /// Top trailing, inside the corner radius; centered in the Toolbar strip when the Toolbar shows.
  func testCloseButtonSitsAtTheTopTrailingCorner() throws {
    let container = makeContainer()
    show(container, [page(), page()])
    let card = container.paneCards[1]
    let button = try XCTUnwrap(card.closeButton)
    XCTAssertEqual(button.frame, NSRect(x: 500 - 8 - 24, y: 600 - 8 - 24, width: 24, height: 24))
    card.showsToolbar = true
    card.layoutSubtreeIfNeeded()
    XCTAssertEqual(button.frame, NSRect(x: 500 - 5 - 24, y: 600 - 4 - 24, width: 24, height: 24))
  }

  func testHoverShowsTheCloseButtonOfThatPaneOnly() throws {
    let container = makeContainer()
    show(container, [page(), page()])
    let (left, right) = (container.paneCards[0], container.paneCards[1])

    try hover(right, entered: true)
    XCTAssertEqual(right.closeButton?.isRevealed, true)
    XCTAssertEqual(right.closeButton?.alphaValue, 1, "Reduce Motion shows it at once")
    XCTAssertEqual(left.closeButton?.isRevealed, false)
    let button = try XCTUnwrap(right.closeButton)
    let center = right.convert(NSPoint(x: button.frame.midX, y: button.frame.midY), to: right.superview)
    XCTAssertTrue(right.hitTest(center) === button)

    try hover(right, entered: false)
    XCTAssertEqual(right.closeButton?.isRevealed, false)
    XCTAssertEqual(right.closeButton?.alphaValue, 0)
  }

  /// Full Keyboard Access: focusing the X shows it, and losing focus hides it again.
  func testKeyboardFocusShowsTheCloseButton() throws {
    let container = makeContainer()
    show(container, [page(), page()])
    let button = try XCTUnwrap(container.paneCards[0].closeButton)
    XCTAssertTrue(button.becomeFirstResponder())
    XCTAssertTrue(button.isRevealed)
    XCTAssertTrue(button.resignFirstResponder())
    XCTAssertFalse(button.isRevealed)
    XCTAssertEqual(button.focusRingType, .default, "the system focus ring")
  }

  func testClickingTheCloseButtonAsksToCloseItsPane() throws {
    let container = makeContainer()
    show(container, [page(), page(), page()])
    var requests: [Int] = []
    container.onCloseRequest = { requests.append($0) }
    let card = container.paneCards[2]
    try hover(card, entered: true)
    let button = try XCTUnwrap(card.closeButton)
    let center = card.convert(NSPoint(x: button.frame.midX, y: button.frame.midY), to: card.superview)
    try XCTUnwrap(card.hitTest(center) as? NSButton).performClick(nil)
    XCTAssertEqual(requests, [2])

    XCTAssertTrue(try XCTUnwrap(container.paneCards[0].closeButton).accessibilityPerformPress())
    XCTAssertEqual(requests, [2, 0], "VoiceOver presses it too, shown or not")
  }

  func testCloseButtonIsLabelledForVoiceOver() throws {
    let container = makeContainer()
    show(container, [page(), page()])
    let button = try XCTUnwrap(container.paneCards[0].closeButton)
    XCTAssertEqual(button.accessibilityLabel(), "Close Pane")
    XCTAssertEqual(button.accessibilityIdentifier(), AXID.Split.close)
    XCTAssertEqual(button.accessibilityRole(), .button)
    XCTAssertTrue(NSAccessibility.unignoredChildren(from: container.paneCards[0].accessibilityChildren() ?? [])
      .contains { ($0 as AnyObject) === button })
  }

  /// A closed pane's placeholder has no X: it has nothing to close.
  func testPlaceholderPaneHasNoCloseButton() throws {
    let container = makeContainer()
    show(container, [page(), nil])
    let card = container.paneCards[1]
    XCTAssertEqual(card.closeButton?.isHidden, true)
    try hover(card, entered: true)
    XCTAssertEqual(card.closeButton?.isRevealed, false)

    show(container, [page(), page()])
    XCTAssertEqual(card.closeButton?.isHidden, false, "the reused card gets its X back with a page")
  }

  /// A card hidden while hovered (its pane closed under the pointer) comes back unhovered when it is reused.
  func testReusedCardDoesNotKeepAStaleHover() throws {
    let container = makeContainer()
    show(container, [page(), page(), page()])
    let card = container.paneCards[2]
    try hover(card, entered: true)

    show(container, [page(), page()])
    show(container, [page(), page(), page()])

    XCTAssertTrue(container.paneCards[2] === card)
    XCTAssertEqual(card.closeButton?.isRevealed, false)
    XCTAssertEqual(card.closeButton?.alphaValue, 0)
  }

  /// A mouse-down on a shown X closes; it does not focus the pane first. Elsewhere in the pane it focuses.
  func testMouseDownOnAShownCloseButtonFocusesNoPane() throws {
    let container = makeContainer()
    show(container, [page(), page()])
    let card = container.paneCards[1]
    let button = try XCTUnwrap(card.closeButton)
    let onButton = card.convert(NSPoint(x: button.frame.midX, y: button.frame.midY), to: container)
    XCTAssertEqual(container.paneIndex(forMouseDownAt: onButton), 1, "a hidden X does not catch the click")
    try hover(card, entered: true)
    XCTAssertNil(container.paneIndex(forMouseDownAt: onButton))
    XCTAssertEqual(container.paneIndex(forMouseDownAt: NSPoint(x: 700, y: 300)), 1)
    XCTAssertEqual(container.paneIndex(forMouseDownAt: NSPoint(x: 100, y: 300)), 0)
  }

  // MARK: Reflow

  /// Reduce Motion: the panes take their new frames at once and the container crossfades.
  func testReduceMotionReflowSetsFramesAtOnceUnderAFade() throws {
    let container = makeContainer(reduceMotion: true)
    let (a, b, c) = (page(), page(), page())
    show(container, [a, b, c])

    show(container, [a, c], animated: true)

    XCTAssertFalse(container.isReflowing)
    XCTAssertEqual(container.paneCards[0].frame, NSRect(x: 0, y: 0, width: 500, height: 600))
    XCTAssertEqual(container.paneCards[1].frame, NSRect(x: 510, y: 0, width: 500, height: 600))
    XCTAssertNotNil(container.layer?.animation(forKey: SplitReflow.fadeKey))
  }

  /// Each page starts where it was on screen, even when it moved to another card, and the spring settles on the
  /// layout's frames. The model changes at once.
  func testReflowStartsFromThePagesOnScreenAndSettlesOnTheLayout() throws {
    let container = makeContainer(onScreen: true, reduceMotion: false)
    let (a, b, c) = (page(), page(), page())
    show(container, [a, b, c])
    let cFrame = container.paneCards[2].frame
    let aFrame = container.paneCards[0].frame

    show(container, [a, c], animated: true)

    XCTAssertTrue(container.isReflowing)
    XCTAssertEqual(container.paneCount, 2)
    XCTAssertEqual(container.liveFactors, [0.5, 0.5])
    XCTAssertTrue(container.paneCards[1].contentView === c)
    XCTAssertEqual(container.paneCards[1].frame, cFrame, "c starts in its old place, not in card 1's")
    XCTAssertEqual(container.paneCards[0].frame, aFrame)
    XCTAssertNil(container.layer?.animation(forKey: SplitReflow.fadeKey))

    waitUntil("the reflow settles") { !container.isReflowing }
    XCTAssertEqual(container.paneCards[0].frame, NSRect(x: 0, y: 0, width: 500, height: 600))
    XCTAssertEqual(container.paneCards[1].frame, NSRect(x: 510, y: 0, width: 500, height: 600))
    XCTAssertEqual(container.dividers[0].frame, NSRect(x: 500, y: 0, width: 10, height: 600))
  }

  /// A second close mid-flight starts from the frames on screen, not from the layout either close left. The clock is
  /// frozen and the driver stepped by hand, so the frame caught mid-flight does not depend on the machine's speed.
  func testInterruptedReflowContinuesFromTheFramesOnScreen() throws {
    let container = makeContainer(onScreen: true, reduceMotion: false)
    container.reflowClock = { 100 }
    let (a, b, c) = (page(), page(), page())
    show(container, [a, b, c])
    show(container, [a, c], animated: true)
    container.reflowDriver.tick(at: 100.06)
    let cOnScreen = container.paneCards[1].frame
    XCTAssertTrue(container.isReflowing)
    XCTAssertLessThan(cOnScreen.minX, 680, "moved from its old place")
    XCTAssertGreaterThan(cOnScreen.minX, 510, "not there yet")

    show(container, [c], animated: true)

    XCTAssertTrue(container.isReflowing)
    XCTAssertEqual(container.paneCards[0].frame, cOnScreen)
    waitUntil("the second reflow settles") { !container.isReflowing }
    XCTAssertEqual(container.paneCards[0].frame, NSRect(x: 0, y: 0, width: 1010, height: 600))
  }

  /// A plain show (switching splits, adding a pane) never animates, and ends a running reflow at the layout.
  func testUnanimatedShowEndsARunningReflow() throws {
    let container = makeContainer(onScreen: true, reduceMotion: false)
    let (a, b, c) = (page(), page(), page())
    show(container, [a, b, c])
    show(container, [a, c], animated: true)
    XCTAssertTrue(container.isReflowing)

    show(container, [a, c])

    XCTAssertFalse(container.isReflowing)
    XCTAssertEqual(container.paneCards[1].frame, NSRect(x: 510, y: 0, width: 500, height: 600))
  }

  /// A divider drag takes over from a reflow: the panes jump to the layout and follow the pointer.
  func testDividerDragEndsAReflow() throws {
    let container = makeContainer(onScreen: true, reduceMotion: false)
    let (a, b, c) = (page(), page(), page())
    show(container, [a, b, c])
    show(container, [a, c], animated: true)

    container.dividers[0].beginDrag()

    XCTAssertFalse(container.isReflowing)
    container.dividers[0].drag(to: 400)
    XCTAssertEqual(container.paneCards[0].frame.width, 400)
    container.dividers[0].endDrag()
  }

  // MARK: Window

  @MainActor
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    var archived: [UUID: ArchivedItem] = [:]

    init(_ sidebar: SidebarModel.Sidebar, reduceMotion: Bool = true) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { SplitPaneCloseTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.rootView.split.reduceMotion = { reduceMotion }
      controller.rootView.reduceMotion = { reduceMotion }
      controller.onArchive = { [unowned self] ids in
        for item in source.archive(ids, reason: .manual, at: SplitPaneCloseTests.now) { archived[item.id] = item }
      }
      controller.onReopenArchived = { [unowned self] id in
        guard let item = archived.removeValue(forKey: id), let space = source.sidebar.spaceOrder.first else {
          return nil
        }
        return try? source.restore(item, fallbackSpace: space).nodeID
      }
    }

    var split: SplitContainerView { controller.rootView.split }
    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }
    func page(_ node: UUID) -> NSView? { tab(node).flatMap { engine.contentView(for: $0) } }
    func layout() { controller.window?.contentView?.layoutSubtreeIfNeeded() }

    /// Hovers pane `index` and clicks its X.
    func clickClose(_ index: Int) throws {
      layout()
      let card = split.paneCards[index]
      let button = try XCTUnwrap(card.closeButton)
      button.reducesMotion = { true }
      card.mouseEntered(with: try XCTUnwrap(NSEvent.enterExitEvent(
        with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, trackingNumber: 0, userData: nil)))
      let center = card.convert(NSPoint(x: button.frame.midX, y: button.frame.midY), to: card.superview)
      try XCTUnwrap(card.hitTest(center) as? NSButton).performClick(nil)
    }
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  /// Today `[t0, split(s0 ... s{count-1})]`, or the split in Pinned.
  private static func makeWorld(panes count: Int, pinned: Bool = false) throws
    -> (sidebar: SidebarModel.Sidebar, split: UUID, panes: [UUID], other: UUID) {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let other = try sidebar.addTab(url: url("t0"), title: "T0", in: .today(space))
    let factors = Array(repeating: 1 / Double(count), count: count)
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: factors,
                                     in: pinned ? .pinned(space) : .today(space))
    let panes = try (0..<count).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    return (sidebar, split, panes, other)
  }

  /// The X on a pane that is not focused closes that pane only: it is archived, focus stays, the split shrinks.
  func testCloseButtonArchivesOnlyItsTodayPaneAndKeepsFocus() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let focusedTab = harness.controller.currentTab

    try harness.clickClose(2)
    waitUntil("the split shrinks to 2 panes") { harness.split.paneCount == 2 }

    XCTAssertNil(harness.source.node(world.panes[2]), "archived")
    XCTAssertEqual(harness.source.children(of: .split(world.split)), [world.panes[0], world.panes[1]])
    XCTAssertEqual(harness.controller.currentTab, focusedTab, "focus stays on the pane that had it")
    XCTAssertEqual(harness.split.focusedIndex, 0)
    XCTAssertTrue(harness.split.paneCards[1].contentView === harness.page(world.panes[1]))
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[0], world.panes[1]])
    harness.controller.close()
  }

  /// The X on the focused pane hands focus to the pane after it, as Cmd-W does.
  func testCloseButtonOnTheFocusedPaneFocusesTheNextPane() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])

    try harness.clickClose(1)
    waitUntil("the split shrinks to 2 panes") { harness.split.paneCount == 2 }

    XCTAssertEqual(harness.controller.sidebarController.current, world.panes[2])
    XCTAssertEqual(harness.split.focusedIndex, 1)
    harness.controller.close()
  }

  /// Cmd-Shift-T brings a pane closed by its X back with its page.
  func testClosedPaneGoesOnTheReopenStack() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    try harness.clickClose(2)
    waitUntil("the split shrinks to 2 panes") { harness.split.paneCount == 2 }
    XCTAssertTrue(harness.controller.canReopenClosed)

    XCTAssertTrue(harness.controller.reopenClosed())

    let reopened = try XCTUnwrap(harness.controller.currentNode)
    guard case .tab(_, let url, _)? = harness.source.node(reopened) else { return XCTFail("no tab reopened") }
    XCTAssertEqual(url, Self.url("s2"))
    XCTAssertNotNil(harness.tab(reopened))
    harness.controller.close()
  }

  /// With one pane left the split ends: the single card shows the page that stayed.
  func testCloseButtonOnATwoPaneSplitEndsTheSplit() throws {
    let world = try Self.makeWorld(panes: 2)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])

    try harness.clickClose(0)
    waitUntil("the split ends") { !harness.controller.rootView.showsSplit }

    XCTAssertNil(harness.source.node(world.split), "a split never keeps a single pane")
    XCTAssertTrue(harness.controller.rootView.card.contentView === harness.page(world.panes[1]))
    XCTAssertEqual(harness.controller.currentNode, world.panes[1])
    XCTAssertFalse(harness.controller.rootView.isCardReflowing, "Reduce Motion: no spring")
    harness.controller.close()
  }

  /// With motion on, the page left alone grows from its pane into the single card.
  func testLastPaneGrowsIntoTheSingleCard() throws {
    let world = try Self.makeWorld(panes: 2)
    let harness = Harness(world.sidebar, reduceMotion: false)
    harness.controller.window?.orderFrontRegardless()
    harness.controller.activate(node: world.panes[0])
    harness.layout()
    let paneFrame = harness.controller.rootView.convert(harness.split.paneCards[0].frame, from: harness.split)

    try harness.clickClose(1)
    waitUntil("the split ends") { !harness.controller.rootView.showsSplit }

    let card = harness.controller.rootView.card
    try PacingEnvironment.requireCaught(harness.controller.rootView.isCardReflowing
                                          && card.frame.width < harness.split.frame.width,
                                        "the card growing from the pane")
    XCTAssertGreaterThanOrEqual(card.frame.width, paneFrame.width)
    waitUntil("the card settles") { !harness.controller.rootView.isCardReflowing }
    XCTAssertEqual(card.frame, harness.split.frame)
    harness.controller.close()
  }

  /// With motion on, the panes left after a close reflow on the spring; Cmd-W (a keyboard close) does not.
  func testCloseButtonReflowsButCmdWDoesNot() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar, reduceMotion: false)
    harness.controller.window?.orderFrontRegardless()
    harness.controller.activate(node: world.panes[0])

    try harness.clickClose(1)
    waitUntil("the split shrinks to 2 panes") { harness.split.paneCount == 2 }
    try PacingEnvironment.requireCaught(harness.split.isReflowing, "the panes reflowing")
    waitUntil("the reflow settles") { !harness.split.isReflowing }

    harness.controller.closeTab(nil)                          // Cmd-W on the focused pane 0
    waitUntil("the split ends") { !harness.controller.rootView.showsSplit }
    XCTAssertFalse(harness.controller.rootView.isCardReflowing)
    harness.controller.close()
  }

  /// A Pinned pane's X closes its page and leaves the placeholder (decision 6); focus stays on the other pane.
  func testCloseButtonOnAPinnedPaneLeavesAPlaceholder() throws {
    let world = try Self.makeWorld(panes: 2, pinned: true)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    try harness.clickClose(1)

    XCTAssertNil(harness.tab(world.panes[1]))
    XCTAssertEqual(harness.source.children(of: .split(world.split)), world.panes, "the pane row stays")
    XCTAssertTrue(harness.split.paneCards[1].emptyStateView is SplitPanePlaceholderView)
    XCTAssertEqual(harness.split.paneCards[1].closeButton?.isHidden, true)
    XCTAssertEqual(harness.controller.currentNode, world.panes[0])
    XCTAssertTrue(harness.controller.canReopenClosed)
    harness.controller.close()
  }
}
