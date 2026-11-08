#if DEBUG
import AppKit
import ShellUI

/// A noninteractive accessibility-only child; it never changes the root's existing accessibility children.
@MainActor
final class SessionObservationView: NSView {
  private let observation: WindowSessionObservation

  init(observation: WindowSessionObservation) {
    self.observation = observation
    super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityIdentifier("arkt.ui-test.window-session-observation")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func accessibilityValue() -> Any? { try? observation.snapshot.json() }
}
#endif
