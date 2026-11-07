import Foundation
import QuartzCore
import Testing
@testable import Motion

/// The shared ease-out curves and fade-duration scale (#619): one place for the numbers every fade uses.
struct MotionCurveTests {
  @Test func `the strong ease-out is the design system's cubic-bezier`() {
    let curve = MotionCurve.strongEaseOut
    #expect([curve.c1x, curve.c1y, curve.c2x, curve.c2y] == [0.23, 1, 0.32, 1])
  }

  @Test func `the system ease-out is CSS ease-out`() {
    let curve = MotionCurve.systemEaseOut
    #expect([curve.c1x, curve.c1y, curve.c2x, curve.c2y] == [0, 0, 0.58, 1])
  }

  @Test func `the timing function carries the control points`() {
    let function = MotionCurve.strongEaseOut.timingFunction
    var points = [Float](repeating: 0, count: 4)
    for index in 1...2 {
      var point: [Float] = [0, 0]
      function.getControlPoint(at: index, values: &point)
      points[(index - 1) * 2] = point[0]
      points[(index - 1) * 2 + 1] = point[1]
    }
    #expect(points == [0.23, 1, 0.32, 1])
  }

  @Test func `the curve's value runs from 0 to 1 and matches the CSS curve between`() {
    let curve = MotionCurve.systemEaseOut
    #expect(curve.value(at: 0) == 0)
    #expect(curve.value(at: 1) == 1)
    #expect(curve.value(at: -0.5) == 0)
    #expect(curve.value(at: 1.5) == 1)
    #expect(abs(curve.value(at: 0.25) - 0.378138) < 1e-4)
    #expect(abs(curve.value(at: 0.5) - 0.684643) < 1e-4)
    #expect(abs(MotionCurve.strongEaseOut.value(at: 0.5) - 0.965983) < 1e-4)
  }

  @Test func `the fade scale runs quick, standard, slow`() {
    #expect(FadeDuration.quick == 0.1)
    #expect(FadeDuration.standard == 0.15)
    #expect(FadeDuration.slow == 0.2)
  }

  @Test func `no source file spells out the strong ease-out but the token`() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    var offenders: [String] = []
    for case let url as URL in files where url.pathExtension == "swift" {
      let text = try String(contentsOf: url, encoding: .utf8)
      if text.contains("0.23, 1, 0.32, 1"), url.lastPathComponent != "MotionCurve.swift" {
        offenders.append(url.lastPathComponent)
      }
    }
    #expect(offenders.isEmpty, "use MotionCurve.strongEaseOut in \(offenders)")
  }
}
