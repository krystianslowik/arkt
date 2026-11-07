import AppKit
import Motion
import QuartzCore

/// The spring that moves Favorite tiles when a sidebar resize changes the grid's column count (#337). Every tile's
/// slot (left edge, width and row, as shares of the row) runs on its own interruptible spring, so a resize that
/// crosses back mid-flight reverses from where each tile is, with its velocity. Slots are width independent, so tiles
/// in motion keep following a sidebar that is still being dragged.
///
/// Reduce Motion, a grid off screen and structure changes never reach it (the grid applies those at once). Driven by
/// the grid's display link; tests present frames on their own clock with `presentFrame()`.
@MainActor
final class FavoritesColumnMotion {
  /// Rare (a resize across a column threshold) and spatial: a firm spring with no visible overshoot, about 0.3 s,
  /// the same feel as folders opening (#109).
  static let parameters = SpringPreset.firm.parameters

  private enum Component: Hashable, Sendable { case left, width, row }

  private struct Key: Hashable, Sendable {
    var item: Int
    var component: Component
  }

  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Off in tests, which present frames on their own clock with `presentFrame()`.
  var drivesFramesItself = true
  /// Each presented frame, and once more when the motion ends.
  var onFrame: (@MainActor () -> Void)?

  private var field = SpringField<Key>()
  private var link: CADisplayLink?

  var isRunning: Bool { !field.keys.isEmpty }

  isolated deinit { link?.invalidate() }

  /// Whether a column change in `view` may move: on screen, and Reduce Motion off.
  func canAnimate(in view: NSView) -> Bool {
    guard let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor else { return false }
    return !reduceMotion()
  }

  /// Sends items `0..<itemCount` to their slots in `columns`. An item already in motion continues from where it is;
  /// the others start from their slots in `oldColumns`.
  func run(itemCount: Int, from oldColumns: Int, to columns: Int, in view: NSView) {
    let t = now()
    for item in 0..<itemCount {
      let from = FavoritesLayout.slot(ofItem: item, columns: oldColumns)
      let to = FavoritesLayout.slot(ofItem: item, columns: columns)
      field.retarget(Key(item: item, component: .left), to: to.left, from: from.left, at: t,
                     parameters: Self.parameters)
      field.retarget(Key(item: item, component: .width), to: to.width, from: from.width, at: t,
                     parameters: Self.parameters)
      field.retarget(Key(item: item, component: .row), to: to.row, from: from.row, at: t,
                     parameters: Self.parameters)
    }
    startLinkIfNeeded(in: view)
  }

  /// Where `item` draws now; nil when it is not in motion (it sits in its grid slot).
  func slot(ofItem item: Int) -> FavoritesLayout.Slot? {
    let t = now()
    guard let left = field.value(of: Key(item: item, component: .left), at: t),
          let width = field.value(of: Key(item: item, component: .width), at: t),
          let row = field.value(of: Key(item: item, component: .row), at: t) else { return nil }
    return FavoritesLayout.Slot(left: left, width: width, row: row)
  }

  /// Presents the frame for now; once every spring has settled the motion ends and the tiles sit in their slots.
  func presentFrame() {
    if field.settledKeys(at: now()).count == field.keys.count { field = SpringField() }
    onFrame?()
    stopLinkIfIdle()
  }

  /// Ends the motion with every tile in its slot (a structure change, Reduce Motion, the grid leaving the screen).
  func settleNow() {
    guard isRunning else { return }
    field = SpringField()
    onFrame?()
    stopLinkIfIdle()
  }

  private func startLinkIfNeeded(in view: NSView) {
    guard drivesFramesItself, link == nil else { return }
    let link = view.displayLink(target: FavoritesColumnMotionLinkTarget(motion: self),
                                selector: #selector(FavoritesColumnMotionLinkTarget.tick(_:)))
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
private final class FavoritesColumnMotionLinkTarget: NSObject {
  weak var motion: FavoritesColumnMotion?
  init(motion: FavoritesColumnMotion) { self.motion = motion }
  @objc func tick(_ link: CADisplayLink) {
    guard let motion else { link.invalidate(); return }
    motion.presentFrame()
  }
}
