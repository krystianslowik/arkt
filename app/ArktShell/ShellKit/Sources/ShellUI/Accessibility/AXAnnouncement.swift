import AppKit

/// App-wide VoiceOver announcements for surfaces whose focus stays put while their content changes, such as a
/// results list driven from a text field (#608). Controllers keep an `announce` seam whose default is `post`, so tests
/// read what would be spoken without a VoiceOver session.
@MainActor
enum AXAnnouncement {
  /// The seam's shape: the words, and whether they interrupt (`.high`) or queue.
  typealias Poster = @MainActor (String, NSAccessibilityPriorityLevel) -> Void

  /// Posts `text` on the application element, which VoiceOver hears whatever window or element has focus.
  static func post(_ text: String, priority: NSAccessibilityPriorityLevel) {
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: priority.rawValue])
  }

  /// A selection move in a list whose focus stays in a field: it interrupts the previous move's words, so holding an
  /// arrow key speaks the row it lands on rather than queueing every row passed.
  static let selectionPriority = NSAccessibilityPriorityLevel.high
}
