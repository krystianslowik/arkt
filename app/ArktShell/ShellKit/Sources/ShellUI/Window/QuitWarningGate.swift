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

  /// The Engine build's Quit item (#560). There Chromium's `AppController` answers `terminate:` and nothing after it
  /// can cancel, so the item asks before it terminates: off, `terminate` runs inside this call; on, `ask` shows the
  /// alert and passes the answer back, and only Quit terminates. A Cmd-Q while the ask is up shows nothing new.
  public func requestQuit(warns: Bool, ask: (@escaping @MainActor (Bool) -> Void) -> Void,
                          terminate: @escaping @MainActor () -> Void) {
    switch begin(warns: warns) {
    case .proceed:
      terminate()
    case .ask:
      ask { [weak self] confirmed in
        if self?.reply(confirmed: confirmed) == .proceed { terminate() }
      }
    case .wait, .stop:
      break
    }
  }
}
