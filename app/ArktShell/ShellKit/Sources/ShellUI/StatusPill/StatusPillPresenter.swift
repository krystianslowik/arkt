import AppKit
import EngineAPI

/// Shows the address of the link under the pointer, one pill per tab, in the card that shows the tab (#114, BH-167,
/// design/status-pill/README.md). The engine reports the link as `.targetURLChanged(tab, URL?)`; `StatusPillModel` decides
/// when the pill shows and hides, and this presenter feeds it a clock, wakes it at its next deadline and draws the
/// result in the tab's `ContentCardView`.
///
/// A tab that is not on screen shows nothing: a tab that leaves the screen loses its pill at once and starts afresh
/// when it comes back, whatever the pointer was over. The pill dodges the pointer (`StatusPillGeometry`) using the
/// pointer positions the card forwards.
///
/// Time is injected: `now` and `schedule` are closures, so a test steps a manual clock and nothing waits.
@MainActor
public final class StatusPillPresenter {
  /// Runs `fire` after `delay` seconds on the main actor; the returned closure cancels it.
  typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void

  private final class Entry {
    var model = StatusPillModel()
    var corner: StatusPillCorner = .leading
    weak var card: ContentCardView?
    var cancelTimer: (@MainActor () -> Void)?
  }

  private let cardFor: @MainActor (TabID) -> ContentCardView?
  private var entries: [TabID: Entry] = [:]
  /// The pointer is sampled this often while a pill is up; the card's tracking area may not see it over a page view.
  static let sampleInterval: TimeInterval = 1.0 / 30
  private var cancelSampler: (@MainActor () -> Void)?

  /// Seconds on any monotonic clock; the model's deadlines are read against it.
  var now: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  var schedule: Schedule = { delay, fire in
    let task = Task { @MainActor in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      fire()
    }
    return { task.cancel() }
  }
  /// The pointer in `card`'s coordinates, or nil when it is not over the window. Tests set it.
  var pointer: @MainActor (ContentCardView) -> CGPoint? = { card in
    guard let window = card.window, window.isKeyWindow else { return nil }
    return card.convert(window.mouseLocationOutsideOfEventStream, from: nil)
  }
  /// Whether a mouse button is down: nothing shows then. Tests set it.
  var isMouseButtonDown: @MainActor () -> Bool = { NSEvent.pressedMouseButtons != 0 }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Tests turn this off and step each pill's crossing by hand.
  var drivesDisplayLink = true
  /// Fades and rises run only while the window is on screen; tests may force them.
  var animatesOffscreen = false

  /// `cardFor` returns the card that shows `tab` in this window, nil for a tab that is not on screen.
  init(cardFor: @escaping @MainActor (TabID) -> ContentCardView?) {
    self.cardFor = cardFor
  }

  // MARK: Engine events

  public func handle(_ event: EngineEvent) {
    guard case .targetURLChanged(let tab, let url) = event else { return }
    guard let card = cardFor(tab) else {
      // Not on screen: nothing to draw, and nothing to remember.
      if let entry = entries.removeValue(forKey: tab) { discard(entry) }
      updateSampler()
      return
    }
    let entry = entry(for: tab, card: card)
    entry.model.isSuppressed = isMouseButtonDown()
    entry.model.targetChanged(url, at: now())
    apply(entry, tab: tab)
  }

  /// The window changed what it shows (or finished a layout): a tab that left the screen loses its pill at once, and
  /// a tab whose page moved to another card (a split pane) takes it along.
  func refresh() {
    defer { updateSampler() }
    for (tab, entry) in entries {
      guard let card = cardFor(tab) else {
        entries[tab] = nil
        discard(entry)
        continue
      }
      if entry.card !== card {
        entry.card?.statusPillView?.hide(animated: false)
        entry.card = card
        apply(entry, tab: tab)
      }
    }
  }

  /// Takes every pill down and stops every timer, as the window goes away.
  func closeAll() {
    cancelSampler?()
    cancelSampler = nil
    for entry in entries.values { discard(entry) }
    entries = [:]
  }

  /// The tab's pill while it is up, for tests.
  func pill(for tab: TabID) -> StatusPillView? {
    guard let pill = entries[tab]?.card?.statusPillView, pill.isShown else { return nil }
    return pill
  }

  var hasPendingTimerForTesting: Bool { entries.values.contains { $0.cancelTimer != nil } }

  // MARK: Pointer

  /// The pointer moved over `card`: the pill crosses to the other corner when it comes within 28 pt.
  func pointerMoved(to point: CGPoint, in card: ContentCardView) {
    for entry in entries.values where entry.card === card && entry.model.displayed != nil {
      updateCorner(of: entry, pointer: point, animated: true)
    }
  }

  // MARK: Sampling

  private var hasVisiblePill: Bool { entries.values.contains { $0.model.displayed != nil } }

  /// Runs while some pill is up and not otherwise: no work when everything is hidden.
  private func updateSampler() {
    guard hasVisiblePill else {
      cancelSampler?()
      cancelSampler = nil
      return
    }
    guard cancelSampler == nil else { return }
    armSampler()
  }

  private func armSampler() {
    cancelSampler = schedule(Self.sampleInterval) { [weak self] in
      guard let self else { return }
      cancelSampler = nil
      guard hasVisiblePill else { return }
      for entry in entries.values where entry.model.displayed != nil {
        if let card = entry.card { updateCorner(of: entry, pointer: pointer(card), animated: true) }
      }
      armSampler()
    }
  }

  // MARK: Drawing

  private func entry(for tab: TabID, card: ContentCardView) -> Entry {
    if let entry = entries[tab] {
      if entry.card !== card {
        entry.card?.statusPillView?.hide(animated: false)
        entry.card = card
      }
      return entry
    }
    let entry = Entry()
    entry.card = card
    entries[tab] = entry
    return entry
  }

  private func discard(_ entry: Entry) {
    entry.cancelTimer?()
    entry.cancelTimer = nil
    entry.model.reset()
    entry.card?.statusPillView?.hide(animated: false)
  }

  /// Draws the model's state and arms (or clears) its timer.
  private func apply(_ entry: Entry, tab: TabID) {
    entry.cancelTimer?()
    entry.cancelTimer = nil
    guard let card = entry.card else { return }
    if let url = entry.model.displayed {
      let pill = prepare(card)
      let text = StatusPillText(url)
      if pill.isShown {
        pill.setText(text)
        updateCorner(of: entry, pointer: pointer(card), animated: true)
      } else {
        // The pointer may already be near the corner the pill would take: it appears in the other one.
        entry.corner = cornerAvoiding(pointer(card), current: entry.corner, text: text, pill: pill, in: card)
        pill.show(text, corner: entry.corner, animated: animates(card))
        card.needsLayout = true
      }
    } else {
      card.statusPillView?.hide(animated: animates(card))
    }
    updateSampler()
    guard let deadline = entry.model.deadline else { return }
    entry.cancelTimer = schedule(max(0, deadline - now())) { [weak self, weak entry] in
      guard let self, let entry else { return }
      entry.cancelTimer = nil
      entry.model.isSuppressed = isMouseButtonDown()
      entry.model.advance(to: now())
      guard let tab = entries.first(where: { $0.value === entry })?.key else { return }
      apply(entry, tab: tab)
    }
  }

  private func prepare(_ card: ContentCardView) -> StatusPillView {
    let pill = card.ensureStatusPill()
    pill.reduceMotion = { [weak self] in self?.reduceMotion() ?? true }
    pill.drivesDisplayLink = drivesDisplayLink
    card.onPointerMoved = { [weak self, weak card] point in
      guard let self, let card else { return }
      pointerMoved(to: point, in: card)
    }
    return pill
  }

  private func animates(_ card: ContentCardView) -> Bool {
    animatesOffscreen || card.window?.isVisible == true
  }

  private func updateCorner(of entry: Entry, pointer: CGPoint?, animated: Bool) {
    guard let card = entry.card, let pill = card.statusPillView, pill.isShown else { return }
    let target = cornerAvoiding(pointer, current: entry.corner, text: pill.text, pill: pill, in: card)
    guard target != entry.corner else { return }
    let width = pill.preferredWidth(maxWidth: StatusPillGeometry.maxWidth(cardWidth: card.bounds.width))
    let oldMinX = pill.frame.minX
    let newMinX = StatusPillGeometry.frame(corner: target, width: width, in: card.bounds).minX
    entry.corner = target
    pill.setCorner(target, from: oldMinX, to: newMinX, animated: animated && animates(card))
    card.needsLayout = true
    card.layoutSubtreeIfNeeded()
  }

  private func cornerAvoiding(_ pointer: CGPoint?, current: StatusPillCorner, text: StatusPillText,
                              pill: StatusPillView, in card: ContentCardView) -> StatusPillCorner {
    let previous = pill.text
    if previous != text { pill.setText(text) }
    let width = pill.preferredWidth(maxWidth: StatusPillGeometry.maxWidth(cardWidth: card.bounds.width))
    return StatusPillGeometry.corner(current: current, pointer: pointer, width: width, in: card.bounds)
  }
}
