import CoreBridge
import Testing

struct ToastTextTests {
  @Test func autoArchivedCountsTabs() {  // BH-085; singular form [I]
    #expect(ToastText.autoArchived(1) == "Auto archived 1 tab")
    #expect(ToastText.autoArchived(3) == "Auto archived 3 tabs")
  }

  @Test func restoredNamesTheKindAndTheSpace() {  // BH-086
    #expect(ToastText.restored(kind: .tab, spaceTitle: "Work") == "Tab restored to Work")
    #expect(ToastText.restored(kind: .folder, spaceTitle: "Work") == "Folder restored to Work")
    #expect(ToastText.restored(kind: .split, spaceTitle: "Work") == "Split View restored to Work")
  }

  @Test func restoredToFavorites() {  // [I]
    #expect(ToastText.restored(kind: .tab, spaceTitle: nil) == "Tab restored to Favorites")
  }

  /// Alerts design 4.3: counts only, and the import failure never names the source browser.
  @Test func failureTextsAndKinds() {
    #expect(ToastText.importFailed == "Couldn't import browser data.")
    #expect(ToastText.restoreFailed == "Couldn't restore from the Archive.")
    #expect(ToastText.restoredGlyph == "arrow.counterclockwise")
  }

  /// Decision 3: the auto-archive toast is shown only when a pass archived two or more tabs.
  @Test func autoArchiveToastOnlyForSeveralTabs() {
    #expect(ToastText.autoArchiveToast(count: 1) == nil)
    let toast = ToastText.autoArchiveToast(count: 3)
    #expect(toast?.text == "Auto archived 3 tabs")
    #expect(toast?.kind == .undo)
    #expect(toast?.actionTitle == "Undo")
    #expect(toast?.shortcut == nil, "the Undo pill carries no key hint")
  }
}
