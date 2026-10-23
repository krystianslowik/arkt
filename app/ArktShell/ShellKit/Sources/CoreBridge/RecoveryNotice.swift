import ShellUI

/// What launch recovery did, as far as the user needs to know (decision 4: recovery is never silent). CoreBridge
/// cannot see `Persistence.OpenOutcome`; the app maps it in one switch. Texts carry no file names or paths.
public enum RecoveryNotice: Hashable, Sendable {
  /// A backup was restored. `liveFileWasDamaged` is false when the live file was missing.
  case restoredFromBackup(liveFileWasDamaged: Bool)
  /// No backup was usable; Arkt started empty. `liveFileWasDamaged` is false when the live file was missing.
  case recreatedEmpty(liveFileWasDamaged: Bool)

  public static let showFilesTitle = "Show Files"

  /// A persistent toast with a "Show Files" action that reveals Arkt's data folder.
  public var toast: Toast {
    Toast(text: text, actionTitle: Self.showFilesTitle, isPersistent: true)
  }

  private var text: String {
    switch self {
    case .restoredFromBackup(liveFileWasDamaged: true):
      "Arkt couldn't read its saved sidebar and restored it from a backup. Recent changes may be missing."
    case .restoredFromBackup(liveFileWasDamaged: false):
      "Arkt's saved sidebar was missing and was restored from a backup."
    case .recreatedEmpty(liveFileWasDamaged: true):
      "Arkt couldn't read its saved sidebar and no backup could be used. The damaged file was kept aside."
    case .recreatedEmpty(liveFileWasDamaged: false):
      "Arkt's saved sidebar was missing and no backup could be used. The backups were kept."
    }
  }
}
