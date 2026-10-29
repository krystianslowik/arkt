import Foundation

/// Whether Cmd-Q should ask before quitting (#487, BH-177). The reply is injected: production presents the alert,
/// tests pass the answer in. No clock.
@MainActor
public final class QuitWarningGate {
  public enum Decision: Equatable, Sendable {
    /// Quit the way the app does when the warning is off.
    case proceed
    /// Show the ask. Do not terminate, and do not prepare the session, until the reply.
    case ask
    /// An ask is already showing. Keep waiting.
    case wait
    /// The user declined. Do not terminate.
    case stop
  }

  public private(set) var isAsking = false

  public init() {}

  /// `warns` is the setting. A second call while the ask is up waits for the same reply.
  public func begin(warns: Bool) -> Decision {
    if isAsking { return .wait }
    guard warns else { return .proceed }
    isAsking = true
    return .ask
  }

  /// The alert's answer. A reply that arrives when nothing is asking does not quit.
  public func reply(confirmed: Bool) -> Decision {
    guard isAsking else { return .wait }
    isAsking = false
    return confirmed ? .proceed : .stop
  }
}
