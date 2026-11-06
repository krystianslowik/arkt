import AppKit

/// The reorder tick (BH-024). One alignment haptic when the drop point settles on a new slot, played now, and
/// none when reordering haptics are off. The same slot, or a point that is not a slot, plays nothing.
public enum ReorderHaptic {
  public static let pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment
  /// With the preview update on this same turn. The theme creator uses the same time (design/theme-creator).
  public static let performanceTime: NSHapticFeedbackManager.PerformanceTime = .now

  public static func cue(enabled: Bool, slotChanged: Bool, hasSlot: Bool) -> NSHapticFeedbackManager.FeedbackPattern? {
    guard enabled, slotChanged, hasSlot else { return nil }
    return pattern
  }
}
