import Foundation
import Synchronization

/// The names the stripper removes from every kept string: profile and Space names (#129). The app owns the data, so it
/// keeps this list current (from App/*); the crash paths read it from any thread, so access is locked.
public final class CrashRedactions: Sendable {
  private let stored = Mutex<[String]>([])

  public init() {}

  public var names: [String] { stored.withLock { $0 } }

  public func update(_ names: [String]) {
    stored.withLock { $0 = names }
  }
}

extension CrashReportRecorder {
  /// The recorder the app runs: a stripper that reads `redactions` at each report, so a name added or renamed after
  /// launch is scrubbed from the next crash. The app and the wiring tests both build the recorder through here.
  public static func production(
    store: CrashReportStore, homeDirectory: String, userName: String, redactions: CrashRedactions,
    consent: @escaping Consent, markAsked: @escaping @Sendable () -> Void
  ) -> CrashReportRecorder {
    CrashReportRecorder(
      store: store,
      stripper: CrashReportStripper(homeDirectory: homeDirectory, userName: userName, redacting: { redactions.names }),
      consent: consent, markAsked: markAsked)
  }
}
