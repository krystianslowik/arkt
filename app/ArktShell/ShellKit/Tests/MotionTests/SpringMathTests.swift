import Foundation
import Testing
@testable import Motion

struct SpringMathTests {
  @Test func stiffnessFromResponse() {
    let p = SpringParameters(dampingRatio: 1, response: 0.5)
    #expect(abs(p.stiffness - pow(2 * .pi / 0.5, 2)) < 1e-9)       // 157.9137
    #expect(abs(p.stiffness - 157.913_670_417) < 1e-6)
  }

  @Test func dampingFromRatio() {
    let p = SpringParameters(dampingRatio: 1, response: 0.5)
    #expect(abs(p.damping - 4 * .pi * 1 * 1 / 0.5) < 1e-9)         // 8 pi = 25.1327
    #expect(abs(p.damping - 2 * (p.stiffness * p.mass).squareRoot()) < 1e-9, "ratio 1 is critical damping")
  }

  @Test func massScalesStiffnessAndDamping() {
    let p = SpringParameters(dampingRatio: 0.7, response: 0.3, mass: 2)
    #expect(abs(p.stiffness - pow(2 * .pi / 0.3, 2) * 2) < 1e-9)
    #expect(abs(p.damping - 4 * .pi * 0.7 * 2 / 0.3) < 1e-9)
  }

  @Test(arguments: SpringPreset.allCases)
  func presetsRoundTripDampingRatio(preset: SpringPreset) {
    let p = preset.parameters
    let ratio = p.damping / (2 * (p.stiffness * p.mass).squareRoot())
    #expect(abs(ratio - p.dampingRatio) < 1e-9)
    #expect(p.response > 0)
  }

  @Test func presetNamesMatchArcTagOrder() {
    #expect(SpringPreset.arcPresets.map(\.rawValue) ==
            ["firm", "firmSlow", "firmExtraSlow", "firmFast", "springy", "springyFast", "springyExtraFast"])
  }

  /// Arkt's own presets follow Arc's, so Arc's tag order stays a prefix of `allCases`.
  @Test func arktPresetsFollowArcs() {
    #expect(SpringPreset.allCases == SpringPreset.arcPresets + [.gather])
  }

  /// `gather` (onboarding spec, section 7.3): particle formations, damping 0.88 and response 0.8 s.
  @Test func gatherIsTheFormationSpring() {
    let p = SpringPreset.gather.parameters
    #expect(p.dampingRatio == 0.88)
    #expect(p.response == 0.80)
    #expect(p.mass == 1)
    #expect(abs(p.stiffness - 61.69) < 0.01, "stiffness \(p.stiffness)")
    #expect(abs(p.damping - 13.82) < 0.01, "damping \(p.damping)")
  }

  /// Preset table plus the CASpringAnimation values the conversion derives (mass 1).
  static let arcPresets: [(SpringPreset, response: Double, dampingRatio: Double,
                           stiffness: Double, damping: Double)] = [
    (.firm,             0.25, 0.90,  631.65,  45.24),
    (.firmSlow,         0.35, 0.90,  322.27,  32.31),
    (.firmExtraSlow,    1.25, 0.90,   25.27,   9.05),
    (.firmFast,         0.15, 0.95, 1754.60,  79.59),
    (.springy,          0.28, 0.63,  503.55,  28.27),
    (.springyFast,      0.18, 0.80, 1218.47,  55.85),
    (.springyExtraFast, 0.08, 0.80, 6168.50, 125.66),
  ]

  @Test(arguments: arcPresets.indices)
  func presetMatchesArc(index: Int) {
    let expected = Self.arcPresets[index]
    let p = expected.0.parameters
    #expect(p.response == expected.response)
    #expect(p.dampingRatio == expected.dampingRatio)
    #expect(p.mass == 1)
    #expect(abs(p.stiffness - expected.stiffness) < 0.01, "\(expected.0) stiffness \(p.stiffness)")
    #expect(abs(p.damping - expected.damping) < 0.01, "\(expected.0) damping \(p.damping)")
  }

  @Test func arcTableCoversEveryArcPreset() {
    #expect(Self.arcPresets.map(\.0) == SpringPreset.arcPresets)
  }
}
