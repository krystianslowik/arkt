import AppKit
import os
import QuartzCore

/// Runs a `PeekSpringSet` on a view's display link and hands every frame's scene to `onFrame`. A new run retargets
/// the springs from where they are (position and velocity), so every transition is interruptible; the interrupted
/// run's completion gets `false`. Each run is a `FramePacer` session and a Points of Interest interval
/// (`ShellSignposts`), so its pacing can be gated and seen in Instruments.
@MainActor
final class PeekAnimator {
  private(set) var springs: PeekSpringSet
  private let now: @MainActor () -> CFTimeInterval
  var onFrame: (@MainActor (PeekScene) -> Void)?
  private var link: CADisplayLink?
  private var completion: ((Bool) -> Void)?
  private var label = ""
  private var interval: OSSignpostIntervalState?
  private var generation = 0
  let pacer = FramePacer()
  private var pacerSession = 0
  /// Pacing of the last run that finished on the display.
  private(set) var lastPacing: FrameStats?
  private(set) var lastLabel = ""

  /// Tests turn this off to step a run by hand: `run` then applies its first frame and waits for `settleNow`, with
  /// no display link, so what a test reads does not depend on how long the machine took to get there.
  var drivesDisplayLink = true

  var isRunning: Bool { completion != nil || link != nil }

  init(scene: PeekScene, now: @escaping @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }) {
    springs = PeekSpringSet(scene: scene)
    self.now = now
  }

  isolated deinit {
    link?.invalidate()
  }

  /// The scene being presented now.
  var currentScene: PeekScene { springs.scene(at: now()) }

  /// Stops any run (its completion gets false) and shows `scene` at once: drag frames, a jump.
  func jump(to scene: PeekScene) {
    finish(completed: false)
    springs.jump(to: scene)
    onFrame?(scene)
  }

  /// Retargets the springs now and runs them on `view`'s display link until they settle. Without a window there is
  /// no display: the run settles at once.
  func run(_ targets: [PeekTarget], label: String, in view: NSView, completion: ((Bool) -> Void)? = nil) {
    finish(completed: false)
    springs.apply(targets, at: now())
    self.completion = completion ?? { _ in }
    self.label = label
    generation += 1
    interval = ShellSignposts.signposter.beginInterval("Peek", "\(label, privacy: .public)")
    guard drivesDisplayLink, view.window != nil else {
      if !drivesDisplayLink { onFrame?(springs.scene(at: now())); return }
      settleNow()
      return
    }
    pacerSession = pacer.begin("peek-\(label)", in: view)
    let link = view.displayLink(target: PeekLinkTarget(animator: self), selector: #selector(PeekLinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
    onFrame?(springs.scene(at: now()))
  }

  /// Jumps to the settled end of the current run and completes it (tests, and runs without a display).
  func settleNow() {
    let end = springs.scene(at: now() + SpringParametersHorizon.seconds)
    springs.jump(to: end)
    onFrame?(end)
    finish(completed: true)
  }

  fileprivate func tick(_ link: CADisplayLink) {
    guard link === self.link else { link.invalidate(); return }
    let t = link.targetTimestamp
    let scene = springs.scene(at: t)
    let token = generation
    onFrame?(scene)
    guard token == generation else { return }     // onFrame started another run
    if springs.isSettled(at: t) { finish(completed: true) }
  }

  private func finish(completed: Bool) {
    link?.invalidate()
    link = nil
    if let stats = pacer.end(session: pacerSession), completed {
      lastPacing = stats
      lastLabel = label
    }
    if let interval { ShellSignposts.signposter.endInterval("Peek", interval) }
    interval = nil
    let done = completion
    completion = nil
    done?(completed)
  }
}

/// Beyond any Peek spring's settling time.
private enum SpringParametersHorizon {
  static let seconds = 30.0
}

/// Display-link target that does not retain the animator.
@MainActor
private final class PeekLinkTarget: NSObject {
  weak var animator: PeekAnimator?
  init(animator: PeekAnimator) { self.animator = animator }
  @objc func tick(_ link: CADisplayLink) {
    guard let animator else { link.invalidate(); return }
    animator.tick(link)
  }
}
