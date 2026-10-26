import AppKit
import CoreBridge
import Persistence
import ShellUI
import os

extension OnboardingRecord: SettingsGroup {
  public static let storageKey = "onboarding.state"
  public static var defaultValue: OnboardingRecord { OnboardingRecord() }
}

/// Whether Arkt is the default browser, and asking macOS to make it so (section 15, item 3). Debug runs with
/// `ARKT_DEFAULT_BROWSER` (and every strict UI-test run) never touch the real setting.
@MainActor
enum DefaultBrowser {
  static let schemes = ["http", "https"]

  static func isDefault() -> Bool {
    #if DEBUG
    if let fake = override { return fake == .isDefault }
    #endif
    guard let probe = URL(string: "https://example.com"),
          let handler = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
    return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
  }

  /// Asks for http, then https; returns when the system prompt closed, whatever the answer.
  static func makeDefault() async {
    #if DEBUG
    if override != nil { return }
    #endif
    let app = Bundle.main.bundleURL
    for scheme in schemes {
      do {
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme)
      } catch {
        AppSession.log.notice("default browser not set \(scheme, privacy: .public) \((error as NSError).code)")
      }
    }
  }

  #if DEBUG
  private static var override: EnvironmentOverrides.DefaultBrowser? {
    EnvironmentOverrides(environment: ProcessInfo.processInfo.environment).defaultBrowser
  }
  #endif
}

/// The app's side of the first run: the Arc check, the count pass and the import through CoreBridge, the default
/// browser, and the saved record. Counts only reach the log, never names, titles, URLs or paths.
@MainActor
final class AppOnboardingServices: OnboardingServices {
  private weak var session: AppSession?
  private let records: OnboardingRecordStore
  var record: OnboardingRecord { records.record }

  init(session: AppSession, records: OnboardingRecordStore) {
    self.session = session
    self.records = records
  }

  func checkArc() async -> Bool {
    guard let session else { return false }
    return await session.arcFiles.isAvailable()
  }

  func countArcData() -> AsyncThrowingStream<OnboardingCounts, any Error> {
    guard let files = session?.arcFiles else {
      return AsyncThrowingStream { $0.finish(throwing: CancellationError()) }
    }
    let source = ArcImportCounter.counts(files)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await counts in source {
            continuation.yield(OnboardingCounts(spaces: counts.spaces, pinnedTabs: counts.pinnedTabs,
                                                favorites: counts.favorites, folders: counts.folders))
          }
          continuation.finish()
        } catch {
          AppSession.log.error("onboarding count failed \(String(describing: type(of: error)), privacy: .public)")
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func importArcData() async -> OnboardingImportResult {
    guard let session, let outcome = await session.performImport(showsFailureToast: false) else { return .failed }
    let summary = outcome.summary
    return .imported(skipped: summary.skipped + summary.archiveSkipped, addedSpaces: outcome.addedSpaces)
  }

  func isDefaultBrowser() -> Bool { DefaultBrowser.isDefault() }
  func makeDefaultBrowser() async { await DefaultBrowser.makeDefault() }

  func saveProgress(_ snapshot: OnboardingFlow.Snapshot) { records.saveProgress(snapshot) }

  func markCompleted() { records.markCompleted() }
}

// MARK: - Presenting

extension AppSession {
  /// The Chromium engine configuration shows the Extensions step (section 15, item 8).
  static var onboardingIncludesExtensions: Bool {
    #if ARKT_CHROMIUM_ENGINE
    true
    #else
    false
    #endif
  }

  /// The launch window shows the first run when the profile has no Space and the flow was never finished, or a run
  /// was left mid-flow. Later windows with no Space keep the empty state; only one window runs it.
  func presentOnboardingIfNeeded(on window: ShellWindowController) {
    #if DEBUG
    if EnvironmentOverrides(environment: ProcessInfo.processInfo.environment).skipsOnboarding { return }
    if AppEnvironment.smokePhase != nil { return }
    #endif
    guard onboardingRecord.showsAutomatically(profileHasSpaces: !window.isShowingEmptyState),
          !windows.controllers.contains(where: \.isShowingOnboarding) else { return }
    presentOnboarding(on: window, mode: .firstRun, resume: onboardingRecord.progress)
  }

  /// Help > Welcome to Arkt: the same flow over the frontmost browser window (section 12).
  func showWelcome() {
    guard canShowWelcome else { return }
    let window = windows.primary ?? windows.openWindow()
    window.showWindow(nil)
    presentOnboarding(on: window, mode: .reentry, resume: nil)
  }

  var canShowWelcome: Bool { !windows.controllers.contains(where: \.isShowingOnboarding) && !importer.isRunning }

  private func presentOnboarding(on window: ShellWindowController, mode: OnboardingMode,
                                 resume: OnboardingFlow.Snapshot?) {
    let services = AppOnboardingServices(session: self, records: onboardingRecords)
    let controller = window.presentOnboarding(
      services: services,
      options: .init(mode: mode, includesExtensions: Self.onboardingIncludesExtensions, resume: resume))
    controller.onFinish = { [weak self, services] in self?.onboardingRecord = services.record }
    Self.log.notice("onboarding shown \(mode.rawValue, privacy: .public) resumed \(resume != nil, privacy: .public)")
  }

  /// A link from another app (FakeEngine; the Chromium engine opens them itself): a new Today tab in the primary
  /// window.
  func openFromOtherApp(_ urls: [URL]) {
    let window = windows.primary ?? windows.openWindow()
    window.showWindow(nil)
    for url in urls where ["http", "https"].contains(url.scheme?.lowercased() ?? "") || url.isFileURL {
      window.openFromOtherApp(url)
    }
  }
}
