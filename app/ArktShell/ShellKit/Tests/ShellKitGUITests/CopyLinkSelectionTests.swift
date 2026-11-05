import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// #404: Copy URL with text selected on the page offers a link to that text (BH-193), and repeated manual link copies
/// suggest the Copy URL shortcut once (BH-196).
@MainActor
final class CopyLinkSelectionTests: XCTestCase {
  @MainActor
  private final class Harness {
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    let board: NSPasteboard
    var tabs: [UUID] = []

    init(_ urls: [String], name: String) {
      let sidebar = StubSidebar()
      let space = sidebar.addSpace(title: "Work")
      for (index, url) in urls.enumerated() {
        tabs.append(sidebar.addTab(url: URL(string: url)!, title: "T\(index)", in: .today(space)))
      }
      board = NSPasteboard(name: .init("CopyLinkSelectionTests.\(name)"))
      board.clearContents()
      controller = ShellWindowController(engine: engine, sidebar: sidebar)
      controller.pasteboard = board
      controller.linkPasteboard = board
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
      if let first = tabs.first { controller.activate(node: first) }
    }

    func engineTab(_ index: Int) throws -> TabID { try XCTUnwrap(controller.engineTab(of: tabs[index])) }
    var clipboard: String? { board.string(forType: .string) }
    var toast: Toast? { controller.toasts.current }
    func click(_ index: Int, _ modifiers: NSEvent.ModifierFlags) throws {
      let outline = try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
      try outline.handleClick(row: outline.row(for: tabs[index]), modifiers: modifiers)
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: BH-193

  /// The page URL is copied at once; the toast offers the link to the selection, and its action copies that link.
  func testCopyURLWithASelectionOffersALinkToTheText() throws {
    let harness = Harness(["https://example.com/read?utm_source=news&page=2"], name: "offer")
    harness.engine.setSelectedText(try harness.engineTab(0), "quick brown fox")

    harness.controller.copyCurrentURL(nil)

    XCTAssertEqual(harness.clipboard, "https://example.com/read?page=2", "the page URL is copied first")
    XCTAssertEqual(harness.toast?.text, "Share a link directly to this text instead?")
    XCTAssertEqual(harness.toast?.actionTitle, "Copy Link to Text")

    harness.controller.toasts.performActionForTesting()

    XCTAssertEqual(harness.clipboard, "https://example.com/read?page=2#:~:text=quick%20brown%20fox")
    XCTAssertEqual(harness.toast?.text, "Copied Link to Text")
    harness.controller.close()
  }

  /// No selection: the plain BH-191 toast, with no offer.
  func testCopyURLWithoutASelectionMakesNoOffer() throws {
    let harness = Harness(["https://example.com/read"], name: "noselection")
    harness.engine.setSelectedText(try harness.engineTab(0), "  \n ")

    harness.controller.copyCurrentURL(nil)

    XCTAssertEqual(harness.toast?.text, "Copied Current URL")
    XCTAssertNil(harness.toast?.actionTitle)
    harness.controller.close()
  }

  /// A multi-selection copies several pages; a link to one page's text is not offered.
  func testCopyURLWithSeveralTabsMakesNoOffer() throws {
    let harness = Harness(["https://example.com/a", "https://example.com/b"], name: "multi")
    harness.engine.setSelectedText(try harness.engineTab(0), "quick brown fox")
    try harness.click(1, .command)

    harness.controller.copyCurrentURL(nil)

    XCTAssertEqual(harness.clipboard, "https://example.com/a\nhttps://example.com/b")
    XCTAssertEqual(harness.toast?.text, "Copied Current URLs")
    harness.controller.close()
  }

  // MARK: BH-196

  /// The third sidebar Copy Link suggests the shortcut; later copies do not.
  func testRepeatedSidebarCopiesSuggestTheShortcutOnce() throws {
    let harness = Harness(["https://example.com/a"], name: "education")
    harness.controller.copyLinkEducation = .ephemeral()

    harness.controller.copyLinks([harness.tabs[0]], markdown: false)
    harness.controller.copyLinks([harness.tabs[0]], markdown: false)
    XCTAssertNil(harness.toast, "no tip before the third copy")
    harness.controller.copyLinks([harness.tabs[0]], markdown: false)
    XCTAssertEqual(harness.toast, CopyLinkEducation.toast)

    harness.controller.toasts.dismiss()
    harness.controller.copyLinks([harness.tabs[0]], markdown: false)
    XCTAssertNil(harness.toast, "the tip shows once")
    XCTAssertEqual(harness.clipboard, "https://example.com/a")
    harness.controller.close()
  }

  /// Someone who already presses Cmd-Shift-C is never told about it.
  func testUsingCopyURLSuppressesTheTip() throws {
    let harness = Harness(["https://example.com/a"], name: "educationshortcut")
    harness.controller.copyLinkEducation = .ephemeral()

    harness.controller.copyCurrentURL(nil)
    harness.controller.toasts.dismiss()
    for _ in 0..<3 { harness.controller.copyLinks([harness.tabs[0]], markdown: false) }

    XCTAssertNil(harness.toast)
    harness.controller.close()
  }
}
