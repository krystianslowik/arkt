import AppKit
import XCTest
@testable import ShellUI

/// #111 (design/archive-search): the Archive window's unified bar, search, filters and chips, sidebar rows with
/// opened folders and match highlights, the footer count, Clear Archive, the education banner and the keyboard.
@MainActor
final class ArchiveSearchWindowTests: XCTestCase {
  private var windows: [NSWindow] = []
  private var savedReduceMotion: (@MainActor () -> Bool)?

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    savedReduceMotion = ArchiveMotion.reduceMotion
    ArchiveMotion.reduceMotion = { true }           // deterministic: no fades while asserting visibility
  }

  override func tearDown() async throws {
    for window in windows {
      for sheet in window.sheets { window.endSheet(sheet) }
      window.close()
    }
    windows = []
    if let savedReduceMotion { ArchiveMotion.reduceMotion = savedReduceMotion }
  }

  private func makeWindow(_ source: RecordingArchiveSource) -> ArchiveWindowController {
    let controller = ArchiveWindowController(dataSource: source)
    controller.searchDebounce = .zero
    if let window = controller.window { windows.append(window) }
    return controller
  }

  private static func row(_ title: String, kind: ArchiveRowKind = .tab(URL(string: "https://a.example")),
                          children: [ArchiveChildRow] = []) -> ArchiveRow {
    ArchiveRow(id: UUID(), title: title, detail: "a.example - Work - 1 hour ago", reason: "Closed", kind: kind,
               place: .space(color: nil), time: "1h", matchedChildren: children)
  }

  private static func page(_ rows: [ArchiveRow], total: Int? = nil, matching: Int? = nil,
                           more: Bool = false) -> ArchiveListPage {
    ArchiveListPage(rows: rows, unreadable: 0, mayHaveMore: more, total: total ?? rows.count,
                    matching: matching ?? rows.count)
  }

  private func shown(_ source: RecordingArchiveSource) async throws -> ArchiveWindowController {
    let controller = makeWindow(source)
    controller.show()
    await controller.pendingLoad?.value
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    return controller
  }

  // MARK: - The bar

  /// Title, search field and filter button share the 52 pt bar (design section 4); the list sits in its field below.
  func testTitleSearchAndFilterShareOneBar() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One")])]
    let controller = try await shown(source)
    let bar = ArchiveMetrics.barHeight

    for view in [controller.titleLabel, controller.searchField, controller.filterButton] as [NSView] {
      XCTAssertGreaterThanOrEqual(view.frame.minY, 0)
      XCTAssertLessThanOrEqual(view.frame.maxY, bar)
    }
    XCTAssertEqual(controller.searchField.frame.height, 32)
    XCTAssertEqual(controller.filterButton.frame.size, NSSize(width: 32, height: 32))
    XCTAssertLessThan(controller.titleLabel.frame.maxX, controller.searchField.frame.minX)
    XCTAssertEqual(controller.searchField.frame.maxX + 8, controller.filterButton.frame.minX)
    let width = try XCTUnwrap(controller.window?.contentView?.bounds.width)
    XCTAssertEqual(controller.filterButton.frame.maxX, width - 10)
    XCTAssertEqual(controller.tableView.enclosingScrollView?.frame.minY ?? 0, bar + 4, accuracy: 0.5)
    XCTAssertEqual(controller.titleLabel.stringValue, "Archive")
    XCTAssertTrue(controller.window?.firstResponder === controller.tableView, "focus starts on the list")
  }

  // MARK: - Search

  func testTypingSearchesTheStoreAndHighlightsTheMatch() async throws {
    let source = RecordingArchiveSource()
    source.pages = [
      Self.page([Self.row("Quarterly report"), Self.row("Lichens")], total: 42),
      Self.page([Self.row("Quarterly report")], total: 42, matching: 1),
    ]
    let controller = try await shown(source)

    controller.setSearchText("REPORT")
    await controller.pendingLoad?.value

    XCTAssertEqual(source.queries.last, ArchiveQuery(text: "REPORT"))
    XCTAssertEqual(controller.rows.map(\.title), ["Quarterly report"])
    XCTAssertEqual(controller.footerLabel.stringValue, "1 result")
    let cell = try XCTUnwrap(controller.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true)
      as? ArchiveRowCellView)
    XCTAssertEqual(cell.titleView.highlights.map { String(cell.title[$0]) }, ["report"])
  }

  func testHighlightIgnoresCaseAndDiacritics() {
    let text = "Crème brûlée and CREME"
    let matches = ArchiveTitleView.matches(of: "creme", in: text)
    XCTAssertEqual(matches.map { String(text[$0]) }, ["Crème", "CREME"])
    XCTAssertTrue(ArchiveTitleView.matches(of: "  ", in: text).isEmpty)
  }

  /// Escape clears a non-empty search (the list reloads unfiltered), then closes the window.
  func testEscapeClearsTheSearchThenCloses() async throws {
    let source = RecordingArchiveSource()
    let controller = try await shown(source)
    controller.setSearchText("zebra")
    await controller.pendingLoad?.value
    let window = try XCTUnwrap(controller.window)

    controller.cancelOperation(nil)
    await controller.pendingLoad?.value
    XCTAssertEqual(controller.searchField.stringValue, "")
    XCTAssertEqual(source.queries.last, ArchiveQuery())
    XCTAssertTrue(window.isVisible)

    controller.cancelOperation(nil)
    XCTAssertFalse(window.isVisible)
  }

  func testDownFromTheSearchFieldSelectsTheFirstRow() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One"), Self.row("Two")])]
    let controller = try await shown(source)
    let window = try XCTUnwrap(controller.window)
    controller.focusSearch()
    let editor = try XCTUnwrap(controller.searchField.currentEditor() as? NSTextView)

    XCTAssertTrue(controller.control(controller.searchField, textView: editor,
                                     doCommandBy: #selector(NSResponder.moveDown(_:))))

    XCTAssertTrue(window.firstResponder === controller.tableView)
    XCTAssertEqual(controller.tableView.selectedRow, 0)
  }

  func testCommandFFocusesTheSearchField() async throws {
    let source = RecordingArchiveSource()
    let controller = try await shown(source)
    let window = try XCTUnwrap(controller.window)
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))

    XCTAssertTrue(window.performKeyEquivalent(with: event))

    XCTAssertNotNil(controller.searchField.currentEditor())
  }

  /// Every opening starts unfiltered with an empty search.
  func testReopeningStartsUnfiltered() async throws {
    let source = RecordingArchiveSource()
    let controller = try await shown(source)
    controller.setSearchText("old")
    await controller.pendingLoad?.value
    controller.setCloseTypeFilter(.closed)
    await controller.pendingLoad?.value
    controller.close()

    controller.show()
    await controller.pendingLoad?.value

    XCTAssertEqual(controller.query, ArchiveQuery())
    XCTAssertEqual(source.queries.last, ArchiveQuery())
    XCTAssertEqual(controller.searchField.stringValue, "")
    XCTAssertTrue(controller.chipStrip.isHidden)
  }

  // MARK: - Filters

  func testFilterMenuListsSpacesLittleArktAndCloseTypesWithChecks() async throws {
    let source = RecordingArchiveSource()
    let work = UUID()
    source.spaceOptions = [ArchiveSpaceOption(id: work, title: "Work", color: .srgb(hex: 0x3B82F6)),
                           ArchiveSpaceOption(id: UUID(), title: "Personal", color: nil)]
    let controller = try await shown(source)

    let menu = controller.makeFilterMenu()
    let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
    XCTAssertEqual(titles, ["Space", "Everywhere", "Work", "Personal", "Little Arkt", "-", "Close Type",
                            "Closed and Auto Archived", "Closed", "Auto Archived"])
    XCTAssertTrue(menu.items[0].isSectionHeader)
    XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.title), ["Everywhere", "Closed and Auto Archived"])
    XCTAssertNotNil(menu.items[2].image, "the Space's color dot")

    let workItem = menu.items[2]
    _ = workItem.target?.perform(workItem.action, with: workItem)
    await controller.pendingLoad?.value

    XCTAssertEqual(source.queries.last, ArchiveQuery(space: .space(work)))
    XCTAssertEqual(controller.makeFilterMenu().items.filter { $0.state == .on }.map(\.title),
                   ["Work", "Closed and Auto Archived"])
  }

  /// Active filters show as chips (a Space chip tinted with the Space color), the filter button stays filled, and
  /// a chip's remove button or Clear Filters takes them off.
  func testChipsShowActiveFiltersAndRemoveThem() async throws {
    let source = RecordingArchiveSource()
    let work = UUID()
    let blue = RGBA.srgb(hex: 0x3B82F6)
    source.spaceOptions = [ArchiveSpaceOption(id: work, title: "Work", color: blue)]
    source.pages = [Self.page([Self.row("One")], total: 42, matching: 3)]
    let controller = try await shown(source)
    XCTAssertTrue(controller.chipStrip.isHidden)
    XCTAssertFalse(controller.filterButton.isActive)

    controller.setSpaceFilter(.space(work))
    await controller.pendingLoad?.value
    controller.setCloseTypeFilter(.closed)
    await controller.pendingLoad?.value
    controller.window?.contentView?.layoutSubtreeIfNeeded()

    XCTAssertFalse(controller.chipStrip.isHidden)
    XCTAssertEqual(controller.chipStrip.chips.map(\.filterName), ["Work", "Closed"])
    XCTAssertEqual(controller.chipStrip.chips.map { $0.accessibilityIdentifier() },
                   [AXID.Archive.chip("Work"), AXID.Archive.chip("Closed")])
    let surface = BrandTokens.surfaceBrand.resolve(controller.chipStrip.archiveFlavor)
    XCTAssertEqual(controller.chipStrip.chips[0].displayedFill, ArchiveTokens.chipFill(blue, over: surface))
    XCTAssertTrue(controller.filterButton.isActive)
    XCTAssertEqual(controller.filterButton.accessibilityValue() as? String, "2 filters active")
    XCTAssertEqual(controller.footerLabel.stringValue, "3 of 42 items")
    XCTAssertEqual(controller.chipStrip.frame.minY, ArchiveMetrics.barHeight)
    XCTAssertGreaterThan(controller.tableView.enclosingScrollView?.frame.minY ?? 0, controller.chipStrip.frame.maxY)

    controller.chipStrip.chips[0].removeButton.performClick(nil)
    await controller.pendingLoad?.value
    XCTAssertEqual(source.queries.last, ArchiveQuery(closeType: .closed))
    XCTAssertEqual(controller.chipStrip.chips.map(\.filterName), ["Closed"])

    controller.chipStrip.clearFilters.performClick(nil)
    await controller.pendingLoad?.value
    XCTAssertEqual(source.queries.last, ArchiveQuery())
    XCTAssertTrue(controller.chipStrip.isHidden)
    XCTAssertFalse(controller.filterButton.isActive)
  }

  func testCountTextFollowsTheQuery() {
    typealias C = ArchiveWindowController
    XCTAssertEqual(C.countText(query: ArchiveQuery(), shown: 3, total: 42, matching: 42), "42 items")
    XCTAssertEqual(C.countText(query: ArchiveQuery(), shown: 1, total: 1, matching: 1), "1 item")
    XCTAssertEqual(C.countText(query: ArchiveQuery(text: "x"), shown: 3, total: 42, matching: 3), "3 results")
    XCTAssertEqual(C.countText(query: ArchiveQuery(text: "x"), shown: 1, total: 42, matching: 1), "1 result")
    XCTAssertEqual(C.countText(query: ArchiveQuery(text: "x"), shown: 0, total: 42, matching: 0), "")
    XCTAssertEqual(C.countText(query: ArchiveQuery(closeType: .closed), shown: 3, total: 42, matching: 3),
                   "3 of 42 items")
    XCTAssertEqual(C.countText(query: ArchiveQuery(), shown: 0, total: 0, matching: 0), "")
  }

  // MARK: - Rows

  /// A folder matched through a tab inside opens with that tab indented under it; the tab is not selectable and
  /// Up / Down skip it.
  func testFolderMatchedThroughAChildShowsItOpen() async throws {
    let source = RecordingArchiveSource()
    let child = ArchiveChildRow(id: UUID(), title: "Q3 report outline", url: URL(string: "https://docs.example"))
    source.pages = [Self.page([
      Self.row("Quarterly report"), Self.row("Research", kind: .folder(tabCount: 4), children: [child]),
      Self.row("Expense report"),
    ])]
    let controller = try await shown(source)
    controller.setSearchText("report")
    await controller.pendingLoad?.value

    XCTAssertEqual(controller.entries, [.item(0), .item(1), .child(item: 1, child: 0), .item(2)])
    XCTAssertEqual(controller.tableView.numberOfRows, 4)
    let folder = try XCTUnwrap(controller.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true)
      as? ArchiveRowCellView)
    folder.layoutSubtreeIfNeeded()
    XCTAssertFalse(folder.chevron.isHidden)
    XCTAssertEqual(folder.countField.stringValue, "4")
    let tab = try XCTUnwrap(controller.tableView.view(atColumn: 0, row: 2, makeIfNecessary: true)
      as? ArchiveRowCellView)
    tab.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(tab.icon.frame.minX, folder.icon.frame.minX - 1, "indented")
    XCTAssertTrue(tab.timeField.isHidden, "no trailing metadata")
    XCTAssertEqual(tab.accessibilityLabel(), "Q3 report outline, in Research")

    let table = try XCTUnwrap(controller.tableView as? ArchiveTableView)
    table.selectRowIndexes([1], byExtendingSelection: false)
    table.moveSelection(by: 1)
    XCTAssertEqual(table.selectedRow, 3, "Down skips the tab under the folder")
    table.moveSelection(by: -1)
    XCTAssertEqual(table.selectedRow, 1)
    XCTAssertFalse(controller.tableView(controller.tableView, shouldSelectRow: 2))
  }

  func testRestoringAnOpenedFolderDropsItsTabsToo() async throws {
    let source = RecordingArchiveSource()
    let child = ArchiveChildRow(id: UUID(), title: "Inside", url: nil)
    let rows = [Self.row("Research", kind: .folder(tabCount: 2), children: [child]), Self.row("Other")]
    source.pages = [Self.page(rows)]
    let controller = try await shown(source)
    controller.tableView.selectRowIndexes([0], byExtendingSelection: false)

    controller.restoreSelected(nil)

    XCTAssertEqual(source.restored, [rows[0].id])
    XCTAssertEqual(controller.entries, [.item(0)])
    XCTAssertEqual(controller.tableView.numberOfRows, 1)
  }

  func testReturnOnTheListRestoresTheSelectedRow() async throws {
    let source = RecordingArchiveSource()
    let rows = [Self.row("One"), Self.row("Two")]
    source.pages = [Self.page(rows)]
    let controller = try await shown(source)
    let table = try XCTUnwrap(controller.tableView as? ArchiveTableView)
    table.selectRowIndexes([1], byExtendingSelection: false)
    let window = try XCTUnwrap(controller.window)
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))

    table.keyDown(with: event)

    XCTAssertEqual(source.restored, [rows[1].id])
  }

  func testRowsShowStoredFaviconsAndFallBackToTheLetterTile() async throws {
    let source = RecordingArchiveSource()
    let rows = [Self.row("With icon"), Self.row("Without")]
    source.pages = [Self.page(rows)]
    let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)?.representation(using: .png, properties: [:])
    source.faviconData = [rows[0].id: try XCTUnwrap(png)]
    let controller = try await shown(source)
    for _ in 0..<50 where source.faviconRequests.isEmpty { await Task.yield() }
    for _ in 0..<50 { await Task.yield() }

    XCTAssertEqual(source.faviconRequests.first, Set(rows.map(\.id)))
    let first = try XCTUnwrap(controller.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true)
      as? ArchiveRowCellView)
    XCTAssertEqual(first.icon.image?.size, NSSize(width: 4, height: 4), "the stored favicon")
    let second = try XCTUnwrap(controller.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true)
      as? ArchiveRowCellView)
    XCTAssertEqual(second.icon.image?.size, NSSize(width: 16, height: 16), "the letter tile")
  }

  /// Restore is the one primary: a mustard pill with graphite text; disabled it is not mustard.
  func testRestoreIsAMustardPillOnlyWhileEnabled() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One")])]
    let controller = try await shown(source)
    let flavor = controller.restorePill.archiveFlavor

    XCTAssertFalse(controller.restorePill.isEnabled)
    XCTAssertNotEqual(controller.restorePill.displayedFill, BrandTokens.accent.resolve(flavor))

    controller.tableView.selectRowIndexes([0], byExtendingSelection: false)
    XCTAssertTrue(controller.restorePill.isEnabled)
    XCTAssertEqual(controller.restorePill.displayedFill, BrandTokens.accent.resolve(flavor))
    XCTAssertEqual(controller.restorePill.displayedTitleColor, BrandTokens.onAccent.resolve(flavor))
    XCTAssertEqual(controller.restorePill.frame.height, 28)
  }

  // MARK: - Empty states

  func testNoResultsSaysWhatWasSearched() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One")]), Self.page([], total: 1, matching: 0)]
    let controller = try await shown(source)
    XCTAssertTrue(controller.emptyState.isHidden)

    controller.setSearchText("zebra")
    await controller.pendingLoad?.value

    XCTAssertFalse(controller.emptyState.isHidden)
    XCTAssertEqual(controller.emptyState.titleField.stringValue, "No Results")
    XCTAssertEqual(controller.emptyState.detailField.stringValue, "Nothing in the Archive matches \u{201C}zebra\u{201D}.")
    XCTAssertFalse(controller.restoreButton.isEnabled)
    XCTAssertTrue(controller.footerLabel.isHidden)
  }

  func testEmptyArchiveSaysSoAndDisablesClearArchive() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([], total: 0, matching: 0)]
    let controller = try await shown(source)

    XCTAssertEqual(controller.emptyState.titleField.stringValue, "No Archived Tabs")
    XCTAssertFalse(controller.clearLink.isEnabled)
  }

  // MARK: - Clear Archive

  func testClearArchiveAsksWithTheCountThenClearsAndConfirms() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One")], total: 42), Self.page([], total: 0, matching: 0)]
    let controller = try await shown(source)
    XCTAssertTrue(controller.clearLink.isEnabled)

    controller.clearLink.performClick(nil)
    let sheet = try XCTUnwrap(controller.clearSheet)
    XCTAssertEqual(sheet.titleField.stringValue, "Clear the Archive?")
    XCTAssertEqual(sheet.bodyField.stringValue,
                   "All 42 archived items are permanently deleted. This cannot be undone.")
    XCTAssertNil(sheet.noteField)
    XCTAssertEqual(sheet.clearButton.keyEquivalent, "", "the destructive button has no Return key")
    XCTAssertEqual(sheet.cancelButton?.keyEquivalent, "")
    XCTAssertTrue(sheet.window?.firstResponder === sheet.cancelButton, "focus starts on Cancel")
    XCTAssertEqual(sheet.clearButton.displayedTitleColor,
                   ArchiveTokens.destructiveText.resolve(sheet.clearButton.archiveFlavor))

    sheet.clearButton.performClick(nil)
    await controller.pendingLoad?.value

    XCTAssertEqual(source.clearCount, 1)
    XCTAssertNil(controller.clearSheet)
    XCTAssertEqual(controller.toasts.current?.text, "The Archive has been cleared.")
    XCTAssertEqual(controller.emptyState.titleField.stringValue, "No Archived Tabs")
  }

  func testCancellingClearArchiveKeepsEverything() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One")])]
    let controller = try await shown(source)

    controller.confirmClearArchive()
    let sheet = try XCTUnwrap(controller.clearSheet)
    sheet.window?.cancelOperation(nil)

    XCTAssertEqual(source.clearCount, 0)
    XCTAssertNil(controller.clearSheet)
    XCTAssertEqual(controller.rows.count, 1)
  }

  func testClearArchiveWithFiltersSaysHiddenItemsAreIncluded() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One")], total: 42, matching: 1)]
    let controller = try await shown(source)
    controller.setCloseTypeFilter(.autoArchived)
    await controller.pendingLoad?.value

    controller.confirmClearArchive()

    let sheet = try XCTUnwrap(controller.clearSheet)
    XCTAssertEqual(try XCTUnwrap(sheet.noteField).stringValue, "This includes items hidden by the current filters.")
    XCTAssertTrue(sheet.bodyField.stringValue.contains("42"), "the whole archive is cleared")
  }

  func testAFailedClearSaysSo() async throws {
    let source = RecordingArchiveSource()
    source.clearSucceeds = false
    source.pages = [Self.page([Self.row("One")])]
    let controller = try await shown(source)

    controller.confirmClearArchive()
    try XCTUnwrap(controller.clearSheet).clearButton.performClick(nil)
    await controller.pendingLoad?.value

    XCTAssertEqual(controller.toasts.current?.text, "The Archive could not be cleared.")
  }

  // MARK: - Education banner (BH-089)

  func testBannerShowsAboveTheListAndGotItDismissesIt() async throws {
    let source = RecordingArchiveSource()
    source.banner = ArchiveBanner(headline: "Arkt archives Today tabs.", detail: "Restored tabs return.")
    source.pages = [Self.page([Self.row("One")])]
    let controller = try await shown(source)

    let banner = try XCTUnwrap(controller.bannerView)
    XCTAssertEqual(banner.headline.stringValue, "Arkt archives Today tabs.")
    XCTAssertEqual(banner.accessibilityIdentifier(), AXID.Archive.banner)
    XCTAssertTrue(banner.openSettings.isHidden, "no Settings window to open")
    XCTAssertEqual(banner.frame.minY, ArchiveMetrics.barHeight)
    XCTAssertGreaterThan(controller.tableView.enclosingScrollView?.frame.minY ?? 0, banner.frame.maxY)

    banner.gotIt.performClick(nil)

    XCTAssertNil(controller.bannerView)
    XCTAssertEqual(source.bannerDismissals, 1)
  }

  func testOpenSettingsDismissesTheBannerAndOpensSettings() async throws {
    let source = RecordingArchiveSource()
    source.banner = ArchiveBanner(headline: "H", detail: "D")
    let controller = makeWindow(source)
    var opened = 0
    controller.onOpenSettings = { opened += 1 }
    controller.show()
    await controller.pendingLoad?.value
    let banner = try XCTUnwrap(controller.bannerView)
    XCTAssertFalse(banner.openSettings.isHidden)

    banner.openSettings.performClick(nil)

    XCTAssertEqual(opened, 1)
    XCTAssertEqual(source.bannerDismissals, 1)
    XCTAssertNil(controller.bannerView)
  }

  func testNoBannerWhenNoneIsDue() async throws {
    let source = RecordingArchiveSource()
    let controller = try await shown(source)
    XCTAssertNil(controller.bannerView)
  }

  // MARK: - Motion

  /// The pill presses to 0.97 (160 ms ease-out) and back; Reduce Motion keeps the fill change only.
  func testPillPressScalesUnlessReduceMotion() throws {
    ArchiveMotion.reduceMotion = { false }
    let pill = ArchivePillButton(style: .primary, title: "Restore")
    pill.frame = NSRect(x: 0, y: 0, width: 80, height: 28)
    let cell = try XCTUnwrap(pill.cell as? ArchivePillCell)

    cell.isHighlighted = true
    let body = try XCTUnwrap(pill.layer?.sublayers?.first)
    XCTAssertEqual(body.transform.m11, 0.97, accuracy: 0.001)
    XCTAssertEqual((body.animation(forKey: "transform") as? CABasicAnimation)?.duration, 0.16)
    XCTAssertTrue(pill.pressing)
    cell.isHighlighted = false
    XCTAssertEqual(body.transform.m11, 1, accuracy: 0.001)

    ArchiveMotion.reduceMotion = { true }
    cell.isHighlighted = true
    XCTAssertEqual(body.transform.m11, 1, accuracy: 0.001, "Reduce Motion: fill only")
    XCTAssertEqual(pill.displayedFill, BrandTokens.accentPressed.resolve(pill.archiveFlavor))
  }

  // MARK: - Auto-load

  func testTheLoadingRowShowsWhileTheNextPageLoads() async throws {
    let source = RecordingArchiveSource()
    source.pages = [Self.page([Self.row("One")], more: true), Self.page([Self.row("One"), Self.row("Two")])]
    source.holdsLoadMore = true
    let controller = makeWindow(source)
    controller.show()
    await controller.pendingLoad?.value

    XCTAssertTrue(controller.isLoadingMore)
    XCTAssertEqual(controller.entries.last, .loading)
    XCTAssertEqual(controller.tableView.numberOfRows, 2)

    source.releaseLoadMore()
    await controller.pendingLoad?.value
    XCTAssertFalse(controller.isLoadingMore)
    XCTAssertEqual(controller.entries, [.item(0), .item(1)])
  }
}

/// Returns the queued pages in order (the last one repeats) and records queries, restores, clears and the banner.
@MainActor
private final class RecordingArchiveSource: ArchiveListDataSource {
  var onChange: (@MainActor () -> Void)?
  var canRestore = true
  var pages: [ArchiveListPage] = []
  var spaceOptions: [ArchiveSpaceOption] = []
  var banner: ArchiveBanner?
  var clearSucceeds = true
  var faviconData: [UUID: Data] = [:]
  var holdsLoadMore = false
  private(set) var queries: [ArchiveQuery] = []
  private(set) var restored: [UUID] = []
  private(set) var clearCount = 0
  private(set) var bannerDismissals = 0
  private(set) var faviconRequests: [Set<UUID>] = []
  private var served = 0
  private var heldLoadMore: CheckedContinuation<Void, Never>?

  func loadPage() async -> ArchiveListPage { next() }

  func loadMore() async -> ArchiveListPage {
    if holdsLoadMore { await withCheckedContinuation { heldLoadMore = $0 } }
    return next()
  }

  func releaseLoadMore() {
    holdsLoadMore = false
    heldLoadMore?.resume()
    heldLoadMore = nil
  }

  func refresh() async -> ArchiveListPage { next() }

  func restore(_ id: UUID) -> Bool {
    restored.append(id)
    return true
  }

  func setQuery(_ query: ArchiveQuery) { queries.append(query) }

  func clearArchive() async -> Bool {
    clearCount += 1
    return clearSucceeds
  }

  func educationBanner() async -> ArchiveBanner? { banner }

  func dismissEducationBanner() {
    bannerDismissals += 1
    banner = nil
  }

  func favicons(for ids: Set<UUID>) async -> [UUID: Data] {
    faviconRequests.append(ids)
    return faviconData.filter { ids.contains($0.key) }
  }

  private func next() -> ArchiveListPage {
    defer { served += 1 }
    return pages.isEmpty ? ArchiveListPage(rows: [], unreadable: 0, mayHaveMore: false)
      : pages[min(served, pages.count - 1)]
  }
}
