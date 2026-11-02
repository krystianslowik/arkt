import AppKit
import Motion
import os
import QuartzCore

/// The bar widening from 680 to 968 pt, and back, on an interruptible spring (#372, design Motion).
///
/// The drawn width is a mask plus a transform of the field row's trailing controls. `presentFrame` only reports
/// that width: it does not lay out. The live panel is resized when the widen starts and once the narrow spring
/// rests, so the list's leading edge never moves. Up or Down retargets from the current width. Reduce Motion
/// snaps the width; the column still fades its content on its own.
@MainActor
final class CommandBarWidthMotion {
  static let parameters = SpringPreset.firmFast.parameters

  private enum Key: Hashable, Sendable { case width }

  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Off in tests, which present frames on their own clock with `presentFrame()`.
  var drivesFramesItself = true
  /// Each presented width, including the width the spring starts from.
  var onFrame: (@MainActor (Double) -> Void)?
  /// The width the spring landed on. Reduce Motion calls it at once.
  var onSettled: (@MainActor (Double) -> Void)?

  private var field = SpringField<Key>()
  private var target = CommandBarGeometry.preferredWidth
  private var resting = CommandBarGeometry.preferredWidth
  private var link: CADisplayLink?
  private var signpost: OSSignpostIntervalState?

  var isRunning: Bool { !field.keys.isEmpty }
  var isSignpostOpen: Bool { signpost != nil }

  /// The width to draw now. At rest this is the last target.
  var width: Double {
    field.value(of: .width, at: now()) ?? resting
  }

  isolated deinit { link?.invalidate() }

  /// Sends the width toward `newWidth`, continuing a run already in flight. `from` is where a new run starts
  /// (the width on screen). A target it already has does not restart the spring.
  func retarget(to newWidth: Double, from: Double, in view: NSView? = nil) {
    if reduceMotion() {
      finish(at: newWidth)
      return
    }
    if isRunning, let current = field.target(of: .width), abs(current - newWidth) < 0.5 { return }
    if !isRunning, abs(from - newWidth) < 0.5 {
      resting = newWidth
      target = newWidth
      return
    }
    target = newWidth
    beginSignpostIfNeeded()
    field.retarget(.width, to: newWidth, from: from, at: now(), parameters: Self.parameters)
    onFrame?(width)
    if let view { startLinkIfNeeded(in: view) }
  }

  /// Presents the frame for now. Once the spring has settled the motion ends. Does not lay out.
  func presentFrame() {
    guard isRunning else { return }
    if field.settledKeys(at: now()).count == field.keys.count {
      finish(at: target)
      return
    }
    onFrame?(width)
  }

  /// Ends the motion on its target (Reduce Motion).
  func settleNow() {
    guard isRunning else { return }
    finish(at: target)
  }

  /// Drops a run without landing it. The bar hides on its own fade and the next show picks the resting width.
  func stopWithoutSettling() {
    guard isRunning || signpost != nil else { return }
    field = SpringField()
    endSignpost()
    stopLinkIfIdle()
  }

  private func finish(at landed: Double) {
    field = SpringField()
    resting = landed
    target = landed
    endSignpost()
    onFrame?(landed)
    onSettled?(landed)
    stopLinkIfIdle()
  }

  private func beginSignpostIfNeeded() {
    guard signpost == nil else { return }
    signpost = ShellSignposts.signposter.beginInterval("CommandBarPreviewWidth")
  }

  private func endSignpost() {
    guard let signpost else { return }
    ShellSignposts.signposter.endInterval("CommandBarPreviewWidth", signpost)
    self.signpost = nil
  }

  private func startLinkIfNeeded(in view: NSView) {
    guard drivesFramesItself, link == nil else { return }
    let link = view.displayLink(target: CommandBarWidthMotionLinkTarget(motion: self),
                                selector: #selector(CommandBarWidthMotionLinkTarget.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  private func stopLinkIfIdle() {
    guard !isRunning else { return }
    link?.invalidate()
    link = nil
  }
}

/// Display-link target that does not retain the motion.
@MainActor
private final class CommandBarWidthMotionLinkTarget: NSObject {
  weak var motion: CommandBarWidthMotion?
  init(motion: CommandBarWidthMotion) { self.motion = motion }
  @objc func tick(_ link: CADisplayLink) {
    guard let motion else { link.invalidate(); return }
    motion.presentFrame()
  }
}
