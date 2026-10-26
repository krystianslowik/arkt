import CrashReporting
import Foundation
import Synchronization

/// Records an uncaught `NSException` as the process goes down (#129). A plain exception handler, not a signal handler:
/// it runs on the crashing thread in a normal context, so reading the defaults and writing one small file is safe. It
/// chains to the handler that was installed before it. The exception's reason text is read into the raw crash and
/// dropped by the stripper; only the name and the stack are kept.
enum UncaughtExceptionCapture {
  private struct State: Sendable {
    var recorder: CrashReportRecorder
    var environment: CrashEnvironment
    var previous: (@convention(c) (NSException) -> Void)?
  }

  private static let state = Mutex<State?>(nil)

  static func install(recorder: CrashReportRecorder, environment: CrashEnvironment) {
    state.withLock { $0 = State(recorder: recorder, environment: environment, previous: NSGetUncaughtExceptionHandler()) }
    NSSetUncaughtExceptionHandler { exception in UncaughtExceptionCapture.handle(exception) }
  }

  private static func handle(_ exception: NSException) {
    guard let snapshot = state.withLock({ $0 }) else { return }
    let environment = snapshot.environment
    snapshot.recorder.record(RawCrash(
      source: .uncaughtException, occurredAt: Date(), osVersion: environment.osVersion,
      architecture: environment.architecture, appVersion: environment.appVersion, appBuild: environment.appBuild,
      engineVersion: environment.engineVersion, exceptionType: exception.name.rawValue, isAbort: true,
      exceptionReason: exception.reason,
      frames: exception.callStackSymbols.compactMap(RawFrame.parse(callStackSymbol:)),
      annotations: [:]))
    snapshot.previous?(exception)
  }
}
