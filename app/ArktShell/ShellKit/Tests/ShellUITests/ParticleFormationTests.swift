import CoreGraphics
import Testing
import simd
@testable import ShellUI

/// The particle formations (onboarding spec, section 7.2): parts by lane, shapes from real things, the retarget and
/// re-tint rules, and the accessibility floors of section 9.
struct ParticleFormationTests {
  static let size = SIMD2<Float>(1120, 720)
  static let mark: [ParticleFormationBuilder.MarkSample] = (0..<200).map { i in
    .init(position: SIMD2(Float(i % 20) / 20 - 0.5, Float(i / 20) / 10 - 0.5), color: ParticleColors.mustard)
  }

  static func input(count: Int = 2_000, now: Float = 10, dark: Bool = false, rt: Bool = false, ic: Bool = false,
                    rm: Bool = false) -> ParticleFormationBuilder.Input {
    ParticleFormationBuilder.Input(size: size, count: count, now: now, epoch: 3, dark: dark, reduceTransparency: rt,
                                   increaseContrast: ic, reduceMotion: rm, mark: mark)
  }

  static let welcome = OnboardingFormation.welcome(mark: CGRect(x: 450, y: 84, width: 220, height: 200))

  @Test func everyMoteGetsATarget() {
    let targets = ParticleFormationBuilder(input: Self.input()).build(Self.welcome)
    #expect(targets.count == 2_000)
    #expect(targets.allSatisfy { $0.extra.w == 3 }, "the formation's epoch")
  }

  /// Welcome: the mark 55 % (lanes 0 to 10), the fold 15 % (11 to 13), the field 30 %.
  @Test func welcomeLanesMakeTheMarkAndTheFold() {
    let targets = ParticleFormationBuilder(input: Self.input()).build(Self.welcome)
    let box = CGRect(x: 450, y: 84, width: 220, height: 200).insetBy(dx: -4, dy: -4)
    for (index, target) in targets.enumerated() where ParticleFormationBuilder.lane(index) < 11 {
      #expect(box.contains(CGPoint(x: CGFloat(target.target.x), y: CGFloat(target.target.y))), "mark mote \(index)")
      #expect(target.color.w == 1)
    }
    let fold = targets.enumerated().filter { (11..<14).contains(ParticleFormationBuilder.lane($0.offset)) }
    #expect(fold.allSatisfy { $0.element.target.y > 360 }, "the fold sweeps along the bottom half")
    let ambient = targets.enumerated().filter { ParticleFormationBuilder.lane($0.offset) >= 14 }
    #expect(ambient.allSatisfy { $0.element.target.z >= 12 }, "the field drifts 12 to 24 pt")
  }

  @Test func startsAreNowPlusAStaggerOfAtMostHalfASecond() {
    let targets = ParticleFormationBuilder(input: Self.input(now: 10)).build(Self.welcome)
    #expect(targets.allSatisfy { $0.motion.y >= 10 && $0.motion.y <= 10.56 })
  }

  @Test func springsAreGatherForShapesAndFirmExtraSlowForTheField() {
    let targets = ParticleFormationBuilder(input: Self.input()).build(Self.welcome)
    let gather = SpringParametersProbe.kc(dampingRatio: 0.88, response: 0.8)
    let field = SpringParametersProbe.kc(dampingRatio: 0.9, response: 1.25)
    #expect(abs(targets[0].motion.z - gather.k) < 1e-3 && abs(targets[0].motion.w - gather.c) < 1e-3)
    #expect(abs(targets[15].motion.z - field.k) < 1e-3 && abs(targets[15].motion.w - field.c) < 1e-3)
  }

  // MARK: Counts

  static func counts(_ state: OnboardingCountFormation.State, pinned: String = "37") -> OnboardingFormation {
    .counts(OnboardingCountFormation(numbers: [
      .init(kind: .pinnedTabs, text: pinned, frame: CGRect(x: 460, y: 100, width: 200, height: 181), fontSize: 210),
      .init(kind: .spaces, text: "4", frame: CGRect(x: 380, y: 330, width: 40, height: 55), fontSize: 64),
      .init(kind: .favorites, text: "12", frame: CGRect(x: 520, y: 330, width: 80, height: 55), fontSize: 64),
      .init(kind: .folders, text: "9", frame: CGRect(x: 690, y: 330, width: 40, height: 55), fontSize: 64),
    ], state: state))
  }

  /// The digits are sampled from Avenir Next at their laid-out size and land on their numbers.
  @Test func digitMotesLandOnTheirNumbers() {
    let targets = ParticleFormationBuilder(input: Self.input()).build(Self.counts(.ready))
    let boxes = [CGRect(x: 440, y: 80, width: 240, height: 220), CGRect(x: 360, y: 315, width: 390, height: 90)]
    for (index, target) in targets.enumerated() where ParticleFormationBuilder.lane(index) < 11 {
      let point = CGPoint(x: CGFloat(target.target.x), y: CGFloat(target.target.y))
      #expect(boxes.contains { $0.contains(point) }, "digit mote \(index) at \(point)")
    }
  }

  @Test func countingDrawsInkAt55PercentAndLandedCategoriesTurnMustard() {
    let counting = ParticleFormationBuilder(input: Self.input()).build(Self.counts(.counting))
    #expect(counting[0].color.w == 0.55)
    let importing = ParticleFormationBuilder(input: Self.input())
      .build(Self.counts(.importing(landed: [.pinnedTabs, .spaces, .favorites, .folders])))
    let digits = importing.enumerated().filter { ParticleFormationBuilder.lane($0.offset) < 11 }.map(\.element)
    #expect(digits.allSatisfy { simd_distance($0.color.xyz, ParticleColors.mustard) < 1e-4 })
  }

  /// P4: a changing count retargets without restarting: start times stay those of the formation before.
  @Test func aRetargetKeepsStartTimes() {
    let first = ParticleFormationBuilder(input: Self.input(now: 10)).build(Self.counts(.counting, pinned: "3"))
    let second = ParticleFormationBuilder(input: Self.input(now: 11)).build(Self.counts(.counting, pinned: "37"),
                                                                            previous: first)
    #expect(zip(first, second).allSatisfy { $0.motion.y == $1.motion.y })
    #expect(zip(first, second).contains { $0.target.xy != $1.target.xy }, "the number's motes moved")
  }

  // MARK: Make it yours

  /// P6: the re-tint spreads from the pressed swatch at 900 pt/s.
  @Test func retintStaggersByDistanceFromTheSwatch() {
    let origin = CGPoint(x: 400, y: 500)
    let theme = SpaceThemeCatalog.families[3].light
    let targets = ParticleFormationBuilder(input: Self.input(now: 0))
      .build(.theme(preview: CGRect(x: 390, y: 110, width: 340, height: 196), theme: theme, origin: origin))
    for (index, target) in targets.enumerated() where ParticleFormationBuilder.lane(index) < 4 {
      let distance = simd_distance(target.target.xy, SIMD2(400, 500))
      #expect(abs(target.motion.y - distance / 900) < 1e-3)
    }
  }

  // MARK: Accessibility floors (section 9)

  @Test func reduceTransparencyDropsTheFieldAndStrengthensShapes() {
    let targets = ParticleFormationBuilder(input: Self.input(rt: true)).build(Self.welcome)
    let plain = ParticleFormationBuilder(input: Self.input()).build(Self.welcome)
    for (index, (target, base)) in zip(targets, plain).enumerated() {
      if ParticleFormationBuilder.lane(index) >= 14 {
        #expect(target.color.w == 0, "no background field")
      } else {
        #expect(target.color.w >= 0.6)
        #expect(abs(target.motion.x - base.motion.x * 1.15) < 1e-4, "15 % larger")
      }
    }
  }

  @Test func increaseContrastRaisesShapesTo80PercentAndUsesFoldShadowForMustardOnLight() {
    let targets = ParticleFormationBuilder(input: Self.input(ic: true))
      .build(.done(mark: CGRect(x: 476, y: 120, width: 168, height: 168)))
    for (index, target) in targets.enumerated() where ParticleFormationBuilder.lane(index) < 13 && target.color.w > 0 {
      #expect(target.color.w >= 0.8, "lane \(ParticleFormationBuilder.lane(index))")
    }
    let orbit = targets.enumerated().first { ParticleFormationBuilder.lane($0.offset) == 9 }
    #expect(orbit.map { simd_distance($0.element.color.xyz, ParticleColors.fold) < 1e-4 } == true)
  }

  @Test func reduceMotionStopsDriftAndPathsAndDissolvesBySeed() {
    let targets = ParticleFormationBuilder(input: Self.input(now: 5, rm: true))
      .build(.extensions(mark: CGRect(x: 508, y: 140, width: 104, height: 104), rings: .zero))
    #expect(targets.allSatisfy { $0.target.z == 0 && $0.extra.x == 0 })
    for (index, target) in targets.enumerated() {
      #expect(abs(target.motion.y - (5 + ParticleFormationBuilder.seed(index) * 0.3)) < 1e-4)
    }
  }

  @Test func darkInkIsPorcelain() {
    let targets = ParticleFormationBuilder(input: Self.input(dark: true)).build(.tour(tip: 4, stage: CGRect(x: 280, y: 90, width: 560, height: 236)))
    #expect(targets.contains { simd_distance($0.color.xyz, ParticleColors.porcelain) < 1e-4 })
    #expect(!targets.contains { simd_distance($0.color.xyz, ParticleColors.graphite) < 1e-4 })
  }

  @Test func everyFormationBuilds() {
    let stage = CGRect(x: 280, y: 90, width: 560, height: 236)
    let formations: [OnboardingFormation] = [
      .none, Self.welcome, Self.counts(.failed), .defaultBrowser(mark: stage), .extensions(mark: stage, rings: stage),
      .tour(tip: 1, stage: stage), .tour(tip: 2, stage: stage), .tour(tip: 3, stage: stage),
      .tour(tip: 5, stage: stage), .done(mark: stage),
    ]
    for formation in formations {
      let targets = ParticleFormationBuilder(input: Self.input(count: 400)).build(formation)
      #expect(targets.allSatisfy { $0.target.x.isFinite && $0.target.y.isFinite && $0.motion.x > 0 }, "\(formation)")
    }
    let card = ParticleFormationBuilder(input: Self.input(count: 400)).buildCard(CGRect(x: 200, y: 10, width: 910, height: 700))
    #expect(card.count == 400)
  }

  // MARK: Samplers and paths

  @Test func glyphsAreSampledFromRealType() {
    let one = GlyphSampler.points("1", size: 64, postScriptName: "AvenirNext-DemiBold")
    let eight = GlyphSampler.points("8", size: 64, postScriptName: "AvenirNext-DemiBold")
    #expect(!one.points.isEmpty && eight.points.count > one.points.count)
    #expect(eight.height > 40 && eight.height < 64)
    #expect(!GlyphSampler.points("\u{2318}", size: 40, postScriptName: nil).points.isEmpty)
  }

  /// P8: one room at +1.4 s, the next at +3.0 s, back to the second from +4.6 s, then rest.
  @Test func roomsPanTwiceAndRestOnTheSecond() {
    #expect(ParticlePath.pan(1) == 0)
    #expect(abs(ParticlePath.pan(2.9) - 1) < 0.01)
    #expect(abs(ParticlePath.pan(4.5) - 2) < 0.01)
    #expect(abs(ParticlePath.pan(8) - 1) < 0.01)
  }

  @Test func curveRunsFromStartToEnd() {
    let path = ParticlePath.curve(x0: 0, y0: 0, x1: 100, y1: 50, bend: -40)
    #expect(path.point(phase: 0, clock: 0) == SIMD2(0, 0))
    #expect(path.point(phase: 1, clock: 0) == SIMD2(100, 50))
  }

  @Test func tiersHaveTheSpecCounts() {
    #expect(ParticleRenderer.Tier.full.count == 20_480 && ParticleRenderer.Tier.full.preferredFrameRate == 120)
    #expect(ParticleRenderer.Tier.fallback.count == 8_192 && ParticleRenderer.Tier.fallback.preferredFrameRate == 60)
  }

  @Test func targetLayoutMatchesTheKernel() {
    #expect(MemoryLayout<ParticleTarget>.stride == 96)
    #expect(MemoryLayout<ParticleState>.stride == 48)
    #expect(MemoryLayout<ParticleUniforms>.stride == 48)
  }
}

/// k and c of a spring as the builder computes them.
enum SpringParametersProbe {
  static func kc(dampingRatio: Float, response: Float) -> (k: Float, c: Float) {
    let w = 2 * Float.pi / response
    return (w * w, 2 * dampingRatio * w)
  }
}

extension SIMD4 where Scalar == Float {
  var xyz: SIMD3<Float> { SIMD3(x, y, z) }
  var xy: SIMD2<Float> { SIMD2(x, y) }
}
