import QuartzCore

/// The command bar's show and hide state in one value (#884). What only exists while the bar is up, the generation
/// of this show, the end of the commit that carried it and the search suggestion request, lives in the session, so
/// it is created and dropped with it. Async replies carry the generation they started under and are accepted only
/// while it is still the current one. One entry point, `send(_:)`; pairs it does not list are no-ops.
@MainActor
struct CommandBarLifecycle {
  enum Phase: Equatable { case hidden, showing, shown }

  enum Event: Equatable {
    case show
    /// The run loop pass that carried the show finished its Core Animation commit at `at`.
    case commitEnded(generation: Int, at: CFTimeInterval)
    /// The first frame with the bar was presented.
    case firstFrame(generation: Int)
    case hide
  }

  struct Session {
    let generation: Int
    var commitTime: CFTimeInterval?
    var suggestions: Task<Void, Never>?
  }

  private enum State {
    case hidden
    /// Shown, waiting for the first frame with the bar (the show latency's end).
    case showing(Session)
    case shown(Session)
  }

  private var state = State.hidden
  private var lastGeneration = 0

  var phase: Phase {
    switch state {
    case .hidden: .hidden
    case .showing: .showing
    case .shown: .shown
    }
  }

  private var session: Session? {
    switch state {
    case .hidden: nil
    case .showing(let session), .shown(let session): session
    }
  }

  /// The current show's generation; nil while hidden.
  var generation: Int? { session?.generation }
  var commitTime: CFTimeInterval? { session?.commitTime }

  /// Whether a reply started under `generation` may still change the bar.
  func accepts(generation: Int) -> Bool { session?.generation == generation }

  mutating func send(_ event: Event) {
    let before = describe()
    switch (state, event) {
    case (_, .show):
      session?.suggestions?.cancel()
      lastGeneration += 1
      state = .showing(Session(generation: lastGeneration))
    case (.showing(var current), .commitEnded(let generation, let time)) where current.generation == generation:
      current.commitTime = time
      state = .showing(current)
    case (.showing(let current), .firstFrame(let generation))
      where current.generation == generation && current.commitTime != nil:
      state = .shown(current)
    case (.showing(let current), .hide), (.shown(let current), .hide):
      current.suggestions?.cancel()
      state = .hidden
    default:
      return
    }
    #if DEBUG
    let after = describe()
    if after != before {
      log.append("\(before) -> \(after)")
      if log.count > 32 { log.removeFirst(log.count - 32) }
    }
    #endif
  }

  /// Hands the session a new suggestion request, cancelling the one it replaces. Ignored while hidden.
  mutating func attach(suggestions task: Task<Void, Never>) {
    switch state {
    case .hidden:
      task.cancel()
    case .showing(var current):
      current.suggestions?.cancel()
      current.suggestions = task
      state = .showing(current)
    case .shown(var current):
      current.suggestions?.cancel()
      current.suggestions = task
      state = .shown(current)
    }
  }

  private func describe() -> String {
    switch state {
    case .hidden: "hidden"
    case .showing(let session): "showing(\(session.generation))"
    case .shown(let session): "shown(\(session.generation))"
    }
  }

  #if DEBUG
  /// The last 32 transitions, for tests and debugging. Debug builds only.
  private(set) var log: [String] = []
  #endif
}
