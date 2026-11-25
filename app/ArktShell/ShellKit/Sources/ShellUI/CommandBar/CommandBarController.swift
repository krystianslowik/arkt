import AppKit
import EngineAPI
import os

/// The command bar (design/command-bar/README.md): one field and one grouped list on a pre-warmed floating panel over
/// the shell window. It does not animate: open and close land on the next frame.
/// Parity: KB-001/BH-100 (Cmd-T), KB-002/BH-101 (Cmd-L), KB-003/BH-103 (Cmd-T/L closes),
/// KB-004/BH-102 (Cmd-L + unedited Enter reloads), KB-084 (Esc), KB-085 (arrows, Cmd-Return, Opt-Return).
@MainActor
public final class CommandBarController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate,
  NSWindowDelegate {
  /// Cmd-T, Cmd-L (with the current URL) and Ctrl-Shift-= (a new Split View pane, KB-070).
  public enum Mode: Equatable { case newTab, currentTab(URL?), newSplitPane }

  /// Where Return opens an address or a search.
  public enum OpenTarget: Equatable, Sendable {
    /// Cmd-L: navigate the current tab.
    case currentTab
    /// Cmd-T, or Opt-Return from any mode: a new Today tab.
    case newTab
    /// Ctrl-Shift-= and the Add Right / Left / Top / Bottom Split items: a new pane next to the focused tab.
    case newSplitPane
  }

  /// Return on Go, Search, a suggestion, Paste and Go or a history row.
  public var onOpen: ((URL, OpenTarget) -> Void)?
  /// Return on a tab row.
  public var onSwitch: ((NodeID) -> Void)?
  /// Return on a folder row: show the folder in the sidebar (BH-104).
  public var onShowFolder: ((NodeID) -> Void)?
  /// Return on an extension row: open its popup (BH-104).
  public var onOpenExtension: ((String) -> Void)?
  /// Cmd-L then Return without editing (KB-004).
  public var onReload: (() -> Void)?
  public var openTabsProvider: () -> [CommandBarResults.OpenTab] = { [] }
  /// The tab on screen, left out of Tabs.
  public var currentTabProvider: () -> NodeID? = { nil }
  public var foldersProvider: () -> [CommandBarResults.Folder] = { [] }
  public var extensionsProvider: () -> [CommandBarResults.Extension] = { [] }
  /// History visits in frecency order. Empty until a history store exists; tests and renders pass synthetic visits.
  public var historyProvider: () -> [CommandBarResults.HistoryVisit] = { [] }
  /// Search engine suggestions for a query (#562), asked for after each keystroke while "Include search engine
  /// suggestions" is on. Nil asks nothing. A reply for older text, or one that lands after the bar hid or opened again,
  /// is dropped.
  public var suggestionsProvider: (@MainActor (String) async -> [String])?
  /// A tab's cached favicon; nil draws its letter tile.
  public var faviconProvider: (NodeID) -> NSImage? = { _ in nil }
  /// "Include search engine suggestions".
  public var settings: CommandBarSettings = .ephemeral()
  /// BH-108: the address on the clipboard when the bar opens with an empty field (nil: no Paste and Go). The default
  /// reads nothing, so tests stay deterministic; the window wires the general pasteboard.
  public var clipboardURLProvider: () -> URL? = { nil }
  /// BH-109: a history row removed with Cmd-Opt-Delete; the session exclusion is already applied. A future history
  /// store persists removals through this hook.
  public var onRemoveSuggestion: ((CommandBarResults.Result) -> Void)?

  /// Show and hide in one value (#884).
  private(set) var lifecycle = CommandBarLifecycle()
  public var isVisible: Bool { lifecycle.phase != .hidden }
  public private(set) var mode: Mode = .newTab
  /// Seconds from show() entry to the presentation time of the first frame with the panel.
  public private(set) var lastShowLatency: Double?
  public var onFirstFrame: ((Double) -> Void)?
  /// Diagnostics for the latency budget (the smoke and the GUI tests): show() main-thread CPU time and
  /// wall time (seconds), and seconds from show() entry to the vsync that started the first tick (`timestamp`).
  @_spi(Smoke) public private(set) var lastShowCPUTime: Double = 0
  @_spi(Smoke) public private(set) var lastShowWallTime: Double = 0
  @_spi(Smoke) public private(set) var lastShowVsyncWait: Double = 0
  /// Seconds from show() entry to the end of the Core Animation commit that carried the show.
  @_spi(Smoke) public private(set) var lastShowCommitDelay: Double = 0
  private(set) var lastFrameInterval: Double = 0

  let panel = CommandBarPanel()
  let barView = CommandBarView()
  /// The light dim over the parent window's content while the bar is open.
  let scrim = CommandBarScrim()
  /// The rows on screen.
  private(set) var results: [CommandBarResults.Result] = []
  /// Group headers by row, for the rows on screen.
  private(set) var groupHeaders: [Int: String] = [:]
  /// The suggestions that arrived for `suggestionsQuery`.
  private var suggestions: [String] = []
  private var suggestionsQuery = ""
  /// BH-109: history rows removed this controller's lifetime stay hidden.
  private var removedSuggestionIDs: Set<String> = []
  /// Says the selected row on a keyboard move (#608) and the result count once typing settles; replaced in tests.
  var announce: AXAnnouncement.Poster = AXAnnouncement.post
  /// Runs the count announcement after typing settles (150 ms). Replaced in tests, which run it by hand.
  var afterTypingSettles: @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { work() } }
  }
  private var typingGeneration = 0
  /// Whether the key event being handled is a held key's repeat. Replaced in tests.
  var isRepeatKey: @MainActor () -> Bool = {
    guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
    return event.isARepeat
  }
  /// The clipboard address read for this show: the pasteboard is read once per show, not on every reload.
  private var clipboardSnapshot: (url: URL?, isRead: Bool) = (nil, false)
  /// The appearance the bar and its cells were last drawn in (the parent window's); a show in another one re-renders.
  private var cellFlavor: ThemeFlavor?
  private var appliedReduceTransparency: Bool?
  private var appliedIncreaseContrast: Bool?
  /// Backing scale the table's cells were configured at; a show at another scale reloads them.
  private var cellScale: CGFloat = 0
  /// The query the cells' title emphasis was drawn for.
  private var cellQuery = ""
  /// Extension icons decoded once, by their PNG data.
  private var extensionIcons: [Data: NSImage] = [:]
  /// Test seam: stands in for the parent window's backing scale.
  var backingScaleOverride: CGFloat?
  /// The panel sits over the parent window, so it shares the parent's display. Read from the parent: the panel
  /// itself still reports the previous display's scale until its frame moves in show().
  private var backingScale: CGFloat { backingScaleOverride ?? parent?.backingScaleFactor ?? 2 }
  private var prefill: String?
  /// Cmd-L on a page: its untouched address leads the list with a selected Reload row (KB-004). The first move of the
  /// selection or edit of the text takes the row away until the next show; Return then runs the selected row.
  private(set) var reloadArmed = false
  private var showStart: CFTimeInterval = 0
  /// On the parent window (always on screen, so it ticks right away), created once and unpaused per show():
  /// creating a link per show cost up to ~2 ms under load. The link retains its target; invalidate() breaks
  /// that cycle.
  private var firstFrameLink: CADisplayLink?
  private var invalidated = false
  private var signpostState: OSSignpostIntervalState?
  private weak var parent: NSWindow?

  public init(parent: NSWindow) {
    self.parent = parent
    super.init()
    panel.contentView = barView
    panel.delegate = self
    barView.field.delegate = self
    barView.table.dataSource = self
    barView.table.delegate = self
    barView.table.target = self
    barView.table.action = #selector(rowClicked(_:))
    // Accessibility rows read the results, not row views: a row never laid out still has its title and caption.
    barView.table.axProxyRows.content = { [weak self] row in
      guard let self, results.indices.contains(row) else { return nil }
      return AXProxyRowContent(identifier: AXID.CommandBar.row,
                               label: results[row].commandBarLabel(position: row + 1, of: results.count),
                               value: results[row].accessibilityCaption)
    }
    // A row that starts a group lists its header ("Tabs") as a group inside it, from the model, so a row scrolled out
    // of view (and so without a cell) still has it.
    // A hovered history row also lists its remove button.
    barView.table.axProxyRows.children = { [weak self] row in
      guard let self else { return [] }
      var children: [NSView] = []
      if let title = groupHeaders[row] {
        let header = headerElement(row)
        header.setAccessibilityLabel(title)
        children.append(header)
      }
      if let cell = barView.table.view(atColumn: 0, row: row, makeIfNecessary: false) as? CommandBarCellView,
         !cell.removeButton.isHidden {
        children.append(cell.removeButton)
      }
      let parent = barView.table.axProxyRows.rowElement(forRow: row)
      children.forEach { $0.setAccessibilityParent(parent) }
      return children
    }
    barView.onHoverRow = { [weak self] row in self?.select(row, byKeyboard: false) }
    barView.table.onMouseDownRow = { [weak self] row in self?.select(row, byKeyboard: false) }
    panel.keyDownHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }
    for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification,
                 NSWindow.didChangeBackingPropertiesNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(parentFrameDidChange(_:)), name: name,
                                             object: parent)
    }
  }

  /// Creates the window-server backing store, lays out and draws once over the parent window (on its display,
  /// at alpha 0 and inert, as after a hide), and leaves the panel ordered in, so a show() does no allocation,
  /// first-draw work or window ordering.
  public func prewarm() {
    cellScale = backingScale
    applyAppearance(force: true)
    if let parent { scrim.attach(to: parent) }        // in for good, at opacity 0, like the panel
    var input = CommandBarResults.Input()
    input.openTabs = [.init(node: UUID(), title: "warm", url: URL(string: "https://warm.example")!)]
    results = CommandBarResults.grouped(query: "warm", input: input)
    groupHeaders = CommandBarResults.groupHeaders(of: results)
    barView.table.reloadData()
    if let parent { panel.setFrame(frame(in: parent), display: true) }
    barView.table.selectRowIndexes([0], byExtendingSelection: false)
    panel.orderFrontRegardless()                  // ordered in for good, at alpha 0 (see CommandBarPanel)
    if barView.field.currentEditor() == nil { _ = panel.makeFirstResponder(barView.field) }
    panel.displayIfNeeded()
    reloadResults(keepSelection: false)
    if let parent { setPanelFrame(frame(in: parent), display: true) }
    panel.displayIfNeeded()
    makeFirstFrameLink()
  }

  private func makeFirstFrameLink() {
    guard firstFrameLink == nil, !invalidated, let parent else { return }
    let link = parent.displayLink(target: self, selector: #selector(firstFrame(_:)))
    link.isPaused = true
    link.add(to: .main, forMode: .common)
    firstFrameLink = link
  }

  /// Tears down the display link (which retains this controller) and the panel. Call when the parent closes;
  /// the controller does not show again afterwards.
  public func invalidate() {
    invalidated = true
    NotificationCenter.default.removeObserver(self)
    firstFrameLink?.invalidate()
    firstFrameLink = nil
    hide(restoreFocus: false)
    scrim.removeFromSuperview()
    panel.orderOut(nil)
  }

  var hasOpenSignpost: Bool { signpostState != nil }

  /// Menu entry point. Cmd-T / Cmd-L while open closes the bar (KB-003, BH-103).
  public func toggle(_ newMode: Mode) {
    if isVisible { hide() } else { show(newMode) }
  }

  public func show(_ newMode: Mode) {
    showStart = CACurrentMediaTime()
    let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    guard let parent, !invalidated else { return }
    makeFirstFrameLink()
    endSignpost()                                   // a second show() before the first frame restarts the interval
    signpostState = ShellSignposts.signposter.beginInterval("CommandBarShow")
    lifecycle.send(.show)
    mode = newMode
    switch newMode {
    case .newTab, .newSplitPane: prefill = nil
    case .currentTab(let url): prefill = url?.absoluteString
    }
    let targetText = prefill ?? ""
    reloadArmed = prefill != nil
    if barView.field.stringValue != targetText { barView.field.stringValue = targetText }
    clipboardSnapshot = (nil, false)
    suggestions = []
    suggestionsQuery = ""
    applyAppearance()
    reloadResults(keepSelection: false)
    setPanelFrame(frame(in: parent), display: false)
    // Already ordered in at alpha 0 (prewarm), so presenting is an alpha change and key status. Ordering in
    // only happens when something ordered the panel out (hidesOnDeactivate while the app was inactive), or
    // when it sits on another Space: an ordered-in window stays on the Space it was ordered in on, so a show
    // on a second desktop or a full-screen Space orders it out and back in there (.fullScreenAuxiliary lets
    // it join a full-screen Space). Done while still hidden, before key status changes.
    if !panel.isVisible || !panel.isOnActiveSpace {
      if panel.isVisible { panel.orderOut(nil) }
      panel.orderFrontRegardless()
    }
    scrim.attach(to: parent)
    scrim.isPresented = true                        // no fade: the bar is whole on the first frame
    panel.isPresented = true
    panel.makeKey()
    if barView.field.currentEditor() == nil { panel.makeFirstResponder(barView.field) }   // kept across hides
    applyCaretColor()
    if !targetText.isEmpty { barView.field.currentEditor()?.selectAll(nil) }
    let generation = lifecycle.generation ?? 0
    // Core Animation commits the implicit transaction in a before-waiting run loop observer (order 2000000);
    // a one-shot observer ordered after it marks the end of the commit that carries this show.
    let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false,
                                                      CFIndex.max) { [weak self] _, _ in
      MainActor.assumeIsolated {
        self?.lifecycle.send(.commitEnded(generation: generation, at: CACurrentMediaTime()))
      }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    firstFrameLink?.isPaused = false
    lastShowWallTime = CACurrentMediaTime() - showStart
    lastShowCPUTime = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1e9
  }

  /// First vsync after the show's commit: that frame is the first composited with the bar.
  @objc private func firstFrame(_ link: CADisplayLink) {
    guard lifecycle.phase == .showing, let generation = lifecycle.generation else { link.isPaused = true; return }
    guard let committed = lifecycle.commitTime, link.timestamp >= committed else { return }
    link.isPaused = true
    let latency = link.targetTimestamp - showStart
    lastShowVsyncWait = link.timestamp - showStart
    lastShowCommitDelay = committed - showStart
    lastFrameInterval = link.targetTimestamp - link.timestamp
    lastShowLatency = latency
    lifecycle.send(.firstFrame(generation: generation))
    endSignpost()
    ShellSignposts.logger.notice("commandbar.show ms=\(latency * 1000, format: .fixed(precision: 2))")
    onFirstFrame?(latency)
  }

  /// Closes the bar on the same frame: no fade. `restoreFocus` returns key status to the shell window (Esc, Return,
  /// Cmd-T/Cmd-L). It is false when the bar hides because something else took focus, which must keep it.
  public func hide(restoreFocus: Bool = true) {
    guard isVisible else { return }
    lifecycle.send(.hide)                           // drops the suggestion request: a late reply must not reload (#880)
    firstFrameLink?.isPaused = true
    endSignpost()
    panel.isPresented = false                       // stays ordered in, inert, at alpha 0
    scrim.isPresented = false
    if restoreFocus { parent?.makeKey() }
  }

  private func endSignpost() {
    guard let state = signpostState else { return }
    ShellSignposts.signposter.endInterval("CommandBarShow", state)
    signpostState = nil
  }

  // MARK: Appearance

  /// Draws the bar, its cells and the scrim in the window behind it: light or dark, opaque under Reduce Transparency,
  /// edged under Increase Contrast. Cheap when nothing changed (a show repeats it).
  private func applyAppearance(force: Bool = false) {
    guard let parent else { return }
    let flavor = ThemeFlavor(appearance: parent.effectiveAppearance)
    let opaque = barView.reduceTransparency()
    let contrast = barView.increaseContrast()
    guard force || flavor != cellFlavor || opaque != appliedReduceTransparency || contrast != appliedIncreaseContrast
    else { return }
    let cellsChanged = flavor != cellFlavor || contrast != appliedIncreaseContrast
    cellFlavor = flavor
    appliedReduceTransparency = opaque
    appliedIncreaseContrast = contrast
    panel.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    barView.apply(flavor: flavor)
    scrim.apply(flavor: flavor)
    if cellsChanged, !results.isEmpty { reapplyCells() }
    applyCaretColor()
  }

  /// The caret is a 2 pt mustard fill (README, Look): mustard's one use on the bar.
  private func applyCaretColor() {
    guard let editor = barView.field.currentEditor() as? NSTextView else { return }
    editor.insertionPointColor = BrandTokens.accent.resolve(flavor).nsColor()
  }

  /// The flavor the bar draws in (tests).
  var flavor: ThemeFlavor { cellFlavor ?? .dark }

  /// Re-renders the cells for a new appearance and keeps the selection.
  private func reapplyCells() {
    let selected = barView.table.selectedRow
    barView.table.reloadData()
    if selected >= 0, selected < results.count { barView.table.selectRowIndexes([selected], byExtendingSelection: false) }
  }

  // MARK: Panel

  /// Clicking back into the shell window (or another app) dismisses the bar, like Arc.
  public func windowDidResignKey(_ notification: Notification) { hide(restoreFocus: false) }

  /// The hidden panel stays ordered in, so app activation can hand it key status back (AppKit restores the
  /// last key window). An invisible key window would swallow typing; pass key status to the shell window.
  /// Deferred: changing key status inside the key-change notification is ignored by AppKit.
  public func windowDidBecomeKey(_ notification: Notification) {
    guard !isVisible else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isVisible else { return }
      self.parent?.makeKey()
    }
  }

  /// The open bar follows the parent when it moves, resizes, changes screen or changes backing scale (re-rendering
  /// result icons at the new scale without waiting for the next show, #212). A closed bar follows only on
  /// `didChangeScreen` (frame only), so the first show after a display change is already on the parent's display.
  @objc private func parentFrameDidChange(_ notification: Notification) {
    guard let parent else { return }
    if isVisible {
      setPanelFrame(frame(in: parent), display: false)
      refreshCellScaleIfNeeded()
    } else if notification.name == NSWindow.didChangeScreenNotification {
      setPanelFrame(frame(in: parent), display: false)
    }
  }

  private func refreshCellScaleIfNeeded() {
    let scale = backingScale
    guard scale != cellScale else { return }
    cellScale = scale
    reapplyCells()
  }

  // MARK: Field and keys

  public func controlTextDidChange(_ obj: Notification) {
    disarmReload()
    reloadResults(keepSelection: false)
    relayout()
    requestSuggestions()
    scheduleCountAnnouncement()
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)): escape(); return true        // Esc, KB-084
    case #selector(NSResponder.insertNewline(_:)): commit(); return true
    case #selector(NSResponder.insertTab(_:)): jumpGroup(forward: true); return true
    case #selector(NSResponder.insertBacktab(_:)): jumpGroup(forward: false); return true
    // Opt-Return's standard binding; handleKeyDown normally takes Opt-Return first. Only an actual Opt-Return opens
    // a new tab here; another key bound to this selector commits like Return.
    case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
      commit(forcing: Self.isReturn(NSApp.currentEvent, withExactly: [.option]) ? .newTab : nil); return true
    // Down and Up, and Ctrl-N and Ctrl-P, which the field editor binds to the same selectors.
    case #selector(NSResponder.moveDown(_:)): moveSelection(+1); return true
    case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
    case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): movePage(+1); return true
    case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): movePage(-1); return true
    default: return false
    }
  }

  /// Keys the field editor has no binding for. Cmd-Opt-Delete (KB-083, BH-109) removes the selected history row;
  /// Cmd-Shift-V is Paste and Go from any state; Cmd-Return searches the web for exactly the typed text; Opt-Return
  /// (KB-085) runs the selected row in a new tab. Return during IME composition goes on to the field editor.
  private func handleKeyDown(_ event: NSEvent) -> Bool {
    guard isVisible else { return false }
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    if event.keyCode == 51, modifiers == [.command, .option] {
      removeSelectedSuggestion()
      return true
    }
    if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "v" {
      pasteAndGo()
      return true
    }
    guard Self.isReturn(event, withExactly: [.command, .option]) else { return false }
    if let editor = barView.field.currentEditor() as? NSTextView, editor.hasMarkedText() { return false }
    if modifiers == .command { searchTypedText() } else { commit(forcing: .newTab) }
    return true
  }

  /// The query the rows are made from: empty for an empty field and for Cmd-L's untouched address, which shows the
  /// empty state (README, Keyboard).
  private var effectiveQuery: String {
    if case .currentTab = mode, let prefill, barView.field.stringValue == prefill { return "" }
    return barView.field.stringValue
  }

  /// Esc clears the text if there is any, otherwise closes; with the Cmd-L address untouched it closes (KB-084).
  private func escape() {
    if effectiveQuery.isEmpty { hide(); return }
    barView.field.stringValue = ""
    barView.field.currentEditor()?.string = ""
    controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: barView.field))
  }

  /// Cmd-Shift-V: opens the clipboard address, from any state (a new-tab surface: Cmd-L and the split pane bar never).
  private func pasteAndGo() {
    guard mode == .newTab, let url = clipboardURLProvider() else { NSSound.beep(); return }
    let target = openTarget
    hide()
    onOpen?(url, target)
  }

  /// Cmd-Return: the web search for exactly the typed text, whatever is selected. Cmd-L's untouched address is not
  /// typed text: nothing to search for.
  private func searchTypedText() {
    let text = effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { NSSound.beep(); return }
    let target = openTarget
    hide()
    onOpen?(URLInputParser.searchURL(for: text), target)
  }

  /// True for a key-down of Return or keypad Enter whose Cmd / Opt / Ctrl / Shift modifiers are exactly one of
  /// `modifiers` (other flags, such as the keypad's, are ignored).
  static func isReturn(_ event: NSEvent?, withExactly modifiers: [NSEvent.ModifierFlags]) -> Bool {
    guard let event, event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76 else { return false }
    return modifiers.contains(event.modifierFlags.intersection([.command, .option, .control, .shift]))
  }

  /// Return. Cmd-L + Return without editing reloads (KB-004, BH-102); otherwise the selected row runs.
  public func commit() { commit(forcing: nil) }

  /// `forced` nil: the mode decides (Cmd-T new tab, Cmd-L current tab, Ctrl-Shift-= new split pane). `.newTab`:
  /// Opt-Return, which opens in a new tab and never reloads.
  private func commit(forcing forced: OpenTarget?) {
    commit(row: max(barView.table.selectedRow, 0), forcing: forced)
  }

  private func commit(row: Int, forcing forced: OpenTarget? = nil) {
    guard row < results.count else { hide(); return }
    let kind = results[row].kind
    let target = forced ?? openTarget
    hide()
    switch kind {
    case .open(let url), .search(let url), .suggestion(let url), .pasteAndGo(let url), .history(let url):
      onOpen?(url, target)
    // A tab row switches in every mode, the split pane bar included: the tab is already open.
    case .switchTo(let node): onSwitch?(node)
    // KB-004: Return reloads; Opt-Return opens the page again in a new tab.
    case .reload(let url): if forced == .newTab { onOpen?(url, .newTab) } else { onReload?() }
    case .folder(let node): onShowFolder?(node)
    case .extensionAction(let id): onOpenExtension?(id)
    }
  }

  /// Where a plain Return opens a row in the current mode.
  private var openTarget: OpenTarget {
    switch mode {
    case .newTab: .newTab
    case .currentTab: .currentTab
    case .newSplitPane: .newSplitPane
    }
  }

  @objc private func rowClicked(_ sender: Any?) {
    let row = barView.table.clickedRow
    if row >= 0 { commit(row: row) }
  }

  /// Test hook: same path as typing into the field.
  @_spi(Smoke) public func setQueryForTesting(_ query: String) {
    barView.field.stringValue = query
    controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: barView.field))
  }

  /// The Paste and Go clipboard read (BH-108): a URL on the pasteboard. Plain text counts only with an
  /// explicit scheme; a schemeless host ("example.com") may be text the user never meant as a URL.
  public static func pasteboardURL(_ pasteboard: NSPasteboard) -> URL? {
    if let string = pasteboard.string(forType: .URL), let url = URL(string: string), url.scheme != nil {
      return url
    }
    guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
          URLInputParser.hasExplicitScheme(text) else { return nil }
    return URLInputParser.url(from: text)
  }

  // MARK: Frame

  /// setFrame is a window-server round trip (measured up to ~2.8 ms) even when nothing changes; skip it then.
  private func setPanelFrame(_ frame: NSRect, display: Bool) {
    guard panel.frame != frame else { return }
    panel.setFrame(frame, display: display)
  }

  private func frame(in parent: NSWindow) -> NSRect {
    let height = CommandBarGeometry.contentHeight(rowCount: results.count, headerCount: groupHeaders.count,
                                                  firstRowHasHeader: groupHeaders[0] != nil)
    return CommandBarGeometry.frame(parentFrame: parent.frame, contentHeight: height)
  }

  /// The top edge stays; the height follows the rows at once.
  private func relayout(display: Bool = true) {
    guard let parent else { return }
    setPanelFrame(frame(in: parent), display: display)
  }

  // MARK: Rows

  /// Asks for the suggestions of the field's text. The reply is used only if the bar is still in the same show and
  /// the field still holds that text (#880, #884).
  private func requestSuggestions() {
    let query = effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let suggestionsProvider, settings.searchSuggestionsEnabled, !query.isEmpty,
          let generation = lifecycle.generation else { return }
    let task = Task { [weak self] in
      let list = await suggestionsProvider(query)
      guard let self, !Task.isCancelled, self.lifecycle.accepts(generation: generation),
            self.effectiveQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
      self.suggestions = list
      self.suggestionsQuery = query
      // Suggestions fill rows below the Search for row: the selection keeps its row.
      self.reloadResults(keepSelection: true)
      self.relayout()
    }
    lifecycle.attach(suggestions: task)
  }

  /// "<n> results" once typing settles; a later keystroke replaces it.
  private func scheduleCountAnnouncement() {
    typingGeneration += 1
    let generation = typingGeneration
    afterTypingSettles { [weak self] in
      guard let self, self.isVisible, self.typingGeneration == generation, !self.effectiveQuery.isEmpty else { return }
      self.announce(CommandBarResults.countAnnouncement(for: self.results), .medium)
    }
  }

  /// Rebuilds the rows from the providers. `keepSelection` keeps the selected row (suggestions arriving, a Space
  /// change); otherwise the first row is selected, as on every keystroke.
  private func reloadResults(keepSelection: Bool) {
    let query = effectiveQuery
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var input = CommandBarResults.Input()
    input.openTabs = openTabsProvider()
    input.currentTab = currentTabProvider()
    input.history = historyProvider()
    input.excluded = removedSuggestionIDs
    input.searchSuggestionsEnabled = settings.searchSuggestionsEnabled
    if trimmed.isEmpty {
      // BH-108: Paste and Go is a new-tab surface, as Cmd-Shift-V is; Cmd-L and the split pane bar never offer it.
      // The pasteboard is read for the empty field only, so a keystroke never pays for it.
      input.clipboardURL = mode == .newTab ? clipboardURLForThisShow() : nil
      input.reloadURL = reloadArmed ? prefill.flatMap { URL(string: $0) } : nil
    } else {
      input.folders = foldersProvider()
      input.extensions = extensionsProvider()
      input.suggestions = suggestionsQuery == trimmed ? suggestions : []
    }
    let fresh = CommandBarResults.grouped(query: query, input: input)
    let headers = CommandBarResults.groupHeaders(of: fresh)
    let scale = backingScale
    let previousSelection = barView.table.selectedRow
    if fresh != results || scale != cellScale || query != cellQuery || headers != groupHeaders {
      // The cells on screen take the new rows in place; rows are added or removed only at the end, and heights noted
      // where a group header came or went. A reload would take every row view out of the window and build them again
      // (#606).
      let oldCount = barView.table.numberOfRows        // what the table holds, before it is told of the new rows
      let oldHeaders = groupHeaders
      results = fresh
      groupHeaders = headers
      cellScale = scale
      cellQuery = query
      barView.setHoveredRow(nil)                      // the rows moved; no honest hover target until the pointer moves
      refreshRowsInPlace(oldCount: oldCount, oldHeaders: oldHeaders)
    }
    guard !results.isEmpty else { return }
    let target = keepSelection && previousSelection >= 0 ? min(previousSelection, results.count - 1) : 0
    if barView.table.selectedRow != target { barView.table.selectRowIndexes([target], byExtendingSelection: false) }
    if !keepSelection { barView.table.scrollRowToVisible(0) }
  }

  private func clipboardURLForThisShow() -> URL? {
    if !clipboardSnapshot.isRead { clipboardSnapshot = (clipboardURLProvider(), true) }
    return clipboardSnapshot.url
  }

  /// BH-111: the open bar's rows follow the current Space; the window calls this on a Space switch.
  public func refreshSuggestions() {
    guard isVisible else { return }
    reloadResults(keepSelection: true)
    relayout()
  }

  // MARK: Removal (BH-109, KB-083)

  /// Cmd-Opt-Delete: removes the selected history row; the next row takes its place.
  public func removeSelectedSuggestion() {
    removeSuggestion(at: barView.table.selectedRow)
  }

  /// Cmd-Opt-Delete or a history row's remove button: the row stays hidden for this controller's lifetime;
  /// `onRemoveSuggestion` is the persistence hook.
  func removeSuggestion(at row: Int) {
    guard results.indices.contains(row), let id = results[row].removalID else { return }
    disarmReload()
    let result = results[row]
    removedSuggestionIDs.insert(id)
    onRemoveSuggestion?(result)
    reloadResults(keepSelection: true)
    relayout()
  }

  // MARK: Selection

  /// Up / Down: wrap on a fresh press, stop at the ends on a held key's repeat (README, Keyboard).
  private func moveSelection(_ delta: Int) {
    guard let next = CommandBarSelection.move(from: barView.table.selectedRow, by: delta, count: results.count,
                                              isRepeat: isRepeatKey()) else { return }
    select(next, byKeyboard: true)
  }

  /// PageUp / PageDown move by five rows and stop at the ends [I].
  private func movePage(_ pages: Int) {
    guard let next = CommandBarSelection.page(from: barView.table.selectedRow, by: pages, count: results.count)
    else { return }
    select(next, byKeyboard: true)
  }

  /// Tab and Shift-Tab: the first row of the next or previous group. Nothing else (site search is gone).
  private func jumpGroup(forward: Bool) {
    guard let next = CommandBarSelection.groupJump(from: barView.table.selectedRow, forward: forward,
                                                   groups: results.map(\.group)) else { return }
    select(next, byKeyboard: true)
  }

  /// A keyboard move scrolls the row into view with the least movement and, since focus stays in the field, speaks
  /// the row's label (#608). A hover does neither: the row under the pointer is already visible.
  private func select(_ row: Int, byKeyboard: Bool) {
    guard row >= 0, row < results.count else { return }
    var row = row
    if barView.table.selectedRow != row, case .reload? = results.first?.kind {
      // Moving off the Reload row takes it away; the rows below it move up one.
      disarmReload()
      row = max(row - 1, 0)
    }
    let changed = barView.table.selectedRow != row
    if changed { barView.table.selectRowIndexes([row], byExtendingSelection: false) }
    guard byKeyboard else { return }
    barView.table.scrollRowToVisible(row)
    if changed {
      announce(results[row].commandBarLabel(position: row + 1, of: results.count), AXAnnouncement.selectionPriority)
    }
  }

  /// The user moved the selection or edited the text: Return runs the selected row from now on.
  private func disarmReload() {
    guard reloadArmed else { return }
    reloadArmed = false
    guard case .reload? = results.first?.kind else { return }
    reloadResults(keepSelection: false)
    relayout()
  }

  /// The accessibility element of `row`'s group header, kept per row (at most five headers).
  private var headerElements: [Int: CommandBarGroupHeaderLabel] = [:]

  private func headerElement(_ row: Int) -> CommandBarGroupHeaderLabel {
    if let existing = headerElements[row] { return existing }
    let header = CommandBarGroupHeaderLabel(labelWithString: "")
    headerElements[row] = header
    return header
  }

  // MARK: Table

  public func numberOfRows(in tableView: NSTableView) -> Int { results.count }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: CommandBarCellView.identifier, owner: nil) as? CommandBarCellView
      ?? CommandBarCellView(frame: .zero)
    configure(cell, row: row)
    return cell
  }

  private func configure(_ cell: CommandBarCellView, row: Int) {
    let result = results[row]
    var favicon: NSImage?
    if case .switchTo(let node) = result.kind { favicon = faviconProvider(node) }
    if let png = result.iconPNG {
      if extensionIcons[png] == nil, extensionIcons.count > 64 { extensionIcons.removeAll() }
      favicon = extensionIcons[png] ?? NSImage(data: png)
      extensionIcons[png] = favicon
    }
    cell.onRemove = result.removalID == nil ? nil : { [weak self] in self?.removeSuggestion(at: row) }
    cell.configure(result, query: cellQuery, position: row + 1, count: results.count, flavor: flavor,
                   scale: cellScale, groupHeader: groupHeaders[row], isFirstRow: row == 0, favicon: favicon,
                   increasedContrast: appliedIncreaseContrast ?? false)
    cell.setHovered(barView.hoveredRow == row)
  }

  /// The rows changed: the table grows or shrinks at the end, rows whose header came or went are re-measured, and each
  /// row the table holds shows its new result.
  private func refreshRowsInPlace(oldCount: Int, oldHeaders: [Int: String]) {
    let table = barView.table
    let count = results.count
    if count != oldCount || oldHeaders != groupHeaders {
      // NSTableView animates height changes by default; the list updates in place, with no motion (README, Motion).
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        context.allowsImplicitAnimation = false
        table.beginUpdates()
        if count > oldCount {
          table.insertRows(at: IndexSet(oldCount..<count), withAnimation: [])
        } else if count < oldCount {
          table.removeRows(at: IndexSet(count..<oldCount), withAnimation: [])
        }
        let changed = Set(oldHeaders.keys).symmetricDifference(groupHeaders.keys).union([0]).filter { $0 < count }
        table.noteHeightOfRows(withIndexesChanged: IndexSet(changed))
        table.endUpdates()
      }
    }
    table.enumerateAvailableRowViews { rowView, row in
      guard results.indices.contains(row) else { return }
      if let rowView = rowView as? CommandBarRowView { style(rowView, row: row) }
      if let cell = rowView.view(atColumn: 0) as? CommandBarCellView { configure(cell, row: row) }
      rowView.setAccessibilityLabel(results[row].commandBarLabel(position: row + 1, of: results.count))
      rowView.setAccessibilityValue(results[row].accessibilityCaption)
    }
    table.rowsDidChange()
  }

  private func style(_ rowView: CommandBarRowView, row: Int) {
    rowView.flavor = flavor
    rowView.headerHeight = CommandBarGeometry.rowHeight(hasHeader: groupHeaders[row] != nil, isFirst: row == 0)
      - CommandBarGeometry.rowHeight
  }

  /// A row that starts a group is taller by its header.
  public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    CommandBarGeometry.rowHeight(hasHeader: groupHeaders[row] != nil, isFirst: row == 0)
  }

  public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = tableView.makeView(withIdentifier: CommandBarRowView.identifier, owner: nil) as? CommandBarRowView
      ?? CommandBarRowView(frame: .zero)
    rowView.identifier = CommandBarRowView.identifier
    if results.indices.contains(row) {
      style(rowView, row: row)
      rowView.setAccessibilityLabel(results[row].commandBarLabel(position: row + 1, of: results.count))
      rowView.setAccessibilityValue(results[row].accessibilityCaption)
    }
    return rowView
  }
}
