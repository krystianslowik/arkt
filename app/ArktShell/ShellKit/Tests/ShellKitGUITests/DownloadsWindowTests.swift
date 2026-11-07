import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@testable import ShellUI

/// The Downloads UI in real windows (#132, design/downloads): the Library button and its popover in a browser window's
/// sidebar, the Library window, the dangerous-file sheet, and the menu commands that open the Library. Time is never
/// waited for: the hover timer is fired by hand, motion is read from the animations added, bytes arrive when a test says.
@MainActor
final class DownloadsWindowTests: XCTestCase {
  private var engine: InMemoryEngine!
  private var settings: AppSettings!
  private var center: DownloadsCenter!
  private var controllers: [ShellWindowController] = []
  private var folder: URL!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    folder = FileManager.default.temporaryDirectory.appending(path: "arkt-downloads-ui-\(UUID().uuidString)")
    engine = InMemoryEngine(downloadFolder: folder)
    settings = AppSettings.ephemeral()
    center = try XCTUnwrap(DownloadsCenter(engine: engine, settings: settings))
    center.announce = { _ in }
  }

  override func tearDown() async throws {
    center.library.window?.close()
    for controller in controllers { controller.close() }
    controllers = []
    try? FileManager.default.removeItem(at: folder)
  }

  private func makeWindow(width: CGFloat = 1200, height: CGFloat = 800) -> ShellWindowController {
    let controller = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
    controller.window?.setFrame(NSRect(x: 100, y: 100, width: width, height: height), display: false)
    center.primaryWindow = { controller }
    center.attach(to: controller)
    controller.rootView.layoutSubtreeIfNeeded()
    controller.showWindow(nil)
    controller.rootView.layoutSubtreeIfNeeded()
    controllers.append(controller)
    return controller
  }

  private func start(_ name: String, total: Int64 = 1_000) -> DownloadID {
    engine.beginDownload(url: URL(string: "https://files.example/\(name)")!, filename: name, totalBytes: total)
  }

  private func scripted(_ name: String, total: Int64? = 400, received: Int64 = 100, state: DownloadState = .inProgress,
                        danger: DownloadDangerType = .notDangerous, start: Date = Date()) -> DownloadID {
    let item = DownloadItem(url: URL(string: "https://files.example/\(name)")!, filename: name,
                            targetPath: folder.appending(path: name), totalBytes: total, receivedBytes: received,
                            state: state, dangerType: danger, startTime: start, bytesPerSecond: 50)
    engine.addScriptedDownload(item)
    return item.id
  }

  // MARK: Button

  func testTheLibraryButtonSitsRightOfArchiveAndBeforeTheDots() throws {
    let controller = makeWindow()
    let sidebar = controller.sidebarController.view
    let button = try XCTUnwrap(sidebar.libraryButton)
    XCTAssertTrue(button.superview === sidebar.bottomBar)
    XCTAssertEqual(button.frame.minX, sidebar.archiveButton.frame.maxX)
    XCTAssertEqual(button.frame.size, sidebar.archiveButton.frame.size)
    XCTAssertGreaterThanOrEqual(sidebar.spaceDots.frame.minX, button.frame.maxX)
    XCTAssertEqual(button.accessibilityLabel(), "Library")
    XCTAssertEqual(button.accessibilityIdentifier(), AXID.Downloads.libraryButton)
  }

  func testAWindowWithoutACenterHasNoButton() {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    XCTAssertNil(controller.sidebarController.view.libraryButton)
    XCTAssertNil(controller.onShowLibrary)
    controller.close()
  }

  func testEveryWindowGetsItsOwnButtonOverOneModel() throws {
    let first = makeWindow(), second = makeWindow()
    let a = try XCTUnwrap(first.sidebarController.view.libraryButton)
    let b = try XCTUnwrap(second.sidebarController.view.libraryButton)
    XCTAssertFalse(a === b)
    a.reduceMotion = { true }
    b.reduceMotion = { true }
    let id = start("a.bin")
    engine.deliverDownloadBytes(id, 250)
    XCTAssertEqual(a.ringStrokeEnd, 0.25, accuracy: 1e-9)
    XCTAssertEqual(b.ringStrokeEnd, 0.25, accuracy: 1e-9)
    XCTAssertEqual(a.ringState, b.ringState)
  }

  func testTheRingFollowsTheEngineAndEndsAsACheck() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    button.reduceMotion = { true }
    let id = start("a.bin")
    XCTAssertEqual(button.ringState, .active(fraction: 0))
    engine.deliverDownloadBytes(id, 500)
    XCTAssertEqual(button.ringStrokeEnd, 0.5, accuracy: 1e-9)
    engine.deliverDownloadBytes(id, 500)
    XCTAssertEqual(button.ringState, .done)
    XCTAssertEqual(button.glyphName, "checkmark")
    XCTAssertTrue(button.dotIsShown && !button.ringIsShown)
    center.showLibrary()
    XCTAssertEqual(button.ringState, .idle, "opening the Library clears the dot")
  }

  // MARK: Popover

  func testAClickShowsThePopoverAboveTheButtonAndEscapeClosesIt() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    _ = start("a.bin")
    button.performClick(nil)
    XCTAssertTrue(popover.isShown)
    let panel = try XCTUnwrap(popover.panel)
    let anchor = try XCTUnwrap(button.window).convertToScreen(button.convert(button.bounds, to: nil))
    XCTAssertEqual(panel.frame.minY, anchor.maxY + DownloadsMetrics.popoverGap, accuracy: 0.5)
    XCTAssertEqual(panel.frame.width, DownloadsMetrics.popoverWidth)
    XCTAssertTrue(panel.parent === controller.window)
    XCTAssertEqual(panel.accessibilityLabel(), "Downloads")
    XCTAssertTrue(panel.onEscape?() == true)
    XCTAssertFalse(popover.isShown)
    button.performClick(nil)
    button.performClick(nil)
    XCTAssertFalse(popover.isShown, "a second click closes it")
  }

  func testHoveringOpensAfterTheDelayAndLeavingClosesAfterTheGrace() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    button.setHovered(true)
    XCTAssertFalse(popover.isShown, "nothing before the pointer has rested")
    popover.firePendingTimer()
    XCTAssertTrue(popover.isShown)
    XCTAssertFalse(popover.panel?.isKeyWindow ?? true, "a hover never takes the keyboard")
    button.setHovered(false)
    XCTAssertTrue(popover.isShown, "the grace keeps it for a moment")
    popover.pointerInPanelChanged(true)
    popover.firePendingTimer()
    XCTAssertTrue(popover.isShown, "the pointer is on the popover")
    popover.pointerInPanelChanged(false)
    popover.firePendingTimer()
    XCTAssertFalse(popover.isShown)
  }

  func testMovingOffAndBackBeforeTheDelayShowsNothing() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    button.setHovered(true)
    button.setHovered(false)
    popover.firePendingTimer()
    XCTAssertFalse(popover.isShown)
  }

  func testAClickElsewhereClosesThePopoverButNotOneInsideIt() throws {
    let controller = makeWindow()
    let button = try XCTUnwrap(controller.sidebarController.view.libraryButton)
    let popover = try XCTUnwrap(center.popover(of: controller))
    button.performClick(nil)
    let panel = try XCTUnwrap(popover.panel)
    popover.handleMouseDown(in: panel, at: NSPoint(x: 10, y: 10))
    XCTAssertTrue(popover.isShown)
    popover.handleMouseDown(in: controller.window, at: button.convert(NSPoint(x: 5, y: 5), to: nil))
    XCTAssertTrue(popover.isShown, "on the button: its own click toggles")
    popover.handleMouseDown(in: controller.window, at: NSPoint(x: 600, y: 400))
    XCTAssertFalse(popover.isShown)
  }

  func testThePopoverListsTheSixNewestAndFiftyDownloadsStayInTheLibrary() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    for index in 1...50 {
      _ = scripted("file-\(index).zip", state: .complete, start: Date(timeIntervalSince1970: 1_000 + Double(index)))
    }
    popover.show(takesKey: false)
    let view = try XCTUnwrap(popover.contentView)
    XCTAssertEqual(view.order.count, 6)
    XCTAssertEqual(view.order.compactMap { id in engine.download(id)?.filename }.first, "file-50.zip", "newest first")
    XCTAssertEqual(try XCTUnwrap(popover.panel).frame.height, view.preferredHeight)
    popover.hide(keyboard: true)
    center.library.show()
    XCTAssertEqual(center.library.listView.rows.count, 50)
  }

  func testRowsComeAndGoInThePopoverAndItResizes() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    let first = start("a.bin")
    popover.show(takesKey: false)
    let height = try XCTUnwrap(popover.panel).frame.height
    let second = start("b.bin")
    let view = try XCTUnwrap(popover.contentView)
    XCTAssertEqual(view.order, [second, first])
    XCTAssertGreaterThan(try XCTUnwrap(popover.panel).frame.height, height)
    XCTAssertEqual(try XCTUnwrap(popover.panel).frame.height, view.preferredHeight)
    popover.show(takesKey: false)                                      // already shown: nothing
    model().cancel(first)
    XCTAssertEqual(view.order, [second])
  }

  func testCancelFailedRetryAndOpenRunThroughTheModel() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    let active = start("a.bin")
    let failed = start("b.bin")
    engine.interruptDownload(failed, reason: .networkDisconnected)
    let done = start("c.bin", total: 10)
    engine.deliverDownloadBytes(done, 10)
    popover.show(takesKey: false)
    let view = try XCTUnwrap(popover.contentView)
    let doneRow = try XCTUnwrap(view.rows[done])
    doneRow.showButton.performClick(nil)
    XCTAssertEqual(engine.revealedDownloads, [done])
    doneRow.onAction?(.open, done)
    XCTAssertEqual(engine.openedDownloads, [done])
    try XCTUnwrap(view.rows[failed]).retryPill.performClick(nil)
    XCTAssertNil(engine.download(failed), "retry replaced the failed row")
    try XCTUnwrap(view.rows[active]).cancelButton.performClick(nil)
    XCTAssertNil(engine.download(active))
    view.clearButton.performClick(nil)
    XCTAssertNil(engine.download(done), "Clear removes the finished rows")
  }

  func testTheEmptyPopoverSaysSo() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.show(takesKey: false)
    let view = try XCTUnwrap(popover.contentView)
    XCTAssertTrue(view.order.isEmpty)
    XCTAssertFalse(view.clearButton.isEnabled)
    XCTAssertEqual(try XCTUnwrap(popover.panel).frame.height, view.preferredHeight)
  }

  func testShowLibraryInThePopoverOpensTheLibraryAndClosesThePopover() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.show(takesKey: false)
    popover.contentView?.onShowLibrary?()
    XCTAssertFalse(popover.isShown)
    XCTAssertTrue(center.library.window?.isVisible == true)
  }

  // MARK: Motion

  func testThePopoverGrowsFromTheButtonAndFadesUnderReduceMotion() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { false }
    popover.show(takesKey: false)
    var animations = popover.entranceAnimations
    XCTAssertEqual(animations["appear.opacity"]?.duration, 0.22)
    XCTAssertEqual(animations["appear.transform"]?.duration, 0.22)
    XCTAssertNotNil(animations["appear.transform"]?.fromValue)
    popover.hide(keyboard: true)
    popover.reduceMotion = { true }
    popover.show(takesKey: false)
    animations = popover.entranceAnimations
    XCTAssertEqual(animations["appear.opacity"]?.duration, 0.15)
    XCTAssertNil(animations["appear.transform"], "Reduce Motion fades only")
  }

  func testANewRowRisesAndAnOldOneFades() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    popover.reduceMotion = { false }
    popover.show(takesKey: false)
    let id = start("a.bin")
    let row = try XCTUnwrap(popover.contentView?.rows[id])
    let opacity = row.layer?.animation(forKey: "appear.opacity") as? CABasicAnimation
    let rise = row.layer?.animation(forKey: "appear.transform") as? CABasicAnimation
    XCTAssertEqual(opacity?.duration, 0.24)
    XCTAssertEqual(rise?.fromValue as? Double, 8)
    row.reduceMotion = { true }
    row.layer?.removeAllAnimations()
    row.playAppearance()
    XCTAssertEqual((row.layer?.animation(forKey: "appear.opacity") as? CABasicAnimation)?.duration, 0.15)
    XCTAssertNil(row.layer?.animation(forKey: "appear.transform"), "no movement under Reduce Motion")
    var removed = false
    row.playRemoval { removed = true }
    let fade = row.layer?.animation(forKey: "remove") as? CABasicAnimation
    XCTAssertEqual(fade?.duration, DownloadsMotion.removeDuration)
    XCTAssertFalse(removed)
  }

  // MARK: Light and dark

  func testBothAppearancesDrawTheRowAndKeepTheTileColour() throws {
    let controller = makeWindow()
    let popover = try XCTUnwrap(center.popover(of: controller))
    let id = start("deck.pdf")
    popover.show(takesKey: false)
    let row = try XCTUnwrap(popover.contentView?.rows[id])
    row.appearance = NSAppearance(named: .aqua)
    let lightText = row.nameField.textColor
    let lightTile = row.tile.displayedFill
    row.appearance = NSAppearance(named: .darkAqua)
    row.viewDidChangeEffectiveAppearance()
    XCTAssertNotEqual(row.nameField.textColor, lightText)
    XCTAssertEqual(row.tile.displayedFill, lightTile)
    row.frame = NSRect(x: 0, y: 0, width: 300, height: 52)
    XCTAssertNotNil(row.bitmapImageRepForCachingDisplay(in: row.bounds))
  }

  // MARK: The Library window

  func testTheLibraryOpensOnTheLastSectionAndRemembersTheNewOne() throws {
    settings.libraryLastSection = .history
    let library = center.library
    library.show()
    XCTAssertEqual(library.section, .history)
    XCTAssertEqual(library.empty, .history)
    library.show(section: .downloads)
    XCTAssertEqual(library.section, .downloads)
    XCTAssertEqual(settings.libraryLastSection, .downloads)
    XCTAssertEqual(library.window?.accessibilityIdentifier(), AXID.Downloads.libraryWindow)
    XCTAssertEqual(library.window?.contentLayoutRect.size.width ?? 0, 800, accuracy: 1)
  }

  func testTheEmptyLibraryHasOneButtonThatOpensTheDownloadsFolder() throws {
    let library = center.library
    var opened: [URL] = []
    library.openFolder = { opened.append($0) }
    library.show(section: .downloads)
    XCTAssertEqual(library.empty, .noDownloads)
    XCTAssertFalse(library.openFolderPill.isHidden)
    XCTAssertEqual(library.openFolderPill.style, .primary)
    library.openFolderPill.performClick(nil)
    XCTAssertEqual(opened, [engine.downloadDefaultFolder])
  }

  func testTheLibraryGroupsByDayAndShowsFiftyRowsWithoutOverlap() throws {
    let library = center.library
    let now = Date()
    for index in 0..<50 {
      let day = Double(index % 3) * 86_400 + Double(index)
      _ = scripted("Very-long-file-name-number-\(index)-" + String(repeating: "x", count: 60) + ".zip",
                   state: index % 7 == 0 ? .interrupted(.networkDisconnected) : .complete,
                   start: now.addingTimeInterval(-day))
    }
    library.show(section: .downloads)
    library.window?.contentView?.layoutSubtreeIfNeeded()
    let list = library.listView
    XCTAssertEqual(list.rows.count, 50)
    XCTAssertEqual(list.sections.map(\.title), ["Today", "Yesterday", "Earlier"])
    let frames = list.order.compactMap { list.rows[$0]?.frame }.sorted { $0.minY < $1.minY }
    for (a, b) in zip(frames, frames.dropFirst()) { XCTAssertLessThanOrEqual(a.maxY, b.minY, "rows overlap") }
    XCTAssertGreaterThanOrEqual(list.contentHeight, (frames.last?.maxY ?? 0))
    for row in list.rows.values { XCTAssertLessThanOrEqual(row.frame.maxX, list.bounds.width) }
  }

  func testKeyboardSelectionOpensRevealsAndRemoves() throws {
    let library = center.library
    let a = start("a.bin", total: 10)
    let b = start("b.bin", total: 10)
    engine.deliverDownloadBytes(a, 10)
    engine.deliverDownloadBytes(b, 10)
    library.show(section: .downloads)
    let list = library.listView
    XCTAssertNil(list.selectedID)
    list.moveSelection(by: 1)
    XCTAssertEqual(list.selectedID, b, "newest first")
    list.moveSelection(by: 1)
    XCTAssertEqual(list.selectedID, a)
    list.moveSelection(by: 1)
    XCTAssertEqual(list.selectedID, a, "stops at the end")
    list.moveSelection(by: -5)
    XCTAssertEqual(list.selectedID, b)
    XCTAssertTrue(try XCTUnwrap(list.rows[b]).isSelected)
    key(list, 36)                                                    // Return
    XCTAssertEqual(engine.openedDownloads, [b])
    key(list, 36, [.command])                                        // Command-Return
    XCTAssertEqual(engine.revealedDownloads, [b])
    key(list, 51)                                                    // Delete
    XCTAssertNil(engine.download(b), "removed from the list")
    XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(engine.download(a)?.targetPath).path()))
    XCTAssertNil(list.selectedID)
  }

  func testSearchFiltersByNameOrHostAndReportsNoMatches() throws {
    let library = center.library
    _ = start("alpha.zip")
    _ = start("beta.pdf")
    library.show(section: .downloads)
    library.setSearchText("alp")
    XCTAssertEqual(library.listView.rows.count, 1)
    library.setSearchText("files.example")
    XCTAssertEqual(library.listView.rows.count, 2, "the host matches too")
    library.setSearchText("zzz")
    XCTAssertEqual(library.empty, .noMatches)
    library.cancelOperation(nil)
    XCTAssertEqual(library.searchField.stringValue, "", "Escape clears the search first")
    XCTAssertEqual(library.listView.rows.count, 2)
  }

  func testTheFooterNamesThePlaceAndChangeOpensSettings() throws {
    let library = center.library
    var changes = 0
    center.onChangeLocation = { changes += 1 }
    library.show(section: .downloads)
    library.window?.contentView?.layoutSubtreeIfNeeded()
    XCTAssertTrue(library.changeLink.target != nil)
    library.changeLink.performClick(nil)
    XCTAssertEqual(changes, 1)
    settings.downloadLocation = DownloadLocationSetting(asksWhereToSave: true)
    library.show(section: .downloads)
    XCTAssertFalse(library.changeLink.isHidden)
    library.show(section: .history)
    XCTAssertTrue(library.changeLink.isHidden && library.clearLink.isHidden, "History has no download footer")
  }

  func testClearListRemovesFinishedRowsAndKeepsRunningOnes() throws {
    let library = center.library
    let done = start("done.bin", total: 10)
    engine.deliverDownloadBytes(done, 10)
    let running = start("run.bin")
    library.show(section: .downloads)
    XCTAssertTrue(library.clearLink.isEnabled)
    library.clearLink.performClick(nil)
    XCTAssertNil(engine.download(done))
    XCTAssertNotNil(engine.download(running))
    XCTAssertFalse(library.clearLink.isEnabled)
  }

  func testSelectingARowShowsItsPrimaryOpenAndHoverTheOthers() throws {
    let library = center.library
    let a = start("a.bin", total: 10), b = start("b.bin", total: 10)
    engine.deliverDownloadBytes(a, 10)
    engine.deliverDownloadBytes(b, 10)
    library.show(section: .downloads)
    let list = library.listView
    list.select(a)
    XCTAssertFalse(try XCTUnwrap(list.rows[a]).primaryOpenPill.isHidden)
    XCTAssertTrue(try XCTUnwrap(list.rows[b]).primaryOpenPill.isHidden)
    XCTAssertTrue(try XCTUnwrap(list.rows[b]).visibleControls.isEmpty)
  }

  func testTheLibraryRailHasTwoSectionsWithTheDownloadCount() throws {
    let library = center.library
    _ = start("a.bin")
    _ = start("b.bin")
    library.show(section: .downloads)
    let root = try XCTUnwrap(library.window?.contentView)
    let downloads = try XCTUnwrap(find(AXID.Downloads.railItem("downloads"), in: root) as? LibraryRailItem)
    let history = try XCTUnwrap(find(AXID.Downloads.railItem("history"), in: root) as? LibraryRailItem)
    XCTAssertTrue(downloads.isCurrent && !history.isCurrent)
    XCTAssertEqual(downloads.accessibilityLabel(), "Downloads, 2")
    history.performClick(nil)
    XCTAssertEqual(library.section, .history)
    XCTAssertEqual(settings.libraryLastSection, .history)
    XCTAssertTrue(history.isCurrent && !downloads.isCurrent)
  }

  // MARK: The dangerous-file sheet

  func testReviewShowsTheSheetAndDeleteIsTheOnlyPrimary() throws {
    let controller = makeWindow()
    let id = scripted("payroll-update.dmg", total: 48_000_000, received: 48_000_000, state: .complete,
                      danger: .dangerousFile)
    center.review(id, on: controller.window)
    let sheet = try XCTUnwrap(center.sheet)
    XCTAssertTrue(controller.window?.attachedSheet === sheet.window)
    XCTAssertEqual(sheet.sheet.content.title, "Arkt blocked \u{201C}payroll-update.dmg\u{201D}")
    XCTAssertEqual(sheet.sheet.content.primaryTitle, "Delete Download")
    XCTAssertEqual(sheet.sheet.content.secondaryTitle, "Show in Finder")
    XCTAssertEqual(sheet.keepLink?.title, "Keep Anyway")
    XCTAssertEqual(sheet.keepLink?.style, .destructive)
    XCTAssertEqual(sheet.deleteButton.keyEquivalent, "\r")
    XCTAssertEqual(sheet.deleteButton.style, .primary)
    XCTAssertNotEqual(sheet.finderButton?.style, .primary)
    XCTAssertEqual(sheet.keepLink?.keyEquivalent, "")
    center.review(id, on: controller.window)
    XCTAssertTrue(center.sheet === sheet, "one sheet at a time")
    sheet.sheet.view.primaryButton.performClick(nil)
    XCTAssertNil(engine.download(id), "Delete Download deletes it")
    XCTAssertNil(center.sheet)
  }

  func testKeepAnywayNeedsASecondClickAndThenOwnsReturn() throws {
    let controller = makeWindow()
    let id = scripted("tool.dmg", total: 100, received: 100, state: .complete, danger: .dangerousFile)
    center.review(id, on: controller.window)
    let sheet = try XCTUnwrap(center.sheet)
    sheet.keepLink?.performClick(nil)
    XCTAssertEqual(engine.download(id)?.dangerType, .dangerousFile, "the first click only arms it")
    XCTAssertTrue(sheet.isArmed)
    XCTAssertEqual(sheet.keepLink?.title, DownloadDangerSheet.armedTitle)
    XCTAssertEqual(sheet.keepLink?.keyEquivalent, "\r")
    XCTAssertEqual(sheet.deleteButton.keyEquivalent, "", "Return no longer deletes")
    sheet.keepLink?.performClick(nil)
    XCTAssertEqual(engine.download(id)?.dangerType, .userValidated)
    XCTAssertNil(center.sheet)
  }

  func testEscapeDisarmsKeepAnywayBeforeItDismissesTheSheet() throws {
    let controller = makeWindow()
    let id = scripted("tool.dmg", total: 100, received: 100, state: .complete, danger: .dangerousFile)
    center.review(id, on: controller.window)
    let sheet = try XCTUnwrap(center.sheet)
    sheet.keepLink?.performClick(nil)
    XCTAssertTrue(sheet.isArmed)
    let escape = try XCTUnwrap((sheet.window as? DialogWindow)?.onEscape)
    XCTAssertTrue(escape())
    XCTAssertFalse(sheet.isArmed)
    XCTAssertEqual(sheet.keepLink?.title, "Keep Anyway")
    XCTAssertEqual(sheet.deleteButton.keyEquivalent, "\r")
    XCTAssertEqual(sheet.keepLink?.keyEquivalent, "")
    XCTAssertNotNil(center.sheet, "the first Escape only disarms")
    XCTAssertEqual(engine.download(id)?.dangerType, .dangerousFile)
    sheet.keepLink?.performClick(nil)
    XCTAssertTrue(sheet.isArmed, "it can be armed again")
    _ = escape()
    _ = escape()
    XCTAssertNil(center.sheet, "Escape on a disarmed sheet dismisses it")
  }

  func testShowInFinderRevealsAndEscapeLeavesTheFileHeld() throws {
    let controller = makeWindow()
    let id = scripted("tool.dmg", total: 100, received: 100, state: .complete, danger: .dangerousFile)
    center.review(id, on: controller.window)
    try XCTUnwrap(center.sheet).finderButton?.performClick(nil)
    XCTAssertEqual(engine.revealedDownloads, [id])
    XCTAssertEqual(engine.download(id)?.dangerType, .dangerousFile)
    center.review(id, on: controller.window)
    _ = try XCTUnwrap(center.sheet).sheet.view.escape()
    XCTAssertNil(center.sheet)
    XCTAssertNotNil(engine.download(id))
  }

  func testABlockedFileCannotBeKept() {
    let content = DownloadDangerSheet.content(
      for: DownloadItem(url: URL(string: "https://files.example/a.zip")!, filename: "a.zip",
                        dangerType: .blockedTooLarge), folderName: "Downloads")
    XCTAssertNil(content.footerLink, "no Keep Anyway for a blocked file")
    XCTAssertEqual(content.primaryTitle, "Delete Download")
  }

  func testReviewOfASafeFileDoesNothing() throws {
    let controller = makeWindow()
    let id = start("a.bin")
    center.review(id, on: controller.window)
    XCTAssertNil(center.sheet)
  }

  // MARK: Menu commands

  func testDownloadsAndHistoryCommandsOpenTheLibraryOnTheirSections() throws {
    let controller = makeWindow()
    let host = controller.engineHost
    XCTAssertEqual(host.claim(.downloads), CommandClaim(isEnabled: true))
    XCTAssertEqual(host.claim(.history), CommandClaim(isEnabled: true))
    XCTAssertTrue(host.perform(.downloads, disposition: .currentTab))
    XCTAssertEqual(center.library.section, .downloads)
    XCTAssertTrue(host.perform(.history, disposition: .currentTab))
    XCTAssertEqual(center.library.section, .history)
    XCTAssertTrue(center.library.window?.isVisible == true)
  }

  func testWithoutALibraryTheEngineKeepsItsOwnCommands() {
    let controller = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    XCTAssertNil(controller.engineHost.claim(.downloads))
    XCTAssertNil(controller.engineHost.claim(.history))
    controller.close()
  }

  // MARK: Helpers

  private func model() -> DownloadsModel { center.model }

  private func find(_ identifier: String, in view: NSView) -> NSView? {
    if view.accessibilityIdentifier() == identifier { return view }
    if let control = view as? NSControl, control.cell?.accessibilityIdentifier() == identifier { return view }
    for subview in view.subviews { if let found = find(identifier, in: subview) { return found } }
    return nil
  }

  private func key(_ view: NSView, _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                 windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: "",
                                 charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)
    if let event { view.keyDown(with: event) }
  }
}
