import AppKit
import EngineAPI

/// What the user decided about a held file.
public enum DownloadDangerAnswer: Equatable, Sendable {
  case delete, showInFinder, keep, dismissed
}

/// The dangerous-file sheet (design/downloads, Behavior): a window sheet titled "Arkt blocked "<name>"", with the kind,
/// size and host, a plain sentence and three answers. The one primary is Delete Download, the safe answer and the Return
/// key. Show in Finder is neutral. Keep Anyway is a quiet red text link at the leading edge, never the default, and needs a
/// second click or Return: the first only arms it ("Click again to keep it"), and Delete Download steps back from Return.
@MainActor
final class DownloadDangerSheet {
  static let width: CGFloat = 420
  static let armedTitle = "Click again to keep it"

  let sheet: DialogSheet
  let item: DownloadItem
  /// Called once with the answer.
  var onFinish: (@MainActor (DownloadDangerAnswer) -> Void)?
  private(set) var isArmed = false

  /// The words, as a content model, so a test reads them without a window.
  static func content(for item: DownloadItem, folderName: String) -> DialogContent {
    let kind = DownloadsFormat.kindDescription(of: item.filename)
    let host = DownloadsFormat.host(of: item.url)
    var line = [kind, DownloadsFormat.size(item.totalBytes ?? item.receivedBytes)].joined(separator: " \u{00B7} ")
    if !host.isEmpty { line += " \u{00B7} from \(host)" }
    let blocked = item.dangerType.isBlocked
    let body = blocked
      ? "Your settings do not allow this file. It cannot be kept."
      : "This file looks unsafe and could harm your Mac. It is saved in \(folderName), but it has not been opened."
    return DialogContent(
      title: "Arkt blocked \u{201C}\(item.filename)\u{201D}", icon: .symbol("exclamationmark.circle"), subtitle: line,
      paragraphs: [.init(body), .init(blocked ? "Delete it to free the space." : "Delete it unless you were expecting it.", secondary: true)],
      footerLink: item.dangerType.canKeep ? "Keep Anyway" : nil, footerLinkIsDestructive: true,
      primaryTitle: "Delete Download", secondaryTitle: "Show in Finder", defaultButton: .primary,
      escapeAnswersCancel: true, primaryHelp: "Deletes the file", width: width)
  }

  init(item: DownloadItem, folderName: String) {
    self.item = item
    sheet = DialogSheet(content: Self.content(for: item, folderName: folderName))
    sheet.view.setAccessibilityIdentifier(AXID.Downloads.dangerSheet)
    sheet.onFooterLink = { [weak self] in self?.keepAnywayPressed() }
    sheet.onAnswer = { [weak self] answer in
      switch answer {
      case .primary: self?.finish(.delete)
      case .secondary: self?.finish(.showInFinder)
      case .cancel: self?.finish(.dismissed)
      }
    }
  }

  var window: NSWindow? { sheet.window }
  var deleteButton: ArchivePillButton { sheet.view.primaryButton }
  var finderButton: ArchivePillButton? { sheet.view.secondaryButton }
  var keepLink: ArchiveLinkButton? { sheet.view.footerLinkButton }

  func begin(on parent: NSWindow) { sheet.begin(on: parent) }

  /// The first press arms Keep Anyway; the second keeps the file. While armed Return answers Keep, so a stray Return
  /// never keeps it and never deletes it by surprise either.
  func keepAnywayPressed() {
    guard let link = keepLink else { return }
    guard isArmed else {
      isArmed = true
      link.title = Self.armedTitle
      link.keyEquivalent = "\r"
      deleteButton.keyEquivalent = ""
      return
    }
    finish(.keep)
  }

  private func finish(_ answer: DownloadDangerAnswer) {
    let callback = onFinish
    onFinish = nil
    callback?(answer)
  }
}

extension DownloadsFormat {
  /// "Disk image", "Archive", "PDF document": the kind a sheet names.
  static func kindDescription(of filename: String) -> String {
    switch (filename as NSString).pathExtension.lowercased() {
    case "dmg", "iso": "Disk image"
    case "pkg", "mpkg": "Installer"
    case "app": "Application"
    case "zip", "gz", "tgz", "tar", "7z", "rar", "bz2", "xz": "Archive"
    case "pdf": "PDF document"
    case "exe", "msi", "bat", "cmd", "scr": "Windows program"
    case "sh", "command", "py", "js": "Script"
    case "": "File"
    case let ext: "\(ext.uppercased()) file"
    }
  }
}
