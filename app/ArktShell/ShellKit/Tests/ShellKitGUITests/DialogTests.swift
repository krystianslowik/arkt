import AppKit
import XCTest
@testable import ShellUI

/// The shared dialog (alerts design 3): layout, buttons and keys, and its three hosts.
@MainActor
final class DialogTests: XCTestCase {
  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  private static let failure = DialogContent.launchFailure(errorCode: "SQLiteError 11")

  /// Launch failure: the 56 pt app icon above the title, Try Again the mustard Return default on the trailing edge,
  /// Quit neutral to its left, Show Data Folder a quiet link at the leading edge, the error code its own line.
  func testTheLaunchAlertLayout() throws {
    let view = DialogSheetView(content: Self.failure, insets: .alert)
    let height = view.layoutContent(width: 420)
    view.frame = NSRect(x: 0, y: 0, width: 420, height: height)
    let icon = try XCTUnwrap(view.iconView)
    XCTAssertEqual(icon.frame, NSRect(x: 20, y: 24, width: 56, height: 56))
    XCTAssertGreaterThan(view.titleField.frame.minY, icon.frame.maxY, "the title stacks under the icon")
    XCTAssertEqual(view.titleField.frame.minX, 20)
    XCTAssertEqual(view.paragraphFields.map(\.stringValue),
                   ["Nothing was changed. Try again, or show the data folder.", "Error: SQLiteError 11"])
    let tryAgain = view.primaryButton
    let quit = try XCTUnwrap(view.cancelButton)
    let link = try XCTUnwrap(view.footerLinkButton)
    XCTAssertEqual(tryAgain.style, .primary)
    XCTAssertEqual(tryAgain.keyEquivalent, "\r")
    XCTAssertEqual(quit.keyEquivalent, "")
    XCTAssertEqual(tryAgain.frame.maxX, 400)
    XCTAssertEqual(quit.frame.maxX, tryAgain.frame.minX - 8)
    XCTAssertEqual(tryAgain.frame.height, 28)
    XCTAssertGreaterThanOrEqual(quit.frame.width, 76)
    XCTAssertEqual(link.frame.minX, 20)
    XCTAssertEqual(link.frame.midY, tryAgain.frame.midY, accuracy: 1)
    XCTAssertEqual(height, tryAgain.frame.maxY + 20)
    XCTAssertTrue(view.initialFocus === tryAgain, "focus starts on the default button")
    XCTAssertEqual(view.accessibilityRole(), .group)
    XCTAssertEqual(view.accessibilityLabel(), "Arkt couldn't open its data")
  }

  /// A 32 pt icon sits beside the title (5 pt lower), and the body is indented 44 under it.
  func testABesideIconIndentsTheBody() throws {
    let prompt = SpaceRemovalPrompt(space: UUID(), title: "Work", hasItems: true)
    let content = prompt.dialogContent(pinnedTabs: 3, todayTabs: 3,
                                       theme: SpaceThemeInfo(baseColors: [.srgb(hex: 0x3B82F6)], isDark: false),
                                       icon: nil)
    let view = DialogSheetView(content: content)
    _ = view.layoutContent(width: 420)
    let icon = try XCTUnwrap(view.iconView)
    XCTAssertEqual(icon.frame, NSRect(x: 20, y: 20, width: 32, height: 32))
    XCTAssertEqual(view.titleField.frame.minX, 64)
    XCTAssertEqual(view.titleField.frame.minY, 25)
    for field in view.paragraphFields { XCTAssertEqual(field.frame.minX, 64) }
    XCTAssertNil(view.footerLinkButton)
    XCTAssertTrue(view.initialFocus === view.cancelButton, "no default: focus starts on Cancel")
  }

  /// The buttons answer; the footer link does not.
  func testButtonsAnswerAndTheLinkDoesNot() throws {
    let view = DialogSheetView(content: Self.failure)
    var answers: [DialogContent.Answer] = []
    var links = 0
    view.onAnswer = { answers.append($0) }
    view.onFooterLink = { links += 1 }
    view.primaryButton.performClick(nil)
    view.cancelButton?.performClick(nil)
    view.footerLinkButton?.performClick(nil)
    XCTAssertEqual(answers, [.primary, .cancel])
    XCTAssertEqual(links, 1)
    XCTAssertFalse(view.escape(), "the launch alert ignores Escape")
  }

  /// The app-modal alert: a borderless dialog panel with 14 pt corners and an edge, Escape ignored; its entrance
  /// scales about the center on a spring with a fade (Reduce Motion: the fade only). Not run modally here.
  func testTheAppModalAlertPanel() throws {
    let alert = DialogAlert(content: Self.failure)
    XCTAssertEqual(alert.panel.accessibilitySubrole(), .dialog)
    XCTAssertTrue(alert.panel.styleMask.contains(.borderless))
    XCTAssertEqual(alert.container.layer?.cornerRadius, 14)
    XCTAssertEqual(alert.container.layer?.borderWidth, 0.5)
    alert.reduceMotion = { false }
    alert.enter()
    XCTAssertTrue(alert.container.layer?.animation(forKey: "dialogTransform") is CASpringAnimation)
    XCTAssertNotNil(alert.container.layer?.animation(forKey: "dialogFade"))
    alert.container.layer?.removeAllAnimations()
    alert.reduceMotion = { true }
    alert.enter()
    XCTAssertNil(alert.container.layer?.animation(forKey: "dialogTransform"))
    XCTAssertNotNil(alert.container.layer?.animation(forKey: "dialogFade"))
    var links = 0
    alert.onFooterLink = { links += 1 }
    alert.view.footerLinkButton?.performClick(nil)
    XCTAssertEqual(links, 1)
    alert.panel.cancelOperation(nil)
    XCTAssertNil(alert.answer, "Escape does not answer the launch alert")
    alert.view.primaryButton.performClick(nil)
    XCTAssertEqual(alert.answer, .primary)
  }

  /// The anchored panel: top-leading corner 12 pt inside the anchor, a non-activating child of the window, 12 pt
  /// corners, a spring entrance; Escape answers Cancel and leaves at once.
  func testTheAnchoredPanel() throws {
    // Both inside the screen: on a CI runner's small screen AppKit moves a parent that does not fit, and its child
    // panel moves with it.
    let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
    let parent = NSWindow(contentRect: NSRect(x: screen.minX, y: screen.minY, width: 700, height: screen.height / 2),
                          styleMask: [.titled], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    let content = DialogContent(title: "example.com wants to", paragraphs: [.init("Know your location")],
                                primaryTitle: "Allow", cancelTitle: "Never Allow", defaultButton: .none, width: 320)
    let panel = DialogPanel(content: content)
    panel.reduceMotion = { false }
    let anchor = NSRect(x: screen.minX + 40, y: screen.minY + 20, width: 600, height: min(600, screen.height - 40))
    panel.show(over: parent, anchoredTo: anchor)
    XCTAssertEqual(panel.panel.frame.minX, anchor.minX + 12)
    XCTAssertEqual(panel.panel.frame.maxY, anchor.maxY - 12)
    XCTAssertTrue(panel.panel.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(panel.panel.parent === parent)
    XCTAssertEqual(panel.container.layer?.cornerRadius, 12)
    XCTAssertTrue(panel.container.layer?.animation(forKey: "dialogTransform") is CASpringAnimation)
    var answers: [DialogContent.Answer] = []
    panel.onAnswer = { answers.append($0) }
    panel.panel.cancelOperation(nil)
    XCTAssertEqual(answers, [.cancel])
    XCTAssertNil(panel.panel.parent, "a keyboard answer takes the panel down at once")
    XCTAssertFalse(panel.panel.isVisible)
    parent.close()
  }
}
