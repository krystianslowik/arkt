import AppKit
import XCTest
@testable import ShellUI

/// The one NOT-MEASURABLE rule and opt-in assert shared by every frame-time gate (#671). Pure inputs: no window, no
/// display link, no real load or environment.
@MainActor
final class PacingEnvironmentTests: XCTestCase {
  final class GateOwner {}

  private var owner: String { String(reflecting: GateOwner.self) }

  private func stats(_ intervals: [Double]) -> FrameStats {
    var stats = FrameStats()
    stats.record(interval: 0.02)                       // the lead-in, kept apart from the gate
    for interval in intervals { stats.record(interval: interval) }
    return stats
  }

  // MARK: Who asserts

  func testTheGateAssertsWithTheEnvironmentSwitch() {
    XCTAssertTrue(PacingEnvironment.gateAsserts(for: GateOwner.self, environment: ["ARKT_PACING_GATE": "1"],
                                                arguments: []))
    XCTAssertFalse(PacingEnvironment.gateAsserts(for: GateOwner.self, environment: ["ARKT_PACING_GATE": "0"],
                                                 arguments: []))
  }

  func testTheGateAssertsWhenItsClassRunsAlone() {
    for selection in [owner, "\(owner)/testOne", "\(owner)/testOne,\(owner)/testTwo"] {
      XCTAssertTrue(PacingEnvironment.gateAsserts(for: GateOwner.self, environment: [:],
                                                  arguments: ["xctest", "-XCTest", selection, "bundle.xctest"]),
                    selection)
    }
  }

  func testTheGateOnlyReportsInsideABatch() {
    let batch = ["xctest", "-XCTest", "\(owner),ShellKitGUITests.OtherTests", "bundle.xctest"]
    XCTAssertFalse(PacingEnvironment.gateAsserts(for: GateOwner.self, environment: [:], arguments: batch))
    XCTAssertFalse(PacingEnvironment.gateAsserts(for: GateOwner.self, environment: [:], arguments: ["xctest"]))
    XCTAssertFalse(PacingEnvironment.gateAsserts(for: GateOwner.self, environment: [:],
                                                 arguments: ["xctest", "-XCTest", "\(owner)Extra"]))
  }

  // MARK: Verdict

  func testTheVerdictAssertsOnlyWhenGatedOnAMeasurableLoad() {
    XCTAssertEqual(PacingEnvironment.frameGateVerdict(gated: true, load1: 4, cores: 10), .asserts)
    XCTAssertEqual(PacingEnvironment.frameGateVerdict(gated: false, load1: 4, cores: 10), .reportsInBatch)
    XCTAssertEqual(PacingEnvironment.frameGateVerdict(gated: true, load1: 10, cores: 10),
                   .reportsUnderLoad("load 10.00 on 10 cores"))
    XCTAssertEqual(PacingEnvironment.frameGateVerdict(gated: false, load1: 12.5, cores: 10),
                   .reportsUnderLoad("load 12.50 on 10 cores"))
    XCTAssertEqual(PacingEnvironment.frameGateVerdict(gated: true, load1: nil, cores: 10),
                   .reportsUnderLoad("load unknown on 10 cores"))
    XCTAssertEqual(PacingEnvironment.frameGateVerdict(gated: true, informational: true, load1: 1, cores: 10),
                   .informational)
  }

  func testTheSummaryLineSaysWhetherItAsserted() {
    let measured = stats([0.0083, 0.0091, 0.0084])
    let line = PacingEnvironment.frameGateSummary(name: "split.reflow", label: "split-reflow-4", stats: measured,
                                                  fps: 120, load1: 4.5, cores: 10, asserted: true)
    XCTAssertEqual(line, "split.reflow.pacing label=split-reflow-4 screenMaxFPS=120 frames=3 over8.6=1 "
                     + "overBudgetPct=66.67 maxMs=9.10 p99Ms=9.10 leadInMs=20.00 load1=4.50 cores=10 asserted=yes "
                     + "hitchesMs=[1@9.10]")
    let reported = PacingEnvironment.frameGateSummary(name: "sidebar", label: "sidebar-reveal-0", stats: measured,
                                                      fps: 120, load1: 4.5, cores: 10, asserted: false)
    XCTAssertTrue(reported.hasPrefix("sidebar.pacing label=sidebar-reveal-0 "), reported)
    XCTAssertTrue(reported.contains(" asserted=no "), reported)
  }

  // MARK: Applying the gate

  func testAnAssertingGateFailsOnAHitch() {
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { $0.compactDescription.contains("frames over 8.6 ms") }
    XCTExpectFailure("a frame over 8.6 ms fails an asserting gate", options: options)
    let verdict = PacingEnvironment.checkFrameGate(
      "gatetest", results: [("hitch", stats(Array(repeating: 0.0083, count: 11) + [0.0095]))],
      gate: GateOwner.self, in: self, fps: 120, verdict: .asserts)
    XCTAssertEqual(verdict, .asserts)
  }

  func testAReportingGateDoesNotFailOnAHitch() {
    for verdict in [PacingEnvironment.FrameGateVerdict.reportsInBatch, .reportsUnderLoad("load 12.00 on 10 cores"),
                    .informational] {
      let result = PacingEnvironment.checkFrameGate(
        "gatetest", results: [("hitch", stats(Array(repeating: 0.0083, count: 11) + [0.0095]))],
        gate: GateOwner.self, in: self, fps: 120, verdict: verdict)
      XCTAssertEqual(result, verdict)
    }
  }

  func testEveryGateStillNeedsTheDisplayLinkToHaveRun() {
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { $0.compactDescription.contains("the display link ran") }
    XCTExpectFailure("too few frames fail even a reporting gate", options: options)
    PacingEnvironment.checkFrameGate("gatetest", results: [("short", stats([0.0083, 0.0083]))],
                                     gate: GateOwner.self, in: self, fps: 120, verdict: .reportsInBatch)
  }
}
