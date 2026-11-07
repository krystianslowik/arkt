import CrashReporting
import Foundation
import MetricKit

/// Turns each `MXCrashDiagnostic` MetricKit delivers on a later launch into a report (#129). MetricKit captures
/// crashes out of process, so the app needs no signal handler. The call stack tree carries image names, offsets and
/// build UUIDs, not symbol names; the UUIDs let a dSYM symbolicate the stack afterwards.
final class MetricKitCrashSource: NSObject, MXMetricManagerSubscriber, Sendable {
  private let recorder: CrashReportRecorder
  private let environment: CrashEnvironment
  /// Told when a report was stored, off the main thread.
  private let onRecorded: @Sendable () -> Void

  init(recorder: CrashReportRecorder, environment: CrashEnvironment, onRecorded: @escaping @Sendable () -> Void) {
    self.recorder = recorder
    self.environment = environment
    self.onRecorded = onRecorded
  }

  func start() { MXMetricManager.shared.add(self) }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    var recorded = false
    for payload in payloads {
      for crash in payload.crashDiagnostics ?? [] {
        if recorder.record(raw(from: crash, delivered: payload.timeStampEnd)) != nil { recorded = true }
      }
    }
    if recorded { onRecorded() }
  }

  private func raw(from crash: MXCrashDiagnostic, delivered: Date) -> RawCrash {
    let signal = crash.signal?.intValue
    let meta = crash.metaData
    return RawCrash(
      source: .metricKit, occurredAt: delivered,
      osVersion: meta.osVersion, architecture: meta.platformArchitecture,
      appVersion: crash.applicationVersion, appBuild: meta.applicationBuildVersion,
      engineVersion: environment.engineVersion,
      exceptionType: MetricKitMapping.exceptionName(type: crash.exceptionType?.intValue, signal: signal),
      isAbort: MetricKitMapping.isAbort(signal: signal),
      exceptionReason: crash.terminationReason,
      frames: MetricKitMapping.frames(fromCallStackTree: crash.callStackTree.jsonRepresentation()),
      annotations: [:])
  }
}
