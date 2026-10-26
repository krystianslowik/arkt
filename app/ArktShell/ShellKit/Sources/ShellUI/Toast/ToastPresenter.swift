import Foundation

/// What a toast is for (alerts design 4.1): its default glyph and how long it stays.
public enum ToastKind: Hashable, Sendable {
  /// A notice, with an optional action (restore, pin, sidebar creation): 4 s.
  case notice
  /// Something failed: the error glyph, 4 s.
  case error
  /// Several tabs went to the Archive at once, with Undo: 6 s (decision 3).
  case undo
  /// A recovery notice: wraps to three lines and stays until dismissed or replaced.
  case persistent

  /// The SF Symbol drawn before the text; nil: none (a notice names its own).
  public var defaultGlyph: String? {
    switch self {
    case .notice: nil
    case .error: "exclamationmark.circle"
    case .undo: "archivebox"
    case .persistent: "exclamationmark.shield"
    }
  }

  /// How long the toast stays while the window is key and the pointer is elsewhere; nil: until dismissed.
  /// TODO(measure): Arc's duration is unknown (BH-192).
  public var duration: Duration? {
    switch self {
    case .notice, .error: .seconds(4)
    case .undo: .seconds(6)
    case .persistent: nil
    }
  }
}

/// A short, non-blocking notice drawn over the bottom of the content card.
public struct Toast: Equatable, Sendable {
  public var text: String
  public var kind: ToastKind
  /// The leading SF Symbol; nil: none.
  public var glyph: String?
  public var actionTitle: String?
  /// The action's key, drawn after its title at half strength ("Reopen" with "\u{2318}Z", #346). The Undo pill has
  /// none (alerts design, decision on the Undo hint).
  public var shortcut: String?
  /// What VoiceOver says instead of `text` (the key spelled out); nil: `text`.
  public var announcement: String?
  /// A polite live region: announced without interrupting (the Peek's "Peek closed", #346). Otherwise announced with
  /// high priority.
  public var isPolite: Bool

  /// `glyph` nil takes the kind's own glyph.
  public init(text: String, kind: ToastKind = .notice, glyph: String? = nil, actionTitle: String? = nil,
              shortcut: String? = nil, announcement: String? = nil, isPolite: Bool = false) {
    self.text = text
    self.kind = kind
    self.glyph = glyph ?? kind.defaultGlyph
    self.actionTitle = actionTitle
    self.shortcut = shortcut
    self.announcement = announcement
    self.isPolite = isPolite
  }

  /// Persistent toasts (recovery notices) stay until dismissed or replaced by another persistent one.
  public var isPersistent: Bool { kind == .persistent }
  /// How long it stays; nil: until dismissed.
  public var duration: Duration? { kind.duration }
  /// What VoiceOver announces when the toast shows.
  public var spokenText: String { announcement ?? text }
}

/// Why a toast's timer is held: a toast that expires unseen taught nothing (alerts design 4.1).
public enum ToastPause: Hashable, Sendable {
  /// The pointer is over the toast.
  case hover
  /// The window is not key.
  case windowInactive
}

/// Injected time: `Task.sleep(for:)` in the app, a manual sleeper in tests.
public typealias ToastSleep = @Sendable (Duration) async throws -> Void

/// Shows one toast at a time. A new toast replaces the current one. A transient toast shown over a persistent one
/// hides it only while the transient one is up; when the transient toast ends, the persistent one comes back. A
/// transient toast's timer runs only while nothing pauses it, and starts again at full length when the last pause
/// ends.
@MainActor
public final class ToastPresenter {

  public private(set) var current: Toast?
  /// Set by the window: draws `current` over the bottom of the content card.
  var view: ToastView? {
    didSet { view?.display(current, animated: false) }
  }

  private struct Entry {
    var toast: Toast
    var onAction: (@MainActor () -> Void)?
  }

  private let sleep: ToastSleep
  private var pauses: Set<ToastPause> = []
  private var transient: Entry?
  private var persistent: Entry?
  /// Bumped on every show and dismiss; a timer dismisses only the toast it was armed for.
  private var generation = 0
  private var timer: Task<Void, Never>?
  /// Timers whose task has not returned yet (cancelled ones included), for `waitForIdleForTesting`.
  private var runningTimers: [Int: Task<Void, Never>] = [:]

  public init(sleep: @escaping ToastSleep = { try await Task.sleep(for: $0) }) {
    self.sleep = sleep
  }

  /// Shows `toast` now. `onAction` runs when its action button is pressed; the toast is dismissed first.
  public func show(_ toast: Toast, onAction: (@MainActor () -> Void)? = nil) {
    let entry = Entry(toast: toast, onAction: onAction)
    if toast.isPersistent {
      persistent = entry
      transient = nil
    } else {
      transient = entry
    }
    update()
  }

  /// Dismisses the visible toast. Dismissing a transient toast reveals a persistent one under it.
  public func dismiss() {
    if transient != nil { transient = nil } else { persistent = nil }
    update()
  }

  /// Dismisses `toast` when it is the one shown; any other toast stays up.
  public func dismiss(_ toast: Toast) {
    dismiss { $0 == toast }
  }

  /// Dismisses the visible toast when `matches` accepts it (the undo toast once its batch came back by Cmd-Z).
  public func dismiss(where matches: (Toast) -> Bool) {
    guard let current, matches(current) else { return }
    dismiss()
  }

  /// Holds or releases the visible toast's timer for `reason`. The last release re-arms it at full length.
  public func setPaused(_ paused: Bool, for reason: ToastPause) {
    let wasPaused = !pauses.isEmpty
    if paused { pauses.insert(reason) } else { pauses.remove(reason) }
    guard wasPaused != !pauses.isEmpty else { return }
    if pauses.isEmpty {
      armTimer()
    } else {
      cancelTimer()
    }
  }

  public var isPaused: Bool { !pauses.isEmpty }

  /// The toast's dismiss button (persistent toasts): takes it down without running its action.
  func dismissFromButton() { dismiss() }

  /// The action button of the visible toast.
  func performAction() {
    guard let action = (transient ?? persistent)?.onAction else { return }
    dismiss()
    action()
  }

  private var visible: Entry? { transient ?? persistent }

  private func update() {
    cancelTimer()
    current = visible?.toast
    view?.display(current, animated: true)
    armTimer()
  }

  /// Bumps the generation, so a timer already past its sleep cannot dismiss anything.
  private func cancelTimer() {
    generation += 1
    timer?.cancel()
    timer = nil
  }

  /// Starts the visible transient toast's timer, unless something pauses it.
  private func armTimer() {
    guard pauses.isEmpty, timer == nil, let duration = transient?.toast.duration else { return }
    let (sleep, armed) = (self.sleep, generation)
    let task = Task { [weak self] in
      defer { self?.runningTimers[armed] = nil }
      do { try await sleep(duration) } catch { return }
      guard !Task.isCancelled, let self, self.generation == armed else { return }
      self.transient = nil
      self.update()
    }
    timer = task
    runningTimers[armed] = task
  }

  // MARK: - Testing

  var isTimerArmedForTesting: Bool { timer != nil }
  var runningTimerCountForTesting: Int { runningTimers.count }

  func performActionForTesting() { performAction() }

  /// Returns once every timer started so far has returned.
  func waitForIdleForTesting() async {
    while let task = runningTimers.values.first { await task.value }
  }
}
