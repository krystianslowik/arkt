import AppKit
import Carbon.HIToolbox
import EngineAPI
import XCTest
@testable import ShellUI

/// W3-7 part D steps 4 and 6 on the shell window itself: reserved keys reach the main menu before the focused view
/// (a web page takes every key equivalent first), and Minimize / Zoom work on the visually borderless window.
@MainActor
final class ShellWindowKeyTests: XCTestCase {
  private var savedMenu: NSMenu?

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    savedMenu = NSApp.mainMenu
  }

  override func tearDown() async throws {
    NSApp.mainMenu = savedMenu
  }

  /// A key-down for `keyCode` as AppKit builds it from a Quartz event (translated by the current layout; the
  /// reserved-key match does not depend on it).
  private func key(_ keyCode: Int, _ flags: CGEventFlags) throws -> NSEvent {
    let source = CGEventSource(stateID: .privateState)
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true))
    event.flags = flags
    return try XCTUnwrap(NSEvent(cgEvent: event))
  }

  /// A window whose first responder takes every key equivalent, as `RenderWidgetHostViewCocoa` does, and a main menu
  /// with Archive Tab (Cmd-W) and Save (Cmd-S) aimed at a probe.
  private func makeWindow() throws -> (ShellWindow, SwallowingView, MenuProbe) {
    let window = ShellWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600))
    let view = SwallowingView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    window.contentView?.addSubview(view)
    XCTAssertTrue(window.makeFirstResponder(view))
    let probe = MenuProbe()
    let menu = NSMenu()
    let holder = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    let file = NSMenu(title: "File")
    for (title, key) in [("Archive Tab", "w"), ("Save", "s")] {
      let item = NSMenuItem(title: title, action: #selector(MenuProbe.hit(_:)), keyEquivalent: key)
      item.keyEquivalentModifierMask = .command
      item.target = probe
      file.addItem(item)
    }
    let space = NSMenuItem(title: "Space 1", action: #selector(MenuProbe.hit(_:)), keyEquivalent: "1")
    space.keyEquivalentModifierMask = .control
    space.target = probe
    file.addItem(space)
    holder.submenu = file
    menu.addItem(holder)
    NSApp.mainMenu = menu
    return (window, view, probe)
  }

  func testAReservedKeyReachesTheMenuBeforeAFocusedViewThatSwallowsKeyEquivalents() throws {
    let (window, view, probe) = try makeWindow()

    XCTAssertTrue(window.performKeyEquivalent(with: try key(kVK_ANSI_W, .maskCommand)))

    XCTAssertEqual(probe.hits, ["Archive Tab"])
    XCTAssertEqual(view.keyEquivalents, 0, "the focused view never saw Cmd-W")
  }

  /// #489: Ctrl-1 has no Cmd, so the engine never hands it back from a page that declined it; it must reach the menu
  /// before the focused page view, as after a reload, when the page holds the keyboard.
  func testCtrlDigitReachesTheMenuBeforeAFocusedViewThatSwallowsKeyEquivalents() throws {
    let (window, view, probe) = try makeWindow()

    XCTAssertTrue(window.performKeyEquivalent(with: try key(kVK_ANSI_1, .maskControl)))

    XCTAssertEqual(probe.hits, ["Space 1"])
    XCTAssertEqual(view.keyEquivalents, 0, "the focused view never saw Ctrl-1")
  }

  /// The page keeps the Ctrl keys the menu has no item for (a terminal in the page uses Ctrl-A, Ctrl-C).
  func testACtrlKeyWithoutAMenuItemGoesToTheFocusedView() throws {
    let (window, view, probe) = try makeWindow()

    XCTAssertTrue(window.performKeyEquivalent(with: try key(kVK_ANSI_A, .maskControl)))

    XCTAssertEqual(view.keyEquivalents, 1)
    XCTAssertTrue(probe.hits.isEmpty)
  }

  func testAnUnreservedKeyGoesToTheFocusedViewFirst() throws {
    let (window, view, probe) = try makeWindow()

    XCTAssertTrue(window.performKeyEquivalent(with: try key(kVK_ANSI_S, .maskCommand)))

    XCTAssertEqual(view.keyEquivalents, 1, "pages keep Cmd-S, as in Chrome")
    XCTAssertTrue(probe.hits.isEmpty)
  }

  /// A reserved key with no item in the menu (Cmd-Q here) goes the usual way.
  func testAReservedKeyWithoutAMenuItemGoesToTheView() throws {
    let (window, view, probe) = try makeWindow()

    XCTAssertTrue(window.performKeyEquivalent(with: try key(kVK_ANSI_Q, .maskCommand)))

    XCTAssertEqual(view.keyEquivalents, 1)
    XCTAssertTrue(probe.hits.isEmpty)
  }

  /// Extra modifiers are not the reserved key: Cmd-Option-W goes to the view.
  func testAReservedKeyWithExtraModifiersGoesToTheView() throws {
    let (window, view, probe) = try makeWindow()

    XCTAssertTrue(window.performKeyEquivalent(with: try key(kVK_ANSI_W, [.maskCommand, .maskAlternate])))

    XCTAssertEqual(view.keyEquivalents, 1)
    XCTAssertTrue(probe.hits.isEmpty)
  }

  // MARK: Window menu items on the borderless window

  func testMinimizeZoomAndFullScreenAreEnabledAndMinimizeWorks() throws {
    let window = ShellWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600))
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    for action in [#selector(NSWindow.performMiniaturize(_:)), #selector(NSWindow.performZoom(_:)),
                   #selector(NSWindow.toggleFullScreen(_:)), #selector(NSWindow.performClose(_:))] {
      let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
      XCTAssertTrue(window.validateUserInterfaceItem(item), "\(action) is enabled on the shell window")
    }

    window.performMiniaturize(nil)
    waitUntil("the window is minimized") { window.isMiniaturized }
    window.deminiaturize(nil)
    waitUntil("the window is back") { !window.isMiniaturized }
  }

  func testZoomResizesTheWindow() throws {
    let window = ShellWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600))
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    let before = window.frame

    window.performZoom(nil)

    waitUntil("the window is zoomed") { window.frame != before }
    XCTAssertTrue(window.isZoomed)
  }
}

/// Takes every key equivalent, as a focused web page does.
@MainActor
private final class SwallowingView: NSView {
  var keyEquivalents = 0
  override var acceptsFirstResponder: Bool { true }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    keyEquivalents += 1
    return true
  }
}

@MainActor
private final class MenuProbe: NSObject {
  var hits: [String] = []
  @objc func hit(_ sender: Any?) { hits.append((sender as? NSMenuItem)?.title ?? "") }
}
