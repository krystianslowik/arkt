import AppKit
import XCTest
@testable import ShellUI

/// Whether this machine can measure frame timing, decided the way the app's `SmokeRunner` decides its pacing
/// verdict: a screen below 120 Hz or a 1-minute load average at or above the active core count is NOT-MEASURABLE.
/// Hosted CI runners are both (60 Hz virtual display, load far above 3 cores). Thresholds are never loosened: on a
/// capable machine every timing check asserts as before.
@MainActor
enum PacingEnvironment {
  /// Why timing cannot be measured here, or nil when it can.
  static func notMeasurableReason(screen: NSScreen? = NSScreen.main) -> String? {
    if let reason = screenNotMeasurableReason(fps: screen?.maximumFramesPerSecond ?? 0) { return reason }
    if case .reportsUnderLoad(let reason) = frameGateVerdict(gated: true, load1: load1(),
                                                              cores: ProcessInfo.processInfo.activeProcessorCount) {
      return reason
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

  // MARK: - Frame-time gate

  /// What a frame-time gate does with its hitch count in this run. Every case measures, prints and attaches.
  enum FrameGateVerdict: Equatable {
    /// Gated and measurable: no frame may go over the hitch threshold (8.6 ms).
    case asserts
    /// Not gated (`gateAsserts` is false): the gate runs inside a longer batch, so it only reports.
    case reportsInBatch
    /// The 1-minute load read after measuring is at or above the core count (NOT-MEASURABLE): it only reports.
    case reportsUnderLoad(String)
    /// A case that is never gated (a measurement kept for comparison).
    case informational

    var asserts: Bool { self == .asserts }
  }

  /// The one rule for every frame-time gate (#671): an informational case never asserts; a load at or above the core
  /// count (or an unknown load) is NOT-MEASURABLE; otherwise the gate asserts only when `gated`
  /// (`gateAsserts(for:)`).
  static func frameGateVerdict(gated: Bool, informational: Bool = false, load1: Double?, cores: Int)
    -> FrameGateVerdict {
    if informational { return .informational }
    guard let load1, load1 < Double(cores) else {
      return .reportsUnderLoad(load1.map { String(format: "load %.2f on %d cores", $0, cores) }
        ?? "load unknown on \(cores) cores")
    }
    return gated ? .asserts : .reportsInBatch
  }

  /// The gate's summary line, `<name>.pacing label=... asserted=yes|no hitchesMs=[frame@ms,...]`. Hitch indices count
  /// from the first gated interval; the lead-in (display-link start-up) is printed apart.
  static func frameGateSummary(name: String, label: String, stats: FrameStats, fps: Int, load1: Double, cores: Int,
                               asserted: Bool) -> String {
    let hitches = stats.intervals.enumerated().filter { $0.element > stats.hitchThreshold }
      .map { String(format: "%d@%.2f", $0.offset, $0.element * 1000) }
    return String(
      format: "%@.pacing label=%@ screenMaxFPS=%d frames=%d over8.6=%d overBudgetPct=%.2f maxMs=%.2f p99Ms=%.2f "
        + "leadInMs=%.2f load1=%.2f cores=%d asserted=%@ hitchesMs=[%@]",
      name, label, fps, stats.frameCount, stats.hitchCount, stats.overBudgetRatio * 100, stats.maxInterval * 1000,
      stats.p99 * 1000, (stats.leadInInterval ?? 0) * 1000, load1, cores, asserted ? "yes" : "no",
      hitches.joined(separator: ","))
  }

  /// The 1-minute load average, or nil when it cannot be read.
  static func load1() -> Double? {
    var load = [0.0]
    return getloadavg(&load, 1) == 1 ? load[0] : nil
  }

  /// Applies the frame-time gate to measured interactions, the same way for every gate: reads the load again after
  /// measuring, prints `<name>.pacing gate=asserts|reports`, one `<name>.hitch` line per late frame (what held the
  /// main thread: app work when cpu is near wall, waiting when off CPU), and a summary line per interaction, which it
  /// also attaches as `<name>.pacing.<label>`. Every interaction must have run on the display link
  /// (`minimumFrames`); the hitch count is asserted only when the verdict is `.asserts`. Call
  /// `skipIfNotMeasurable(screen:)` before measuring. `verdict` overrides the computed one (tests).
  @discardableResult
  static func checkFrameGate(
    _ name: String, results: [(String, FrameStats)], details: [HitchDetail] = [], gate testClass: AnyClass,
    in testCase: XCTestCase, fps: Int, informational: Bool = false, minimumFrames: Int = 10,
    verdict override: FrameGateVerdict? = nil, file: StaticString = #filePath, line: UInt = #line
  ) -> FrameGateVerdict {
    let load = load1()
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let verdict = override ?? frameGateVerdict(gated: gateAsserts(for: testClass), informational: informational,
                                               load1: load, cores: cores)
    print("\(name).pacing gate=\(verdict.asserts ? "asserts" : "reports")")
    for d in details {
      print(String(format: "%@.hitch label=%@ frame=%d ms=%.2f busyMs=%.2f cpuMs=%.2f offCpuMs=%.2f passes=%d",
                   name, d.label, d.frame, d.interval * 1000, (d.longest?.wall ?? 0) * 1000,
                   (d.longest?.cpu ?? 0) * 1000, (d.longest?.offCPU ?? 0) * 1000, d.passes))
    }
    for (label, stats) in results {
      let summary = frameGateSummary(name: name, label: label, stats: stats, fps: fps, load1: load ?? 0, cores: cores,
                                     asserted: verdict.asserts)
      print(summary)
      let attachment = XCTAttachment(string: summary)
      attachment.name = "\(name).pacing.\(label)"
      attachment.lifetime = .keepAlways
      testCase.add(attachment)
      XCTAssertGreaterThan(stats.frameCount, minimumFrames, "\(label): the display link ran (is the display awake?)",
                           file: file, line: line)
      switch verdict {
      case .asserts:
        XCTAssertEqual(stats.hitchCount, 0, "\(label): frames over 8.6 ms", file: file, line: line)
      case .reportsInBatch:
        print("\(name).pacing reported only: set ARKT_PACING_GATE=1 or run \(String(describing: testClass)) alone")
      case .reportsUnderLoad(let reason):
        print("\(name).pacing skipped assert: NOT-MEASURABLE (\(reason))")
      case .informational:
        print("\(name).pacing informational: \(label) is not gated")
      }
    }
    return verdict
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
