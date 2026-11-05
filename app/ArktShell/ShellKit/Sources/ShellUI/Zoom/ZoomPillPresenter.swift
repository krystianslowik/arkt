import EngineAPI
import Foundation

/// Injected time for the zoom pill's auto-close: `Task.sleep(for:)` in the app, a parked sleeper in tests.
public typealias ZoomPillSleep = @Sendable (Duration) async throws -> Void

/// What the zoom pill shows.
public struct ZoomPillDisplay: Equatable, Sendable {
  /// The tab whose zoom it shows and whose zoom its buttons change.
  public var tab: TabID
  public var zoom: TabZoom

  /// "125%".
  public var percentText: String { "\(zoom.percent)%" }
}

/// The state behind the zoom pill (#579, design/extensions `surf-zoom`). The pill only listens: Cmd-+, Cmd-- and Cmd-0
/// are the engine's page commands (the main menu's `commandDispatch:` items), and each change the user asked for comes
/// back as `.zoomChanged(userInitiated: true)`. No AppKit in this file.
///
/// - A user-initiated change of the tab on screen to a zoom other than the default shows the pill and speaks the
///   percent. Changes the engine makes on its own (a site's saved zoom, another tab on the same site; Chromium keeps
///   zoom per host) never show it; while it is up they only update the percent.
/// - Back at the default zoom (Reset, Cmd-0, minus or plus onto it) the pill closes, or does not show: there is
///   nothing to reset. VoiceOver still hears the new percent.
/// - The percent is spoken `announceDelay` after the last change the user made, so a held zoom key speaks only where
///   it stopped.
/// - It closes `autoClose` after the last change while the pointer is elsewhere; the pointer over it holds it open,
///   and leaving starts the full time again.
/// - Switching tabs closes it; it does not come back with the tab.
@MainActor
public final class ZoomPillPresenter {
  /// How long the pill stays without the pointer (design: 2 s).
  public static let autoClose: Duration = .seconds(2)
  /// How long after the last user change the percent is spoken.
  public static let announceDelay: Duration = .milliseconds(250)

  private let engine: any EngineClient
  /// The auto-close sleeper; tests replace it.
  public var sleep: ZoomPillSleep
  /// The announcement's sleeper; tests replace it.
  public var announceSleep: ZoomPillSleep
  /// The tab on screen whose zoom may show: the current tab, or the focused pane while a split shows.
  public private(set) var visibleTab: TabID?
  /// What the pill shows; nil while it is closed.
  public private(set) var display: ZoomPillDisplay?
  /// True while the change that opens the pill is drawn: the view animates an entrance for that one only.
  public private(set) var isOpening = false
  private var hovering = false
  /// Bumped on every arm, cancel and close; a timer closes only the pill it was armed for.
  private var generation = 0
  private var timer: Task<Void, Never>?
  private var announcement: Task<Void, Never>?

  /// The display changed: the view redraws.
  public var onChange: (@MainActor () -> Void)?
  /// What VoiceOver says after a change the user made ("Zoom 125%").
  public var onAnnouncement: (@MainActor (String) -> Void)?

  public init(engine: any EngineClient, sleep: @escaping ZoomPillSleep = { try await Task.sleep(for: $0) },
              announceSleep: @escaping ZoomPillSleep = { try await Task.sleep(for: $0) }) {
    self.engine = engine
    self.sleep = sleep
    self.announceSleep = announceSleep
  }

  /// True while an auto-close timer runs.
  var isTimerArmed: Bool { timer != nil }

  // MARK: Engine events

  public func handle(_ event: EngineEvent) {
    guard case .zoomChanged(let tab, let zoom, let userInitiated) = event else { return }
    if userInitiated, tab == visibleTab || tab == display?.tab { announce(zoom) }
    if let shown = display, shown.tab == tab {
      guard !zoom.isDefault else { return close() }
      display?.zoom = zoom
      onChange?()
      if userInitiated { armTimer() }
      return
    }
    guard userInitiated, tab == visibleTab, !zoom.isDefault else { return }
    display = ZoomPillDisplay(tab: tab, zoom: zoom)
    isOpening = true
    onChange?()
    isOpening = false
    armTimer()
  }

  // MARK: Tabs

  /// The tab on screen changed. The pill belongs to the tab it opened for, so it closes when another one shows.
  public func shownTabChanged(_ tab: TabID?) {
    visibleTab = tab
    if let shown = display, shown.tab != tab { close() }
  }

  /// `tab` closed or left the window.
  public func forget(_ tab: TabID) {
    if display?.tab == tab { close() }
    if visibleTab == tab { visibleTab = nil }
  }

  // MARK: The user

  public func zoomIn() {
    guard let tab = display?.tab else { return }
    engine.zoomIn(tab)
  }

  public func zoomOut() {
    guard let tab = display?.tab else { return }
    engine.zoomOut(tab)
  }

  /// Back to the default zoom; the change that reports it closes the pill.
  public func reset() {
    guard let tab = display?.tab else { return }
    engine.resetZoom(tab)
  }

  /// The pointer entered or left the pill.
  public func setHovering(_ hovering: Bool) {
    guard hovering != self.hovering else { return }
    self.hovering = hovering
    if hovering { cancelTimer() } else { armTimer() }
  }

  public func close() {
    cancelTimer()
    hovering = false
    guard display != nil else { return }
    display = nil
    onChange?()
  }

  // MARK: Timer

  /// Speaks `zoom` once the changes stop; a newer change replaces a pending one.
  private func announce(_ zoom: TabZoom) {
    announcement?.cancel()
    let text = "Zoom \(zoom.percent)%"
    let sleep = announceSleep
    announcement = Task { [weak self] in
      do { try await sleep(Self.announceDelay) } catch { return }
      guard let self, !Task.isCancelled else { return }
      self.announcement = nil
      self.onAnnouncement?(text)
    }
  }

  /// True while an announcement waits for the changes to stop.
  var isAnnouncementPending: Bool { announcement != nil }

  private func cancelTimer() {
    generation += 1
    timer?.cancel()
    timer = nil
  }

  private func armTimer() {
    cancelTimer()
    guard display != nil, !hovering else { return }
    let armed = generation
    let sleep = sleep
    timer = Task { [weak self] in
      do { try await sleep(Self.autoClose) } catch { return }
      guard let self, self.generation == armed else { return }
      self.timer = nil
      self.close()
    }
  }
}
