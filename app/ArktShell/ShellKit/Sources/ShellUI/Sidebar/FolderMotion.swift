import AppKit
import Motion
import QuartzCore

/// Where every sidebar row draws while folders open and close (#109): the rows that come and go slide in under the
/// folder row and fade, and every row below them follows by the height still missing. Pure math over row indexes;
/// the outline turns the result into layer transforms, never frames.
enum FolderMotionLayout {
  struct RowStyle: Equatable, Sendable {
    /// Points along the outline's flipped y axis: negative moves the row up.
    var offsetY: CGFloat
    var alpha: CGFloat
    /// About the row's center: a row arriving from Little Arkt's Open in grows from 0.96 (#352).
    var scale: CGFloat = 1
    /// The selection fill's layer opacity: 1 at rest, 0 when the old selection has faded for Little Arkt's arrival
    /// (#455). The row's text, favicon and hover X are not faded.
    var selectionAlpha: CGFloat = 1

    static let rest = RowStyle(offsetY: 0, alpha: 1)
  }

  /// One folder's spring: the rows it shows and hides, and how far open it is (1 open, 0 closed; a spring may
  /// overshoot a little).
  struct Transition: Equatable, Sendable {
    var changingRows: Set<Int>
    var progress: Double
  }

  /// A row moves up by the missing share of the changing rows above it, for every folder in motion; a changing row
  /// fades with its folder's progress.
  static func styles(rowHeights: [CGFloat], transitions: [Transition]) -> [RowStyle] {
    var styles = Array(repeating: RowStyle.rest, count: rowHeights.count)
    for transition in transitions {
      let missing = CGFloat(1 - transition.progress)
      let alpha = CGFloat(min(max(transition.progress, 0), 1))
      var goneAbove: CGFloat = 0
      for row in rowHeights.indices {
        styles[row].offsetY -= missing * goneAbove
        if transition.changingRows.contains(row) {
          styles[row].alpha *= alpha
          goneAbove += rowHeights[row]
        }
      }
    }
    return styles
  }
}

/// The springs of the folders opening and closing in one outline: one interruptible spring per folder, from 0 (its
/// changing rows hidden) to 1 (shown), on the outline's display link. A new target for a folder in motion continues
/// from where it is, with its velocity, so a second click mid-close reverses without a jump.
///
/// Keyboard toggles and Reduce Motion never reach it (the outline applies those at once); a page that is not on
/// screen settles at once as well.
@MainActor
final class FolderMotion {
  /// Folder toggles happen tens of times a day: a firm spring with no visible overshoot, settled in about 0.3 s.
  static let parameters = SpringPreset.firm.parameters

  var now: @MainActor () -> CFTimeInterval = { CACurrentMediaTime() }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  /// Off in tests, which present frames on their own clock with `presentFrame()`.
  var drivesFramesItself = true
  /// Each frame: every folder in motion with its progress.
  var onFrame: (@MainActor ([NodeID: Double]) -> Void)?
  /// A folder's spring settled; `open` is where it came to rest.
  var onSettle: (@MainActor (_ folder: NodeID, _ open: Bool) -> Void)?

  private var field = SpringField<NodeID>()
  /// The rows each folder in motion shows and hides.
  private(set) var changing: [NodeID: Set<NodeID>] = [:]
  private var link: CADisplayLink?

  var isRunning: Bool { !field.keys.isEmpty }

  isolated deinit { link?.invalidate() }

  /// Whether a toggle in `view` may move: on screen, and Reduce Motion off.
  func canAnimate(in view: NSView) -> Bool {
    guard let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor else { return false }
    return !reduceMotion()
  }

  func isMoving(_ folder: NodeID) -> Bool { field.keys.contains(folder) }

  /// Sends `folder` open (1) or closed (0). A folder already in motion continues from where it is; a new one starts
  /// from the other end. `changing` replaces the rows it moves.
  func run(_ folder: NodeID, open: Bool, changing rows: Set<NodeID>, in view: NSView) {
    field.retarget(folder, to: open ? 1 : 0, from: open ? 0 : 1, at: now(), parameters: Self.parameters)
    changing[folder] = rows
    startLinkIfNeeded(in: view)
  }

  /// Drops `folder` from the motion with no settle callback (it left the outline).
  func cancel(_ folder: NodeID) {
    field.remove(folder)
    changing[folder] = nil
    stopLinkIfIdle()
  }

  /// The progress of every folder in motion now.
  func progress() -> [NodeID: Double] {
    let t = now()
    var values: [NodeID: Double] = [:]
    for folder in field.keys { values[folder] = field.value(of: folder, at: t) }
    return values
  }

  /// Presents the frame for now: settled folders call `onSettle` and leave, then `onFrame` gets the rest.
  func presentFrame() {
    let t = now()
    for folder in field.settledKeys(at: t) {
      let open = (field.target(of: folder) ?? 1) > 0.5
      field.remove(folder)
      changing[folder] = nil
      onSettle?(folder, open)
    }
    onFrame?(progress())
    stopLinkIfIdle()
  }

  /// Ends every spring at its target (a page leaving the screen, tests).
  func settleNow() {
    for folder in field.keys {
      let open = (field.target(of: folder) ?? 1) > 0.5
      field.remove(folder)
      changing[folder] = nil
      onSettle?(folder, open)
    }
    onFrame?([:])
    stopLinkIfIdle()
  }

  private func startLinkIfNeeded(in view: NSView) {
    guard drivesFramesItself, link == nil else { return }
    let link = view.displayLink(target: FolderMotionLinkTarget(motion: self),
                                selector: #selector(FolderMotionLinkTarget.tick(_:)))
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
private final class FolderMotionLinkTarget: NSObject {
  weak var motion: FolderMotion?
  init(motion: FolderMotion) { self.motion = motion }
  @objc func tick(_ link: CADisplayLink) {
    guard let motion else { link.invalidate(); return }
    motion.presentFrame()
  }
}
