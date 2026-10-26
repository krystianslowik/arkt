import AppKit
import os
import QuartzCore

/// Drives a scalar along a spring on the view's display link. Interruptible: `stop()` returns the
/// last presented value and its velocity so a new gesture can continue from exactly where the spring was.
///
/// Callbacks may re-enter: calling `animate` (or `stop`) from `onUpdate` or `completion` is safe, and a
/// run started there is not cancelled by the run that invoked the callback.
///
/// Chains are bounded: a completion that always starts another run cannot recurse or loop forever.
/// Immediate-path completions nest at most `maxImmediateDepth` deep, and stopping a run whose
/// completion keeps restarting gives up after `maxStopPasses`; both cut-offs drop the remaining
/// completion and log a fault.
@MainActor
public final class SpringDriver {
  /// Deepest chain of synchronous (immediate-path) completions that start another immediate run.
  public static let maxImmediateDepth = 16
  /// Most runs `stopAll` stops in a row when interrupted completions keep starting new ones.
  public static let maxStopPasses = 16
  private static let logger = Logger(subsystem: "dev.arkt.shell", category: "motion")
  /// DEBUG builds stop at an `assertionFailure` when a chain is cut off (a caller bug). Tests that
  /// exercise the cut-off on purpose turn this off.
  static var assertsOnDroppedCompletion = true

  private let now: @MainActor () -> CFTimeInterval
  private let reduceMotion: @MainActor () -> Bool
  private(set) var link: CADisplayLink?
  private var run: SpringRun?
  private var lastTime: CFTimeInterval = 0
  /// Bumped whenever a run ends; a callback that started or stopped a run changes it.
  private var generation = 0
  private var onUpdate: ((Double) -> Void)?
  private var completion: ((Bool) -> Void)?
  private var immediateDepth = 0

  public var isRunning: Bool { run != nil }

  /// Tests turn this off to step a run by hand with `tick(at:)`: `animate` then sets the run up without a display
  /// link, so what a test reads does not depend on how long the machine took to get there.
  var drivesDisplayLink = true

  public init(now: @escaping @MainActor () -> CFTimeInterval = { CACurrentMediaTime() },
              reduceMotion: @escaping @MainActor () -> Bool = {
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
              }) {
    self.now = now
    self.reduceMotion = reduceMotion
  }

  isolated deinit {
    link?.invalidate()
  }

  /// Animates `from` -> `to` on `view`'s display link. Any running animation is stopped first
  /// (its completion gets `false`).
  ///
  /// Immediate path: if Reduce Motion is on or `view` has no window (no display to drive), this calls
  /// `onUpdate(to)` and then `completion(true)` synchronously, before `animate` returns.
  ///
  /// Chains: a completion may start another run, but a completion that always restarts is cut off
  /// after `maxImmediateDepth` nested immediate completions (or `maxStopPasses` restarts from
  /// interrupted completions). The cut-off drops that completion, logs a fault and, in DEBUG,
  /// fails an assertion. Callers that loop on purpose must stop on their own condition.
  public func animate(in view: NSView, from: Double, to: Double, initialVelocity: Double,
                      parameters: SpringParameters, onUpdate: @escaping (Double) -> Void,
                      completion: ((Bool) -> Void)? = nil) {
    guard let window = view.window else {
      stopAll()
      finishImmediately(to: to, onUpdate: onUpdate, completion: completion)
      return
    }
    let threshold = 0.5 / max(window.backingScaleFactor, 1)   // half a device pixel, in points
    guard start(from: from, to: to, initialVelocity: initialVelocity, parameters: parameters,
                threshold: threshold, onUpdate: onUpdate, completion: completion) else { return }
    guard drivesDisplayLink else { return }
    let proxy = WeakTarget(driver: self)
    let link = view.displayLink(target: proxy, selector: #selector(WeakTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  /// Stops without completing (completion gets `false`). Returns the last presented value and the
  /// velocity at that frame, `(from, initialVelocity)` before the first frame, or nil if idle.
  @discardableResult
  public func stop() -> (value: Double, velocity: Double)? {
    guard let run else { return nil }
    let state = run.interrupt(at: lastTime)
    finish(completed: false)
    return state
  }

  /// Sets up a run without a display link. Returns false if it took the Reduce Motion path.
  @discardableResult
  func start(from: Double, to: Double, initialVelocity: Double, parameters: SpringParameters,
             threshold: Double, onUpdate: @escaping (Double) -> Void,
             completion: ((Bool) -> Void)?) -> Bool {
    stopAll()
    if reduceMotion() {
      finishImmediately(to: to, onUpdate: onUpdate, completion: completion)
      return false
    }
    let t0 = now()
    run = SpringRun(from: from, to: to, initialVelocity: initialVelocity, parameters: parameters,
                    start: t0, threshold: threshold)
    lastTime = t0
    self.onUpdate = onUpdate
    self.completion = completion
    return true
  }

  /// Presents the frame for `timestamp` (the display link's `targetTimestamp`).
  func tick(at timestamp: CFTimeInterval) {
    guard let run, let onUpdate else { return }
    let current = generation
    let frame = run.frame(at: timestamp)
    lastTime = timestamp
    onUpdate(frame.value)
    guard current == generation else { return }   // onUpdate stopped or replaced this run
    if frame.done { finish(completed: true) }
  }

  /// Jumps to `to` and completes synchronously, unless this is already `maxImmediateDepth` immediate
  /// completions deep (a completion that always restarts); then the chain ends without a completion.
  private func finishImmediately(to: Double, onUpdate: (Double) -> Void, completion: ((Bool) -> Void)?) {
    onUpdate(to)
    guard immediateDepth < Self.maxImmediateDepth else {
      Self.logger.fault("SpringDriver: immediate completion chain hit \(Self.maxImmediateDepth); dropped")
      #if DEBUG
      if Self.assertsOnDroppedCompletion { assertionFailure("SpringDriver: completion chain does not terminate") }
      #endif
      return
    }
    immediateDepth += 1
    defer { immediateDepth -= 1 }
    completion?(true)
  }

  /// Stops until idle, in case a completion handler started another run. After `maxStopPasses`
  /// the remaining run is dropped without calling its completion.
  private func stopAll() {
    var passes = 0
    while isRunning {
      guard passes < Self.maxStopPasses else {
        Self.logger.fault("SpringDriver: interrupted completions restarted \(Self.maxStopPasses) times; dropped")
        #if DEBUG
        if Self.assertsOnDroppedCompletion { assertionFailure("SpringDriver: interrupted completions keep restarting") }
        #endif
        completion = nil
        finish(completed: false)
        return
      }
      passes += 1
      stop()
    }
  }

  private func finish(completed: Bool) {
    link?.invalidate(); link = nil
    run = nil
    generation += 1
    let done = completion
    onUpdate = nil; completion = nil
    done?(completed)
  }
}

/// Display-link target that does not retain the driver (CADisplayLink retains its target). If the
/// driver is gone or the link is stale, the link invalidates itself.
@MainActor
private final class WeakTarget: NSObject {
  weak var driver: SpringDriver?

  init(driver: SpringDriver) { self.driver = driver }

  @objc func tick(_ link: CADisplayLink) {
    guard let driver, driver.link === link else { link.invalidate(); return }
    driver.tick(at: link.targetTimestamp)
  }
}
