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
