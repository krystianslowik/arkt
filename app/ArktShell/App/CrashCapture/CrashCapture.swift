import AppKit
import CrashReporting
import ShellUI
import SidebarModel
import os

/// Crash reporting for the app (#129): captures crashes behind the Settings > Privacy switch, keeps stripped reports
/// in `<data folder>/CrashReports`, asks once after the first crash, and hands a report to the browser as a prefilled
/// GitHub issue. Nothing is uploaded; the user reviews and submits the issue.
///
/// Disk work runs off the main actor (`@concurrent`); the main actor only awaits. The uncaught-exception handler is the
/// one synchronous writer, as the process goes down.
@MainActor
final class CrashCapture {
  static let log = Logger(subsystem: "dev.arkt.shell", category: "crash")

  private let store: CrashReportStore
  private let recorder: CrashReportRecorder
  private let redactions = CrashRedactions()
  private let environment = CrashEnvironment.current()
  private let settings: AppSettings
  private var metricKit: MetricKitCrashSource?
  /// Reports on this Mac at the last check, for Settings, which never waits on disk.
  private(set) var storedCount = 0
  private var isAsking = false
  private var sheet: DialogSheet?
  private var lastEnabled: Bool

  /// `directory` is the data folder; reports go in its `CrashReports` folder. The consent switch and the answered flag
  /// are read from the app's defaults at each crash (`AppEnvironment.userDefaults`, which a test run points at its own
  /// suite), so they apply at once and the handler needs no main actor.
  init(directory: URL, settings: AppSettings) {
    self.settings = settings
    lastEnabled = settings.sendsCrashReports
    store = CrashReportStore(directory: directory.appending(path: "CrashReports", directoryHint: .isDirectory))
    recorder = CrashReportRecorder.production(
      store: store, homeDirectory: NSHomeDirectory(), userName: NSUserName(), redactions: redactions,
      consent: {
        let defaults = AppEnvironment.userDefaults
        return (enabled: defaults.bool(forKey: AppSettings.Key.sendsCrashReports),
         asked: defaults.bool(forKey: AppSettings.Key.crashReportAskAnswered))
      },
      markAsked: { AppEnvironment.userDefaults.set(true, forKey: AppSettings.Key.crashReportAskAnswered) })
  }

  /// The current profile and Space names, scrubbed from every report. Called with the sidebar at launch and after each
  /// change. "default" is the unnamed profile, not a user's text, and would shred ordinary symbols.
  func updateRedactions(from sidebar: SidebarModel.Sidebar) {
    redactions.update(sidebar.spaces.values.flatMap { [$0.title, $0.profile] }.filter { $0 != "default" })
  }

  /// Installs both capture sources and counts the reports already kept.
  func start() {
    UncaughtExceptionCapture.install(recorder: recorder, environment: environment)
    let source = MetricKitCrashSource(recorder: recorder, environment: environment) { [weak self] in
      Task { @MainActor in
        self?.refreshCount()
        self?.askAgain?()
      }
    }
    source.start()
    metricKit = source
    refreshCount()
  }

  /// Set by the session: asks again once MetricKit delivered a report after the launch's first look.
  var askAgain: (@MainActor () -> Void)?

  // MARK: Count

  func refreshCount() {
    Task { [store] in
      let count = await Self.count(in: store)
      storedCount = count
    }
  }

  @concurrent
  private static func count(in store: CrashReportStore) async -> Int { (try? store.reports().count) ?? 0 }

  // MARK: Settings

  /// The switch changed: with it off, the stored reports go (all of them once the ask was answered).
  func settingsDidChange() {
    guard settings.sendsCrashReports != lastEnabled else { return }
    lastEnabled = settings.sendsCrashReports
    Task { [recorder] in
      await Self.consentChanged(recorder)
      refreshCount()
    }
  }

  @concurrent
  private static func consentChanged(_ recorder: CrashReportRecorder) async { recorder.consentChanged() }

  /// Settings > Privacy > Send Crash Report: the newest kept report, as a GitHub issue in the browser.
  func sendNewest() {
    Task { [store] in
      guard let report = await Self.newest(in: store) else { return }
      Self.open(report)
    }
  }

  @concurrent
  private static func newest(in store: CrashReportStore) async -> CrashReport? { try? store.reports().first }

  private static func open(_ report: CrashReport) {
    NSWorkspace.shared.open(GitHubIssueLink.make(for: report).url)
  }

  // MARK: The one-time ask

  /// After a crash with the switch off and nothing answered yet, asks "Arkt quit unexpectedly. Send a report?" once, as
  /// a sheet on `parent`. `parent` returns nil while no window can take it (a first run covers the window): the ask is
  /// then left for the next launch, never skipped silently into an answer.
  func askIfNeeded(parent: @escaping @MainActor () -> NSWindow?) {
    guard !isAsking, !settings.crashReportAskAnswered, !settings.sendsCrashReports else { return }
    isAsking = true
    Task { [recorder] in
      let report = await Self.reportToAskAbout(recorder)
      guard let report, let window = parent() else {
        isAsking = false
        return
      }
      present(report, on: window)
    }
  }

  @concurrent
  private static func reportToAskAbout(_ recorder: CrashReportRecorder) async -> CrashReport? {
    recorder.reportToAskAbout()
  }

  private func present(_ report: CrashReport, on window: NSWindow) {
    let sheet = DialogSheet(content: .crashReportAsk)
    sheet.onAnswer = { [weak self] answer in self?.resolve(answer, report: report) }
    self.sheet = sheet
    sheet.begin(on: window)
    Self.log.notice("crash report ask shown")
  }

  private func resolve(_ dialogAnswer: DialogContent.Answer, report: CrashReport) {
    let answer: CrashReportPolicy.Answer = switch dialogAnswer {
    case .primary: .send
    case .secondary: .alwaysSend
    case .cancel: .dontSend
    }
    let resolution = CrashReportPolicy.resolution(for: answer)
    Self.log.notice("crash report ask answered \(String(describing: answer), privacy: .public)")
    settings.crashReportAskAnswered = resolution.marksAsked
    if resolution.enablesSwitch { settings.sendsCrashReports = true }
    if resolution.opensReport { Self.open(report) }
    sheet = nil
    isAsking = false
    guard resolution.deletesReport else {
      refreshCount()
      return
    }
    Task { [store] in
      await Self.remove(report.id, from: store)
      refreshCount()
    }
  }

  @concurrent
  private static func remove(_ id: String, from store: CrashReportStore) async { store.remove(id: id) }
}
