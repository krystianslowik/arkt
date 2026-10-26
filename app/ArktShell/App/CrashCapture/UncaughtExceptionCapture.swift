import CrashReporting
import Foundation
import Synchronization

/// Records an uncaught `NSException` as the process goes down (#129). A plain exception handler, not a signal handler:
/// it runs on the crashing thread in a normal context, so reading the defaults and writing one small file is safe. It
/// chains to the handler that was installed before it, once, whatever the recording does. The exception's reason text
/// is read into the raw crash and dropped by the stripper; only the name and the stack are kept.
///
/// AppKit usually catches an exception on the main run loop before it reaches this handler, so this mostly covers
/// throws off the main thread and outside a run loop; MetricKit reports the rest.
enum UncaughtExceptionCapture {
  private struct Target: Sendable {
    var recorder: CrashReportRecorder
    var environment: CrashEnvironment
  }

  private static let chain = UncaughtHandlerChain()
  private static let target = Mutex<Target?>(nil)

  /// A second call does nothing.
  static func install(recorder: CrashReportRecorder, environment: CrashEnvironment) {
    guard chain.install(previous: NSGetUncaughtExceptionHandler()) else { return }
    target.withLock { $0 = Target(recorder: recorder, environment: environment) }
    NSSetUncaughtExceptionHandler { exception in UncaughtExceptionCapture.handle(exception) }
  }

  private static func handle(_ exception: NSException) {
    chain.handle(exception) {
      guard let snapshot = target.withLock({ $0 }) else { return }
      let environment = snapshot.environment
      snapshot.recorder.record(RawCrash(
        source: .uncaughtException, occurredAt: Date(), osVersion: environment.osVersion,
        architecture: environment.architecture, appVersion: environment.appVersion, appBuild: environment.appBuild,
        engineVersion: environment.engineVersion, exceptionType: exception.name.rawValue, isAbort: true,
        exceptionReason: exception.reason,
        frames: exception.callStackSymbols.compactMap(RawFrame.parse(callStackSymbol:)),
        annotations: [:]))
    }
  }
}
