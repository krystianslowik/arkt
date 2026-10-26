import Foundation

/// Turns raw crashes into stored reports, behind the consent gate (#129). Both capture sources (MetricKit, the
/// uncaught-exception handler) call `record`; nothing else writes reports.
public struct CrashReportRecorder: Sendable {
  public typealias Consent = @Sendable () -> (enabled: Bool, asked: Bool)

  private let store: CrashReportStore
  private let stripper: CrashReportStripper
  private let newID: @Sendable () -> String
  private let consent: Consent

  /// `consent` is read at each call, so the switch applies at once.
  public init(store: CrashReportStore, stripper: CrashReportStripper,
              newID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
              consent: @escaping Consent) {
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

  /// The switch or the answer changed: with the switch off, only the report the ask still needs stays.
  public func consentChanged() {
    let state = consent()
    guard !state.enabled else { return }
    if state.asked { store.removeAll() } else { store.keepNewest(1) }
  }

  /// One uncaught exception ends in one abort: the first stored exception report not yet matched takes it.
  private func markAbortCovered() -> Bool {
    guard var report = try? store.reports().last(where: { $0.source == .uncaughtException && !$0.abortCovered })
    else { return false }
    report.abortCovered = true
    return (try? store.save(report)) != nil
  }
}
