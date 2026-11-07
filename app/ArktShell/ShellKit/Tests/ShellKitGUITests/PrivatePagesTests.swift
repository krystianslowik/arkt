import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@_spi(Smoke) @testable import ShellUI

/// #668 (design/private-pages, direction B): a blank or incognito window's sidebar lists that window's own pages in
/// open order, at most 20. Past the cap the new page does not open and a toast offers Close Oldest. Cmd-W closes the
/// shown page, and the window on the last one. Nothing reaches the shared sidebar, the Archive or the saved session.
/// InMemoryEngine; no wall-clock waits.
@MainActor
final class PrivatePagesTests: XCTestCase {
  private var sets: [ShellWindowSet] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    for set in sets { for controller in set.controllers { controller.window?.orderOut(nil) } }
    sets = []
  }

  private struct Fixture {
    let set: ShellWindowSet
    let source: ModelSidebarSource
    let engine: InMemoryEngine
  }

  private func makeFixture() throws -> Fixture {
    var sidebar = SidebarModel.Sidebar()
    let work = sidebar.addSpace(title: "Work")
    _ = try sidebar.addTab(url: EngineWorld.url("shared"), title: "Shared", in: .today(work))
    let engine = InMemoryEngine()
    let source = ModelSidebarSource(sidebar: sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return Fixture(set: set, source: source, engine: engine)
  }

  /// A private window with one page, opened from the command bar as a user would.
  private func privateWindow(_ f: Fixture, incognito: Bool = true) throws -> ShellWindowController {
    let window = f.set.openWindow(opensFirstTab: false)
    if incognito { window.makeIncognito() } else { window.makeBlank() }
    window.sidebarController.view.privatePages.reduceMotion = { true }
    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("first-page.example")
    window.commandBar.commit()
    _ = try XCTUnwrap(window.currentTab)
    return window
  }

  /// Opens pages with Paste URL as New Tab's path until the window has `count`.
  private func fill(_ window: ShellWindowController, to count: Int) {
    while window.privatePageOrder.pages.count < count {
      window.openPrivately(EngineWorld.url("page-\(window.privatePageOrder.pages.count)"), inNewPage: true)
    }
  }

  private func list(_ window: ShellWindowController) -> PrivatePagesView { window.sidebarController.view.privatePages }

  private func rowTabs(_ window: ShellWindowController) -> [TabID] { list(window).rows.map(\.tab) }

  // MARK: The list

  /// The rows follow open order, kept apart from `privateTabs` (README "Order"): a background page goes at the
  /// bottom, not next to its opener, and showing a page never moves its row.
  func testRowsFollowOpenOrderNotTheShowOrder() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    let first = try XCTUnwrap(window.currentTab)
    let engineWindow = try XCTUnwrap(window.engineWindow)
    let popup = f.engine.engineCreateTab(url: EngineWorld.url("popup"), in: engineWindow, opener: first)
    let background = f.engine.engineCreateTab(url: EngineWorld.url("background"), in: engineWindow, opener: first,
                                              active: false)
    XCTAssertEqual(window.privateTabs, [first, background, popup], "privateTabs keeps the order pages come back in")
    XCTAssertEqual(window.privatePageOrder.pages, [first, popup, background])
    XCTAssertEqual(rowTabs(window), [first, popup, background])
    XCTAssertEqual(list(window).rows.filter(\.isShown).map(\.tab), [popup])

    list(window).rows[0].accessibilityPerformPress()
    XCTAssertEqual(window.currentTab, first, "a row click shows its page")
    XCTAssertEqual(f.engine.activeTab(in: engineWindow), first, "and the engine is told")
    XCTAssertEqual(rowTabs(window), [first, popup, background], "the list does not reorder")
    XCTAssertEqual(list(window).rows.filter(\.isShown).map(\.tab), [first])

    f.engine.engineActivate(background)
    XCTAssertEqual(window.currentTab, background)
    XCTAssertEqual(rowTabs(window), [first, popup, background])

    f.engine.engineCloseTab(popup)
    XCTAssertEqual(rowTabs(window), [first, background], "a closed page leaves the list")
    window.window?.performClose(nil)
  }

  /// Rows show the page title and follow its changes; an empty title falls back to the address.
  func testRowsShowAndFollowThePageTitle() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    let page = try XCTUnwrap(window.currentTab)
    f.engine.setDocumentTitle(page, "Your cart - Example Store")
    XCTAssertEqual(list(window).rows.first?.titleLabel.stringValue, "Your cart - Example Store")
    XCTAssertEqual(list(window).rows.first?.accessibilityLabel(), "Your cart - Example Store")
    f.engine.setDocumentTitle(page, "")
    XCTAssertEqual(list(window).rows.first?.titleLabel.stringValue,
                   f.engine.snapshot(of: page)?.url.map(HostDisplay.hostOrAddress))
    window.window?.performClose(nil)
  }

  /// "Pages" is a list; each row is a button named by its title, and the shown page's row reads as selected.
  func testVoiceOverReadsAListOfPageButtons() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    fill(window, to: 3)
    let pages = list(window)
    XCTAssertEqual(pages.listView.accessibilityRole(), .list)
    XCTAssertEqual(pages.listView.accessibilityLabel(), "Pages")
    XCTAssertEqual(pages.listView.accessibilityChildren()?.count, 3)
    for row in pages.rows {
      XCTAssertEqual(row.accessibilityRole(), .button)
      XCTAssertEqual(row.accessibilityLabel(), row.titleLabel.stringValue)
      XCTAssertEqual(row.isAccessibilitySelected(), row.tab == window.currentTab)
    }
    XCTAssertFalse(pages.titleLabel.isAccessibilityElement(), "the list carries the name, not a second element")
    window.window?.performClose(nil)
  }

  /// The footer names the window's kind, in the band where a normal window has its bottom bar; a normal window shows
  /// neither the list nor the label.
  func testFooterNamesTheWindowKindAndReplacesTheBottomBar() throws {
    let f = try makeFixture()
    let normal = f.set.openWindow()
    XCTAssertTrue(normal.sidebarController.view.privatePages.isHidden)
    XCTAssertTrue(normal.sidebarController.view.windowKindLabel.isHidden)
    XCTAssertFalse(normal.sidebarController.view.bottomBar.isHidden)
    for incognito in [false, true] {
      let window = try privateWindow(f, incognito: incognito)
      let sidebar = window.sidebarController.view
      sidebar.layoutSubtreeIfNeeded()
      XCTAssertEqual(sidebar.windowKindLabel.stringValue, incognito ? "Incognito" : "Blank")
      XCTAssertFalse(sidebar.windowKindLabel.isHidden)
      XCTAssertTrue(sidebar.bottomBar.isHidden, "no Archive or New Tab in the footer band")
      XCTAssertFalse(sidebar.privatePages.isHidden)
      let band = NSRect(x: 0, y: sidebar.bounds.height - SidebarContainerView.privateFooterHeight,
                        width: sidebar.bounds.width, height: SidebarContainerView.privateFooterHeight)
      XCTAssertTrue(band.contains(sidebar.windowKindLabel.frame), "the label sits in the 40 pt band")
      XCTAssertLessThanOrEqual(sidebar.privatePages.frame.maxY, band.minY, "the list ends above the footer")
      window.window?.performClose(nil)
    }
  }

  /// The bottom bar is gone in a private window, but Extensions is not: the same button sits at the trailing end of
  /// the footer band, beside the window's kind, opens the same panel and dims with the sidebar. Archive, New Tab and
  /// Library stay out of reach.
  func testExtensionsSitsInTheFooterBand() throws {
    let f = try makeFixture()
    for incognito in [false, true] {
      let window = try privateWindow(f, incognito: incognito)
      window.window?.setFrame(NSRect(x: 0, y: 0, width: 640, height: 420), display: false)
      let sidebar = window.sidebarController.view
      sidebar.layoutSubtreeIfNeeded()
      let button = try XCTUnwrap(window.extensionsButton)
      XCTAssertTrue(sidebar.extensionsButton === button)
      XCTAssertFalse(button.isHiddenOrHasHiddenAncestor, "Extensions is reachable in a private window")
      XCTAssertFalse(button.isDescendant(of: sidebar.bottomBar))
      XCTAssertTrue(sidebar.bottomBar.isHidden, "Archive, New Tab and Library stay hidden")
      XCTAssertEqual(button.accessibilityLabel(), "Extensions")
      XCTAssertEqual(button.toolTip, "Extensions")

      let frame = sidebar.convert(button.bounds, from: button)
      let footer = SidebarContainerView.privateFooterHeight
      let band = NSRect(x: 0, y: sidebar.bounds.height - footer, width: sidebar.bounds.width, height: footer)
      XCTAssertTrue(band.contains(frame), "the button sits in the 40 pt band")
      XCTAssertEqual(frame.midY, band.midY, accuracy: 0.5, "centered in the band, as the label")
      XCTAssertEqual(frame.maxX, sidebar.bounds.width - SidebarMetrics.horizontalPadding,
                     "at the trailing end, as in the bottom bar")
      XCTAssertEqual(frame.width, SidebarMetrics.bottomBarButtonSize)
      XCTAssertFalse(frame.intersects(sidebar.windowKindLabel.frame), "the kind label never runs under it")
      XCTAssertEqual(sidebar.windowKindLabel.frame.midX, band.midX, accuracy: 0.5, "the kind stays centered")
      XCTAssertNotNil(button.image, "drawn in the chrome flavor's foreground")

      sidebar.isDimmed = true
      XCTAssertEqual(button.alphaValue, SidebarContainerView.dimmedAlpha, "dims with the sidebar when not key")
      sidebar.isDimmed = false
      XCTAssertEqual(button.alphaValue, 1)

      let panel = try XCTUnwrap(window.extensionsPanel)
      window.window?.orderFront(nil)
      button.performClick(nil)
      XCTAssertTrue(panel.isShown, "the same action opens the Extensions panel")
      let panelFrame = try XCTUnwrap(panel.panel?.frame)
      let host = try XCTUnwrap(window.window)
      let buttonOnScreen = host.convertToScreen(button.convert(button.bounds, to: nil))
      let sidebarOnScreen = host.convertToScreen(sidebar.convert(sidebar.bounds, to: nil))
      XCTAssertEqual(panelFrame.minY, buttonOnScreen.maxY + ExtensionsPanelMetrics.gap, accuracy: 0.5,
                     "the panel opens just above the button in the band")
      XCTAssertEqual(panelFrame.minX, sidebarOnScreen.minX + ExtensionsPanelMetrics.sidebarInset, accuracy: 0.5,
                     "12 pt in from the sidebar, as from the bottom bar")
      XCTAssertTrue(button.isOpen)
      panel.hide(keyboard: false)
      XCTAssertFalse(button.isOpen)
      window.window?.performClose(nil)
    }
  }

  /// A container switched back to a normal window returns the button to the bottom bar, left of New Tab.
  func testExtensionsReturnsToTheBottomBarInANormalWindow() {
    let container = SidebarContainerView(source: StubSidebar.sample())
    container.frame = NSRect(x: 0, y: 0, width: ShellMetrics.standard.sidebarMinWidth, height: 420)
    let button = ExtensionsButton()
    container.extensionsButton = button
    container.setPrivateKind(.blank)
    container.isDimmed = true
    container.layoutSubtreeIfNeeded()
    XCTAssertFalse(button.isDescendant(of: container.bottomBar))
    XCTAssertEqual(button.alphaValue, SidebarContainerView.dimmedAlpha)

    container.setPrivateKind(.standard)
    container.layoutSubtreeIfNeeded()
    XCTAssertTrue(button.isDescendant(of: container.bottomBar))
    XCTAssertEqual(button.alphaValue, 1, "the bottom bar carries the dimming, not the button twice")
    XCTAssertEqual(button.frame.maxX, container.newTabButton.frame.minX)
  }

  /// The welcome card ("New Space") is for a profile without Spaces. A blank or incognito window draws no Spaces, but
  /// its pages are on the card: the welcome never covers them.
  func testThePageIsNotCoveredByTheWelcomeCard() throws {
    let f = try makeFixture()
    for incognito in [false, true] {
      let window = try privateWindow(f, incognito: incognito)
      XCTAssertFalse(window.isShowingEmptyState)
      XCTAssertNil(window.rootView.card.emptyStateView, "no welcome over the private page")
      window.window?.performClose(nil)
    }
    let normal = f.set.openWindow()
    XCTAssertFalse(normal.isShowingEmptyState, "a normal window with Spaces shows no welcome either")
  }

  /// An update or announcement banner (#648) in a private window sits above the footer band and the Pages list ends
  /// above the banner: it covers no row and not the footer label.
  func testABannerLeavesTheRowsAndTheFooterUncovered() throws {
    let container = SidebarContainerView(source: StubSidebar.sample())
    container.frame = NSRect(x: 0, y: 0, width: ShellMetrics.standard.sidebarMinWidth, height: 420)
    container.setPrivateKind(.incognito)
    container.setBanner(SidebarNotice.update(version: "1.4.2"), animated: false, reduceMotion: true)
    container.layoutSubtreeIfNeeded()
    let banner = container.convert(container.banner.row.bounds, from: container.banner.row)
    XCTAssertGreaterThan(banner.height, 0)
    XCTAssertLessThanOrEqual(container.privatePages.frame.maxY, banner.minY, "the list ends above the banner")
    XCTAssertLessThanOrEqual(banner.maxY, container.windowKindLabel.frame.minY, "the banner is above the footer label")
    XCTAssertFalse(banner.intersects(container.windowKindLabel.frame))

    container.setBanner(nil, animated: false, reduceMotion: true)
    container.layoutSubtreeIfNeeded()
    XCTAssertEqual(container.privatePages.frame.maxY, 420 - SidebarContainerView.privateFooterHeight,
                   "without a banner the list reaches the footer band")
  }

  // MARK: The cap

  /// The 21st page of any kind does not open: Paste URL as New Tab, a foreground `window.open` and a background
  /// `target=_blank` page. The shown page stays shown, the toast says why and offers Close Oldest.
  func testTheTwentyFirstPageDoesNotOpen() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    fill(window, to: 20)
    let shown = try XCTUnwrap(window.currentTab)
    let engineWindow = try XCTUnwrap(window.engineWindow)
    let tabsBefore = Set(f.engine.tabIDs)
    XCTAssertEqual(rowTabs(window).count, 20)

    window.openPrivately(EngineWorld.url("pasted-21"), inNewPage: true)
    XCTAssertEqual(Set(f.engine.tabIDs), tabsBefore, "Paste URL as New Tab makes no page")
    XCTAssertEqual(window.currentTab, shown)
    XCTAssertEqual(window.toasts.current?.text, "This window has 20 pages open, the most it keeps.")
    XCTAssertEqual(window.toasts.current?.actionTitle, "Close Oldest")
    window.toasts.dismiss()

    let popup = f.engine.engineCreateTab(url: EngineWorld.url("popup-21"), in: engineWindow, opener: shown)
    XCTAssertNil(f.engine.snapshot(of: popup), "a foreground window.open page is closed at once")
    XCTAssertEqual(window.currentTab, shown, "the shown page stays shown")
    XCTAssertEqual(f.engine.activeTab(in: engineWindow), shown, "the engine's pick is answered with the shown page")
    XCTAssertEqual(window.toasts.current?.actionTitle, "Close Oldest")
    window.toasts.dismiss()

    let background = f.engine.engineCreateTab(url: EngineWorld.url("background-21"), in: engineWindow,
                                              opener: shown, active: false)
    XCTAssertNil(f.engine.snapshot(of: background), "a background target=_blank page is closed at once")
    XCTAssertEqual(window.currentTab, shown)
    XCTAssertNotNil(window.toasts.current)

    XCTAssertEqual(Set(f.engine.tabIDs), tabsBefore)
    XCTAssertEqual(window.privatePageOrder.pages.count, 20)
    XCTAssertEqual(window.privateTabs.count, 20)
    XCTAssertEqual(rowTabs(window).count, 20)

    window.commandBar.show(.newTab)
    window.commandBar.setQueryForTesting("navigate-at-cap.example")
    window.commandBar.commit()
    XCTAssertEqual(window.currentTab, shown, "a command-bar visit navigates the shown page, which the cap allows")
    XCTAssertTrue(f.engine.snapshot(of: shown)?.url?.absoluteString.contains("navigate-at-cap.example") ?? false)
    window.window?.performClose(nil)
  }

  /// Close Oldest closes the top row that is neither shown nor playing sound, a muted page that plays included, and
  /// the refused page does not open afterwards.
  func testCloseOldestSparesTheShownPageAndPagesPlayingSound() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    fill(window, to: 20)
    let order = window.privatePageOrder.pages
    list(window).rows[0].accessibilityPerformPress()        // the first page is shown, as in the `cap` screen
    XCTAssertEqual(window.currentTab, order[0])
    f.engine.setAudible(order[1], true)
    f.engine.setMuted(order[1], muted: true)                  // muted, still playing: spared
    f.engine.setMuted(order[2], muted: true)                  // muted and quiet: closable
    let tabsBefore = Set(f.engine.tabIDs)

    window.openPrivately(EngineWorld.url("refused"), inNewPage: true)
    XCTAssertEqual(window.toasts.current?.actionTitle, "Close Oldest")
    window.toasts.performActionForTesting()
    XCTAssertNil(f.engine.snapshot(of: order[2]), "the earliest page neither shown nor playing closes")
    XCTAssertNotNil(f.engine.snapshot(of: order[0]))
    XCTAssertNotNil(f.engine.snapshot(of: order[1]))
    XCTAssertEqual(Set(f.engine.tabIDs), tabsBefore.subtracting([order[2]]), "the refused page does not open")
    XCTAssertEqual(window.currentTab, order[0])
    XCTAssertEqual(rowTabs(window), order.filter { $0 != order[2] })
    XCTAssertNil(window.toasts.current, "the toast goes")

    window.openPrivately(EngineWorld.url("repeated"), inNewPage: true)
    XCTAssertEqual(window.privatePageOrder.pages.count, 20, "repeating the click opens the page")
    XCTAssertEqual(window.privatePageOrder.pages.last, window.currentTab)
    window.window?.performClose(nil)
  }

  /// When every page is shown or playing sound nothing can be closed for the user: the toast has no action.
  func testEveryPageShownOrPlayingLeavesTheToastWithoutAnAction() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    fill(window, to: 20)
    let shown = try XCTUnwrap(window.currentTab)
    for tab in window.privatePageOrder.pages where tab != shown { f.engine.setAudible(tab, true) }
    XCTAssertNil(window.privatePageToCloseOldest)

    window.openPrivately(EngineWorld.url("refused"), inNewPage: true)
    XCTAssertEqual(window.toasts.current?.text, "This window has 20 pages open. Close one to open another.")
    XCTAssertNil(window.toasts.current?.actionTitle)
    XCTAssertEqual(window.privatePageOrder.pages.count, 20)
    window.window?.performClose(nil)
  }

  /// The cap toast takes the window's flavor: these windows have no Space theme.
  func testTheCapToastFollowsTheWindowFlavor() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    window.sidebarController.view.setFlavor(.dark)
    fill(window, to: 20)
    window.openPrivately(EngineWorld.url("refused"), inNewPage: true)
    XCTAssertEqual(window.toasts.view?.flavor, .dark)
    window.window?.performClose(nil)
  }

  // MARK: Cmd-W

  /// Cmd-W closes the shown page and the page shown before it comes back; on the last page it closes the window.
  func testCmdWClosesTheShownPageThenTheWindowOnTheLastOne() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    let first = try XCTUnwrap(window.currentTab)
    fill(window, to: 3)
    let order = window.privatePageOrder.pages
    list(window).rows[1].accessibilityPerformPress()
    XCTAssertEqual(window.currentTab, order[1])

    window.closeTab(nil)
    XCTAssertNil(f.engine.snapshot(of: order[1]))
    XCTAssertEqual(window.currentTab, order[2], "the page shown before it comes back")
    XCTAssertEqual(rowTabs(window), [order[0], order[2]])
    XCTAssertFalse(window.isClosed)

    window.closeTab(nil)
    XCTAssertEqual(window.currentTab, first)
    XCTAssertEqual(rowTabs(window), [first])
    XCTAssertFalse(window.isClosed)

    window.closeTab(nil)
    XCTAssertTrue(window.isClosed, "Cmd-W on the last page closes the window")
    XCTAssertTrue(f.engine.tabIDs.isEmpty)
  }

  /// Close Tab on a crashed private page closes it as Cmd-W does (#667): that page alone, the window with the last.
  func testCloseOnACrashedPrivatePageClosesOnlyThatPage() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    fill(window, to: 2)
    let crashed = try XCTUnwrap(window.currentTab)
    f.engine.crash(crashed, status: .crashed)
    try XCTUnwrap(window.crashedTabs.onClose)(crashed)
    XCTAssertNil(f.engine.snapshot(of: crashed))
    XCTAssertFalse(window.isClosed)
    XCTAssertEqual(rowTabs(window).count, 1)
    let last = try XCTUnwrap(window.currentTab)
    f.engine.crash(last, status: .crashed)
    try XCTUnwrap(window.crashedTabs.onClose)(last)
    XCTAssertTrue(window.isClosed, "the last page closes the window")
  }

  // MARK: Nothing leaves the window

  /// Twenty pages, refusals, Close Oldest and Cmd-W: no sidebar save, no row on the shared sidebar, nothing archived
  /// and no session saved for the window.
  func testNothingReachesTheSharedSidebarArchiveOrSession() throws {
    let f = try makeFixture()
    var saves = 0
    f.source.onDidChange = { _ in saves += 1 }
    let before = f.source.sidebar
    for incognito in [false, true] {
      let window = try privateWindow(f, incognito: incognito)
      var archived: [NodeID] = []
      window.onArchive = { archived.append(contentsOf: $0) }
      fill(window, to: 20)
      window.openPrivately(EngineWorld.url("refused"), inNewPage: true)
      window.toasts.performActionForTesting()
      window.closeTab(nil)
      XCTAssertFalse(window.savesSession)
      XCTAssertTrue(archived.isEmpty, "nothing is archived")
      XCTAssertTrue(window.sidebarController.spaces.isEmpty)
      window.window?.performClose(nil)
    }
    XCTAssertEqual(saves, 0, "no sidebar save")
    XCTAssertEqual(f.source.sidebar, before, "nothing reaches the shared sidebar")
  }

  // MARK: Worst case

  /// The smallest window (640 x 420, 150 pt sidebar), 20 pages with 80-character and one-letter titles: rows keep
  /// their 34 pt pitch inside the list, titles truncate at the tail, only the rows scroll, the list fades while rows
  /// are hidden below and the footer stays in its band. The shown last row scrolls into view, at once under Reduce
  /// Motion and with the system scroll animation otherwise.
  func testTwentyRowsInTheSmallestWindow() throws {
    let f = try makeFixture()
    let window = try privateWindow(f)
    let nsWindow = try XCTUnwrap(window.window)
    nsWindow.setFrame(NSRect(x: 80, y: 80, width: 640, height: 420), display: false)
    window.rootView.sidebarWidth = ShellMetrics.standard.sidebarMinWidth
    let long = String(repeating: "Search results for a very long query ", count: 3).prefix(80)
    fill(window, to: 20)
    for (index, tab) in window.privatePageOrder.pages.enumerated() {
      f.engine.setDocumentTitle(tab, index.isMultiple(of: 2) ? String(long) : "x")
    }
    list(window).rows[0].accessibilityPerformPress()
    window.rootView.layoutSubtreeIfNeeded()
    let sidebar = window.sidebarController.view
    sidebar.layoutSubtreeIfNeeded()
    let pages = list(window)
    pages.layoutSubtreeIfNeeded()

    XCTAssertEqual(sidebar.bounds.width, ShellMetrics.standard.sidebarMinWidth)
    XCTAssertEqual(pages.rows.count, 20)
    let width = pages.scrollView.contentSize.width
    for (index, row) in pages.rows.enumerated() {
      XCTAssertEqual(row.frame, NSRect(x: 0, y: CGFloat(index) * 34, width: width, height: 34))
      XCTAssertLessThanOrEqual(row.titleLabel.frame.maxX, row.bounds.width - PrivatePageRowView.padding)
      XCTAssertGreaterThan(row.titleLabel.frame.width, 0)
      XCTAssertEqual(row.titleLabel.lineBreakMode, .byTruncatingTail)
    }
    XCTAssertEqual(pages.rows[0].titleLabel.stringValue.count, 80)
    let visibleRows = Int(pages.scrollView.contentView.bounds.height / 34)
    XCTAssertGreaterThanOrEqual(visibleRows, 5, "about 7 rows fit at the smallest window")
    XCTAssertLessThan(visibleRows, 20, "the list scrolls")
    XCTAssertTrue(pages.hasRowsBelow)
    XCTAssertIdentical(pages.scrollView.layer?.mask, pages.fade, "rows hidden below fade out")
    // Built before the window showed, then shown: the fade follows the layer's orientation in the window.
    nsWindow.orderFront(nil)
    defer { nsWindow.orderOut(nil) }
    nsWindow.displayIfNeeded()                            // the layer tree is assembled on the first display
    CATransaction.flush()
    let flipped = pages.scrollView.layer?.contentsAreFlipped() == true
    let fadeTop = CGPoint(x: 0.5, y: flipped ? 0 : 1)
    XCTAssertEqual(pages.fade.startPoint, fadeTop, "the fade runs from the top of the list (opaque) to its bottom")
    XCTAssertEqual(pages.fade.locations?.last, 1)
    XCTAssertEqual((pages.fade.colors?.first).map { ($0 as! CGColor).alpha }, 1, "opaque at the top")
    let footerTop = sidebar.bounds.height - SidebarContainerView.privateFooterHeight
    XCTAssertLessThanOrEqual(pages.frame.maxY, footerTop)
    XCTAssertGreaterThanOrEqual(sidebar.windowKindLabel.frame.minY, footerTop)
    XCTAssertGreaterThan(pages.titleLabel.frame.minY, 0)

    list(window).rows[19].accessibilityPerformPress()
    XCTAssertEqual(pages.lastReveal?.tab, pages.rows[19].tab)
    XCTAssertEqual(pages.lastReveal?.animated, false, "Reduce Motion: the scroll jumps")
    let clip = pages.scrollView.contentView.bounds
    XCTAssertEqual(clip.maxY, pages.listView.frame.height, accuracy: 0.5, "the shown last row is in view at once")
    XCTAssertFalse(pages.hasRowsBelow)
    XCTAssertNil(pages.scrollView.layer?.mask, "no fade once the last row is in view")

    // A background page added at the bottom does not scroll the list (the window is full, so close one first).
    list(window).rows[0].accessibilityPerformPress()
    let top = pages.scrollView.contentView.bounds.origin
    XCTAssertEqual(top.y, 0, accuracy: 0.5)
    window.closeOldestPrivatePage()
    let engineWindow = try XCTUnwrap(window.engineWindow)
    f.engine.engineCreateTab(url: EngineWorld.url("late"), in: engineWindow, opener: window.currentTab, active: false)
    XCTAssertEqual(pages.rows.count, 20)
    XCTAssertEqual(pages.scrollView.contentView.bounds.origin, top, "a background page does not scroll the list")

    // Without Reduce Motion the reveal uses the system scroll animation; nothing here waits for it to run.
    pages.reduceMotion = { false }
    list(window).rows[19].accessibilityPerformPress()
    XCTAssertEqual(pages.lastReveal?.tab, pages.rows[19].tab)
    XCTAssertEqual(pages.lastReveal?.animated, true, "the system scroll animation without Reduce Motion")
    window.window?.performClose(nil)
  }
}
