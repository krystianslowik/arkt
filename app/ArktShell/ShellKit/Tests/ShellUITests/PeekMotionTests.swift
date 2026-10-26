import CoreGraphics
import Motion
import Testing
@testable import ShellUI

/// Peek motion as pure functions of time (docs/design/peek.md, Motion).
struct PeekMotionTests {
  static let link = CGVector(dx: -300, dy: -200)

  private func settled(_ set: PeekSpringSet) -> PeekScene { set.scene(at: 100) }

  // MARK: Open

  @Test func openStartsThirtyPercentTowardsTheLinkSmallAndTransparent() {
    let start = PeekMotion.openStart(linkOffset: Self.link, reduceMotion: false)
    #expect(abs(start[.cardX] - -90) < 1e-9 && abs(start[.cardY] - -60) < 1e-9)
    #expect(start[.cardScale] == 0.90 && start[.cardOpacity] == 0)
    #expect(start[.scrim] == 0 && start[.recede] == 1 && start[.controls] == 0 && start[.grabber] == 0)
  }

  @Test func openSettlesAtRest() {
    var set = PeekSpringSet(scene: PeekMotion.openStart(linkOffset: Self.link, reduceMotion: false))
    set.apply(PeekMotion.targets(for: .open, reduceMotion: false), at: 0)
    #expect(settled(set) == .rest)
    #expect(set.isSettled(at: 2))
    #expect(!set.isSettled(at: 0.05))
  }

  @Test func openUsesTheDesignPresetsAndDelays() {
    let targets = PeekMotion.targets(for: .open, reduceMotion: false)
    func target(_ c: PeekChannel) -> PeekTarget? { targets.first { $0.channel == c } }
    #expect(target(.cardY)?.parameters == SpringPreset.firmSlow.parameters)
    #expect(target(.recede)?.value == PeekMotion.recededScale)
    #expect(target(.controls)?.parameters == SpringPreset.springyFast.parameters)
    #expect(target(.controls)?.delay == 0.07)
    #expect(target(.grabber)?.delay == 0.11)
    #expect(target(.cardOpacity)?.parameters == SpringParameters(dampingRatio: 1, response: 0.16))
  }

  @Test func controlsHoldUntilTheirDelay() {
    var set = PeekSpringSet(scene: PeekMotion.openStart(linkOffset: Self.link, reduceMotion: false))
    set.apply(PeekMotion.targets(for: .open, reduceMotion: false), at: 0)
    #expect(set.scene(at: 0.06)[.controls] == 0)
    #expect(set.scene(at: 0.15)[.controls] > 0)
  }

  // MARK: Interruption

  @Test func anEscDuringTheOpenRetargetsFromTheCurrentPositionAndVelocity() {
    var set = PeekSpringSet(scene: PeekMotion.openStart(linkOffset: Self.link, reduceMotion: false))
    set.apply(PeekMotion.targets(for: .open, reduceMotion: false), at: 0)
    let before = set.scene(at: 0.12)
    let velocity = set.velocity(of: .cardY, at: 0.12)
    set.apply(PeekMotion.targets(for: .closeInPlace, reduceMotion: false), at: 0.12)
    let after = set.scene(at: 0.12)
    #expect(abs(after[.cardY] - before[.cardY]) < 1e-6, "no jump")
    #expect(abs(set.velocity(of: .cardY, at: 0.12) - velocity) < 1e-6, "velocity carried")
    #expect(settled(set)[.cardOpacity] == 0)
    #expect(settled(set)[.cardScale] == 0.97)
  }

  @Test func closeTowardsTheLinkEndsSmallAndTransparent() {
    var set = PeekSpringSet(scene: .rest)
    set.apply(PeekMotion.targets(for: .close(linkOffset: Self.link), reduceMotion: false), at: 0)
    let end = settled(set)
    #expect(end[.cardOpacity] == 0 && end[.cardScale] == 0.92 && end[.scrim] == 0 && end[.recede] == 1)
    #expect(abs(end[.cardX] - -90) < 1e-9)
  }

  // MARK: Drag

  @Test func dragFollowsDownOneToOneAndScalesAndFades() {
    let scene = PeekMotion.dragScene(offset: 150, reduceMotion: false)
    #expect(scene[.cardY] == 150)
    #expect(abs(scene[.cardScale] - 0.97) < 1e-9)
    #expect(abs(scene[.scrim] - 0.625) < 1e-9)
    #expect(scene[.controls] == 0 && scene[.grabber] == 0)
    let far = PeekMotion.dragScene(offset: 600, reduceMotion: false)
    #expect(far[.cardScale] == 0.94 && far[.scrim] == 0.25)
  }

  @Test func dragUpwardIsRubberBanded() {
    let scene = PeekMotion.dragScene(offset: -100, reduceMotion: false)
    #expect(abs(scene[.cardY] - -pow(100, 0.7)) < 1e-9)
    #expect(scene[.cardScale] == 1 && scene[.scrim] == 1)
  }

  @Test func controlsFadeWithinTheFirstSixtyPoints() {
    #expect(abs(PeekMotion.dragScene(offset: 30, reduceMotion: false)[.controls] - 0.5) < 1e-9)
  }

  @Test(arguments: [(130.0, 0.0, true), (100.0, 900.0, true), (100.0, 500.0, false), (-50.0, 1200.0, true),
                    (119.0, 799.0, false)])
  func releaseDismissesPastTheDistanceOrSpeed(offset: Double, velocity: Double, dismiss: Bool) {
    #expect(PeekMotion.releaseDismisses(offset: offset, velocity: velocity) == dismiss)
  }

  @Test func aFlingCarriesTheReleaseVelocityAndEndsBelow() {
    var set = PeekSpringSet(scene: PeekMotion.dragScene(offset: 140, reduceMotion: false))
    set.apply(PeekMotion.targets(for: .fling(velocity: 1500), reduceMotion: false), at: 0)
    #expect(abs(set.velocity(of: .cardY, at: 0) - 1500) < 1e-6)
    let end = settled(set)
    #expect(end[.cardY] == 520 && end[.cardOpacity] == 0 && end[.cardScale] == 0.90)
  }

  @Test func aSnapBackKeepsTheVelocityAndBouncesOnce() {
    var set = PeekSpringSet(scene: PeekMotion.dragScene(offset: 80, reduceMotion: false))
    set.apply(PeekMotion.targets(for: .snapBack(velocity: -400), reduceMotion: false), at: 0)
    #expect(abs(set.velocity(of: .cardY, at: 0) - -400) < 1e-6)
    let samples = stride(from: 0.0, through: 0.6, by: 0.004).map { set.scene(at: $0)[.cardY] }
    #expect(samples.contains { $0 < -0.5 }, "springy overshoots past rest")
    #expect(settled(set) == .rest)
  }

  // MARK: Expand and split

  @Test func expandGrowsTheMaskAndClearsTheChrome() {
    var set = PeekSpringSet(scene: .rest)
    set.apply(PeekMotion.targets(for: .expand, reduceMotion: false), at: 0)
    let end = settled(set)
    #expect(end[.expand] == 1 && end[.scrim] == 0 && end[.controls] == 0 && end[.recede] == 1)
    #expect(end[.cardOpacity] == 1)
  }

  // MARK: Reduce Motion

  @Test func reduceMotionOpensWithAFadeOnly() {
    let start = PeekMotion.openStart(linkOffset: Self.link, reduceMotion: true)
    #expect(start[.cardX] == 0 && start[.cardY] == 0 && start[.cardScale] == 1 && start[.cardOpacity] == 0)
    let targets = PeekMotion.targets(for: .open, reduceMotion: true)
    #expect(Set(targets.map(\.channel)).isDisjoint(with: [.cardX, .cardY, .cardScale, .recede]))
    var set = PeekSpringSet(scene: start)
    set.apply(targets, at: 0)
    #expect(settled(set) == PeekScene.rest.with(.recede, 1))
  }

  @Test func reduceMotionNeverRecedesTheSource() {
    #expect(PeekMotion.restScene(reduceMotion: true)[.recede] == 1)
  }

  @Test(arguments: [PeekTransition.close(linkOffset: CGVector(dx: 10, dy: 10)), .closeInPlace, .fling(velocity: 900)])
  func reduceMotionClosesWithAFadeOnly(transition: PeekTransition) {
    let targets = PeekMotion.targets(for: transition, reduceMotion: true)
    #expect(Set(targets.map(\.channel)).isDisjoint(with: [.cardX, .cardY, .cardScale]))
    #expect(targets.first { $0.channel == .cardOpacity }?.value == 0)
  }

  @Test func reduceMotionSnapsBackWithoutBounce() {
    let targets = PeekMotion.targets(for: .snapBack(velocity: 0), reduceMotion: true)
    #expect(targets.first { $0.channel == .cardY }?.parameters == SpringPreset.firm.parameters)
  }

  @Test func reduceMotionExpandFadesOutThenIn() {
    let out = PeekMotion.targets(for: .expand, reduceMotion: true)
    #expect(out.first { $0.channel == .cardOpacity }?.value == 0)
    #expect(!out.contains { $0.channel == .expand })
    let back = PeekMotion.targets(for: .fadeIn, reduceMotion: true)
    #expect(back.first { $0.channel == .cardOpacity }?.value == 1)
  }

  // MARK: Reopen (BH-150, #346)

  /// A reopened Peek opens at the same place, without the travel from the link: scale 0.96 and transparent at its
  /// frame, nothing around it yet.
  @Test func reopenStartsInPlaceSlightlySmallAndTransparent() {
    let start = PeekMotion.reopenStart(reduceMotion: false)
    #expect(start[.cardX] == 0 && start[.cardY] == 0)
    #expect(start[.cardScale] == 0.96 && start[.cardOpacity] == 0)
    #expect(start[.scrim] == 0 && start[.recede] == 1 && start[.controls] == 0 && start[.grabber] == 0)
    let reduced = PeekMotion.reopenStart(reduceMotion: true)
    #expect(reduced[.cardScale] == 1 && reduced[.cardOpacity] == 0)
  }

  /// The motion table's Reopen row: `firm` for the card and around it; the controls after 60 ms, the grabber after
  /// 90 ms (the prototype's values).
  @Test func reopenUsesFirmAndSettlesAtRest() {
    let targets = PeekMotion.targets(for: .reopen, reduceMotion: false)
    func target(_ c: PeekChannel) -> PeekTarget? { targets.first { $0.channel == c } }
    #expect(target(.cardScale)?.parameters == SpringPreset.firm.parameters)
    #expect(target(.scrim)?.parameters == SpringPreset.firm.parameters)
    #expect(target(.recede)?.value == PeekMotion.recededScale)
    #expect(target(.controls)?.delay == 0.06)
    #expect(target(.grabber)?.delay == 0.09)
    #expect(target(.cardX) == nil && target(.cardY) == nil, "no travel")
    var set = PeekSpringSet(scene: PeekMotion.reopenStart(reduceMotion: false))
    set.apply(targets, at: 0)
    #expect(settled(set) == .rest)
  }

  /// The keyframe `peek-kf-reopen-60ms`: on its way, still below full scale, more than half visible.
  @Test func reopenAtSixtyMillisecondsIsOnItsWay() {
    var set = PeekSpringSet(scene: PeekMotion.reopenStart(reduceMotion: false))
    set.apply(PeekMotion.targets(for: .reopen, reduceMotion: false), at: 0)
    let frame = set.scene(at: 0.06)
    #expect(frame[.cardScale] > 0.96 && frame[.cardScale] < 1)
    #expect(frame[.cardOpacity] > 0.3 && frame[.cardOpacity] < 1)
    #expect(frame[.controls] == 0)
  }

  @Test func reduceMotionReopensWithAFadeOnly() {
    let targets = PeekMotion.targets(for: .reopen, reduceMotion: true)
    #expect(Set(targets.map(\.channel)).isDisjoint(with: [.cardX, .cardY, .cardScale, .recede]))
    #expect(targets.first { $0.channel == .cardOpacity }?.parameters == SpringParameters(dampingRatio: 1, response: 0.20))
  }
}
