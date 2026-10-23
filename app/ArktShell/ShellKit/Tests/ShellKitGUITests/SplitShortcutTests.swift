import AppKit
import Carbon.HIToolbox
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Split View S5: the View menu's split items and their shortcuts (KB-070 to KB-075, BH-116, BH-117, BH-120, BH-122,
/// BH-124, BH-128). Key equivalents are checked with key events translated by the current keyboard layout, the same
/// way AppKit sees a real key press.
@MainActor
final class SplitShortcutTests: XCTestCase {
  private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// A Space with Today `[t0, split(s0 ... sN-1), t1]`.
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
    /// The View menu's split items, aimed at `controller`: a nil target finds nothing in the inactive test runner.
    let menu = NSMenu()
    var archived: [UUID] = []

    init(_ sidebar: SidebarModel.Sidebar) {
      let source = ModelSidebarSource(sidebar: sidebar, now: { SplitShortcutTests.now })
      self.source = source
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      controller.onArchive = { [unowned self] ids in
        archived += ids
        _ = source.archive(ids, reason: .manual, at: SplitShortcutTests.now)
      }
      SplitMenu.items().forEach { menu.addItem($0) }
      Self.aim(menu, at: controller)
    }

    private static func aim(_ menu: NSMenu, at target: AnyObject) {
      for item in menu.items {
        if item.action != nil { item.target = target }
        if let submenu = item.submenu { aim(submenu, at: target) }
      }
    }

    var current: UUID? { controller.sidebarController.current }

    func tab(_ node: UUID) -> TabID? { controller.engineTab(of: node) }

    func children(_ location: SidebarLocation) -> [UUID] { source.children(of: location) }

    /// The menu item that runs `action` (and has `tag`, for the pane items).
    func item(_ action: Selector, tag: Int? = nil) throws -> NSMenuItem {
      var found: NSMenuItem?
      func search(_ menu: NSMenu) {
        for item in menu.items {
          if item.action == action, tag == nil || item.tag == tag { found = found ?? item }
          if let submenu = item.submenu { search(submenu) }
        }
      }
      search(menu)
      return try XCTUnwrap(found, "no menu item for \(action)")
    }

    func isEnabled(_ action: Selector, tag: Int? = nil) throws -> Bool {
      controller.validateMenuItem(try item(action, tag: tag))
    }

    /// Ctrl-Shift and the key with `keyCode`, as the menu bar would get it.
    @discardableResult
    func press(_ keyCode: Int) throws -> Bool {
      menu.performKeyEquivalent(with: try SplitShortcutTests.controlShiftKey(keyCode))
    }

    /// Lets deferred work (the re-show after a source change) run.
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    func close() {
      controller.commandBar.hide(restoreFocus: false)
      controller.close()
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  private static func makeWorld(panes count: Int = 2) throws -> World {
    var sidebar = SidebarModel.Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let t0 = try sidebar.addTab(url: url("t0"), title: "T0", in: .today(space))
    let factors = Array(repeating: 1 / Double(count), count: count)
    let split = try sidebar.addSplit(orientation: .horizontal, widthFactors: factors, in: .today(space))
    let panes = try (0..<count).map { try sidebar.addTab(url: url("s\($0)"), title: "S\($0)", in: .split(split)) }
    let t1 = try sidebar.addTab(url: url("t1"), title: "T1", in: .today(space))
    return World(sidebar: sidebar, space: space, today: [t0, t1], split: split, panes: panes)
  }

  /// The US-layout characters of the keys under test; on another layout the key events carry other characters.
  private static let usBase: [Int: String] = [
    kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
    kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
  ]

  /// A key-down built from a Quartz event, so AppKit translates it with the current keyboard layout: on the US
  /// layout Ctrl-Shift-= arrives as characters "=" and charactersIgnoringModifiers "+". Skips on a layout whose key at
  /// `keyCode` is not the US one (non-US layouts are a recorded risk, not a gate).
  static func key(_ keyCode: Int, flags: NSEvent.ModifierFlags) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let plain = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    plain.flags = []
    let base = NSEvent(cgEvent: plain)?.charactersIgnoringModifiers
    try XCTSkipUnless(base == usBase[keyCode], "keyboard layout is not US-compatible for key \(keyCode)")
    let cg = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    var quartz: CGEventFlags = []
    if flags.contains(.control) { quartz.insert(.maskControl) }
    if flags.contains(.shift) { quartz.insert(.maskShift) }
    if flags.contains(.option) { quartz.insert(.maskAlternate) }
    if flags.contains(.command) { quartz.insert(.maskCommand) }
    cg.flags = quartz
    return try XCTUnwrap(NSEvent(cgEvent: cg))
  }

  static func controlShiftKey(_ keyCode: Int) throws -> NSEvent { try key(keyCode, flags: [.control, .shift]) }

  // MARK: Add Split View (KB-070, BH-116, BH-117)

  /// Ctrl-Shift-= opens the command bar for the new pane; Enter adds it right after the focused pane and focuses it.
  func testCtrlShiftEqualsOpensTheBarInSplitPaneModeAndEnterAddsAPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    XCTAssertTrue(try harness.press(kVK_ANSI_Equal))

    XCTAssertTrue(harness.controller.commandBar.isVisible)
    XCTAssertEqual(harness.controller.commandBar.mode, .newSplitPane)
    XCTAssertEqual(harness.children(.split(world.split)), world.panes, "nothing is added before Enter")

    harness.controller.commandBar.onOpen?(Self.url("new"), .newSplitPane)

    let panes = harness.children(.split(world.split))
    XCTAssertEqual(panes.count, 3)
    XCTAssertEqual([panes[0], panes[2]], world.panes, "the new pane sits right after the focused one")
    XCTAssertEqual(harness.current, panes[1])
    let tab = try XCTUnwrap(harness.tab(panes[1]))
    XCTAssertEqual(harness.controller.currentTab, tab)
    XCTAssertEqual(harness.engine.snapshot(of: tab)?.url, Self.url("new"))
    XCTAssertEqual(harness.controller.rootView.split.paneCount, 3)
    harness.close()
  }

  /// Ctrl-Shift-= on a plain tab splits it: the tab and the new pane side by side, in the tab's place.
  func testAddSplitViewOnAPlainTabCreatesASideBySideSplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    try harness.press(kVK_ANSI_Equal)
    harness.controller.commandBar.onOpen?(Self.url("new"), .newSplitPane)

    let today = harness.children(.today(world.space))
    XCTAssertEqual(today.count, 3)
    guard case .split(let split, let layout)? = harness.source.node(today[0]) else { return XCTFail("no split") }
    XCTAssertEqual(layout.orientation, .horizontal)
    let panes = harness.children(.split(split))
    XCTAssertEqual(panes.first, world.today[0])
    XCTAssertEqual(panes.count, 2)
    XCTAssertEqual(harness.current, panes[1])
    XCTAssertEqual(Array(today[1...]), [world.split, world.today[1]])
    harness.close()
  }

  /// Esc (the bar hides without a commit) adds nothing; a later Cmd-T commit opens a plain new tab.
  func testDismissedBarAddsNoPane() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    try harness.press(kVK_ANSI_Equal)
    harness.controller.commandBar.hide()
    harness.controller.commandBar.onOpen?(Self.url("tab"), .newTab)

    XCTAssertEqual(harness.children(.split(world.split)), world.panes)
    XCTAssertEqual(harness.children(.today(world.space)).count, 4, "Cmd-T added a plain Today tab")
    harness.close()
  }

  /// BH-116: a full split shows "Cannot Add New Pane" at the key press, and the bar stays closed.
  func testCtrlShiftEqualsOnAFullSplitShowsCannotAddNewPaneToast() throws {
    let world = try Self.makeWorld(panes: 4)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])

    try harness.press(kVK_ANSI_Equal)

    XCTAssertEqual(harness.controller.toasts.current?.text, "Cannot Add New Pane")
    XCTAssertFalse(harness.controller.commandBar.isVisible)
    XCTAssertEqual(harness.children(.split(world.split)), world.panes)
    harness.close()
  }

  /// BH-117: Add Left / Top Split put the new pane before the focused tab; Top and Bottom split a plain tab top to
  /// bottom.
  func testAddSideSplitsPlaceThePaneAndSetTheOrientation() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])

    harness.controller.addSplitTop(nil)
    XCTAssertEqual(harness.controller.commandBar.mode, .newSplitPane)
    harness.controller.commandBar.onOpen?(Self.url("top"), .newSplitPane)

    let first = harness.children(.today(world.space))[0]
    guard case .split(let split, let layout)? = harness.source.node(first) else { return XCTFail("no split") }
    XCTAssertEqual(layout.orientation, .vertical)
    var panes = harness.children(.split(split))
    XCTAssertEqual(panes.count, 2)
    XCTAssertEqual(panes[1], world.today[0], "the new pane is on top")
    XCTAssertEqual(harness.current, panes[0])

    harness.controller.commandBar.hide()
    harness.controller.activate(node: world.panes[1])
    harness.controller.addSplitLeft(nil)
    harness.controller.commandBar.onOpen?(Self.url("left"), .newSplitPane)

    panes = harness.children(.split(world.split))
    XCTAssertEqual(panes.count, 3)
    XCTAssertEqual([panes[0], panes[2]], world.panes, "the new pane is left of the focused pane")
    XCTAssertEqual(harness.current, panes[1])
    harness.close()
  }

  // MARK: Close this Split Pane (KB-071, BH-122)

  /// Ctrl-Shift-- takes the focused pane out without archiving it: a two-pane split collapses into the surviving
  /// tab, the separated tab lands right after it with its page kept, and focus stays on the survivor (decision 9).
  func testCtrlShiftMinusSeparatesTheFocusedPaneWithoutArchiving() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let page = try XCTUnwrap(harness.tab(world.panes[0]))

    XCTAssertTrue(try harness.press(kVK_ANSI_Minus))
    harness.settle()

    XCTAssertEqual(harness.archived, [])
    XCTAssertEqual(harness.children(.today(world.space)),
                   [world.today[0], world.panes[1], world.panes[0], world.today[1]])
    XCTAssertEqual(harness.tab(world.panes[0]), page, "the separated tab keeps its page")
    XCTAssertEqual(harness.current, world.panes[1])
    XCTAssertEqual(harness.controller.currentTab, harness.tab(world.panes[1]))
    XCTAssertTrue(harness.controller.rootView.split.isHidden)
    harness.close()
  }

  /// In a larger split the pane after the separated one keeps focus and the split stays on screen.
  func testCtrlShiftMinusInAThreePaneSplitFocusesTheNextPane() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])

    try harness.press(kVK_ANSI_Minus)
    harness.settle()

    XCTAssertEqual(harness.archived, [])
    XCTAssertEqual(harness.children(.today(world.space)),
                   [world.today[0], world.split, world.panes[1], world.today[1]])
    XCTAssertEqual(harness.children(.split(world.split)), [world.panes[0], world.panes[2]])
    XCTAssertEqual(harness.current, world.panes[2])
    XCTAssertEqual(harness.controller.rootView.split.paneCount, 2)
    XCTAssertEqual(harness.controller.rootView.split.focusedIndex, 1)
    harness.close()
  }

  // MARK: Pane focus (KB-072, KB-073, BH-128)

  func testCtrlShiftNumberFocusesPaneN() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    XCTAssertTrue(try harness.press(kVK_ANSI_3))
    XCTAssertEqual(harness.current, world.panes[2])
    XCTAssertEqual(harness.controller.rootView.split.focusedIndex, 2)

    try harness.press(kVK_ANSI_2)
    XCTAssertEqual(harness.current, world.panes[1])
    harness.close()
  }

  func testNumberBeyondThePaneCountDoesNothing() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])

    try harness.press(kVK_ANSI_3)

    XCTAssertEqual(harness.current, world.panes[1])
    XCTAssertFalse(try harness.isEnabled(#selector(ShellWindowController.focusSplitPane(_:)), tag: 2))
    XCTAssertTrue(try harness.isEnabled(#selector(ShellWindowController.focusSplitPane(_:)), tag: 1))
    harness.close()
  }

  /// Ctrl-Shift-] and Ctrl-Shift-[ step through the panes and wrap around (PARITY(NEEDS-RUNTIME-CHECK RT-06)).
  func testNextAndPreviousPaneWrapAround() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[2])

    XCTAssertTrue(try harness.press(kVK_ANSI_RightBracket))
    XCTAssertEqual(harness.current, world.panes[0])
    try harness.press(kVK_ANSI_RightBracket)
    XCTAssertEqual(harness.current, world.panes[1])

    XCTAssertTrue(try harness.press(kVK_ANSI_LeftBracket))
    XCTAssertEqual(harness.current, world.panes[0])
    try harness.press(kVK_ANSI_LeftBracket)
    XCTAssertEqual(harness.current, world.panes[2])
    harness.close()
  }

  // MARK: Expand, separate and convert (KB-075, BH-124, BH-120)

  /// Expand Current Split keeps the focused pane where the split was, shown alone, and the others follow it.
  func testExpandCurrentSplitKeepsTheFocusedPaneShown() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[1])
    let page = try XCTUnwrap(harness.tab(world.panes[1]))

    harness.controller.expandCurrentSplit(nil)
    harness.settle()

    XCTAssertEqual(harness.children(.today(world.space)),
                   [world.today[0], world.panes[1], world.panes[0], world.panes[2], world.today[1]])
    XCTAssertEqual(harness.current, world.panes[1])
    XCTAssertEqual(harness.controller.currentTab, page)
    XCTAssertTrue(harness.controller.rootView.split.isHidden)
    XCTAssertEqual(harness.controller.visibleNodes, [world.panes[1]])
    XCTAssertEqual(harness.archived, [])
    harness.close()
  }

  /// Separate Page from Split View takes the focused page out and keeps it focused, shown alone [I].
  func testSeparatePageFromSplitKeepsThePageFocused() throws {
    let world = try Self.makeWorld(panes: 3)
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])

    harness.controller.separatePageFromSplit(nil)
    harness.settle()

    XCTAssertEqual(harness.children(.today(world.space)),
                   [world.today[0], world.split, world.panes[0], world.today[1]])
    XCTAssertEqual(harness.children(.split(world.split)), [world.panes[1], world.panes[2]])
    XCTAssertEqual(harness.current, world.panes[0])
    XCTAssertTrue(harness.controller.rootView.split.isHidden)
    XCTAssertEqual(harness.archived, [])
    harness.close()
  }

  /// BH-120: the convert item flips the orientation, is retitled for the new state, and the split re-lays out.
  func testConvertFlipsTheOrientationAndRetitlesTheItem() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.panes[0])
    let convert = try harness.item(#selector(ShellWindowController.convertSplitOrientation(_:)))

    XCTAssertTrue(harness.controller.validateMenuItem(convert))
    XCTAssertEqual(convert.title, "Convert to Vertical Split View")

    harness.controller.convertSplitOrientation(convert)
    harness.settle()

    guard case .split(_, let layout)? = harness.source.node(world.split) else { return XCTFail("split gone") }
    XCTAssertEqual(layout.orientation, .vertical)
    XCTAssertEqual(harness.controller.rootView.split.axis, .stacked)
    XCTAssertTrue(harness.controller.validateMenuItem(convert))
    XCTAssertEqual(convert.title, "Convert to Horizontal Split View")

    harness.controller.convertSplitOrientation(convert)
    guard case .split(_, let back)? = harness.source.node(world.split) else { return XCTFail("split gone") }
    XCTAssertEqual(back.orientation, .horizontal)
    harness.close()
  }

  // MARK: Validation

  /// The pane items need a focused pane; adding a split needs a current tab.
  func testPaneItemsAreDisabledOutsideASplit() throws {
    let world = try Self.makeWorld()
    let harness = Harness(world.sidebar)
    harness.controller.activate(node: world.today[0])
    let paneActions: [(Selector, Int?)] = [
      (#selector(ShellWindowController.closeSplitPane(_:)), nil),
      (#selector(ShellWindowController.separatePageFromSplit(_:)), nil),
      (#selector(ShellWindowController.expandCurrentSplit(_:)), nil),
      (#selector(ShellWindowController.convertSplitOrientation(_:)), nil),
      (#selector(ShellWindowController.nextSplitPane(_:)), nil),
      (#selector(ShellWindowController.previousSplitPane(_:)), nil),
      (#selector(ShellWindowController.focusSplitPane(_:)), 0),
    ]
    let addActions: [Selector] = [
      #selector(ShellWindowController.addSplitPane(_:)),
      #selector(ShellWindowController.addSplitRight(_:)), #selector(ShellWindowController.addSplitLeft(_:)),
      #selector(ShellWindowController.addSplitTop(_:)), #selector(ShellWindowController.addSplitBottom(_:)),
    ]

    for (action, tag) in paneActions {
      XCTAssertFalse(try harness.isEnabled(action, tag: tag), "\(action) outside a split")
    }
    for action in addActions { XCTAssertTrue(try harness.isEnabled(action), "\(action) on a plain tab") }
    XCTAssertFalse(try harness.press(kVK_ANSI_Minus), "a disabled item takes no key")
    XCTAssertEqual(harness.children(.today(world.space)), [world.today[0], world.split, world.today[1]])

    harness.controller.activate(node: world.panes[0])
    for (action, tag) in paneActions {
      XCTAssertTrue(try harness.isEnabled(action, tag: tag), "\(action) in a split")
    }
    harness.close()
  }
}
