import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@_spi(Smoke) @testable import ShellUI

/// #668 (design/private-pages, "The list"): a page playing sound has a mute button on its row at all times, a hovered
/// row has a close button, and both are buttons VoiceOver names by the page title. InMemoryEngine; no wall-clock waits.
@MainActor
final class PrivatePageControlsTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private func makeWindow() throws -> (ShellWindowController, InMemoryEngine) {
    var sidebar = SidebarModel.Sidebar()
    _ = sidebar.addSpace(title: "Work")
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    let window = set.openWindow(opensFirstTab: false)
    window.makeIncognito()
    window.sidebarController.view.privatePages.reduceMotion = { true }
    window.openPrivately(EngineWorld.url("first"))
    _ = try XCTUnwrap(window.currentTab)
    return (window, engine)
  }

  private func fill(_ window: ShellWindowController, to count: Int) {
    while window.privatePageOrder.pages.count < count {
      window.openPrivately(EngineWorld.url("page-\(window.privatePageOrder.pages.count)"), inNewPage: true)
    }
  }

  private func rows(_ window: ShellWindowController) -> [PrivatePageRowView] {
    window.sidebarController.view.privatePages.rows
  }

  private func row(_ window: ShellWindowController, _ tab: TabID) throws -> PrivatePageRowView {
    try XCTUnwrap(rows(window).first { $0.tab == tab })
  }

  /// A page playing sound shows its mute button whether or not the row is hovered; a silent page shows none. The
  /// button mutes and unmutes the page, shows the muted glyph with the pressed fill, and VoiceOver reads "Mute" or
  /// "Unmute" with the title. A muted page that went quiet keeps its button so it can be unmuted.
  func testAPagePlayingSoundHasAMuteButton() throws {
    let (window, engine) = try makeWindow()
    fill(window, to: 3)
    let pages = window.privatePageOrder.pages
    engine.setDocumentTitle(pages[1], "Weekly radio stream")
    XCTAssertTrue(try row(window, pages[1]).muteButton.isHidden, "a silent page has no mute button")

    engine.setAudible(pages[1], true)
    let playing = try row(window, pages[1])
    XCTAssertFalse(playing.muteButton.isHidden, "shown without hover")
    XCTAssertEqual(playing.muteButton.accessibilityLabel(), "Mute Weekly radio stream")
    XCTAssertFalse(playing.muteButton.isPressedLook)

    playing.muteButton.performClick(nil)
    XCTAssertEqual(engine.snapshot(of: pages[1])?.isMuted, true)
    XCTAssertEqual(playing.muteButton.accessibilityLabel(), "Unmute Weekly radio stream")
    XCTAssertEqual(playing.muteButton.symbolName, "speaker.slash.fill")
    XCTAssertTrue(playing.muteButton.isPressedLook, "a muted page's button takes the pressed fill")

    engine.setAudible(pages[1], false)
    XCTAssertFalse(try row(window, pages[1]).muteButton.isHidden, "a quiet muted page keeps its button")
    try row(window, pages[1]).muteButton.performClick(nil)
    XCTAssertEqual(engine.snapshot(of: pages[1])?.isMuted, false)
    XCTAssertTrue(try row(window, pages[1]).muteButton.isHidden)
    XCTAssertEqual(window.currentTab, pages[2], "muting does not show the page")
    window.window?.performClose(nil)
  }

  /// A hovered row shows its close button; it closes that page, the shown page stays shown, and on the last page it
  /// closes the window, as Cmd-W does. VoiceOver reads "Close" with the title, hovered or not.
  func testAHoveredRowHasACloseButton() throws {
    let (window, engine) = try makeWindow()
    fill(window, to: 3)
    let pages = window.privatePageOrder.pages
    engine.setDocumentTitle(pages[0], "Your cart")
    window.rootView.layoutSubtreeIfNeeded()
    window.sidebarController.view.layoutSubtreeIfNeeded()
    let first = try row(window, pages[0])
    first.layoutSubtreeIfNeeded()
    XCTAssertEqual(first.closeButton.alphaValue, 0, "no close button until hovered")
    XCTAssertNil(first.closeButton.hitTest(NSPoint(x: first.closeButton.frame.midX, y: first.closeButton.frame.midY)))
    XCTAssertEqual(first.closeButton.accessibilityLabel(), "Close Your cart")
    let titleWidth = first.titleLabel.frame.width

    first.setHovered(true)
    first.layoutSubtreeIfNeeded()
    XCTAssertEqual(first.closeButton.alphaValue, 1)
    XCTAssertLessThan(first.titleLabel.frame.width, titleWidth, "the title makes room for the button")
    XCTAssertEqual(first.backgroundFill, ShellTokens.sidebarItemHovered.resolve(first.flavor), "the hovered fill")

    first.closeButton.performClick(nil)
    XCTAssertNil(engine.snapshot(of: pages[0]))
    XCTAssertEqual(window.currentTab, pages[2], "closing a hidden page leaves the shown one")
    XCTAssertEqual(rows(window).map(\.tab), [pages[1], pages[2]])

    try row(window, pages[2]).closeButton.performClick(nil)
    XCTAssertEqual(window.currentTab, pages[1], "closing the shown page shows the one before it")
    try row(window, pages[1]).closeButton.performClick(nil)
    XCTAssertTrue(window.isClosed, "the last page's close button closes the window")
  }

  /// Worst case: the smallest window, 20 pages, every page playing sound and every other title 80 characters. Each
  /// row keeps its favicon, some title and its mute button inside the row; the hovered row fits its close button too.
  func testEveryPagePlayingInTheSmallestWindow() throws {
    let (window, engine) = try makeWindow()
    let nsWindow = try XCTUnwrap(window.window)
    nsWindow.setFrame(NSRect(x: 80, y: 80, width: 640, height: 420), display: false)
    window.rootView.sidebarWidth = ShellMetrics.standard.sidebarMinWidth
    fill(window, to: 20)
    let long = String(String(repeating: "Search results for a very long query ", count: 3).prefix(80))
    for (index, tab) in window.privatePageOrder.pages.enumerated() {
      engine.setDocumentTitle(tab, index.isMultiple(of: 2) ? long : "x")
      engine.setAudible(tab, true)
    }
    window.rootView.layoutSubtreeIfNeeded()
    window.sidebarController.view.layoutSubtreeIfNeeded()
    for row in rows(window) {
      row.layoutSubtreeIfNeeded()
      XCTAssertFalse(row.muteButton.isHidden)
      XCTAssertEqual(row.muteButton.frame.size, NSSize(width: 16, height: 16))
      XCTAssertLessThanOrEqual(row.muteButton.frame.maxX, row.bounds.width - PrivatePageRowView.padding)
      XCTAssertLessThanOrEqual(row.titleLabel.frame.maxX, row.muteButton.frame.minX - PrivatePageRowView.gap)
      XCTAssertGreaterThan(row.titleLabel.frame.width, 20, "some title stays")
      XCTAssertGreaterThanOrEqual(row.faviconView.frame.minX, PrivatePageRowView.padding)
    }
    let hovered = rows(window)[0]
    hovered.setHovered(true)
    hovered.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(hovered.closeButton.frame.maxX, hovered.bounds.width - PrivatePageRowView.padding)
    XCTAssertLessThanOrEqual(hovered.muteButton.frame.maxX, hovered.closeButton.frame.minX - PrivatePageRowView.gap)
    XCTAssertLessThanOrEqual(hovered.titleLabel.frame.maxX, hovered.muteButton.frame.minX - PrivatePageRowView.gap)
    XCTAssertGreaterThan(hovered.titleLabel.frame.width, 0)

    window.openPrivately(EngineWorld.url("refused"), inNewPage: true)
    XCTAssertNil(window.toasts.current?.actionTitle, "every hidden page plays: nothing to close for the user")
    window.window?.performClose(nil)
  }

  /// VoiceOver reaches a row's buttons as its children: the mute button while the page has sound, the close button
  /// always.
  func testVoiceOverReachesTheRowButtons() throws {
    let (window, engine) = try makeWindow()
    let page = try XCTUnwrap(window.currentTab)
    engine.setDocumentTitle(page, "Radio")
    var children = try row(window, page).accessibilityChildren() as? [NSView] ?? []
    XCTAssertEqual(children.map { $0.accessibilityLabel() }, ["Close Radio"])
    engine.setAudible(page, true)
    children = try row(window, page).accessibilityChildren() as? [NSView] ?? []
    XCTAssertEqual(children.map { $0.accessibilityLabel() }, ["Mute Radio", "Close Radio"])
    XCTAssertTrue(children.allSatisfy { $0.accessibilityRole() == .button })
    window.window?.performClose(nil)
  }

  /// Two closes within the 0.20 s motion: the second one moves the rows on from where they are on screen, not from
  /// where the first one left their frames, so they never jump. The list's clock is frozen (layer speed 0), so the
  /// on-screen place is the first move's start, without waiting.
  func testASecondCloseMidMotionMovesOnFromTheScreen() throws {
    let tabs = (0..<5).map { _ in TabID() }
    func contents(_ tabs: [TabID]) -> [PrivatePageRowContent] {
      tabs.map { PrivatePageRowContent(tab: $0, title: "Page", url: nil, favicon: nil, isShown: false) }
    }
    let list = PrivatePagesView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
    list.reduceMotion = { false }
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 400), styleMask: [.borderless],
                        backing: .buffered, defer: false)
    host.isReleasedWhenClosed = false
    host.contentView = list
    host.orderFront(nil)
    defer { host.orderOut(nil) }
    list.setPages(contents(tabs))
    list.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let documentLayer = try XCTUnwrap(list.rows.first?.layer?.superlayer, "the rows' layers are in the tree")
    documentLayer.speed = 0                                   // frozen: every motion stays at its start
    documentLayer.timeOffset = 0
    host.displayIfNeeded()
    CATransaction.flush()
    let row = try XCTUnwrap(list.rows.first { $0.tab == tabs[4] })
    let onScreenAtStart = try XCTUnwrap(row.layer?.position)

    list.setPages(contents(Array(tabs.dropFirst())))          // the first close: row 4 starts moving up one row
    CATransaction.flush()
    list.setPages(contents(Array(tabs.dropFirst(2))))         // the second close, while the first move has not run
    let move = try XCTUnwrap(row.layer?.animation(forKey: PrivatePagesMotion.moveKey) as? CABasicAnimation)
    let from = try XCTUnwrap((move.fromValue as? NSValue)?.pointValue)
    XCTAssertEqual(from.y, onScreenAtStart.y, accuracy: 0.5, "the second move starts where the row is on screen")
  }
}
