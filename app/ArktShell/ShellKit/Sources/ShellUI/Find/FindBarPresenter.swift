import EngineAPI
import Foundation

/// Injected time for the find bar's debounce: `Task.sleep(for:)` in the app, a parked sleeper in tests.
public typealias FindSleep = @Sendable (Duration) async throws -> Void

/// What the find bar shows for the tab on screen.
public struct FindBarDisplay: Equatable, Sendable {
  /// The query in the field.
  public var text: String
  /// "3 of 12" or "No matches"; empty for an empty field and before the first reply.
  public var countText: String
  /// True when the search finished with no match: plain text, the step buttons dim, the field nudges once.
  public var hasNoMatches: Bool
}

/// The state behind the find bar (#134, design/find-in-page direction A) and its calls to the engine. One bar per tab:
/// each tab keeps its own text, count and open state while it is hidden. The view draws `display` and sends what the
/// user does back here; no AppKit in this file.
///
/// Typing searches as you type, `debounce` after the last keystroke, on an injected sleeper. Return and Cmd-G go to
/// the next match, Shift-Return and Shift-Cmd-G to the previous one; both run a search that is still waiting for its
/// timer at once. Esc and the close button end the find with `.activate` (the current match becomes the page's
/// selection). A tab that left the window (the engine ends its find on a move, contract rule 22) is `forget`-ed
/// without a stop call.
@MainActor
public final class FindBarPresenter {
  /// How long after the last keystroke the search runs (design: 250 ms).
  public static let debounce: Duration = .milliseconds(250)
  /// Counts above this read "999+".
  nonisolated static let countCap = 999

  private struct Entry {
    var text = ""
    var isOpen = false
    /// The engine holds a find for this tab; replies are taken only while it does.
    var isActive = false
    var ordinal = 0
    var count = 0
    var hasResult = false
    /// The newest reply taken for this tab; request ids never go back, so it never resets.
    var lastRequestID = 0
  }

  private let engine: any EngineClient
  /// The debounce's sleeper. Set before the first keystroke; tests replace it.
  public var sleep: FindSleep
  /// The tab whose bar may show: the window's current tab, nil for none (a split, an empty Space).
  public private(set) var visibleTab: TabID?
  /// True while `open()` runs its change: the view animates an entrance for that show only, not for a tab switch.
  public private(set) var isOpening = false
  private var entries: [TabID: Entry] = [:]
  private var pending: [TabID: Task<Void, Never>] = [:]

  /// The display changed: the view redraws.
  public var onChange: (@MainActor () -> Void)?
  /// Cmd-F: the field takes the keyboard and selects its text.
  public var onFocusRequested: (@MainActor () -> Void)?
  /// The user closed the bar: the page takes the keyboard back.
  public var onClosed: (@MainActor () -> Void)?
  /// A search ended with no match where the last one had some: the field nudges once.
  public var onNoMatches: (@MainActor () -> Void)?
  /// The count to speak after a final reply.
  public var onAnnouncement: (@MainActor (String) -> Void)?

  public init(engine: any EngineClient, sleep: @escaping FindSleep = { try await Task.sleep(for: $0) }) {
    self.engine = engine
    self.sleep = sleep
  }

  // MARK: Reading

  /// The bar of the tab on screen; nil while it is closed or no tab shows one.
  public var display: FindBarDisplay? {
    guard let tab = visibleTab, let entry = entries[tab], entry.isOpen else { return nil }
    guard !entry.text.isEmpty, entry.hasResult else {
      return FindBarDisplay(text: entry.text, countText: "", hasNoMatches: false)
    }
    return FindBarDisplay(text: entry.text, countText: Self.countText(ordinal: entry.ordinal, count: entry.count),
                          hasNoMatches: entry.count == 0)
  }

  public func isOpen(_ tab: TabID) -> Bool { entries[tab]?.isOpen ?? false }

  /// The shown tab remembers a query, so Find Next and Find Previous have something to find again.
  public var canFindAgain: Bool {
    visibleTab.flatMap { entries[$0] }.map { !$0.text.isEmpty } ?? false
  }

  /// Searches waiting for their timer; for tests.
  var pendingSearches: Int { pending.count }

  /// "3 of 12", "3 of 999+", or "No matches" for no match.
  nonisolated static func countText(ordinal: Int, count: Int) -> String {
    guard count > 0 else { return "No matches" }
    return "\(ordinal) of \(count > countCap ? "\(countCap)+" : "\(count)")"
  }

  // MARK: Showing

  /// The window shows `tab` (nil: none). A tab's bar hides while another shows and comes back with its text.
  public func shownTabChanged(_ tab: TabID?) {
    visibleTab = tab
    onChange?()
  }

  /// `tab` left this window or closed: its bar and text go, and nothing is sent to the engine (a move ends the find
  /// there by itself).
  public func forget(_ tab: TabID) {
    cancelPending(tab)
    guard entries.removeValue(forKey: tab) != nil, tab == visibleTab else { return }
    onChange?()
  }

  // MARK: The user

  /// Cmd-F: shows the bar for the shown tab and asks for focus; with the bar open it only asks again, so the text is
  /// selected. A remembered query is searched again, as the bar comes back with its highlights.
  public func open() {
    guard let tab = visibleTab else { return }
    var entry = entries[tab] ?? Entry()
    entry.isOpen = true
    entries[tab] = entry
    if !entry.text.isEmpty, !entry.isActive { runSearch(tab, forward: true) }
    isOpening = true
    onChange?()
    isOpening = false
    onFocusRequested?()
  }

  /// The field's text changed. An empty field clears at once; anything else searches after the debounce.
  public func setText(_ text: String) {
    guard let tab = visibleTab else { return }
    var entry = entries[tab] ?? Entry()
    guard text != entry.text else { return }
    entry.text = text
    cancelPending(tab)
    if text.isEmpty {
      entry.isActive = false
      entry.ordinal = 0
      entry.count = 0
      entry.hasResult = false
      entries[tab] = entry
      engine.findInPage(tab, text: "", forward: true, matchCase: false)
    } else {
      entries[tab] = entry
      schedule(tab)
    }
    onChange?()
  }

  /// Return, Cmd-G (`forward`), Shift-Return, Shift-Cmd-G. With the bar closed, Find Next opens it on the last text.
  public func step(forward: Bool) {
    guard let tab = visibleTab, let entry = entries[tab], !entry.text.isEmpty else { return }
    guard entry.isOpen else {
      open()
      return
    }
    runSearch(tab, forward: forward)
  }

  /// Esc and the close button: ends the find with `.activate`, which leaves the current match as the page's selection (Cmd-C copies it, the next Cmd-F starts there), hides the bar, and keeps the text for the next Cmd-F.
  public func close() {
    guard let tab = visibleTab, var entry = entries[tab], entry.isOpen else { return }
    cancelPending(tab)
    entry.isOpen = false
    entry.isActive = false
    entry.ordinal = 0
    entry.count = 0
    entry.hasResult = false
    entries[tab] = entry
    engine.stopFinding(tab, action: .activate)
    onChange?()
    onClosed?()
  }

  // MARK: Engine events

  /// A find reply. Replies of a search the bar no longer holds, and replies older than the one shown, are dropped.
  public func handle(_ event: EngineEvent) {
    guard case .findResult(let tab, let requestID, let ordinal, let count, let isFinal) = event,
          var entry = entries[tab], entry.isActive, requestID >= entry.lastRequestID else { return }
    let hadNoMatches = entry.hasResult && entry.count == 0
    entry.lastRequestID = requestID
    entry.ordinal = ordinal
    entry.count = count
    entry.hasResult = true
    entries[tab] = entry
    guard tab == visibleTab, entry.isOpen else { return }
    onChange?()
    guard isFinal else { return }
    if count == 0, !hadNoMatches { onNoMatches?() }
    onAnnouncement?(Self.countText(ordinal: ordinal, count: count))
  }

  // MARK: Searching

  private func schedule(_ tab: TabID) {
    cancelPending(tab)
    let sleep = sleep
    pending[tab] = Task { [weak self] in
      do { try await sleep(Self.debounce) } catch { return }
      guard let self, !Task.isCancelled else { return }
      pending[tab] = nil
      runSearch(tab, forward: true)
    }
  }

  private func cancelPending(_ tab: TabID) {
    pending.removeValue(forKey: tab)?.cancel()
  }

  /// Sends the tab's text to the engine; the engine tells a new search from a step.
  private func runSearch(_ tab: TabID, forward: Bool) {
    guard var entry = entries[tab], !entry.text.isEmpty else { return }
    cancelPending(tab)
    entry.isActive = true
    entries[tab] = entry
    engine.findInPage(tab, text: entry.text, forward: forward, matchCase: false)
  }
}
