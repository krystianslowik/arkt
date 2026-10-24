import AppKit
import XCTest

/// Whether this machine can measure frame timing, decided the way the app's `SmokeRunner` decides its pacing
/// verdict: a screen below 120 Hz or a 1-minute load average at or above the active core count is NOT-MEASURABLE.
/// Hosted CI runners are both (60 Hz virtual display, load far above 3 cores). Thresholds are never loosened: on a
/// capable machine every timing check asserts as before.
@MainActor
enum PacingEnvironment {
  /// Why timing cannot be measured here, or nil when it can.
  static func notMeasurableReason(screen: NSScreen? = NSScreen.main) -> String? {
    let fps = screen?.maximumFramesPerSecond ?? 0
    if fps < 120 { return "screen \(fps) Hz" }
    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    if getloadavg(&load, 1) != 1 || load[0] >= Double(cores) {
      return String(format: "load %.2f on %d cores", load[0], cores)
    }
    return nil
  }

  /// Skips the test as NOT-MEASURABLE when this machine cannot measure timing.
  static func skipIfNotMeasurable(screen: NSScreen? = NSScreen.main) throws {
    if let reason = notMeasurableReason(screen: screen) {
      throw XCTSkip("NOT-MEASURABLE (\(reason))")
    }
  }

  /// For a test that must observe a transient state (a settle caught mid-flight): when `caught` is false, the test
  /// fails on a machine that can measure timing and is skipped as NOT-MEASURABLE on one that cannot, because
  /// there a stalled main thread or a 60 Hz display can finish the transient before the test looks.
  static func requireCaught(
    _ caught: Bool, _ what: String, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    guard !caught else { return }
    try skipIfNotMeasurable()
    _ = try XCTUnwrap(nil as Void?, "did not catch: \(what)", file: file, line: line)
  }
}
