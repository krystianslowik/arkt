import AppKit

/// The reorder tick (BH-024). One alignment haptic, played now, when the drop point settles on a new slot.
/// The same slot, a point that is not a slot, or the setting off, plays nothing.
public enum ReorderHaptic {
  public static let pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment
  public static let performanceTime: NSHapticFeedbackManager.PerformanceTime = .now

  public static func play(enabled: Bool, slotChanged: Bool, hasSlot: Bool,
                          performer: NSHapticFeedbackPerformer) {
    guard enabled, slotChanged, hasSlot else { return }
    performer.perform(pattern, performanceTime: performanceTime)
  }
}

/// The shared settings the browser windows read when a reorder settles. `AppSession` binds the one `AppSettings`.
/// A drag test replaces `SidebarOutlineDrop.playsReorderHaptics` instead.
@MainActor
public enum ReorderHapticGate {
  public static var enabled: () -> Bool = { true }

  public static func bind(_ settings: AppSettings) {
    enabled = { [weak settings] in settings?.playsReorderHaptics ?? true }
  }
}
