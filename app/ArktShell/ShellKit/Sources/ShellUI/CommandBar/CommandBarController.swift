import AppKit
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
  private(set) var results: [CommandBarResults.Result] = []
  /// Backing scale the table's cells were configured at; a show at another scale reloads them.
  private var cellScale: CGFloat = 0
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
    barView.onHoverRow = { [weak self] row in self?.select(row, scroll: false) }
    panel.keyDownHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }
  }

  /// Creates the window-server backing store, lays out and draws once off-screen, and leaves the panel ordered
  /// in at alpha 0, so a show() does no allocation, first-draw work or window ordering.
  public func prewarm() {
    cellScale = backingScale
    results = CommandBarResults.make(query: "warm.example", openTabs: [
      .init(node: UUID(), title: "warm", url: URL(string: "https://warm.example")!),
    ])
    barView.table.reloadData()
    panel.setFrame(NSRect(x: -10_000, y: -10_000, width: CommandBarGeometry.preferredWidth,
                          height: CommandBarGeometry.contentHeight(rowCount: results.count)), display: true)
    barView.table.selectRowIndexes([0], byExtendingSelection: false)
    panel.orderFrontRegardless()                  // ordered in for good, at alpha 0 (see CommandBarPanel)
    panel.displayIfNeeded()
    results = []
    barView.table.reloadData()
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
    firstFrameLink?.invalidate()
    firstFrameLink = nil
    hide(restoreFocus: false)
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
    switch newMode {
    case .newTab, .newSplitPane: prefill = nil
    case .currentTab(let url): prefill = url?.absoluteString
    }
    barView.field.stringValue = prefill ?? ""
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
    panel.isPresented = true
    panel.makeKey()
    if barView.field.currentEditor() == nil { panel.makeFirstResponder(barView.field) }   // kept across hides
    barView.field.currentEditor()?.selectAll(nil)
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
    ShellSignposts.logger.info("commandbar.show ms=\(latency * 1000, format: .fixed(precision: 2))")
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
    panel.isPresented = false                       // stays ordered in; alpha 0, inert (CommandBarPanel)
    if restoreFocus { parent?.makeKey() }
  }

  private func endSignpost() {
    guard let state = signpostState else { return }
    ShellSignposts.signposter.endInterval("CommandBarShow", state)
    signpostState = nil
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

  // MARK: Field and keys

  public func controlTextDidChange(_ obj: Notification) {
    reloadResults()
    if let parent { setPanelFrame(frame(in: parent), display: true) }
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)): hide(); return true          // Esc, KB-084
    case #selector(NSResponder.insertNewline(_:)): commit(); return true
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
  private func handleKeyDown(_ event: NSEvent) -> Bool {
    guard isVisible, Self.isReturn(event, withExactly: [.command, .option]) else { return false }
    if let editor = barView.field.currentEditor() as? NSTextView, editor.hasMarkedText() { return false }
    commit(forcing: .newTab)
    return true
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
    let kind = results[row].kind
    let target = forced ?? openTarget
    hide()
    switch kind {
    case .open(let url), .search(let url): onOpen?(url, target)
    // [I] A "Switch to Tab" result switches in every mode, the split pane bar included: the tab is already open.
    case .switchTo(let node): onSwitch?(node)
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

  /// setFrame is a window-server round trip (measured up to ~2.8 ms) even when nothing changes; skip it then.
  private func setPanelFrame(_ frame: NSRect, display: Bool) {
    guard panel.frame != frame else { return }
    panel.setFrame(frame, display: display)
  }

  private func frame(in parent: NSWindow) -> NSRect {
    CommandBarGeometry.frame(parentFrame: parent.frame,
                             contentHeight: CommandBarGeometry.contentHeight(rowCount: results.count))
  }

  /// Reloads the table only when the results (or the backing scale of the icon bitmaps) changed. A warm show usually repeats the previous results, and
  /// NSTableView drops its reuse queue between shows, so a reload rebuilt every cell (about 8 ms of main-thread
  /// layout and text drawing in the show's commit, which made every other show land a frame late; C7 phase 3).
  private func reloadResults() {
    let fresh = CommandBarResults.make(query: barView.field.stringValue, openTabs: openTabsProvider())
    let scale = backingScale
    if fresh != results || scale != cellScale {
      results = fresh
      cellScale = scale
      barView.table.reloadData()
    }
    if !results.isEmpty { barView.table.selectRowIndexes([0], byExtendingSelection: false) }
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
    if barView.table.selectedRow != row { barView.table.selectRowIndexes([row], byExtendingSelection: false) }
    if scroll { barView.table.scrollRowToVisible(row) }
  }

  // MARK: Table

  public func numberOfRows(in tableView: NSTableView) -> Int { results.count }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: CommandBarCellView.identifier, owner: nil) as? CommandBarCellView
      ?? CommandBarCellView(frame: .zero)
    cell.configure(results[row], scale: cellScale)
    return cell
  }

  public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let rowView = tableView.makeView(withIdentifier: CommandBarRowView.identifier, owner: nil) as? CommandBarRowView
      ?? CommandBarRowView()
    rowView.identifier = CommandBarRowView.identifier
    return rowView
  }
}
