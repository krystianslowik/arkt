import AppKit
import EngineAPI
import os

/// Arc's command bar: a pre-warmed floating panel over the shell window.
/// Parity: KB-001/BH-100 (Cmd-T), KB-002/BH-101 (Cmd-L), KB-003/BH-103 (Cmd-T/L closes),
/// KB-004/BH-102 (Cmd-L + unedited Enter reloads), KB-084 (Esc closes), KB-085 (Cmd-Enter, Opt-Enter, arrow wrap).
/// RT-08 has not been run against Arc: Esc, Enter on an empty query, Cmd-Enter / Opt-Enter, arrow wrap, PageUp /
/// PageDown and hover selection follow the [I] rules noted where they are handled.
@MainActor
public final class CommandBarController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate,
  NSWindowDelegate {
  /// Cmd-T, Cmd-L (with the current URL) and Ctrl-Shift-= (a new Split View pane, KB-070).
  public enum Mode: Equatable { case newTab, currentTab(URL?), newSplitPane }

  /// Where Enter opens a URL or search result.
  public enum OpenTarget: Equatable, Sendable {
    /// Cmd-L: navigate the current tab.
    case currentTab
    /// Cmd-T, or Cmd-Enter / Opt-Enter from any mode: a new Today tab.
    case newTab
    /// Ctrl-Shift-= and the Add Right / Left / Top / Bottom Split items: a new pane next to the focused tab.
    case newSplitPane
  }

  /// Enter on a URL or search result.
  public var onOpen: ((URL, OpenTarget) -> Void)?
  /// Enter on a "Switch to Tab" result.
  public var onSwitch: ((NodeID) -> Void)?
  /// Cmd-L then Enter without editing (KB-004).
  public var onReload: (() -> Void)?
  public var openTabsProvider: () -> [CommandBarResults.OpenTab] = { [] }
  /// The empty state's Recent tabs, most recently viewed first, with when. Empty: the open tabs stand in.
  public var recentTabsProvider: () -> [CommandBarResults.OpenTab] = { [] }
  /// Archived matches for a query (#111): the store search runs off the main actor; the bar lists the matches when
  /// they land, if the query is still the same.
  public var archivedProvider: (@MainActor (String) async -> [CommandBarResults.ArchivedMatch])?
  /// Enter on an archived match: restore it (BH-086).
  public var onRestoreArchived: ((UUID) -> Void)?
  /// Settings: search suggestions and the BH-113 notice dismissal.
  public var settings: CommandBarSettings = .ephemeral()
  /// BH-108: the URL on the clipboard when the bar is open with an empty query (nil: no Paste and Go). The
  /// default reads nothing, so tests stay deterministic; the window wires the general pasteboard.
  public var clipboardURLProvider: () -> URL? = { nil }
  /// BH-104: the Spaces a query can switch to; the handler switches.
  public var spacesProvider: () -> [CommandBarResults.Space] = { [] }
  public var onSwitchSpace: ((SpaceID) -> Void)?
  /// BH-106 / KB-081: the actions the action search lists; the handler runs a chosen one.
  public var actionsProvider: () -> [CommandBarAction] = { [] }
  public var onAction: ((String) -> Void)?
  /// BH-107 / KB-082: the engines an alias + Tab can scope to.
  public var siteSearchProvider: () -> [SiteSearchEngine] = { SiteSearchEngines.seeded }
  /// BH-109: a removed suggestion; the session exclusion is already applied. A future history store persists
  /// removals through this hook.
  public var onRemoveSuggestion: ((CommandBarResults.Result) -> Void)?
  /// History visits for the query. Empty until a history store exists; tests and screenshots pass synthetic visits.
  public var historyProvider: () -> [CommandBarResults.HistoryVisit] = { [] }
  /// The preview thumbnail (#370). Nil keeps the well. A slow reply must not block the bar: the column shows the
  /// well first and drops the image if the selection moved.
  public var thumbnailForPreview: (@MainActor (CommandBarPreview.Thumbnail) async -> PageImage?)?
  /// A cached favicon for a live tab's well. Nil shows the row's symbol.
  public var faviconForPreview: (@MainActor (CommandBarPreview.Thumbnail) -> NSImage?)?

  /// The bar's scope: normal, action search (BH-106) or a site-search engine (BH-107).
  public private(set) var scope: CommandBarResults.Scope = .normal
  /// Whether the search-suggestion privacy notice (BH-113) is up.
  public private(set) var isNoticeVisible = false
  /// BH-109: suggestions removed this controller's lifetime stay hidden.
  private var removedSuggestionIDs: Set<String> = []

  public private(set) var isVisible = false
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
  /// The appearance the bar and its cells were last drawn in (the parent window's); a show in another one re-renders.
  private var cellFlavor: ThemeFlavor?
  /// The rows on screen: `unfilteredResults` through the selected filter pill.
  private(set) var results: [CommandBarResults.Result] = []
  /// Every row for the query, before the filter; the pills count these.
  private(set) var unfilteredResults: [CommandBarResults.Result] = []
  /// The selected filter pill; All on every open.
  public private(set) var filter: CommandBarFilter = .all
  /// Group headers by row (empty state), for the rows on screen.
  private var groupHeaders: [Int: String] = [:]
  /// Says a filter change aloud ("Tabs, 3 results"); replaced in tests.
  var announce: @MainActor (String) -> Void = { text in
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
  }
  /// Test seam for the dismiss fade: when set, it is handed the step that ends the fade (panel and scrim to alpha 0)
  /// instead of the layer animation's completion, so a test ends the fade by hand, with no clock.
  var dismissFinisher: (@MainActor (@escaping @MainActor () -> Void) -> Void)?
  private var dismissGeneration = 0
  /// The input of the latest reload, for the pill counts.
  private var lastInput = CommandBarResults.Input()
  /// The clipboard URL read for this show: the pasteboard is read once per show, not on every reload (Esc, a filter).
  private var clipboardSnapshot: (url: URL?, isRead: Bool) = (nil, false)

  private func clipboardURLForThisShow() -> URL? {
    if !clipboardSnapshot.isRead { clipboardSnapshot = (clipboardURLProvider(), true) }
    return clipboardSnapshot.url
  }
  private static let fadeKey = "commandBar.fade"
  /// The archived matches of `archivedQuery`, shown while the field still holds that query.
  private var archived: [CommandBarResults.ArchivedMatch] = []
  private var archivedQuery = ""
  private var archivedSearch: Task<Void, Never>?
  /// Backing scale the table's cells were configured at; a show at another scale reloads them.
  private var cellScale: CGFloat = 0
  /// The field text the cells' title emphasis was drawn for.
  private var cellQuery = ""
  /// Test seam: stands in for the parent window's backing scale.
  var backingScaleOverride: CGFloat?
  /// The panel sits over the parent window, so it shares the parent's display. Read from the parent: the panel
  /// itself still reports the previous display's scale until its frame moves in show().
  private var backingScale: CGFloat { backingScaleOverride ?? parent?.backingScaleFactor ?? 2 }
  private var prefill: String?
  private var showStart: CFTimeInterval = 0
  /// On the parent window (always on screen, so it ticks right away), created once and unpaused per show():
  /// creating a link per show cost up to ~2 ms under load. The link retains its target; invalidate() breaks
  /// that cycle.
  private var firstFrameLink: CADisplayLink?
  /// End of the run loop pass (and so of the Core Animation commit) that carried the latest show; nil until
  /// it lands. The first frame is the first vsync after it.
  private var showCommitTime: CFTimeInterval?
  private var showGeneration = 0
  private var invalidated = false
  private var signpostState: OSSignpostIntervalState?
  private weak var parent: NSWindow?
  private var thumbnailTask: Task<Void, Never>?
  private var thumbnailGate = CommandBarThumbnailGate()

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
                               label: results[row].accessibilityLabel(position: row + 1, of: results.count),
                               value: results[row].accessibilityCaption)
    }
    barView.onHoverRow = { [weak self] row in self?.select(row, scroll: false) }
    barView.onDismissNotice = { [weak self] in self?.dismissNotice() }
    barView.onEscapeKey = { [weak self] in self?.hide() }
    barView.pills.onSelect = { [weak self] in self?.setFilter($0) }
    barView.previewColumn.onSplit = { [weak self] in self?.openSplitFromPreview() }
    barView.previewColumn.onPrimary = { [weak self] in self?.commit() }
    barView.widthMotion.onSettled = { [weak self] _ in self?.widthDidSettle() }
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
    results = CommandBarResults.make(query: "warm.example", openTabs: [
      .init(node: UUID(), title: "warm", url: URL(string: "https://warm.example")!),
    ])
    barView.table.reloadData()
    if let parent { panel.setFrame(frame(in: parent), display: true) }
    barView.table.selectRowIndexes([0], byExtendingSelection: false)
    panel.orderFrontRegardless()                  // ordered in for good, at alpha 0 (see CommandBarPanel)
    if barView.field.currentEditor() == nil { _ = panel.makeFirstResponder(barView.field) }
    panel.displayIfNeeded()
    reloadResults()
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
    mode = newMode
    scope = .normal                                   // a fresh bar starts unscoped (BH-106, BH-107)
    updateScopeChrome()
    switch newMode {
    case .newTab, .newSplitPane: prefill = nil
    case .currentTab(let url): prefill = url?.absoluteString
    }
    let targetText = prefill ?? ""
    if barView.field.stringValue != targetText { barView.field.stringValue = targetText }
    filter = .all                                     // All is the default on every open
    clipboardSnapshot = (nil, false)
    applyAppearance()
    reloadResults()
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
    isVisible = true                                // before makeKey: windowDidBecomeKey reads it
    scrim.attach(to: parent)
    dismissGeneration += 1                          // a fade-out still running is over: the bar is back
    scrim.isPresented = true
    panel.isPresented = true
    fadeLayers(CommandBarMotion.entrance(reduceMotion: false), toModel: 1)
    panel.makeKey()
    if barView.field.currentEditor() == nil { panel.makeFirstResponder(barView.field) }   // kept across hides
    applyCaretColor()
    if !targetText.isEmpty { barView.field.currentEditor()?.selectAll(nil) }
    showGeneration += 1
    let generation = showGeneration
    showCommitTime = nil
    // Core Animation commits the implicit transaction in a before-waiting run loop observer (order 2000000);
    // a one-shot observer ordered after it marks the end of the commit that carries this show.
    let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false,
                                                      CFIndex.max) { [weak self] _, _ in
      MainActor.assumeIsolated {
        guard let self, self.showGeneration == generation else { return }
        self.showCommitTime = CACurrentMediaTime()
      }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    firstFrameLink?.isPaused = false
    lastShowWallTime = CACurrentMediaTime() - showStart
    lastShowCPUTime = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1e9
  }

  /// First vsync after the show's commit: that frame is the first composited with the bar.
  @objc private func firstFrame(_ link: CADisplayLink) {
    guard isVisible else { link.isPaused = true; return }
    guard let committed = showCommitTime, link.timestamp >= committed else { return }
    link.isPaused = true
    let latency = link.targetTimestamp - showStart
    lastShowVsyncWait = link.timestamp - showStart
    lastShowCommitDelay = committed - showStart
    lastFrameInterval = link.targetTimestamp - link.timestamp
    lastShowLatency = latency
    endSignpost()
    ShellSignposts.logger.notice("commandbar.show ms=\(latency * 1000, format: .fixed(precision: 2))")
    onFirstFrame?(latency)
  }

  /// `restoreFocus` returns key status to the shell window (Esc, Enter, Cmd-T/Cmd-L). It is false when the
  /// bar hides because something else took focus, which must keep it.
  public func hide(restoreFocus: Bool = true) {
    guard isVisible else { return }
    isVisible = false
    firstFrameLink?.isPaused = true
    showCommitTime = nil
    endSignpost()
    panel.isPresented = false                       // stays ordered in, inert at once; alpha 0 after the fade
    barView.selectionMotion.settleNow()
    thumbnailTask?.cancel()
    _ = thumbnailGate.begin()
    barView.widthMotion.stopWithoutSettling()
    barView.releaseDrawnWidth()
    barView.previewColumn.setContent(nil, flavor: flavor)
    fadeOut()
    if restoreFocus { parent?.makeKey() }
  }

  // MARK: Fades (design/command-bar/README.md, Motion)

  private var fadingLayers: [CALayer] { [barView.layer, scrim.layer].compactMap { $0 } }

  /// Runs `fade` on the bar and the scrim and leaves `toModel` as their opacity. Reduce Motion keeps fades.
  private func fadeLayers(_ fade: CommandBarMotion.Fade, toModel: Float) {
    for layer in fadingLayers {
      // A fade interrupting another starts where the layer is drawn now, so a show in the middle of a fade-out does not
      // jump to 0 first.
      let isInterrupting = layer.animation(forKey: Self.fadeKey) != nil
      let from = isInterrupting ? (layer.presentation()?.opacity ?? fade.fromOpacity) : fade.fromOpacity
      layer.removeAnimation(forKey: Self.fadeKey)
      layer.opacity = toModel
      var run = fade
      run.fromOpacity = from
      layer.add(CommandBarMotion.animation(run), forKey: Self.fadeKey)
    }
  }

  /// The dismiss fade: opacity to 0 in 0.1 s; the panel stays ordered in and goes to alpha 0 when it ends (unless the
  /// bar was shown again meanwhile).
  private func fadeOut() {
    dismissGeneration += 1
    let generation = dismissGeneration
    let finish: @MainActor () -> Void = { [weak self] in
      guard let self, generation == dismissGeneration, !isVisible else { return }
      panel.alphaValue = 0
    }
    let fade = CommandBarMotion.exit(reduceMotion: false)
    if let dismissFinisher {
      fadeLayers(fade, toModel: 0)
      dismissFinisher(finish)
    } else {
      CATransaction.begin()
      CATransaction.setCompletionBlock { MainActor.assumeIsolated { finish() } }
      fadeLayers(fade, toModel: 0)
      CATransaction.commit()
    }
  }

  private func endSignpost() {
    guard let state = signpostState else { return }
    ShellSignposts.signposter.endInterval("CommandBarShow", state)
    signpostState = nil
  }

  // MARK: Appearance

  private var appliedReduceTransparency: Bool?

  /// Draws the bar, its cells and the scrim in the window behind it: light or dark, opaque under Reduce Transparency.
  /// Cheap when nothing changed (a show repeats it).
  private func applyAppearance(force: Bool = false) {
    guard let parent else { return }
    let flavor = ThemeFlavor(appearance: parent.effectiveAppearance)
    let opaque = barView.reduceTransparency()
    guard force || flavor != cellFlavor || opaque != appliedReduceTransparency else { return }
    let flavorChanged = flavor != cellFlavor
    cellFlavor = flavor
    appliedReduceTransparency = opaque
    panel.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    barView.apply(flavor: flavor)
    scrim.apply(flavor: flavor)
    if flavorChanged, !results.isEmpty { reapplyCells() }
    applyCaretColor()
  }

  /// The caret is a mustard fill (README, Brand rules).
  private func applyCaretColor() {
    (barView.field.currentEditor() as? NSTextView)?.insertionPointColor = ShellTokens.commandBarTick.resolve(flavor).nsColor()
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
  /// `didChangeScreen` (frame only), so the first show after a display change is already on the parent's display;
  /// ordinary moves and resizes while closed do nothing.
  @objc private func parentFrameDidChange(_ notification: Notification) {
    guard let parent else { return }
    if isVisible {
      syncWidth(display: false)
      refreshCellScaleIfNeeded()
    } else if notification.name == NSWindow.didChangeScreenNotification {
      setPanelFrame(frame(in: parent), display: false)
    }
  }

  private func refreshCellScaleIfNeeded() {
    let scale = backingScale
    guard scale != cellScale else { return }
    cellScale = scale
    let selected = barView.table.selectedRow
    barView.table.reloadData()
    if selected >= 0, selected < results.count {
      barView.table.selectRowIndexes([selected], byExtendingSelection: false)
    }
  }

  // MARK: Field and keys

  public func controlTextDidChange(_ obj: Notification) {
    searchArchive()
    reloadResults()
    relayout()
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)): escape(); return true        // Esc, KB-084
    case #selector(NSResponder.insertNewline(_:)): commit(); return true
    case #selector(NSResponder.insertTab(_:)): return insertTabCommand()
    case #selector(NSResponder.insertBacktab(_:)): return insertBacktabCommand()
    case #selector(NSResponder.deleteBackward(_:)):
      // [I] Backspace on the empty scoped field leaves the scope (Chromium omnibox convention; Arc unverified).
      if scope != .normal, barView.field.stringValue.isEmpty { exitScope(); return true }
      return false
    // Opt-Return's standard binding; handleKeyDown normally takes Opt-Return first. Only an actual Opt-Return opens
    // a new tab here; another key bound to this selector commits like Return.
    case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
      commit(forcing: Self.isReturn(NSApp.currentEvent, withExactly: [.option]) ? .newTab : nil); return true
    case #selector(NSResponder.moveDown(_:)): moveSelection(+1); return true
    case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
    case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): movePage(+1); return true
    case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): movePage(-1); return true
    default: return false
    }
  }

  /// Cmd-Return and Opt-Return (KB-085) [I]: open the selected result in a new tab, from Cmd-T and from Cmd-L
  /// alike (Chromium's omnibox opens Opt-Return in a new tab; Arc unverified, RT-08). Any other modifier, or
  /// Return during IME composition, goes on to the field editor.
  /// Cmd-Opt-Delete (KB-083, BH-109) removes the selected suggestion.
  private func handleKeyDown(_ event: NSEvent) -> Bool {
    guard isVisible else { return false }
    if event.keyCode == 51,
       event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option] {
      removeSelectedSuggestion()
      return true
    }
    let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    if modifiers == [.command], let digit = Self.filterDigit(forKeyCode: event.keyCode),
       let picked = CommandBarFilter(commandDigit: digit) {
      setFilter(picked)                                // Cmd-1 to Cmd-4
      return true
    }
    if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "v" {      // Cmd-Shift-V: Paste and Go from any state
      pasteAndGo()
      return true
    }
    guard Self.isReturn(event, withExactly: [.command, .option]) else { return false }
    if let editor = barView.field.currentEditor() as? NSTextView, editor.hasMarkedText() { return false }
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    // Cmd-Return on a preview row opens that page in a new split pane (#372). Opt-Return stays a new tab, and so
    // does Cmd-Return on every row without a preview (KB-085).
    if flags == .command, currentPreview != nil {
      openSplitFromPreview()
      return true
    }
    commit(forcing: .newTab)
    return true
  }

  // MARK: Scopes (BH-106 action search, BH-107 site search)

  /// Tab is smart (`CommandBarTabAction`): it scopes the search when the selected row shows a Tab key cap or the bar is
  /// empty and just opened for a new tab (the hint strip shows Tab for action search), and otherwise cycles the filters.
  /// Already scoped: consumed, changes nothing [I].
  private func insertTabCommand() -> Bool {
    switch tabAction {
    case .scopeSite(let engine): enterScope(.siteSearch(engine))
    case .scopeActions: enterScope(.actions)
    case .cycleFilter: setFilter(filter.next)
    case .consume: break
    }
    return true
  }

  /// Shift-Tab goes back through the filters; inside a scope it does nothing.
  private func insertBacktabCommand() -> Bool {
    if scope == .normal { setFilter(filter.previous) }
    return true
  }

  private var tabAction: CommandBarTabAction {
    let row = barView.table.selectedRow
    return CommandBarTabAction.decide(scope: scope, queryIsEmpty: queryIsEmpty, isNewTab: mode == .newTab,
                                      selected: results.indices.contains(row) ? results[row] : nil)
  }

  private var queryIsEmpty: Bool {
    barView.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Esc clears the query if there is one, and closes the bar when it is already empty (KB-084; README, Keyboard).
  private func escape() {
    if barView.field.stringValue.isEmpty { hide(); return }
    barView.field.stringValue = ""
    barView.field.currentEditor()?.string = ""
    controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: barView.field))
  }

  /// Cmd-1 to Cmd-4: the digit on a key code, so any keyboard layout's number row works.
  private static func filterDigit(forKeyCode code: UInt16) -> Int? {
    switch code {
    case 18: 1
    case 19: 2
    case 20: 3
    case 21: 4
    default: nil
    }
  }

  /// Picks `newFilter`: the pills, the rows and the hint strip follow, and VoiceOver hears "Tabs, 3 results".
  public func setFilter(_ newFilter: CommandBarFilter) {
    guard scope == .normal else { return }
    filter = newFilter
    reloadResults()
    relayout()
    let count = CommandBarResults.counts(query: barView.field.stringValue, input: lastInput)[newFilter] ?? 0
    announce("\(newFilter.title), \(count == 1 ? "1 result" : "\(count) results")")
  }

  /// Cmd-Shift-V: opens the clipboard URL, from any state (a new-tab surface: Cmd-L and the split pane bar never).
  private func pasteAndGo() {
    guard mode == .newTab, let url = clipboardURLProvider() else { NSSound.beep(); return }
    let target = openTarget
    hide()
    onOpen?(url, target)
  }

  private func enterScope(_ newScope: CommandBarResults.Scope) {
    scope = newScope
    filter = .all                                      // the pills do not apply inside a scope
    barView.field.stringValue = ""
    updateScopeChrome()
    reloadResults()
    relayout()
  }

  private func exitScope() {
    scope = .normal
    updateScopeChrome()
    reloadResults()
    relayout()
  }

  private func updateScopeChrome() {
    let title: String?
    let placeholder: String
    switch scope {
    case .normal:
      title = nil
      placeholder = CommandBarView.placeholder
    case .actions:
      title = "Actions"
      placeholder = "Search actions..."
    case .siteSearch(let engine):
      title = engine.name
      placeholder = "Search \(engine.name)"
    }
    barView.setScope(title: title)
    barView.refreshPlaceholder(placeholder)
  }

  /// True for a key-down of Return or keypad Enter whose Cmd / Opt / Ctrl / Shift modifiers are exactly one of
  /// `modifiers` (other flags, such as the keypad's, are ignored).
  static func isReturn(_ event: NSEvent?, withExactly modifiers: [NSEvent.ModifierFlags]) -> Bool {
    guard let event, event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76 else { return false }
    return modifiers.contains(event.modifierFlags.intersection([.command, .option, .control, .shift]))
  }

  /// Enter. Cmd-L + Enter without editing reloads (KB-004, BH-102). On an empty query Enter takes the first
  /// result, which is the first open tab, and closes the bar when there is none [I] (RT-08).
  public func commit() { commit(forcing: nil) }

  /// `forced` nil: the mode decides (Cmd-T new tab, Cmd-L current tab, Ctrl-Shift-= new split pane). `.newTab`:
  /// Cmd-Enter / Opt-Enter, which open in a new tab and never reload.
  private func commit(forcing forced: OpenTarget?) {
    let text = barView.field.stringValue
    if forced == nil, case .currentTab = mode, let prefill, text == prefill { hide(); onReload?(); return }
    commit(row: max(barView.table.selectedRow, 0), forcing: forced)
  }

  private func commit(row: Int, forcing forced: OpenTarget? = nil) {
    guard row < results.count else { hide(); return }
    guard results[row].isActionable else { return }     // the empty row of a filter that matches nothing
    // A whole alias with nothing after it has nothing to search for: Return scopes, like Tab (the row's Tab key cap).
    if scope == .normal, let engine = results[row].siteSearchEngine,
       engine.alias.caseInsensitiveCompare(barView.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
         == .orderedSame {
      enterScope(.siteSearch(engine))
      return
    }
    let kind = results[row].kind
    let target = forced ?? openTarget
    hide()
    switch kind {
    case .open(let url), .search(let url), .pasteAndGo(let url), .siteSearch(let url): onOpen?(url, target)
    // [I] A "Switch to Tab" result switches in every mode, the split pane bar included: the tab is already open.
    case .switchTo(let node):
      // Opt-Return on a visible preview opens a new tab (#372). A switch row with no preview, including
      // the empty query, still switches under Opt-Return (KB-085).
      let showsPreview = CommandBarPreview.content(for: results[row].previewFacts, queryIsEmpty: queryIsEmpty) != nil
      if forced == .newTab, showsPreview, let url = results[row].previewFacts?.url {
        onOpen?(url, .newTab)
      } else {
        onSwitch?(node)
      }
    case .history(let url):
      if forced == nil, let facts = results[row].previewFacts, facts.isAlsoOpen, let node = facts.node {
        onSwitch?(node)
      } else {
        onOpen?(url, target)
      }
    case .restore(let id): onRestoreArchived?(id)
    case .action(let id): onAction?(id)
    case .switchSpace(let space): onSwitchSpace?(space)
    case .noMatch: break
    }
  }

  /// Where a plain Enter opens a result in the current mode.
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

  /// setFrame is a window-server round trip (measured up to ~2.8 ms) even when nothing changes; skip it then.
  private func setPanelFrame(_ frame: NSRect, display: Bool) {
    guard panel.frame != frame else { return }
    panel.setFrame(frame, display: display)
  }

  private func frame(in parent: NSWindow) -> NSRect {
    let isEmptyState = scope == .normal && queryIsEmpty
    let maxRows = isEmptyState ? CommandBarGeometry.maxEmptyStateRows : CommandBarGeometry.maxVisibleRows
    let shown = min(results.count, maxRows)
    let headers = groupHeaders.keys.filter { $0 < shown }.count
    return CommandBarGeometry.frame(parentFrame: parent.frame,
                                    contentHeight: CommandBarGeometry.contentHeight(
                                      rowCount: results.count, headerCount: headers, showsNotice: isNoticeVisible,
                                      maxRows: maxRows),
                                    showsPreview: currentPreview != nil)
  }

  /// Sets the panel's frame for the current results and notice. A preview widens on the spring; leaving one
  /// narrows on the spring and lays the narrow frame out once it rests.
  private func relayout(display: Bool = true) {
    syncWidth(display: display)
  }

  /// The selected row's preview, when the query is non-empty and the row is a tab or a history visit.
  private var currentPreview: CommandBarPreview.Content? {
    let row = barView.table.selectedRow
    guard results.indices.contains(row) else { return nil }
    return CommandBarPreview.content(for: results[row].previewFacts, queryIsEmpty: queryIsEmpty)
  }

  private func refreshPreview() {
    let content = currentPreview
    let previous = barView.previewColumn.content
    if let content, content != previous {
      let appeared = previous == nil
      barView.previewColumn.setContent(content, flavor: flavor)
      if appeared { announce("Preview, \(content.title)") }
      loadThumbnail(for: content)
    }
    syncWidth(display: false)
  }

  private func loadThumbnail(for content: CommandBarPreview.Content) {
    let token = thumbnailGate.begin()
    thumbnailTask?.cancel()
    barView.previewColumn.showWell(favicon: faviconForPreview?(content.thumbnail))
    let request = content.thumbnail
    thumbnailTask = Task { [weak self] in
      let image = await self?.thumbnailForPreview?(request)
      let cgImage = image.flatMap(CommandBarPreviewImage.cgImage(from:))
      guard let self, self.thumbnailGate.accepts(token), !Task.isCancelled else { return }
      self.barView.previewColumn.showImage(cgImage)
    }
  }

  private func openSplitFromPreview() {
    guard let content = currentPreview else { return }
    hide()
    onOpen?(content.url, .newSplitPane)
  }

  /// One layout when the bar becomes wide (the mask stays at the width on screen), then the spring. Narrowing
  /// keeps that wide panel until the spring rests, so the column can clip away, but the height follows the rows
  /// at once. A window resize with no preview snaps: it is not a preview spring. The list's leading edge stays.
  private func syncWidth(display: Bool) {
    guard let parent else { return }
    let target = frame(in: parent)
    let drawn = barView.drawnWidth
    if currentPreview != nil {
      if panel.frame != target {
        barView.holdDrawnWidth(drawn)
        setPanelFrame(target, display: display)
        barView.layoutSubtreeIfNeeded()
      }
      barView.widthMotion.retarget(to: Double(target.width), from: Double(barView.drawnWidth), in: barView)
    } else if barView.widthMotion.isRunning || barView.previewColumn.content != nil {
      barView.keepDrawnWidth()
      let clipping = NSRect(x: target.minX, y: target.minY, width: max(panel.frame.width, target.width),
                            height: target.height)
      if panel.frame != clipping {
        setPanelFrame(clipping, display: display)
        barView.layoutSubtreeIfNeeded()
      }
      barView.widthMotion.retarget(to: Double(target.width), from: Double(barView.drawnWidth), in: barView)
    } else {
      barView.releaseDrawnWidth()
      setPanelFrame(target, display: display)
    }
  }

  /// The spring landed. The narrow frame is applied once here; a wide landing is already the panel's frame.
  private func widthDidSettle() {
    barView.releaseDrawnWidth()
    guard let parent else { return }
    if currentPreview == nil {
      barView.previewColumn.setContent(nil, flavor: flavor)
    }
    setPanelFrame(frame(in: parent), display: false)
    barView.layoutSubtreeIfNeeded()
  }

  /// Asks for the archived matches of the field's text; a reply for an older text is dropped.
  private func searchArchive() {
    archivedSearch?.cancel()
    let query = barView.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let archivedProvider, !query.isEmpty else {
      archivedSearch = nil
      return
    }
    archivedSearch = Task { [weak self] in
      let matches = await archivedProvider(query)
      guard let self, !Task.isCancelled,
            self.barView.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
      self.archived = matches
      self.archivedQuery = query
      // reloadResults syncs the width. A direct setFrame here would snap a narrowing spring.
      self.reloadResults()
    }
  }

  /// Reloads the table only when the results (or the backing scale of the icon bitmaps) changed. A warm show usually repeats the previous results, and
  /// NSTableView drops its reuse queue between shows, so a reload rebuilt every cell (about 8 ms of main-thread
  /// layout and text drawing in the show's commit, which made every other show land a frame late; C7 phase 3).
  private func reloadResults() {
    let text = barView.field.stringValue
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // While the store answers a longer query, the previous matches that still contain it stay, so rows do not
    // blink out and back per keystroke.
    let current: [CommandBarResults.ArchivedMatch] = if archivedQuery == trimmed {
      archived
    } else if !archivedQuery.isEmpty, trimmed.hasPrefix(archivedQuery) {
      archived.filter { $0.title.localizedStandardContains(trimmed) || $0.subtitle.localizedStandardContains(trimmed) }
    } else {
      []
    }
    var input = CommandBarResults.Input()
    input.openTabs = openTabsProvider()
    input.spaces = spacesProvider()
    input.actions = actionsProvider()
    // BH-108: Paste and Go is a new-tab surface; Cmd-L's prefill and the split pane bar never offer it. The row
    // shows only on an empty query, so a typed keystroke never pays for a pasteboard read.
    let queryIsEmpty = barView.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    input.clipboardURL = scope == .normal && mode == .newTab && queryIsEmpty ? clipboardURLForThisShow() : nil
    input.excluded = removedSuggestionIDs
    input.searchSuggestionsEnabled = settings.searchSuggestionsEnabled
    input.scope = scope
    input.archived = current
    input.recentTabs = scope == .normal && trimmed.isEmpty ? recentTabsProvider() : []
    input.siteSearchEngines = scope == .normal ? siteSearchProvider() : []
    input.history = historyProvider()
    lastInput = input
    unfilteredResults = CommandBarResults.make(query: text, input: input)
    let fresh = scope == .normal ? filter.apply(to: unfilteredResults, query: text) : unfilteredResults
    let headers = CommandBarResults.groupHeaders(of: fresh)
    let scale = backingScale
    barView.selectionAnimates = false                 // new rows do not slide the fill
    if fresh != results || scale != cellScale || text != cellQuery || headers != groupHeaders {
      results = fresh
      groupHeaders = headers
      barView.groupHeaders = headers
      cellScale = scale
      cellQuery = text
      barView.setHoveredRow(nil)                      // the rows shifted; no honest hover target anymore
      barView.table.reloadData()
    }
    if results.first?.isActionable == true, barView.table.selectedRow != 0 {
      barView.table.selectRowIndexes([0], byExtendingSelection: false)
    } else if results.first?.isActionable == false {
      barView.table.deselectAll(nil)                   // the empty row of a filter is not selectable
    }
    barView.selectionAnimates = true
    updatePillsAndHints(query: text, trimmed: trimmed)
    updateNotice()
    refreshPreview()
  }

  /// The pills (selection and counts of the unfiltered rows) and the hint strip, for the rows on screen.
  private func updatePillsAndHints(query: String, trimmed: String) {
    barView.pills.update(selected: filter, counts: CommandBarResults.counts(query: query, input: lastInput),
                         showsCounts: CommandBarFilter.showsCounts(forQuery: query), flavor: flavor)
    refreshHints()
  }

  /// The strip follows the selected row: its Tab item is what Tab will do.
  private func refreshHints() {
    let row = barView.table.selectedRow
    let tab = CommandBarTabAction.hint(scope: scope, queryIsEmpty: queryIsEmpty, isNewTab: mode == .newTab,
                                       selected: results.indices.contains(row) ? results[row] : nil)
    barView.hintStrip.update(CommandBarHints.content(isEmptyQuery: queryIsEmpty, tab: tab,
                                                     offersPasteAndGo: mode == .newTab), flavor: flavor)
  }

  // MARK: Notice (BH-113) and refresh (BH-111)

  /// The notice rides along with the rows that send the query to the engine ("Search ..." rows).
  private func updateNotice() {
    let hasEngineRow = results.contains {
      if case .search = $0.kind { return true }
      if case .siteSearch = $0.kind { return $0.siteSearchEngine == nil }   // an alias row sends nothing yet
      return false
    }
    let shows = settings.searchSuggestionsEnabled && !settings.searchSuggestionNoticeDismissed && hasEngineRow
    guard shows != isNoticeVisible else { return }
    isNoticeVisible = shows
    barView.setNoticeVisible(shows)
  }

  /// The notice's X: dismissed for good (BH-113, persisted by `settings`).
  public func dismissNotice() {
    settings.dismissSearchSuggestionNotice()
    updateNotice()
    relayout()
  }

  /// BH-111: the open bar's suggestions follow the current Space; the window calls this on a Space switch.
  public func refreshSuggestions() {
    guard isVisible else { return }
    reloadResults()
    relayout()
  }

  // MARK: Removal (BH-109, KB-083)

  /// Cmd-Opt-Delete.
  public func removeSelectedSuggestion() {
    let row = barView.table.selectedRow
    guard row >= 0 else { return }
    removeSuggestion(at: row)
  }

  /// The hover X or Cmd-Opt-Delete: the row stays hidden for this controller's lifetime; `onRemoveSuggestion`
  /// is the persistence hook. A row without a `removalID` (the user's own input, verbs) is not removable.
  func removeSuggestion(at row: Int) {
    guard results.indices.contains(row), let id = results[row].removalID else { return }
    let result = results[row]
    removedSuggestionIDs.insert(id)
    onRemoveSuggestion?(result)
    reloadResults()
    relayout()
    if !results.isEmpty {                             // the next suggestion takes the removed row's place
      barView.table.selectRowIndexes([min(row, results.count - 1)], byExtendingSelection: false)
    }
  }

  /// Up / Down wrap at the ends [I] (KB-085; Arc unverified, RT-08).
  private func moveSelection(_ delta: Int) {
    guard let next = CommandBarSelection.step(from: barView.table.selectedRow, by: delta, count: results.count)
    else { return }
    select(next, scroll: true)
  }

  /// PageUp / PageDown move by the visible row count and stop at the ends [I].
  private func movePage(_ pages: Int) {
    guard let next = CommandBarSelection.page(from: barView.table.selectedRow, by: pages, count: results.count)
    else { return }
    select(next, scroll: true)
  }

  /// `scroll` is false for hover: the row under the pointer is already visible.
  private func select(_ row: Int, scroll: Bool) {
    guard row >= 0, row < results.count else { return }
    let changed = barView.table.selectedRow != row
    if changed {
      barView.table.selectRowIndexes([row], byExtendingSelection: false)
      refreshHints()
    }
    if scroll { barView.table.scrollRowToVisible(row) }
    if changed { refreshPreview() }
  }

  // MARK: Table

  public func numberOfRows(in tableView: NSTableView) -> Int { results.count }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: CommandBarCellView.identifier, owner: nil) as? CommandBarCellView
      ?? CommandBarCellView(frame: .zero)
    cell.configure(results[row], query: cellQuery, position: row + 1, count: results.count, flavor: flavor,
                   scale: cellScale, groupHeader: groupHeaders[row])
    cell.onRemove = results[row].removalID != nil ? { [weak self] in self?.removeSuggestion(at: row) } : nil
    cell.setCloseHovered(barView.hoveredRow == row)
    return cell
  }

  /// A row that starts a group is taller by its header.
  public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    CommandBarGeometry.rowHeight + (groupHeaders[row] != nil ? CommandBarGeometry.groupHeaderHeight : 0)
  }

  public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = tableView.makeView(withIdentifier: CommandBarRowView.identifier, owner: nil) as? CommandBarRowView
      ?? CommandBarRowView(frame: .zero)
    rowView.identifier = CommandBarRowView.identifier
    if results.indices.contains(row) {
      rowView.setAccessibilityLabel(results[row].accessibilityLabel(position: row + 1, of: results.count))
      rowView.setAccessibilityValue(results[row].accessibilityCaption)
    }
    return rowView
  }
}
