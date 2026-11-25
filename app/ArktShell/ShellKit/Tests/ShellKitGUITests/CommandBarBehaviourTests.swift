import AppKit
import XCTest
import EngineAPI
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// The grouped command bar's behaviour (#993, design/command-bar/README.md): the keyboard (wrap and repeat, Tab
/// between groups, Cmd-Return, Esc, Cmd-Shift-V), the selected row's verb, no motion on open and close, search
/// suggestions arriving late (#884), the announcements, and the layout in the worst case and the smallest window.
/// Nothing here waits on a clock: the count announcement and the suggestion replies are run by hand.
@MainActor
final class CommandBarBehaviourTests: XCTestCase {
  var shell: ShellWindowController!
  var bar: CommandBarController!
  var window: NSWindow!
  var announcements: [String] = []
  var priorities: [NSAccessibilityPriorityLevel] = []
  /// The count announcements waiting for typing to settle, in order.
  var settled: [@MainActor () -> Void] = []
  /// What the injected key-repeat check answers.
  var repeating = false
  /// Suggestion requests waiting for a reply.
  var pending: [(query: String, reply: CheckedContinuation<[String], Never>)] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1280, height: 800), display: true)
    shell.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    bar = CommandBarController(parent: window)
    bar.announce = { [unowned self] text, priority in
      announcements.append(text)
      priorities.append(priority)
    }
    bar.afterTypingSettles = { [unowned self] work in settled.append(work) }
    bar.isRepeatKey = { [unowned self] in repeating }
    bar.prewarm()
    announcements = []
    priorities = []
  }

  // XCTest keeps each test case object until the run ends: release the windows too, not only hide them (#805).
  override func tearDown() async throws {
    for request in pending { request.reply.resume(returning: []) }
    pending = []
    bar.invalidate()
    shell.close()
    bar = nil
    window = nil
    shell = nil
  }

  // MARK: Helpers

  private func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                               windowNumber: bar.panel.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code))
    bar.panel.sendEvent(event)
  }

  private func selector(_ action: Selector) -> Bool {
    bar.control(bar.barView.field, textView: NSTextView(), doCommandBy: action)
  }

  private func down() { XCTAssertTrue(selector(#selector(NSResponder.moveDown(_:)))) }
  private func up() { XCTAssertTrue(selector(#selector(NSResponder.moveUp(_:)))) }
  private func tab() -> Bool { selector(#selector(NSResponder.insertTab(_:))) }
  private func backtab() -> Bool { selector(#selector(NSResponder.insertBacktab(_:))) }
  private func escape() -> Bool { selector(#selector(NSResponder.cancelOperation(_:))) }
  private var selected: Int { bar.barView.table.selectedRow }

  /// Every group: two tabs, a folder, two history rows, an extension and the Search group for "git".
  private func showAllGroups() {
    let tabs: [CommandBarResults.OpenTab] = [
      .init(node: UUID(), title: "Git - Branches", url: URL(string: "https://git-scm.com/book/branches")!),
      .init(node: UUID(), title: "acme/git-tools", url: URL(string: "https://github.com/acme/git-tools")!),
    ]
    let folders: [CommandBarResults.Folder] = [.init(node: UUID(), title: "Git reading list", tabCount: 6)]
    bar.openTabsProvider = { tabs }
    bar.foldersProvider = { folders }
    bar.historyProvider = {
      [.init(title: "Git - Book", url: URL(string: "https://git-scm.com/book")!,
             visited: Date(timeIntervalSinceNow: -26 * 3600)),
       .init(title: "Git cheat sheet", url: URL(string: "https://training.example/git")!)]
    }
    bar.extensionsProvider = { [.init(id: "pilot", name: "Git Pilot", description: "Pull request shortcuts")] }
    bar.toggle(.newTab)
    bar.setQueryForTesting("git")
  }

  private func cell(_ row: Int) throws -> CommandBarCellView {
    bar.barView.layoutSubtreeIfNeeded()
    let cell = try XCTUnwrap(bar.barView.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? CommandBarCellView)
    cell.layoutSubtreeIfNeeded()
    return cell
  }

  /// Bounded main-actor turns until `condition` holds (no wall clock).
  private func turns(until condition: () -> Bool, _ label: String) async throws {
    for _ in 0..<10_000 {
      if condition() { return }
      await Task.yield()
    }
    XCTAssertTrue(condition(), "\(label) did not happen")
  }

  private func suggestingByHand() {
    bar.suggestionsProvider = { [unowned self] query in
      await withCheckedContinuation { pending.append((query, $0)) }
    }
  }

  // MARK: Groups and selection

  func testTheGroupsComeInOrderAndTheFirstRowIsSelected() throws {
    showAllGroups()
    XCTAssertEqual(bar.results.map(\.group), [.tabs, .tabs, .folders, .history, .history, .extensions, .search])
    XCTAssertEqual(bar.groupHeaders, [0: "Tabs", 2: "Folders", 3: "History", 5: "Extensions", 6: "Search"])
    XCTAssertEqual(selected, 0)
  }

  /// Up and Down wrap on a fresh press; a held key's repeat stops at the ends.
  func testArrowsWrapOnAPressAndStopAtTheEndsOnRepeat() throws {
    showAllGroups()
    let last = bar.results.count - 1
    up()
    XCTAssertEqual(selected, last, "a fresh Up on the first row wraps")
    down()
    XCTAssertEqual(selected, 0, "a fresh Down on the last row wraps")
    repeating = true
    up()
    XCTAssertEqual(selected, 0, "a repeat stops at the first row")
    for _ in 0..<20 { down() }
    XCTAssertEqual(selected, last, "a repeat stops at the last row")
  }

  /// Tab and Shift-Tab jump to the first row of the next or previous group and do nothing else.
  func testTabJumpsBetweenGroups() throws {
    showAllGroups()
    XCTAssertTrue(tab())
    XCTAssertEqual(selected, 2, "Folders")
    XCTAssertTrue(tab())
    XCTAssertEqual(selected, 3, "History")
    down()
    XCTAssertTrue(backtab())
    XCTAssertEqual(selected, 2, "Shift-Tab from inside History goes to the start of Folders")
    for _ in 0..<6 { XCTAssertTrue(tab()) }
    XCTAssertEqual(selected, 6, "stops on the last group")
    XCTAssertEqual(bar.barView.field.stringValue, "git", "Tab never edits the text")
  }

  /// A keyboard move speaks the row's label at high priority; a hover selects without speaking.
  func testArrowMovesAnnounceTheSelectedRowAndHoverDoesNot() throws {
    showAllGroups()
    announcements = []
    down()
    XCTAssertEqual(announcements.last, "acme/git-tools, github.com/acme/git-tools, open tab, 2 of 7")
    XCTAssertEqual(priorities.last, .high)
    let spoken = announcements.count
    _ = bar.barView.onHoverRow?(4)
    XCTAssertEqual(selected, 4)
    XCTAssertEqual(announcements.count, spoken, "a pointer hover selects without speaking")
  }

  /// Once typing settles, the count is said once; an earlier keystroke's announcement is dropped.
  func testTheCountIsAnnouncedOnceTypingSettles() throws {
    bar.toggle(.newTab)
    bar.setQueryForTesting("zq")
    bar.setQueryForTesting("zqx")
    XCTAssertEqual(settled.count, 2)
    settled[0]()
    XCTAssertEqual(announcements, [], "a later keystroke replaced it")
    settled[1]()
    XCTAssertEqual(announcements, ["No matches. Return searches the web."])
    bar.setQueryForTesting("t1.example")
    settled[2]()
    XCTAssertEqual(announcements.last, "2 results")
  }

  // MARK: The selected row

  /// The selected row shows its verb and the Return key cap; the Search for row shows the key cap only; an unselected
  /// history row shows its time.
  func testTheSelectedRowShowsItsVerbAndTheKeyCap() throws {
    showAllGroups()
    let first = try cell(0)
    XCTAssertEqual(first.trailingText.stringValue, "Switch to Tab")
    XCTAssertFalse(first.returnKey.isHidden)
    XCTAssertEqual(first.returnKey.text, CommandBarKeyCaps.return)
    let history = try cell(3)
    XCTAssertEqual(history.trailingText.stringValue, "Yesterday")
    XCTAssertTrue(history.returnKey.isHidden)
    bar.barView.table.selectRowIndexes([3], byExtendingSelection: false)
    XCTAssertEqual(history.trailingText.stringValue, "Open")
    XCTAssertTrue(first.returnKey.isHidden, "only the selected row carries a verb")
    for (row, verb) in [(2, "Show Folder"), (5, "Open Extension")] {
      bar.barView.table.selectRowIndexes([row], byExtendingSelection: false)
      XCTAssertEqual(try cell(row).trailingText.stringValue, verb)
    }
    bar.barView.table.selectRowIndexes([6], byExtendingSelection: false)
    let search = try cell(6)
    XCTAssertEqual(search.title.stringValue, "Search for \u{201C}git\u{201D}")
    XCTAssertTrue(search.trailingText.isHidden, "the Search for row has no verb")
    XCTAssertFalse(search.returnKey.isHidden)
  }

  /// The selection is a neutral fill drawn by the row itself, below its group header.
  func testTheSelectionIsANeutralFillBelowTheHeader() throws {
    showAllGroups()
    bar.barView.layoutSubtreeIfNeeded()
    let row = try XCTUnwrap(bar.barView.table.rowView(atRow: 0, makeIfNecessary: true) as? CommandBarRowView)
    XCTAssertTrue(row.isSelected)
    XCTAssertEqual(row.fillRect.minY, CommandBarGeometry.firstGroupHeaderHeight)
    XCTAssertEqual(row.fillRect.height, CommandBarGeometry.rowHeight)
  }

  func testTheCaretIsMustard() throws {
    bar.toggle(.newTab)
    let editor = try XCTUnwrap(bar.barView.field.currentEditor() as? NSTextView)
    XCTAssertEqual(editor.insertionPointColor, BrandTokens.accent.resolve(bar.flavor).nsColor())
    XCTAssertTrue(editor is CommandBarFieldEditor, "the 2 pt caret's editor")
    XCTAssertEqual(CommandBarFieldEditor.caretWidth, 2)
  }

  /// A history row under the pointer shows its remove button at the trailing edge; clicking it removes the row, as
  /// Cmd-Opt-Delete does. Other rows have none.
  func testAHoveredHistoryRowShowsItsRemoveButton() throws {
    var removed: CommandBarResults.Result?
    bar.onRemoveSuggestion = { removed = $0 }
    showAllGroups()
    bar.barView.layoutSubtreeIfNeeded()
    let history = try cell(3)
    XCTAssertTrue(history.removeButton.isHidden, "only while hovered")
    bar.barView.setHoveredRow(3)
    history.layoutSubtreeIfNeeded()
    XCTAssertFalse(history.removeButton.isHidden)
    XCTAssertEqual(history.removeButton.accessibilityLabel(), "Remove from History")
    XCTAssertEqual(history.removeButton.accessibilityIdentifier(), AXID.CommandBar.rowRemove)
    XCTAssertEqual(history.removeButton.frame.size, NSSize(width: 20, height: 20))
    XCTAssertEqual(history.removeButton.frame.maxX, history.bounds.width - CommandBarGeometry.rowHorizontalPadding)
    XCTAssertLessThanOrEqual(history.trailingText.frame.maxX, history.removeButton.frame.minX - 8)
    XCTAssertTrue(bar.barView.table.axProxyRows.children?(3).contains(history.removeButton) ?? false)
    bar.barView.setHoveredRow(0)
    XCTAssertTrue(try cell(0).removeButton.isHidden, "a tab row has none")
    bar.barView.setHoveredRow(3)
    history.removeButton.performClick(nil)
    XCTAssertEqual(removed?.title, "Git - Book")
    XCTAssertFalse(bar.results.contains { $0.title == "Git - Book" })
  }

  /// A mouse-down on a row gives it the full fill before the click runs it (feedback on press, action on release): a
  /// real mouse-down event to the table selects the row under the pointer. The release that runs the row is the
  /// table's own click action (`rowClicked`).
  func testAMouseDownSelectsTheRowUnderThePointer() throws {
    showAllGroups()
    bar.barView.layoutSubtreeIfNeeded()
    bar.barView.displayIfNeeded()
    let table = bar.barView.table
    XCTAssertEqual(selected, 0)
    let rect = table.rect(ofRow: 2)
    let point = table.convert(NSPoint(x: rect.midX, y: rect.maxY - 10), to: nil)
    func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: bar.panel.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
    }
    // The table tracks the press until the release, so the release is queued first and ends the tracking.
    NSApp.postEvent(try mouse(.leftMouseUp), atStart: false)
    table.mouseDown(with: try mouse(.leftMouseDown))
    XCTAssertEqual(selected, 2, "the pressed row takes the selection fill")
  }

  /// A keystroke that adds a group header changes row heights without animating them, even when it lands inside an
  /// animation group someone else opened (a window or sidebar animation running): NSTableView animates height
  /// changes made inside one.
  func testRowHeightChangesDoNotAnimate() throws {
    let rows: [CommandBarResults.OpenTab] = [
      .init(node: UUID(), title: "Git tab", url: URL(string: "https://t.example")!),
      .init(node: UUID(), title: "Other", url: URL(string: "https://o.example")!),
    ]
    bar.openTabsProvider = { rows }
    bar.toggle(.newTab)                                    // Tabs: two rows
    bar.barView.layoutSubtreeIfNeeded()
    bar.barView.displayIfNeeded()
    let table = bar.barView.table
    XCTAssertNotNil(table.rowView(atRow: 1, makeIfNecessary: false))
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.5
      context.allowsImplicitAnimation = true
      bar.setQueryForTesting("git")                        // row 1 becomes the Search row, taller by its header
    }
    XCTAssertEqual(bar.groupHeaders, [0: "Tabs", 1: "Search"])
    // An animated height change leaves the row view at its old height after layout and moves it over the group's
    // duration; an instant one puts it at its new height at once.
    table.layoutSubtreeIfNeeded()
    for row in 0..<table.numberOfRows {
      let view = try XCTUnwrap(table.rowView(atRow: row, makeIfNecessary: false), "row \(row)")
      XCTAssertEqual(view.frame, table.rect(ofRow: row), "row \(row) is at its new frame at once")
      XCTAssertNil(view.layer?.animationKeys(), "row \(row)")
    }
  }

  /// Group headers reach accessibility from the model, for rows scrolled out of view as well.
  func testGroupHeadersAreAccessibleWithoutACell() throws {
    showAllGroups()
    let children = try XCTUnwrap(bar.barView.table.axProxyRows.children)
    XCTAssertEqual(children(2).first?.accessibilityLabel(), "Folders")
    XCTAssertEqual(children(2).first?.accessibilityRole(), .group)
    XCTAssertEqual(children(1), [])
  }

  /// Cmd-Return on Cmd-L's untouched address has no typed text to search for: nothing opens.
  func testCommandReturnOnAnUntouchedCmdLOpensNothing() throws {
    var opened = false
    bar.onOpen = { _, _ in opened = true }
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    try key(36, "\r", [.command])
    XCTAssertFalse(opened)
    XCTAssertTrue(bar.isVisible)
  }

  // MARK: Return

  func testReturnRunsEachKindOfRow() throws {
    var folder: NodeID?
    var extensionID: String?
    var opened: [URL] = []
    bar.onShowFolder = { folder = $0 }
    bar.onOpenExtension = { extensionID = $0 }
    bar.onOpen = { url, _ in opened.append(url) }
    showAllGroups()
    bar.barView.table.selectRowIndexes([2], byExtendingSelection: false)
    bar.commit()
    XCTAssertNotNil(folder)
    XCTAssertFalse(bar.isVisible, "the bar closes")
    showAllGroups()
    bar.barView.table.selectRowIndexes([5], byExtendingSelection: false)
    bar.commit()
    XCTAssertEqual(extensionID, "pilot")
    showAllGroups()
    bar.barView.table.selectRowIndexes([3], byExtendingSelection: false)
    bar.commit()
    XCTAssertEqual(opened.last?.absoluteString, "https://git-scm.com/book")
  }

  /// Cmd-Return searches the web for exactly the typed text, whatever is selected.
  func testCommandReturnSearchesTheTypedText() throws {
    var opened: (URL, CommandBarController.OpenTarget)?
    bar.onOpen = { opened = ($0, $1) }
    var switched = false
    bar.onSwitch = { _ in switched = true }
    showAllGroups()
    XCTAssertEqual(selected, 0, "a tab row is selected")
    try key(36, "\r", [.command])
    XCTAssertFalse(switched)
    XCTAssertEqual(opened?.0, URLInputParser.searchURL(for: "git"))
    XCTAssertEqual(opened?.1, .newTab)
    XCTAssertFalse(bar.isVisible)
  }

  // MARK: Esc and Cmd-Shift-V

  func testEscClearsTheTextFirstAndClosesOnTheSecondPress() throws {
    showAllGroups()
    XCTAssertTrue(escape())
    XCTAssertTrue(bar.isVisible, "the first Esc only clears")
    XCTAssertEqual(bar.barView.field.stringValue, "")
    XCTAssertEqual(bar.results.first?.group, .tabs, "the empty state is back")
    XCTAssertTrue(escape())
    XCTAssertFalse(bar.isVisible)
  }

  func testEscOnTheUntouchedCmdLAddressCloses() throws {
    bar.toggle(.currentTab(URL(string: "https://example.com")))
    XCTAssertTrue(escape())
    XCTAssertFalse(bar.isVisible)
  }

  func testCommandShiftVOpensTheClipboardURLFromAnyState() throws {
    var opened: (URL, CommandBarController.OpenTarget)?
    bar.clipboardURLProvider = { URL(string: "https://clip.example/x") }
    bar.onOpen = { opened = ($0, $1) }
    showAllGroups()                                        // a typed query: the Paste and Go row is not showing
    try key(9, "v", [.command, .shift])
    XCTAssertEqual(opened?.0.absoluteString, "https://clip.example/x")
    XCTAssertEqual(opened?.1, .newTab)
    XCTAssertFalse(bar.isVisible)
  }

  func testCommandShiftVWithNothingOnTheClipboardKeepsTheBar() throws {
    var opened = false
    bar.onOpen = { _, _ in opened = true }
    showAllGroups()
    try key(9, "v", [.command, .shift])
    XCTAssertFalse(opened)
    XCTAssertTrue(bar.isVisible)
  }

  func testCmdLOffersNoPasteAndGo() throws {
    var opened = false
    bar.clipboardURLProvider = { URL(string: "https://clip.example/x") }
    bar.onOpen = { _, _ in opened = true }
    bar.toggle(.currentTab(nil))
    XCTAssertFalse(bar.results.contains { $0.kind.name == "pasteAndGo" })
    try key(9, "v", [.command, .shift])
    XCTAssertFalse(opened)
  }

  func testTheClipboardIsReadOnceForAShowNotOnEveryReload() throws {
    var reads = 0
    bar.clipboardURLProvider = { reads += 1; return URL(string: "https://clip.example") }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.results.first?.kind.name, "pasteAndGo")
    bar.setQueryForTesting("x")
    bar.setQueryForTesting("")
    XCTAssertEqual(reads, 1, "one pasteboard read for the whole show")
    bar.hide()
    bar.toggle(.newTab)
    XCTAssertEqual(reads, 2, "and a fresh one for the next show")
  }

  /// Reduce Transparency: the blur goes and the panel fills with `commandBarSurfaceOpaque`; otherwise the glass tint.
  func testReduceTransparencyFillsTheOpaqueSurface() throws {
    var reduced = false
    bar.barView.reduceTransparency = { reduced }
    bar.barView.apply(flavor: .light)
    XCTAssertFalse(bar.barView.effectView.isHidden)
    XCTAssertEqual(bar.barView.surfaceTint.layer?.backgroundColor, ShellTokens.commandBarSurface.light.cgColor)
    reduced = true
    bar.barView.apply(flavor: .dark)
    XCTAssertTrue(bar.barView.effectView.isHidden)
    XCTAssertEqual(bar.barView.surfaceTint.layer?.backgroundColor, ShellTokens.commandBarSurfaceOpaque.dark.cgColor)
  }

  // MARK: Motion

  /// Open and close do not animate: the bar and the scrim are whole on the first frame and gone on the same frame.
  func testOpenAndCloseDoNotAnimate() throws {
    bar.toggle(.newTab)
    XCTAssertEqual(bar.panel.alphaValue, 1)
    XCTAssertTrue(bar.scrim.isPresented)
    XCTAssertNil(bar.barView.layer?.animationKeys(), "no fade, no scale")
    XCTAssertNil(bar.scrim.layer?.animationKeys())
    XCTAssertEqual(bar.lifecycle.phase, .showing)
    bar.toggle(.newTab)
    XCTAssertEqual(bar.panel.alphaValue, 0, "hidden at once; the panel stays ordered in")
    XCTAssertFalse(bar.scrim.isPresented)
    XCTAssertEqual(bar.lifecycle.phase, .hidden)
    XCTAssertNil(bar.barView.layer?.animationKeys())
  }

  /// A selection move is an instant fill change: nothing animates.
  func testASelectionMoveIsInstant() throws {
    showAllGroups()
    bar.barView.layoutSubtreeIfNeeded()
    down()
    let row = try XCTUnwrap(bar.barView.table.rowView(atRow: 1, makeIfNecessary: false) as? CommandBarRowView)
    XCTAssertTrue(row.isSelected)
    XCTAssertNil(row.layer?.animationKeys())
  }

  // MARK: Suggestions (#562, #884)

  /// Suggestions fill rows below the Search for row; the selection keeps its row.
  func testSuggestionsFillBelowTheSearchRowWithoutMovingTheSelection() async throws {
    suggestingByHand()
    showAllGroups()
    down()
    try await turns(until: { pending.count == 1 }, "the request")
    XCTAssertEqual(pending.map(\.query), ["git"])
    let before = bar.results
    pending.removeFirst().reply.resume(returning: ["git rebase onto", "git stash pop", "git log"])
    try await turns(until: { bar.results.count == before.count + 2 }, "the suggestions")
    XCTAssertEqual(Array(bar.results.prefix(before.count)), before, "nothing above them moved")
    XCTAssertEqual(bar.results.suffix(2).map(\.title), ["git rebase onto", "git stash pop"])
    XCTAssertEqual(selected, 1, "the selection stays")
  }

  /// A reply for text the field no longer holds is dropped.
  func testAStaleSuggestionReplyIsDropped() async throws {
    suggestingByHand()
    showAllGroups()
    bar.setQueryForTesting("gi")
    try await turns(until: { pending.count == 2 }, "the requests")
    XCTAssertEqual(pending.map(\.query), ["git", "gi"])
    let count = bar.results.count
    pending.removeFirst().reply.resume(returning: ["git stale"])
    for _ in 0..<50 { await Task.yield() }
    XCTAssertEqual(bar.results.count, count)
    XCTAssertFalse(bar.results.contains { $0.title == "git stale" })
  }

  /// #884: a reply that lands after the bar hid and opened again on the same text is from an earlier show and is
  /// dropped; the hide cancelled its request.
  func testAReplyFromAnEarlierShowIsDropped() async throws {
    suggestingByHand()
    showAllGroups()
    try await turns(until: { pending.count == 1 }, "the request")
    let firstShow = try XCTUnwrap(bar.lifecycle.generation)
    bar.hide()
    XCTAssertNil(bar.lifecycle.generation)
    showAllGroups()
    XCTAssertGreaterThan(try XCTUnwrap(bar.lifecycle.generation), firstShow)
    try await turns(until: { pending.count == 2 }, "the second show's request")
    let count = bar.results.count
    pending.removeFirst().reply.resume(returning: ["git old"])
    for _ in 0..<50 { await Task.yield() }
    XCTAssertFalse(bar.results.contains { $0.title == "git old" })
    XCTAssertEqual(bar.results.count, count)
  }

  /// With "Include search engine suggestions" off, the engine is never asked.
  func testSuggestionsOffAsksNothing() async throws {
    suggestingByHand()
    bar.settings.setSearchSuggestionsEnabled(false)
    showAllGroups()
    for _ in 0..<50 { await Task.yield() }
    XCTAssertEqual(pending.count, 0)
    XCTAssertTrue(bar.results.contains { $0.kind == .search(URLInputParser.searchURL(for: "git")) })
  }

  // MARK: Layout

  /// A row that starts a group is taller by its header: 20 at the top of the list, 26 elsewhere; the panel is the
  /// spec's sum.
  func testGroupHeadersMakeTheirRowsTaller() throws {
    showAllGroups()
    let table = bar.barView.table
    XCTAssertEqual(table.rect(ofRow: 0).height, 36 + 20)
    XCTAssertEqual(table.rect(ofRow: 1).height, 36)
    XCTAssertEqual(table.rect(ofRow: 2).height, 36 + 26)
    let spec: CGFloat = 54 + 1 + 6 + 8 + 7 * 36 + 20 + 4 * 26
    XCTAssertEqual(bar.panel.frame.height, spec)
  }

  /// A Go row and every group full; in an 800 pt window the panel stops 24 above the bottom and the list scrolls, and
  /// a move to the last row scrolls it into view.
  func testTheWorstCaseScrollsAndTheSelectionFollows() throws {
    let parent = window.frame
    bar.openTabsProvider = {
      (1...5).map { .init(node: UUID(), title: "Layout \($0)", url: URL(string: "https://layout.example/t\($0)")!) }
    }
    bar.foldersProvider = { (1...5).map { .init(node: UUID(), title: "layout.example \($0)", tabCount: $0) } }
    bar.historyProvider = {
      (1...5).map { .init(title: "Layout page \($0)", url: URL(string: "https://layout.example/h\($0)")!) }
    }
    bar.extensionsProvider = {
      (1...5).map { .init(id: "e\($0)", name: "Layout tool \($0)", description: "For layout.example pages") }
    }
    bar.toggle(.newTab)
    bar.setQueryForTesting("layout.example")
    XCTAssertEqual(bar.results.count, 14, "Go, 3 tabs, 3 folders, 3 history, 3 extensions, Search for")
    let natural = CommandBarGeometry.contentHeight(rowCount: 14, headerCount: 5, firstRowHasHeader: false)
    let limit = parent.height - CommandBarGeometry.top(windowHeight: parent.height) - 24
    XCTAssertEqual(bar.panel.frame.height, min(natural, limit), accuracy: 0.5)
    bar.barView.layoutSubtreeIfNeeded()
    let table = bar.barView.table
    let last = bar.results.count - 1
    if natural > limit {
      XCTAssertFalse(table.visibleRect.contains(table.rect(ofRow: last)), "the last row starts out of view")
    }
    up()
    XCTAssertEqual(selected, last)
    XCTAssertTrue(table.visibleRect.contains(table.rect(ofRow: last)), "the selection scrolled into view")
  }

  /// The smallest window, 640 x 420: the panel is 592 wide with its top at 59, and nothing reaches past the window.
  func testTheSmallestWindow() throws {
    window.setFrame(NSRect(x: 100, y: 100, width: 640, height: 420), display: true)
    let parent = window.frame
    showAllGroups()
    let frame = bar.panel.frame
    XCTAssertEqual(frame.width, min(600, parent.width - 48), accuracy: 0.5)
    XCTAssertEqual(frame.maxY, parent.maxY - CommandBarGeometry.top(windowHeight: parent.height), accuracy: 1)
    XCTAssertGreaterThanOrEqual(frame.minY, parent.minY + 24 - 1)
    XCTAssertGreaterThanOrEqual(frame.minX, parent.minX)
    XCTAssertLessThanOrEqual(frame.maxX, parent.maxX)
  }

  /// A long title truncates with a tail ellipsis and keeps its place; the URL truncates first and is dropped under
  /// 48 pt; the field never wraps.
  func testTitlesTruncateAndTheURLGoesFirst() throws {
    let long = String(repeating: "A very long page title that keeps going ", count: 6)
    let longURL = URL(string: "https://long.example/" + String(repeating: "path/", count: 30))!
    let shortURL = URL(string: "https://short.example/" + String(repeating: "p/", count: 60))!
    let rows: [CommandBarResults.OpenTab] = [.init(node: UUID(), title: long, url: longURL),
                                             .init(node: UUID(), title: "Short", url: shortURL)]
    bar.openTabsProvider = { rows }
    bar.toggle(.newTab)
    let first = try cell(0)
    XCTAssertLessThan(first.title.frame.width, first.title.fittingSize.width, "the title is cut")
    XCTAssertTrue(first.subtitle.isHidden, "no room for 48 pt of URL: it is dropped")
    XCTAssertLessThanOrEqual(first.title.frame.maxX, first.trailingText.frame.minX)
    let second = try cell(1)
    XCTAssertEqual(second.title.frame.width, second.title.fittingSize.width, accuracy: 0.5, "a short title is whole")
    XCTAssertFalse(second.subtitle.isHidden)
    XCTAssertLessThan(second.subtitle.frame.width, second.subtitle.fittingSize.width, "the URL is cut")
    XCTAssertFalse(bar.barView.field.cell?.wraps ?? true)
  }

  // MARK: The window's providers

  /// The window's empty state: the tabs viewed in this window, newest first, without the tab on screen.
  func testTheWindowsEmptyStateListsViewedTabsNewestFirstWithoutTheTabOnScreen() throws {
    let sidebar = shell.sidebar
    let current = try XCTUnwrap(shell.sidebarController.currentSpace)
    let other = try sidebar.addSpace(title: "Other")
    let second = try sidebar.addTab(url: URL(string: "https://second.example")!, title: "Second", in: .today(current))
    let third = try sidebar.addTab(url: URL(string: "https://third.example")!, title: "Third", in: .today(current))
    let elsewhere = try sidebar.addTab(url: URL(string: "https://else.example")!, title: "Elsewhere", in: .today(other))
    shell.activate(node: elsewhere)                        // viewed in another Space
    shell.activate(node: second)
    shell.activate(node: third)                            // the tab on screen
    shell.commandBar.clipboardURLProvider = { nil }
    shell.commandBar.toggle(.newTab)
    defer { shell.commandBar.hide() }
    let rows = shell.commandBar.results.filter { $0.group == .tabs }
    XCTAssertEqual(rows.prefix(2).map(\.kind), [.switchTo(second), .switchTo(elsewhere)])
    XCTAssertFalse(rows.contains { $0.kind == .switchTo(third) }, "the tab on screen is not offered")
  }

  /// The window lists its enabled extension actions with each extension's description, takes a new list when the
  /// installed extensions or the actions change, and Return runs the action as a toolbar click would.
  func testTheWindowsExtensionsAndOpenExtension() throws {
    let engine = InMemoryEngine()
    let window = ShellWindowController(engine: engine, sidebar: StubSidebar.sample())
    defer { window.close() }
    window.showWindow(nil)
    let engineWindow = try XCTUnwrap(window.engineWindow)
    engine.setInstalledExtensions([
      InstalledExtensionInfo(id: "pilot", name: "Git Pilot", version: "1", description: "Pull request shortcuts"),
      InstalledExtensionInfo(id: "off", name: "Git Off", version: "1", description: "Turned off", isEnabled: false),
    ])
    engine.setExtensionActions([ExtensionAction(id: "pilot", name: "Git Pilot"),
                                ExtensionAction(id: "off", name: "Git Off")], in: engineWindow)
    let bar = window.commandBar
    bar.toggle(.newTab)
    bar.setQueryForTesting("shortcuts")
    let extensions = bar.results.filter { $0.group == .extensions }
    XCTAssertEqual(extensions.map(\.title), ["Git Pilot"], "matched on the description; the disabled one is left out")
    XCTAssertEqual(extensions.first?.secondaryText, "Pull request shortcuts")

    // A change of the installed list (a new description) and a change of the actions each take effect on the next
    // keystroke; an action whose extension the list does not know yet is kept, with no description.
    engine.setInstalledExtensions([
      InstalledExtensionInfo(id: "pilot", name: "Git Pilot", version: "1", description: "Pull request shortcuts, v2"),
    ])
    bar.setQueryForTesting("shortcut")
    XCTAssertEqual(bar.results.first { $0.group == .extensions }?.secondaryText, "Pull request shortcuts, v2")
    engine.setExtensionActions([ExtensionAction(id: "pilot", name: "Git Pilot"),
                                ExtensionAction(id: "new", name: "Shortcuts Plus")], in: engineWindow)
    bar.setQueryForTesting("shortcuts")
    XCTAssertEqual(bar.results.filter { $0.group == .extensions }.map(\.title), ["Shortcuts Plus", "Git Pilot"],
                   "a name match ranks first")
    XCTAssertEqual(bar.results.first { $0.group == .extensions }?.secondaryText, "")

    let row = try XCTUnwrap(bar.results.firstIndex { $0.kind == .extensionAction("pilot") })
    bar.barView.table.selectRowIndexes([row], byExtendingSelection: false)
    bar.commit()
    XCTAssertFalse(bar.isVisible)
    XCTAssertEqual(engine.ranExtensionActions.map(\.0), ["pilot"])
  }
}
