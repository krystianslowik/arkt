import AppKit
import Testing
@testable import ShellUI

/// When Cmd-Z belongs to the text being edited (#346, KB-011): the router passes Undo on instead of reopening.
@MainActor
struct ReopenUndoRouterTests {
  /// Stands in for Chromium's page view: it reports the focused field's `ui::TextInputType` and, as in a password
  /// field, has no input context.
  private final class PageView: NSView {
    @objc var textInputType: Int

    init(textInputType: Int) {
      self.textInputType = textInputType
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var inputContext: NSTextInputContext? { nil }
  }

  /// `ui::TEXT_INPUT_TYPE_PASSWORD`.
  private static let password = 2

  @Test func `a page's password field is text being edited`() {
    #expect(ReopenUndoRouter.isEditingText(PageView(textInputType: Self.password)))
  }

  @Test func `a page with nothing editable focused is not`() {
    #expect(!ReopenUndoRouter.isEditingText(PageView(textInputType: 0)))
  }

  @Test func `a field editor is, a plain view is not`() {
    #expect(ReopenUndoRouter.isEditingText(NSTextView()))
    #expect(!ReopenUndoRouter.isEditingText(NSView()))
    #expect(!ReopenUndoRouter.isEditingText(nil))
  }
}
