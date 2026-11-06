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
    if let reason = screenNotMeasurableReason(fps: screen?.maximumFramesPerSecond ?? 0) { return reason }
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

  /// Whether a frame-time gate asserts its hitch count here, or only prints and attaches its numbers. It asserts when
  /// `ARKT_PACING_GATE=1` is set, or when the selected tests are all in `testClass` (the gate run alone): run inside a
  /// longer GUI batch, the tests before it leave main-thread work that lands in its frames (#602).
  static func gateAsserts(for testClass: AnyClass,
                          environment: [String: String] = ProcessInfo.processInfo.environment,
                          arguments: [String] = CommandLine.arguments) -> Bool {
    if environment["ARKT_PACING_GATE"] == "1" { return true }
    guard let flag = arguments.firstIndex(of: "-XCTest"), arguments.indices.contains(flag + 1) else { return false }
    let name = String(reflecting: testClass)
    let selected = arguments[flag + 1].split(separator: ",").map(String.init)
    return !selected.isEmpty && selected.allSatisfy { $0 == name || $0.hasPrefix(name + "/") }
  }

  /// Why this screen cannot drive the scripted 120 Hz frames, or nil when it can. Only the screen is checked: a test
  /// that measures thread CPU time holds under load, so it must not skip on it.
  static func screenNotMeasurableReason(fps: Int) -> String? {
    fps < 120 ? "screen \(fps) Hz" : nil
  }

  /// Skips the test as NOT-MEASURABLE when the screen cannot drive the scripted 120 Hz frames, for a test that
  /// measures thread CPU time. Unlike `skipIfNotMeasurable`, a loaded machine is measurable: CPU time does not
  /// depend on what else runs.
  static func skipIfScreenBelow120Hz(fps: Int) throws {
    if let reason = screenNotMeasurableReason(fps: fps) {
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
