import CoreGraphics
import Motion

/// The hover reveal's motion (BH-004, GS-018), as pure math. The overlay's position is one scalar, `offset`: points
/// from its resting place, 0 revealed and `concealedOffset` (negative) fully off the window's left edge. A spring
/// drives it, so a reveal turned around mid-flight carries its velocity into the conceal.
///
/// Per frame only the overlay layer's transform and opacity change; its view frame stays put, so AppKit never
/// relayouts, redisplays or rebuilds tracking areas under it while it moves.
public enum SidebarRevealMotion {
  /// Entry: a firm spring with no visible bounce, for a panel the pointer is aiming at.
  /// PARITY(NEEDS-RUNTIME-CHECK RT-10): Arc's reveal curve.
  public static let revealPreset = SpringPreset.firm
  /// Exit is quicker than entry: the pointer has already moved on.
  public static let concealPreset = SpringPreset.firmFast
  /// Blur radius of the overlay's shadow; the concealed overlay clears it too.
  public static let shadowRadius: CGFloat = 12

  /// Offset at which the overlay and its shadow are fully off the window's left edge.
  public static func concealedOffset(overlayFrame: CGRect) -> CGFloat {
    -(overlayFrame.maxX + 2 * shadowRadius)
  }

  /// What one frame presents for `offset` on a `distance`-point travel (`-concealedOffset`).
  /// - Full motion: the overlay slides, pixel-aligned at `scale` so text stays sharp, at full opacity. An overshoot
  ///   past the resting place is clamped so no gap opens at the window's left edge.
  /// - Reduce Motion: no movement; the overlay fades in place.
  /// `progress` is 0 concealed to 1 revealed either way (it fades the traffic lights).
  public static func presentation(offset: CGFloat, distance: CGFloat, reduceMotion: Bool,
                                  scale: CGFloat) -> (translation: CGFloat, alpha: CGFloat, progress: CGFloat) {
    let progress = distance > 0 ? min(max(1 + offset / distance, 0), 1) : 1
    if reduceMotion { return (0, progress, progress) }
    let scale = max(scale, 1)
    let translation = (min(offset, 0) * scale).rounded() / scale
    return (translation == 0 ? 0 : translation, 1, progress)
  }
}
