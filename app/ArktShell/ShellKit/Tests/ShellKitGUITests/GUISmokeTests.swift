import AppKit
import XCTest
@testable import ShellUI

@MainActor
final class GUISmokeTests: XCTestCase {
  func testCanCreateWindow() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                          styleMask: [.titled], backing: .buffered, defer: false)
    XCTAssertEqual(window.frame.width, 200)
  }
}
