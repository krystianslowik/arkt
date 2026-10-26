import Motion
import Testing
@testable import ShellUI

/// Little Arkt's motion table (docs/design/little-arkt.md, Motion): springs from `SpringPreset` on transform and
/// opacity only, interruptible, with fade-only Reduce Motion variants.
struct LittleArktMotionTests {
  private func settle(_ start: LittleArktScene, _ transition: LittleArktTransition, reduce: Bool) -> LittleArktScene {
    var springs = LittleArktSpringSet(scene: start)
    springs.apply(LittleArktMotion.targets(for: transition, reduceMotion: reduce), at: 0)
    return springs.scene(at: 30)
  }

  @Test func appearStartsTenHigherSmallerAndClear() {
    let start = LittleArktMotion.appearStart(reduceMotion: false)
    #expect(start[.lift] == 10 && start[.scale] == 0.94 && start[.opacity] == 0)
    #expect(settle(start, .appear, reduce: false) == .rest)
  }

  @Test func appearUsesFirmForTheMoveAndACriticalFade() {
    let targets = LittleArktMotion.targets(for: .appear, reduceMotion: false)
    #expect(targets.first { $0.channel == .scale }?.parameters == SpringPreset.firm.parameters)
    #expect(targets.first { $0.channel == .lift }?.parameters == SpringPreset.firm.parameters)
    #expect(targets.first { $0.channel == .opacity }?.parameters == SpringParameters(dampingRatio: 1, response: 0.16))
  }

  @Test func reduceMotionAppearIsAFadeInPlace() {
    let start = LittleArktMotion.appearStart(reduceMotion: true)
    #expect(start[.lift] == 0 && start[.scale] == 1 && start[.opacity] == 0)
    let targets = LittleArktMotion.targets(for: .appear, reduceMotion: true)
    #expect(targets.map(\.channel) == [.opacity])
    #expect(settle(start, .appear, reduce: true) == .rest)
  }

  /// The prototype's kick (0.45 per second on `springy`) peaks at about 1 %.
  @Test func nudgeSwellsAboutOnePercentAndSettlesAtRest() {
    var springs = LittleArktSpringSet(scene: .rest)
    springs.apply(LittleArktMotion.targets(for: .nudge, reduceMotion: false), at: 0)
    let peak = stride(from: 0.0, through: 0.3, by: 0.005).map { springs.scene(at: $0)[.scale] }.max() ?? 1
    #expect(peak > 1.008 && peak < 1.02)
    #expect(springs.scene(at: 30) == .rest)
    #expect(LittleArktMotion.targets(for: .nudge, reduceMotion: false).first?.parameters
      == SpringPreset.springy.parameters)
  }

  @Test func reduceMotionNudgeDipsTheFrameToAboutSixtyPercentWithoutScale() {
    var springs = LittleArktSpringSet(scene: .rest)
    springs.apply(LittleArktMotion.targets(for: .nudge, reduceMotion: true), at: 0)
    let samples = stride(from: 0.0, through: 0.4, by: 0.005).map { springs.scene(at: $0) }
    let lowest = samples.map { $0[.opacity] }.min() ?? 1
    #expect(lowest > 0.55 && lowest < 0.65)
    #expect(samples.allSatisfy { $0[.scale] == 1 && $0[.lift] == 0 })
    #expect(springs.scene(at: 30) == .rest)
  }

  @Test func closeShrinksToNinetySevenAndFades() {
    let end = settle(.rest, .close, reduce: false)
    #expect(end[.scale] == 0.97 && end[.opacity] == 0)
    #expect(LittleArktMotion.targets(for: .close, reduceMotion: false).allSatisfy {
      $0.parameters == SpringPreset.firmFast.parameters
    })
    let reduced = settle(.rest, .close, reduce: true)
    #expect(reduced[.scale] == 1 && reduced[.opacity] == 0)
  }

  @Test func fadeOutIsTwelveHundredthsInBothModes() {
    for reduce in [false, true] {
      let targets = LittleArktMotion.targets(for: .fadeOut, reduceMotion: reduce)
      #expect(targets.map(\.channel) == [.opacity])
      #expect(targets.first?.parameters == SpringParameters(dampingRatio: 1, response: 0.12))
    }
  }

  @Test func aCloseDuringTheAppearPicksUpFromTheCurrentValues() {
    var springs = LittleArktSpringSet(scene: LittleArktMotion.appearStart(reduceMotion: false))
    springs.apply(LittleArktMotion.targets(for: .appear, reduceMotion: false), at: 0)
    let mid = springs.scene(at: 0.04)
    springs.apply(LittleArktMotion.targets(for: .close, reduceMotion: false), at: 0.04)
    let after = springs.scene(at: 0.041)
    #expect(abs(after[.scale] - mid[.scale]) < 0.01)
    #expect(abs(after[.opacity] - mid[.opacity]) < 0.05)
    #expect(springs.scene(at: 30)[.opacity] == 0)
  }
}
