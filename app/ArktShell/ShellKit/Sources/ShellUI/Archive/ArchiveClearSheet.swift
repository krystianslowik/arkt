import AppKit

/// The Clear Archive confirmation (BH-087, design section 6), on the shared dialog sheet (alerts design 3.3): the count
/// in the question, a note when filters hide some of what is cleared, Cancel and a quiet red Clear Archive. Focus starts
/// on Cancel, neither button has the Return key, and Escape cancels.
@MainActor
final class ArchiveClearSheet {
  static let width: CGFloat = 400

  let sheet: DialogSheet
  /// Called once with the choice: true for Clear Archive.
  var onFinish: (@MainActor (Bool) -> Void)?

  /// The body for `count` archived items (nil when the count is unknown).
  static func body(count: Int?) -> String {
    switch count {
    case nil: "All archived items are permanently deleted. This cannot be undone."
    case 1?: "The 1 archived item is permanently deleted. This cannot be undone."
    case let count?: "All \(count) archived items are permanently deleted. This cannot be undone."
    }
  }

  static let note = "This includes items hidden by the current filters."

  static func content(count: Int?, hiddenByFilters: Bool) -> DialogContent {
    var paragraphs = [DialogContent.Paragraph(body(count: count))]
    if hiddenByFilters { paragraphs.append(.init(note, secondary: true)) }
    return DialogContent(title: "Clear the Archive?", paragraphs: paragraphs, primaryTitle: "Clear Archive",
                         cancelTitle: "Cancel", defaultButton: .none, isDestructive: true, width: width)
  }

  init(count: Int?, hiddenByFilters: Bool) {
    sheet = DialogSheet(content: Self.content(count: count, hiddenByFilters: hiddenByFilters))
    sheet.view.primaryButton.setAccessibilityIdentifierWithCell(AXID.Archive.clearConfirm)
    sheet.onAnswer = { [weak self] answer in
      let callback = self?.onFinish
      self?.onFinish = nil
      callback?(answer == .primary)
    }
  }

  var window: NSWindow? { sheet.window }
  var titleField: NSTextField { sheet.view.titleField }
  var bodyField: NSTextField { sheet.view.paragraphFields[0] }
  /// The filters note; nil when no filter hides anything.
  var noteField: NSTextField? { sheet.view.paragraphFields.dropFirst().first }
  var clearButton: ArchivePillButton { sheet.view.primaryButton }
  var cancelButton: ArchivePillButton? { sheet.view.cancelButton }

  /// Shows the sheet on `parent`; `onFinish` reports the choice.
  func begin(on parent: NSWindow) { sheet.begin(on: parent) }
}
