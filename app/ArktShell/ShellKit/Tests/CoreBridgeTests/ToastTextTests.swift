import CoreBridge
import Testing

struct ToastTextTests {
  @Test func autoArchivedCountsTabs() {  // BH-085; singular form [I]
    #expect(ToastText.autoArchived(1) == "Auto archived 1 tab")
    #expect(ToastText.autoArchived(3) == "Auto archived 3 tabs")
  }

  @Test func restoredNamesTheKindAndTheSpace() {  // BH-086
    #expect(ToastText.restored(kind: .tab, spaceTitle: "Work") == "Tab restored to Work. Click to view.")
    #expect(ToastText.restored(kind: .folder, spaceTitle: "Work") == "Folder restored to Work. Click to view.")
    #expect(ToastText.restored(kind: .split, spaceTitle: "Work") == "Split View restored to Work. Click to view.")
  }

  @Test func restoredToFavorites() {  // [I]
    #expect(ToastText.restored(kind: .tab, spaceTitle: nil) == "Tab restored to Favorites. Click to view.")
  }
}
