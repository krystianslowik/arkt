import AppKit
import XCTest

/// Steps a scripted interaction once per display frame, so a scripted swipe exercises the same
/// per-frame path (and the same pacing measurement) as a real trackpad gesture.
@MainActor
final class FrameScript: NSObject {
  private var link: CADisplayLink?
  private var remaining: Int
  private let step: @MainActor (CFTimeInterval) -> Void
  private let done: @MainActor () -> Void

  init(view: NSView, frames: Int, step: @escaping @MainActor (CFTimeInterval) -> Void,
       done: @escaping @MainActor () -> Void) {
    remaining = frames
    self.step = step
    self.done = done
    super.init()
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @objc private func tick(_ link: CADisplayLink) {
    guard remaining > 0 else { link.invalidate(); self.link = nil; done(); return }
    remaining -= 1
    step(link.timestamp)
  }
}

/// Waits on a display link until `count` consecutive frame intervals are within `threshold`, or until
/// `timeout` passes (then it gives up waiting and the measurement runs anyway; warm-up never fails a test).
@MainActor
final class StableFrames: NSObject {
  private var link: CADisplayLink?
  private let count: Int
  private let threshold: Double
  private let deadline: CFTimeInterval
  private var last: CFTimeInterval?
  private var stable = 0
  private var continuation: CheckedContinuation<Int, Never>?

  private init(view: NSView, count: Int, threshold: Double, timeout: Double) {
    self.count = count
    self.threshold = threshold
    self.deadline = CACurrentMediaTime() + timeout
    super.init()
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  /// Returns the stable run reached (`count` when the display settled before the timeout).
  static func wait(on view: NSView, count: Int, threshold: Double, timeout: Double = 2) async -> Int {
    let waiter = StableFrames(view: view, count: count, threshold: threshold, timeout: timeout)
    // A display link that never ticks (display asleep) must not hang the test: the measurement then reports it.
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(timeout + 0.5))
      waiter.finish()
    }
    return await withCheckedContinuation { waiter.continuation = $0 }
  }

  @objc private func tick(_ link: CADisplayLink) {
    if let last { stable = link.timestamp - last <= threshold ? stable + 1 : 0 }
    last = link.timestamp
    if stable >= count || link.timestamp >= deadline { finish() }
  }

  /// Stops the link and resumes the waiter once; later calls do nothing.
  private func finish() {
    link?.invalidate()
    link = nil
    continuation?.resume(returning: stable)
    continuation = nil
  }
}
