import Foundation

/// When the status pill shows and hides, as a pure state machine over a clock the caller supplies (design/status-pill,
/// "Behavior"): nothing in it reads the time or sleeps, so a test steps it with numbers.
///
/// - A link under the pointer starts a 0.4 s wait; leaving it first cancels the wait.
/// - While the pill is up, another link replaces its address at once, with no wait.
/// - Leaving every link hides the pill after 0.1 s, so a gap between two close links does not blink it. A link entered
///   within that grace keeps it up.
struct StatusPillModel: Equatable, Sendable {
  static let showDelay: TimeInterval = 0.4
  static let hideDelay: TimeInterval = 0.1

  enum Phase: Equatable, Sendable {
    case hidden
    /// A link is under the pointer; the pill shows at `until`.
    case waiting(URL, until: TimeInterval)
    case shown(URL)
    /// The pointer left every link; the pill goes at `until` unless a link comes first.
    case leaving(URL, until: TimeInterval)
  }

  private(set) var phase: Phase = .hidden
  /// Held while a mouse button is down: a wait that ends then shows nothing.
  var isSuppressed = false

  /// The address on screen; nil while the pill is not up.
  var displayed: URL? {
    switch phase {
    case .shown(let url), .leaving(let url, _): url
    case .hidden, .waiting: nil
    }
  }

  /// The time `advance(to:)` next changes something; nil when nothing is pending.
  var deadline: TimeInterval? {
    switch phase {
    case .waiting(_, let until), .leaving(_, let until): until
    case .hidden, .shown: nil
    }
  }

  /// The engine reported the link under the pointer: `url`, or nil when the pointer left it.
  mutating func targetChanged(_ url: URL?, at now: TimeInterval) {
    guard let url else {
      switch phase {
      case .hidden, .leaving: break
      case .waiting: phase = .hidden
      case .shown(let shown): phase = .leaving(shown, until: now + Self.hideDelay)
      }
      return
    }
    switch phase {
    case .hidden:
      phase = .waiting(url, until: now + Self.showDelay)
    case .waiting(let waiting, _):
      if waiting != url { phase = .waiting(url, until: now + Self.showDelay) }
    case .shown, .leaving:
      phase = .shown(url)
    }
  }

  /// Applies every deadline at or before `now`.
  mutating func advance(to now: TimeInterval) {
    switch phase {
    case .waiting(let url, let until) where now >= until:
      phase = isSuppressed ? .hidden : .shown(url)
    case .leaving(_, let until) where now >= until:
      phase = .hidden
    default:
      break
    }
  }

  /// Hides at once: the tab left the screen.
  mutating func reset() { phase = .hidden }
}
