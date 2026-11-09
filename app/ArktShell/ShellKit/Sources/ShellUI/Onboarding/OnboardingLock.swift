/// What holds the first run in place (#879, #877): the system's default-browser prompt, the Skip setup question, an
/// import, or the end. Every navigation entry point of `OnboardingController` asks the same lock; the step itself
/// stays in `OnboardingFlow`. A value type with no clock, so tests drive it without a window.
enum OnboardingLock: Equatable, Sendable {
  /// Nothing waits: the step's buttons, Back, the arrows and Escape work.
  case idle
  /// Make default asked macOS; the step waits for the prompt to close.
  case promptingDefault
  /// The Skip setup question is up. `duringImport`: it was asked over a running import, which a No returns to.
  case askingSkip(duringImport: Bool)
  /// An import runs (the step's own, or the browser data import over the step). `skipWhenDone`: Skip setup was
  /// confirmed during it, so its end finishes the run.
  case importing(skipWhenDone: Bool)
  /// Start browsing or a confirmed Skip setup: the flow is over.
  case finished

  enum Event: Equatable, Sendable {
    /// Make default pressed.
    case promptDefault
    /// The system prompt closed, whatever the answer.
    case promptClosed
    /// Skip setup pressed (footer, or Escape on Welcome).
    case askSkip
    /// The Skip setup question's answer.
    case skipAnswered(confirmed: Bool)
    /// Import pressed (or Try again).
    case importStarted
    /// The import ended, imported, failed or cancelled.
    case importEnded
    /// The flow ends.
    case finish
  }

  /// Step buttons, Back, the arrows and Escape act.
  var acceptsNavigation: Bool { self == .idle }

  /// The flow is over.
  var isFinished: Bool { self == .finished }

  /// The default-browser step shows its prompt note and disabled buttons.
  var isPromptingDefault: Bool { self == .promptingDefault }

  /// Skip setup was confirmed during the import that runs now.
  var skipsWhenImportEnds: Bool { self == .importing(skipWhenDone: true) }

  /// The lock after `event`, or nil when the pair is not a transition (the event is ignored).
  func next(after event: Event) -> OnboardingLock? {
    switch (self, event) {
    case (.idle, .promptDefault): .promptingDefault
    case (.promptingDefault, .promptClosed): .idle
    case (.idle, .askSkip): .askingSkip(duringImport: false)
    case (.importing(skipWhenDone: false), .askSkip): .askingSkip(duringImport: true)
    case (.askingSkip(let duringImport), .skipAnswered(let confirmed)):
      duringImport ? .importing(skipWhenDone: confirmed) : .idle
    // The import ended while the question was up: the answer no longer waits for it.
    case (.askingSkip(duringImport: true), .importEnded): .askingSkip(duringImport: false)
    case (.idle, .importStarted): .importing(skipWhenDone: false)
    case (.importing, .importEnded): .idle
    case (.finished, .finish): nil
    case (_, .finish): .finished
    default: nil
    }
  }
}

/// The current lock and, in debug builds, every transition it took, for tests and the console.
struct OnboardingLockState {
  struct Transition: Equatable {
    let from: OnboardingLock
    let event: OnboardingLock.Event
    let to: OnboardingLock
  }

  private(set) var lock: OnboardingLock = .idle

  #if DEBUG
  /// Accepted transitions in order. Debug builds only.
  private(set) var log: [Transition] = []
  #endif

  /// Applies `event`; returns false (and changes nothing) when the lock ignores it.
  @discardableResult
  mutating func send(_ event: OnboardingLock.Event) -> Bool {
    guard let next = lock.next(after: event) else { return false }
    #if DEBUG
    log.append(Transition(from: lock, event: event, to: next))
    #endif
    lock = next
    return true
  }
}
