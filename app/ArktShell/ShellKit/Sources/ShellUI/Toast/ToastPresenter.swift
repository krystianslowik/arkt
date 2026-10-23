import Foundation

/// A short, non-blocking notice drawn over the bottom of the content card.
public struct Toast: Equatable, Sendable {
  public var text: String
  public var actionTitle: String?
  /// Persistent toasts (recovery notices) stay until dismissed or replaced by another persistent one.
  public var isPersistent: Bool

  public init(text: String, actionTitle: String? = nil, isPersistent: Bool = false) {
    self.text = text
    self.actionTitle = actionTitle
    self.isPersistent = isPersistent
  }
}

/// Injected time: `Task.sleep(for:)` in the app, a manual sleeper in tests.
public typealias ToastSleep = @Sendable (Duration) async throws -> Void

/// Shows one toast at a time. A new toast replaces the current one. A transient toast shown over a persistent one
/// hides it only while the transient one is up; when the transient toast ends, the persistent one comes back.
@MainActor
public final class ToastPresenter {
  public static let defaultDuration: Duration = .seconds(4)       // TODO(measure): Arc's duration is unknown (BH-192)

  public private(set) var current: Toast?
  /// Set by the window: draws `current` over the bottom of the content card.
  var view: ToastView? {
    didSet { view?.display(current, animated: false) }
  }

  private struct Entry {
    var toast: Toast
    var onAction: (@MainActor () -> Void)?
  }

  private let duration: Duration
  private let sleep: ToastSleep
  private var transient: Entry?
  private var persistent: Entry?
  /// Bumped on every show and dismiss; a timer dismisses only the toast it was armed for.
  private var generation = 0
  private var timer: Task<Void, Never>?
  /// Timers whose task has not returned yet (cancelled ones included), for `waitForIdleForTesting`.
  private var runningTimers: [Int: Task<Void, Never>] = [:]

  public init(duration: Duration = ToastPresenter.defaultDuration,
              sleep: @escaping ToastSleep = { try await Task.sleep(for: $0) }) {
    self.duration = duration
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

  /// The action button of the visible toast.
  func performAction() {
    guard let action = (transient ?? persistent)?.onAction else { return }
    dismiss()
    action()
  }

  private var visible: Entry? { transient ?? persistent }

  private func update() {
    generation += 1
    timer?.cancel()
    timer = nil
    current = visible?.toast
    view?.display(current, animated: true)
    if transient != nil { armTimer() }
  }

  private func armTimer() {
    let (sleep, duration, armed) = (self.sleep, self.duration, generation)
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
