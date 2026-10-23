import CoreBridge
import ShellUI
import Testing

struct RecoveryNoticeTests {
  static let allCases: [RecoveryNotice] = [
    .restoredFromBackup(liveFileWasDamaged: true),
    .restoredFromBackup(liveFileWasDamaged: false),
    .recreatedEmpty(liveFileWasDamaged: true),
    .recreatedEmpty(liveFileWasDamaged: false),
  ]

  @Test func restoredFromBackupIsPersistentWithShowFiles() {
    let toast = RecoveryNotice.restoredFromBackup(liveFileWasDamaged: true).toast
    #expect(toast.isPersistent && toast.actionTitle == "Show Files")
    #expect(
      toast.text
        == "Arkt couldn't read its saved sidebar and restored it from a backup. Recent changes may be missing.")
  }

  @Test func restoredWhenLiveFileMissing() {
    let toast = RecoveryNotice.restoredFromBackup(liveFileWasDamaged: false).toast
    #expect(toast.text == "Arkt's saved sidebar was missing and was restored from a backup.")
  }

  @Test func recreatedEmpty() {
    let toast = RecoveryNotice.recreatedEmpty(liveFileWasDamaged: true).toast
    #expect(
      toast.text
        == "Arkt couldn't read its saved sidebar and no backup could be used. The damaged file was kept aside.")
  }

  @Test func recreatedEmptyWhenLiveFileMissing() {
    let toast = RecoveryNotice.recreatedEmpty(liveFileWasDamaged: false).toast
    #expect(toast.text == "Arkt's saved sidebar was missing and no backup could be used. The backups were kept.")
  }

  @Test func everyNoticeIsPersistentWithShowFiles() {
    for notice in Self.allCases {
      #expect(notice.toast.isPersistent)
      #expect(notice.toast.actionTitle == "Show Files")
    }
  }

  @Test func noFileNamesOrPathsInText() {
    for notice in Self.allCases {
      #expect(!notice.toast.text.contains("/"))
      #expect(!notice.toast.text.contains(".sqlite"))
    }
  }
}
