import AppKit
import XCTest
@_spi(Smoke) @testable import ShellUI

@MainActor
final class CommandBarSettingsLifetimeTests: XCTestCase {
  func testReplacementAndInvalidationStopOldSettingUpdates() {
    _ = NSApplication.shared
    let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let bar = CommandBarController(parent: parent)
    let old = CommandBarSettings.ephemeral()
    let replacement = CommandBarSettings.ephemeral()
    bar.settings = old
    bar.show(.newTab)
    bar.setQueryForTesting("example query")
    XCTAssertTrue(bar.isNoticeVisible)
    bar.settings = replacement
    old.setSearchSuggestionsEnabled(false)
    XCTAssertTrue(bar.results.contains { $0.kind.name == "search" })
    replacement.dismissSearchSuggestionNotice()
    XCTAssertFalse(bar.isNoticeVisible)
    replacement.setSearchSuggestionsEnabled(false)
    XCTAssertFalse(bar.results.contains { $0.kind.name == "search" })
    bar.invalidate()
    replacement.setSearchSuggestionsEnabled(true)
    XCTAssertFalse(bar.results.contains { $0.kind.name == "search" })
  }
}
