import Foundation

/// The consent rules (#129, the maintainer's decisions): one switch in Settings > Privacy, off by default; after the
/// first crash the next launch asks once; no answer is asked again.
public enum CrashReportPolicy {
  public enum CaptureAction: Equatable, Sendable {
    /// The switch is on: keep the report with the others.
    case store
    /// The switch is off and the ask is still to come: keep this one report, so the ask has something to offer.
    case holdForAsk
    /// The switch is off and the ask was answered: keep nothing.
    case discard
  }

  public enum Answer: Equatable, Sendable { case send, dontSend, alwaysSend }

  /// What an answer does. Every answer ends the ask.
  public struct Resolution: Equatable, Sendable {
    public var marksAsked: Bool
    public var opensReport: Bool
    public var deletesReport: Bool
    public var enablesSwitch: Bool
  }

  public static func captureAction(enabled: Bool, asked: Bool) -> CaptureAction {
    if enabled { return .store }
    return asked ? .discard : .holdForAsk
  }

  /// The launch asks when a report is held, the switch is off and nothing was answered yet. With the switch on the
  /// user has already said yes; Settings > Privacy sends a stored report.
  public static func shouldAsk(enabled: Bool, asked: Bool, hasReport: Bool) -> Bool {
    !enabled && !asked && hasReport
  }

  /// Send opens the report once and deletes it, the switch stays off; Don't Send deletes it; Always Send opens it,
  /// keeps it and turns the switch on.
  public static func resolution(for answer: Answer) -> Resolution {
    switch answer {
    case .send: Resolution(marksAsked: true, opensReport: true, deletesReport: true, enablesSwitch: false)
    case .dontSend: Resolution(marksAsked: true, opensReport: false, deletesReport: true, enablesSwitch: false)
    case .alwaysSend: Resolution(marksAsked: true, opensReport: true, deletesReport: false, enablesSwitch: true)
    }
  }
}
