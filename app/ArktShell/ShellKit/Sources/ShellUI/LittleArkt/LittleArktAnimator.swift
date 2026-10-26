import AppKit
import os
import Motion
import QuartzCore

/// Runs a `LittleArktSpringSet` on a view's display link and hands every frame's scene to `onFrame`. A new run
/// retargets the springs from where they are (value and velocity), so every transition is interruptible; the
/// interrupted run's completion gets `false`. Without a window there is no display: the run settles at once.
@MainActor
final class LittleArktAnimator {
  private(set) var springs: LittleArktSpringSet
  private let now: @MainActor () -> CFTimeInterval
  var onFrame: (@MainActor (LittleArktScene) -> Void)?
  private var link: CADisplayLink?
  private var completion: ((Bool) -> Void)?
  private var generation = 0
  private var interval: OSSignpostIntervalState?

  var isRunning: Bool { link != nil }

  init(scene: LittleArktScene, now: @escaping @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }) {
    springs = LittleArktSpringSet(scene: scene)
    self.now = now
  }

  isolated deinit {
    link?.invalidate()
  }

  var currentScene: LittleArktScene { springs.scene(at: now()) }

  /// Stops any run (its completion gets false) and shows `scene` at once.
  func jump(to scene: LittleArktScene) {
    finish(completed: false)
    springs.jump(to: scene)
    onFrame?(scene)
  }

  func run(_ targets: [LittleArktTarget], label: StaticString, in view: NSView,
           completion: ((Bool) -> Void)? = nil) {
    finish(completed: false)
    springs.apply(targets, at: now())
    self.completion = completion ?? { _ in }
    generation += 1
    interval = ShellSignposts.signposter.beginInterval("LittleArkt", "\(label, privacy: .public)")
    guard view.window != nil else {
      settleNow()
      return
    }
    let target = LittleArktLinkTarget { [weak self] link in self?.tick(link) }
    let link = view.displayLink(target: target, selector: #selector(LittleArktLinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
    onFrame?(springs.scene(at: now()))
  }

  /// Jumps to the settled end of the current run and completes it (tests, and runs without a display).
  func settleNow() {
    let end = springs.scene(at: now() + 30)
    springs.jump(to: end)
    onFrame?(end)
    finish(completed: true)
  }

  private func tick(_ link: CADisplayLink) {
    guard link === self.link else { link.invalidate(); return }
    let t = link.targetTimestamp
    let token = generation
    onFrame?(springs.scene(at: t))
    guard token == generation else { return }     // onFrame started another run
    if springs.isSettled(at: t) { finish(completed: true) }
  }

  private func finish(completed: Bool) {
    link?.invalidate()
    link = nil
    if let interval { ShellSignposts.signposter.endInterval("LittleArkt", interval) }
    interval = nil
    let done = completion
    completion = nil
    done?(completed)
  }
}

/// Display-link target that does not retain the animator.
@MainActor
private final class LittleArktLinkTarget: NSObject {
  let onTick: @MainActor (CADisplayLink) -> Void
  init(_ onTick: @escaping @MainActor (CADisplayLink) -> Void) { self.onTick = onTick }
  @objc func tick(_ link: CADisplayLink) { onTick(link) }
}
