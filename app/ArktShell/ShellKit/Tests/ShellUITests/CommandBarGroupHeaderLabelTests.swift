import AppKit
import Testing
@testable import ShellUI

/// The command bar's group header element. An accessibility client (VoiceOver, a window manager) asks every view in
/// the window for its label and whether it is an element. A header without a published label once answered by asking
/// for its own label, which AppKit derives by asking whether it is an element: the stack overflowed and the app
/// crashed on launch.
@MainActor
struct CommandBarGroupHeaderLabelTests {
  @Test func aRowCellsHeaderIsNotAnElementAndAnswersWithoutRecursing() {
    let header = CommandBarGroupHeaderLabel(labelWithString: "")
    header.attributedStringValue = NSAttributedString(string: "Tabs")
    #expect(!header.isAccessibilityElement(), "a cell's visible header stays out of the tree")
    _ = header.accessibilityLabel()
    _ = header.accessibilityAttributeNames()
  }

  @Test func aHeaderWithoutAPublishedLabelIsNotAnElement() {
    let header = CommandBarGroupHeaderLabel(labelWithString: "Tabs")
    #expect(!header.isAccessibilityElement())
    _ = header.accessibilityLabel()
    _ = header.accessibilityAttributeNames()
  }

  @Test func aPublishedHeaderIsAGroupNamedByItsLabel() {
    let header = CommandBarGroupHeaderLabel(labelWithString: "")
    header.setAccessibilityLabel("Folders")
    #expect(header.isAccessibilityElement())
    #expect(header.accessibilityLabel() == "Folders")
    #expect(header.accessibilityRole() == .group)
    header.setAccessibilityLabel(nil)
    #expect(!header.isAccessibilityElement())
  }
}
