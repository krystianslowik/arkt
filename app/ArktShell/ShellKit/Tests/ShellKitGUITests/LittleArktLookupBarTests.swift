import AppKit
import EngineAPI
import EngineAPITestSupport
@testable import CoreBridge
import SidebarModel
import XCTest
@testable import ShellUI

/// The quick lookup bar (#354, docs/design/little-arkt.md "Quick lookup"): the "Little Arkt" tag before the field,
/// the field's label, Return opening the result in a new Little Arkt window, Esc closing it with nothing, no open or
/// close animation, and the Settings row that reports a taken combination.
@MainActor
final class LittleArktLookupBarTests: XCTestCase {
  private var bars: [LittleArktLookupController] = []
  private var sets: [ShellWindowSet] = []
  private var controllers: [SettingsWindowController] = []
  private var suiteName = ""
  private var defaults = UserDefaults.standard

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate()
    suiteName = "dev.arkt.tests.lookupBar.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() async throws {
    for bar in bars { bar.hide() }
    bars = []
    for set in sets {
      for controller in set.controllers { controller.window?.orderOut(nil) }
      for little in set.littleArkts { little.window.orderOut(nil) }
    }
    sets = []
    controllers.forEach { $0.window?.close() }
    controllers = []
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  private func makeBar() -> LittleArktLookupController {
    let bar = LittleArktLookupController()
    bars.append(bar)
    return bar
  }

  // MARK: Menu

  /// File > New Little Arkt Window on Cmd-Opt-N (KB-044), in the File menu after New Window. Incognito and Blank
  /// Window sit between them (#487).
  func testFileMenuHasNewLittleArktWindowOnOptionCommandN() throws {
    _ = NSApplication.shared
    let commands = AppCommands()
    let menu = MainMenu.make(commands: commands).menu
    let file = try XCTUnwrap(menu.items.first { $0.title == "File" }?.submenu)
    let item = try XCTUnwrap(file.items.first { $0.title == "New Little Arkt Window" })
    XCTAssertEqual(item.keyEquivalent, "n")
    XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option])
    XCTAssertEqual(item.action, #selector(AppCommands.newLittleArktWindow(_:)))
    XCTAssertNotNil(item.target, "targets the app's commands, so the engine's AppController never sees it")
    let newWindow = try XCTUnwrap(file.items.firstIndex { $0.title == "New Window" })
    XCTAssertEqual(file.items.firstIndex(of: item), newWindow + 3)
  }

  // MARK: Bar

  /// The tag, the placeholder and the field's label; the panel is the command bar's, at 34 % of the screen.
  func testTheBarShowsTheTagAndTheFieldLabel() throws {
    let bar = makeBar()
    let screen = try XCTUnwrap(NSScreen.main)
    bar.show(on: screen)
    XCTAssertTrue(bar.isVisible)
    XCTAssertTrue(bar.panel.isVisible)
    XCTAssertEqual(bar.panel.animationBehavior, .none, "keyboard-initiated: no open animation")
    XCTAssertEqual(bar.panel.alphaValue, 1, accuracy: 0.001)
    let expected = LittleArktLookup.frame(in: screen.visibleFrame, rowCount: bar.results.count)
    XCTAssertEqual(bar.panel.frame.size, expected.size)
    XCTAssertEqual(bar.panel.frame.midX, expected.midX, accuracy: 0.5)
    XCTAssertEqual(bar.panel.frame.maxY, expected.maxY, accuracy: 1, "top edge at 34 % of the screen")
    XCTAssertEqual(bar.barView.tagView.text, "Little Arkt")
    XCTAssertEqual(bar.barView.field.placeholderAttributedString?.string, "Search or Enter URL...")
    XCTAssertEqual(bar.barView.field.accessibilityLabel(), "Little Arkt: Search or Enter URL")
    XCTAssertEqual(bar.barView.tagView.accessibilityLabel(), "Little Arkt")
    XCTAssertFalse(bar.barView.tagView.isHidden, "the tag is part of the lookup bar, not the Cmd-T bar")
  }

  /// The tag sits before the input and the input starts after it.
  func testTheTagSitsBeforeTheInput() throws {
    let bar = makeBar()
    bar.show(on: try XCTUnwrap(NSScreen.main))
    bar.barView.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(bar.barView.tagView.frame.width, 0)
    XCTAssertGreaterThanOrEqual(bar.barView.field.frame.minX, bar.barView.tagView.frame.maxX,
                               "no overlap between the tag and the field")
    XCTAssertLessThan(bar.barView.tagView.frame.minX, bar.barView.field.frame.minX)
  }

  /// Return opens the typed URL through the app and closes the bar with no close animation (one alpha step).
  func testReturnOpensTheResultAndClosesTheBar() throws {
    let bar = makeBar()
    var opened: URL?
    let entry = expectation(description: "open")
    bar.onOpen = { url in opened = url; entry.fulfill() }
    bar.show(on: try XCTUnwrap(NSScreen.main))
    bar.setQueryForTesting("atlas.example/three-days")
    bar.commit()
    wait(for: [entry], timeout: 1)
    XCTAssertEqual(opened?.absoluteString, "https://atlas.example/three-days")
    XCTAssertFalse(bar.isVisible)
    XCTAssertFalse(bar.panel.isVisible)
    XCTAssertEqual(bar.panel.alphaValue, 0)
  }

  /// Esc closes the bar with nothing opened.
  func testEscapeClosesWithNothingOpened() throws {
    let bar = makeBar()
    var opened: URL?
    bar.onOpen = { opened = $0 }
    bar.show(on: try XCTUnwrap(NSScreen.main))
    bar.setQueryForTesting("atlas.example")
    // Esc reaches a text field's delegate as `cancelOperation:`; that is the path a key press takes.
    XCTAssertTrue(bar.control(bar.barView.field, textView: NSTextView(frame: .zero),
                              doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    XCTAssertNil(opened)
    XCTAssertFalse(bar.isVisible)
    XCTAssertFalse(bar.panel.isVisible, "no close animation: the panel is gone at once")
  }

  /// A "Switch to Tab" result hands the row to the app instead of opening a page.
  func testASwitchToTabResultHandsTheNodeToTheApp() throws {
    let bar = makeBar()
    let node = NodeID()
    let url = try XCTUnwrap(URL(string: "https://atlas.example/notes"))
    bar.openTabsProvider = { [CommandBarResults.OpenTab(node: node, title: "Notes", url: url)] }
    var switched: NodeID?
    bar.onSwitch = { switched = $0 }
    bar.show(on: try XCTUnwrap(NSScreen.main))
    bar.setQueryForTesting("Notes")
    bar.commit()
    XCTAssertEqual(switched, node)
    XCTAssertFalse(bar.isVisible)
  }

  // MARK: The Little Arkt window

  private func makeSet() throws -> (set: ShellWindowSet, engine: InMemoryEngine) {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return (set, engine)
  }

  /// The lookup's result becomes its own Little Arkt window, with the page in it and no browser window built.
  func testTheResultOpensInANewLittleArktWindow() throws {
    let (set, engine) = try makeSet()
    _ = set.openWindow(opensFirstTab: false)
    let url = try XCTUnwrap(URL(string: "https://atlas.example/three-days"))

    let little = set.openLittleArkt(url: url)

    XCTAssertEqual(set.littleArkts.count, 1)
    XCTAssertEqual(set.controllers.count, 1, "no browser window")
    XCTAssertTrue(little.window.isVisible)
    let id = try XCTUnwrap(little.engineWindow)
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    XCTAssertEqual(engine.snapshot(of: tab)?.url, url)
    XCTAssertEqual(little.topBar.hostLabel.stringValue, "atlas.example")
  }

  /// Two results cascade from the top-right, the layout's 28 pt step.
  func testASecondLookupWindowCascades() throws {
    let (set, _) = try makeSet()
    let first = try XCTUnwrap(URL(string: "https://atlas.example/one"))
    let second = try XCTUnwrap(URL(string: "https://atlas.example/two"))
    let one = set.openLittleArkt(url: first)
    let two = set.openLittleArkt(url: second)
    XCTAssertEqual(two.window.frame.minX, one.window.frame.minX - LittleArktLayout.cascadeStep)
    XCTAssertEqual(two.window.frame.maxY, one.window.frame.maxY - LittleArktLayout.cascadeStep)
  }

  // MARK: Settings > Links

  private func makeSettings() -> SettingsWindowController {
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: SettingsServices())
    controllers.append(controller)
    return controller
  }

  /// The Links section carries the switch, off by default, and the design's row label.
  func testTheLinksSectionCarriesTheHotKeySwitch() throws {
    let controller = makeSettings()
    controller.show(pane: .general)
    let toggle = try XCTUnwrap(Self.view(AXID.Settings.control("general", "littleArktHotKey"),
                                         in: controller) as? SettingsSwitch)
    XCTAssertEqual(toggle.state, .off, "off by default (decision 2026-10-25)")
    let row = try XCTUnwrap(toggle.enclosingSettingsRow)
    XCTAssertEqual(row.labelText, "Open Little Arkt when I press \u{2325}\u{2318}N")
    XCTAssertEqual(row.captionText, "", "no conflict line while the combination is free")
  }

  /// A combination another app holds reads under the switch, and the line can arrive while the window is open.
  func testTheTakenCombinationShowsTheConflictLine() throws {
    let settings = AppSettings(defaults: defaults)
    settings.setLittleArktHotKeyTaken(true)
    let controller = SettingsWindowController(settings: settings, services: SettingsServices())
    controllers.append(controller)
    controller.show(pane: .general)
    let toggle = try XCTUnwrap(Self.view(AXID.Settings.control("general", "littleArktHotKey"),
                                         in: controller) as? SettingsSwitch)
    XCTAssertEqual(toggle.enclosingSettingsRow?.captionText, "\u{2325}\u{2318}N is used by another app.")

    settings.setLittleArktHotKeyTaken(false)
    XCTAssertEqual(toggle.enclosingSettingsRow?.captionText, "", "the line goes when the combination is free")
  }

  /// The switch writes the app setting the hotkey reads.
  func testTheSwitchWritesTheSetting() throws {
    let settings = AppSettings(defaults: defaults)
    let controller = SettingsWindowController(settings: settings, services: SettingsServices())
    controllers.append(controller)
    controller.show(pane: .general)
    let toggle = try XCTUnwrap(Self.view(AXID.Settings.control("general", "littleArktHotKey"),
                                         in: controller) as? SettingsSwitch)
    toggle.onChange?(true)
    XCTAssertTrue(settings.opensLittleArktWithHotKey)
    XCTAssertTrue(defaults.bool(forKey: AppSettings.Key.globalLittleBrowserHotkeyEnabled))
  }

  private static func view(_ identifier: String, in controller: SettingsWindowController) -> NSView? {
    func find(_ root: NSView) -> NSView? {
      if root.accessibilityIdentifier() == identifier { return root }
      for child in root.subviews {
        if let hit = find(child) { return hit }
      }
      return nil
    }
    guard let root = controller.window?.contentView else { return nil }
    return find(root)
  }
}
