import AppKit
import EngineAPI

/// The extension remove sheet (#720; design/alerts-sheets-toasts `ext-remove`, spec sections 1 and 3.2) on the shared
/// dialog sheet, built the way Delete Space is: the extension's icon tile, Remove "<name>"? (two lines at most, then
/// truncated), a Report abuse checkbox (off; only for an extension with a Web Store report page, #721), Cancel and a
/// quiet red Remove. Focus starts on Cancel, neither button has
/// the Return key and Escape cancels, so no key press removes an extension. AppKit owns the sheet's slide, and its
/// Reduce Motion variant.
@MainActor
public final class ExtensionRemoveSheet {
  /// The extension the sheet asks about.
  public let extensionID: String
  let sheet: DialogSheet
  /// Called once when the user answers: Remove with the Report abuse state (false without the checkbox), or nil for
  /// Cancel and Escape. Not called when the sheet is dismissed because the extension went away.
  var onFinish: (@MainActor (_ reportAbuse: Bool?) -> Void)?

  static func content(for action: ExtensionAction) -> DialogContent {
    DialogContent(title: "Remove \u{201C}\(action.name)\u{201D}?",
                  icon: action.iconPNG.map { .image($0) } ?? .symbol("puzzlepiece.extension"),
                  primaryTitle: "Remove", cancelTitle: "Cancel", defaultButton: .none, isDestructive: true,
                  primaryHelp: "Removes the extension from Arkt",
                  checkbox: action.canReportAbuse ? .init("Report abuse") : nil, titleMaxLines: 2)
  }

  init(action: ExtensionAction) {
    extensionID = action.extensionID
    sheet = DialogSheet(content: Self.content(for: action))
    sheet.onAnswer = { [weak self] answer in
      guard let self else { return }
      let callback = self.onFinish
      self.onFinish = nil
      callback?(answer == .primary ? self.sheet.isCheckboxOn : nil)
    }
  }

  var window: NSWindow? { sheet.window }

  /// Shows the sheet on `parent`.
  func begin(on parent: NSWindow) { sheet.begin(on: parent) }

  /// Closes the sheet without an answer.
  func dismiss() {
    onFinish = nil
    sheet.dismiss()
  }
}
