import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// #118: Copy URL (KB-013, BH-191), Copy URL as Markdown (KB-014), Copy URL as Quote (KB-015) and Paste URL as New
/// Tab (KB-016). The URL is tracker-stripped; the toasts follow BH-191's strings.
@MainActor
final class CopyLinkTests: XCTestCase {
  /// One Space "Work" with a Today tab per URL.
  @MainActor
  private struct World {
    var sidebar = StubSidebar()
    var space: UUID = UUID()
    var tabs: [UUID] = []
    var urls: [String] = []
  }

  @MainActor
  private final class Harness {
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    let pasteboard: NSPasteboard

    init(_ sidebar: StubSidebar, pasteboard: NSPasteboard) {
      self.pasteboard = pasteboard
      controller = ShellWindowController(engine: engine, sidebar: sidebar)
      controller.pasteboard = pasteboard
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    func activate(_ node: UUID) { controller.activate(node: node) }
    func tab(of node: UUID) -> TabID? { controller.engineTab(of: node) }
    func outline() throws -> SidebarOutlineController {
      try XCTUnwrap(controller.sidebarController.currentPage?.outlineController)
    }
    func row(_ node: UUID) throws -> Int {
      let row = try outline().row(for: node)
      XCTAssertGreaterThanOrEqual(row, 0, "no outline row for the node")
      return row
    }
    func click(_ node: UUID, _ modifiers: NSEvent.ModifierFlags = []) throws {
      try outline().handleClick(row: row(node), modifiers: modifiers)
    }
    func todayNodes() -> [UUID] {
      controller.currentSpace.map { controller.sidebar.children(of: .today($0)) } ?? []
    }
    var clipboard: String? { pasteboard.string(forType: .string) }
    var toast: String? { controller.toasts.current?.text }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static func makeWorld(_ urls: [String], titles: [String] = []) -> World {
    var world = World()
    world.space = world.sidebar.addSpace(title: "Work")
    for (index, url) in urls.enumerated() {
      let title = index < titles.count ? titles[index] : "T\(index)"
      world.tabs.append(world.sidebar.addTab(url: URL(string: url)!, title: title, in: .today(world.space)))
      world.urls.append(url)
    }
    return world
  }

  private func pasteboard(_ name: String) -> NSPasteboard { NSPasteboard(name: .init(name)) }

  // MARK: Copy URL (KB-013, BH-191)

  func testCopyURLCopiesTheCleanURLAndSaysWhatItDid() throws {
    let world = Self.makeWorld(["https://example.com/read?utm_source=news&page=2"])
    let board = pasteboard("CopyLinkTests.clean")
    board.clearContents()
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])

    harness.controller.copyCurrentURL(nil)

    XCTAssertEqual(harness.clipboard, "https://example.com/read?page=2")
    XCTAssertEqual(harness.toast, "Copied a clean link without trackers")
    harness.controller.close()
  }

  func testCopyURLWithoutTrackersUsesTheCurrentURLString() throws {
    let world = Self.makeWorld(["https://example.com/read?page=2"])
    let board = pasteboard("CopyLinkTests.current")
    board.clearContents()
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])

    harness.controller.copyCurrentURL(nil)

    XCTAssertEqual(harness.clipboard, "https://example.com/read?page=2")
    XCTAssertEqual(harness.toast, "Copied Current URL")
    harness.controller.close()
  }

  /// BH-191: a multi-selection copies every selected tab, one URL per line, with the plural toast.
  func testCopyURLWithAMultiSelectionCopiesEverySelectedTab() throws {
    let world = Self.makeWorld(["https://example.com/a?utm_source=x", "https://example.com/b",
                                "https://example.com/c"])
    let board = pasteboard("CopyLinkTests.multi")
    board.clearContents()
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])
    try harness.click(world.tabs[1], .command)

    harness.controller.copyCurrentURL(nil)

    XCTAssertEqual(harness.clipboard, "https://example.com/a\nhttps://example.com/b")
    XCTAssertEqual(harness.toast, "Copied clean links without trackers")
    harness.controller.close()
  }

  // MARK: Markdown and Quote (KB-014, KB-015)

  func testCopyURLAsMarkdownCopiesATitleAndLink() throws {
    let world = Self.makeWorld(["https://example.com/read?utm_source=x"], titles: ["Example Title"])
    let board = pasteboard("CopyLinkTests.markdown")
    board.clearContents()
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])
    harness.engine.finishLoad(try XCTUnwrap(harness.tab(of: world.tabs[0])), title: "Example Title")

    harness.controller.copyCurrentURLAsMarkdown(nil)

    XCTAssertEqual(harness.clipboard, "[Example Title](https://example.com/read)")
    harness.controller.close()
  }

  func testCopyURLAsQuoteCopiesAQuotedLink() throws {
    let world = Self.makeWorld(["https://example.com/read?utm_source=x"], titles: ["Example Title"])
    let board = pasteboard("CopyLinkTests.quote")
    board.clearContents()
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])
    harness.engine.finishLoad(try XCTUnwrap(harness.tab(of: world.tabs[0])), title: "Example Title")

    harness.controller.copyCurrentURLAsQuote(nil)

    XCTAssertEqual(harness.clipboard, "> [Example Title](https://example.com/read)")
    harness.controller.close()
  }

  // MARK: In a Peek (KB-013: "global, Peek")

  /// With a Peek open, Copy URL copies the Peek's page, not the tab behind it.
  func testCopyURLInAPeekCopiesThePeeksPage() throws {
    let world = Self.makeWorld(["https://example.com/behind?utm_source=x"])
    let board = pasteboard("CopyLinkTests.peek")
    board.clearContents()
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])
    let source = try XCTUnwrap(harness.tab(of: world.tabs[0]))

    harness.controller.peek.open(try XCTUnwrap(URL(string: "https://example.com/peeked?utm_source=y&page=2")),
                                 from: source)
    XCTAssertTrue(harness.controller.peek.isOpen, "the Peek opened")

    harness.controller.copyCurrentURL(nil)

    XCTAssertEqual(harness.clipboard, "https://example.com/peeked?page=2", "the Peek's URL, not the tab's")
    XCTAssertEqual(harness.toast, "Copied a clean link without trackers")
    harness.controller.close()
  }

  // MARK: Paste URL as New Tab (KB-016)

  func testPasteURLAsNewTabOpensTheClipboardURL() throws {
    let world = Self.makeWorld(["https://example.com/first"])
    let board = pasteboard("CopyLinkTests.paste")
    board.clearContents()
    board.setString("https://example.com/pasted", forType: .string)
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])

    harness.controller.pasteURLAsNewTab(nil)

    let pasted = harness.todayNodes()
    XCTAssertEqual(pasted.count, 2, "a new Today tab")
    let node = try XCTUnwrap(pasted.last { candidate in
      if case .tab(_, let url, _)? = harness.controller.sidebar.node(candidate) {
        return url.absoluteString == "https://example.com/pasted"
      }
      return false
    }, "the pasted URL's row")
    XCTAssertEqual(harness.controller.currentNode, node, "the pasted tab is current")
    harness.controller.close()
  }

  /// Text on the clipboard is not a URL: nothing opens and nothing is copied over it.
  func testPasteURLAsNewTabIgnoresNonURLText() throws {
    let world = Self.makeWorld(["https://example.com/first"])
    let board = pasteboard("CopyLinkTests.pastenoturl")
    board.clearContents()
    board.setString("just some text", forType: .string)
    let harness = Harness(world.sidebar, pasteboard: board)
    harness.activate(world.tabs[0])

    harness.controller.pasteURLAsNewTab(nil)

    XCTAssertEqual(harness.todayNodes().count, 1)
    XCTAssertEqual(harness.clipboard, "just some text", "the clipboard is left alone")
    harness.controller.close()
  }
}
