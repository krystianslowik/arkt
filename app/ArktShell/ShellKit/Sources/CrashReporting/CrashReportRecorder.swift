import Foundation

/// Turns raw crashes into stored reports, behind the consent gate (#129). Both capture sources (MetricKit, the
/// uncaught-exception handler) call `record`; nothing else writes reports.
public struct CrashReportRecorder: Sendable {
  public typealias Consent = @Sendable () -> (enabled: Bool, asked: Bool)

  private let store: CrashReportStore
  private let stripper: CrashReportStripper
  private let newID: @Sendable () -> String
  private let consent: Consent
  private let markAsked: @Sendable () -> Void

  /// `consent` is read at each call, so the switch applies at once. `markAsked` records that the one-time ask is
  /// settled; it runs when the user turns the switch off, which is an answer.
  public init(store: CrashReportStore, stripper: CrashReportStripper,
              newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
              consent: @escaping Consent, markAsked: @escaping @Sendable () -> Void = {}) {
    self.markAsked = markAsked
    self.store = store
    self.stripper = stripper
    self.newID = newID
    self.consent = consent
  }

  /// Stores the stripped report when the gate allows it and returns it; nil when nothing was stored.
  @discardableResult
  public func record(_ raw: RawCrash) -> CrashReport? {
    let state = consent()
    let action = CrashReportPolicy.captureAction(enabled: state.enabled, asked: state.asked)
    guard action != .discard else { return nil }
    if raw.source == .metricKit, raw.isAbort, markAbortCovered() { return nil }
    let report = stripper.report(from: raw, id: newID())
    if action == .holdForAsk { store.removeAll() }
    do { try store.save(report) } catch { return nil }
    return report
  }

  /// The report the launch's one-time ask is about, nil when the rules say not to ask.
  public func reportToAskAbout() -> CrashReport? {
    let state = consent()
    let newest = try? store.reports().first
    guard CrashReportPolicy.shouldAsk(enabled: state.enabled, asked: state.asked, hasReport: newest != nil) else {
      return nil
    }
    return newest
  }

  /// The switch changed. Off is the user's answer: every stored report goes, and the ask never comes back.
  public func consentChanged() {
    guard !consent().enabled else { return }
    store.removeAll()
    markAsked()
  }

  /// One uncaught exception ends in one abort: the first stored exception report not yet matched takes it.
  private func markAbortCovered() -> Bool {
    guard var report = try? store.reports().last(where: { $0.source == .uncaughtException && !$0.abortCovered })
    else { return false }
    report.abortCovered = true
    return (try? store.save(report)) != nil
  }
}
