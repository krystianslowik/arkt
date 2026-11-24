import AppKit
import XCTest

/// #808, #863: the titlebar container also hosts AppKit's titlebar decoration, which draws the window's top rim (a
/// bright top edge with rounded corners). A window that narrows the container to its traffic lights draws that rim
/// ending in a corner next to the buttons. Checks that the container and every decoration in it span the window, that
/// only the buttons' host (`NSTitlebarView`) is `buttonHostWidth` wide, and that each point in `clicks` (window
/// coordinates) still hits a view inside the paired content view.
@MainActor
func assertTopRimSpansTheWindow(_ window: NSWindow, buttonHostWidth: CGFloat, clicks: [(NSPoint, NSView)],
                                _ label: String, file: StaticString = #filePath, line: UInt = #line) throws {
  let titlebar = try XCTUnwrap(window.standardWindowButton(.closeButton)?.superview, file: file, line: line)
  let container = try XCTUnwrap(titlebar.superview, file: file, line: line)          // NSTitlebarContainerView
  XCTAssertEqual(container.frame.minX, 0, "container, \(label)", file: file, line: line)
  XCTAssertEqual(container.frame.width, window.frame.width, "container, \(label)", file: file, line: line)
  let decorations = container.subviews.filter { $0 !== titlebar && !$0.isHidden }
  XCTAssertFalse(decorations.isEmpty, "the titlebar decoration is a sibling of the button host, \(label)",
                 file: file, line: line)
  for decoration in decorations {
    let inWindow = decoration.convert(decoration.bounds, to: nil)
    XCTAssertEqual(inWindow.minX, 0, "\(type(of: decoration)), \(label)", file: file, line: line)
    XCTAssertEqual(inWindow.width, window.frame.width, "\(type(of: decoration)), \(label)", file: file, line: line)
  }
  let host = titlebar.convert(titlebar.bounds, to: nil)
  XCTAssertEqual(host.minX, 0, "button host, \(label)", file: file, line: line)
  XCTAssertEqual(host.width, buttonHostWidth, "only the buttons' host is narrowed, \(label)", file: file, line: line)

  // The full-width decoration takes no clicks: the bar's controls beside and far from the buttons keep theirs.
  let frameView = try XCTUnwrap(window.contentView?.superview, file: file, line: line)   // NSThemeFrame
  for (point, target) in clicks {
    let hit = try XCTUnwrap(frameView.hitTest(frameView.convert(point, from: nil)), file: file, line: line)
    XCTAssertTrue(hit.isDescendant(of: target), "\(point): got \(hit), want \(target), \(label)",
                  file: file, line: line)
  }
}

/// The center of `view` in its window's coordinates.
@MainActor
func centerInWindow(_ view: NSView) -> NSPoint {
  let rect = view.convert(view.bounds, to: nil)
  return NSPoint(x: rect.midX, y: rect.midY)
}

/// #989: the titlebar geometry the shell sets, in window coordinates: the container, the buttons' host and close,
/// minimize and zoom, with each button's visibility.
@MainActor
func titlebarGeometry(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
  let close = try XCTUnwrap(window.standardWindowButton(.closeButton), file: file, line: line)
  let titlebar = try XCTUnwrap(close.superview, file: file, line: line)              // NSTitlebarView
  let container = try XCTUnwrap(titlebar.superview, file: file, line: line)          // NSTitlebarContainerView
  let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap {
    window.standardWindowButton($0)
  }
  XCTAssertEqual(buttons.count, 3, file: file, line: line)
  return ["container \(container.convert(container.bounds, to: nil))",
          "host \(titlebar.convert(titlebar.bounds, to: nil))"]
    + buttons.map { "button \($0.convert($0.bounds, to: nil)) hidden \($0.isHidden)" }
}

/// #989: each change makes AppKit lay its titlebar out again on its own (the buttons go back to AppKit's own places and
/// their host to the window's full width). A new title, as the engine sets on every tab switch, leaves the geometry the
/// window set as it was at once, with no layout pass between; with `relayouts`, every other change and a button moved
/// from outside leave it as it was after the next layout pass, before anything is drawn.
@MainActor
func assertTitlebarStaysPut(_ window: NSWindow, _ label: String, relayouts: Bool = true,
                            file: StaticString = #filePath, line: UInt = #line) throws {
  let placed = try titlebarGeometry(window, file: file, line: line)
  let titles = ["GitHub", "Inbox (3) - a very long page title that a tab switch brings in", "", "Почта - 受信トレイ"]
  for title in titles {
    window.title = title
    XCTAssertEqual(try titlebarGeometry(window, file: file, line: line), placed, "after title \"\(title)\", \(label)",
                   file: file, line: line)
  }
  guard relayouts else { return }
  let zoom = try XCTUnwrap(window.standardWindowButton(.zoomButton), file: file, line: line)
  let changes: [(String, () -> Void)] = [
    ("subtitle", { window.subtitle = "subtitle" }),
    ("represented URL", { window.representedURL = URL(string: "https://example.com/") }),
    ("document edited", { window.isDocumentEdited = true }),
    ("dark appearance", { window.appearance = NSAppearance(named: .darkAqua) }),
    ("a button moved", { zoom.setFrameOrigin(.zero) }),
  ]
  for (change, apply) in changes {
    apply()
    window.layoutIfNeeded()
    XCTAssertEqual(try titlebarGeometry(window, file: file, line: line), placed, "after \(change), \(label)",
                   file: file, line: line)
  }
  window.subtitle = ""
  window.representedURL = nil
  window.isDocumentEdited = false
  window.appearance = nil
  window.layoutIfNeeded()
}
