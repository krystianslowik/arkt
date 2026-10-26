import Foundation
import Testing
import ShellUI

/// The default error toast's text per failed sidebar mutation (BH-116 for a full split).
@MainActor
struct SidebarMutationErrorTextTests {
  @Test func fullSplitSaysCannotAddNewPane() {
    #expect(ShellWindowController.errorText(for: .addPane, error: SplitEditError.splitFull) == "Cannot Add New Pane")
  }

  @Test func otherSplitFailuresSayTheSplitViewCouldNotChange() {
    let text = "Couldn't change the Split View."
    #expect(ShellWindowController.errorText(for: .addPane, error: SplitEditError.invalid) == text)
    #expect(ShellWindowController.errorText(for: .editSplit, error: SplitEditError.invalid) == text)
    #expect(ShellWindowController.errorText(for: .editSplit, error: CocoaError(.featureUnsupported)) == text)
  }

  @Test func tabAndSpaceTextsIgnoreTheError() {
    #expect(ShellWindowController.errorText(for: .addTab, error: SplitEditError.splitFull) == "Couldn't add the tab.")
    #expect(ShellWindowController.errorText(for: .addSpace, error: CocoaError(.featureUnsupported))
      == "Couldn't create a Space.")
  }

  /// BH-046: a move into a full Favorites section says so [I]; every other failed move is generic.
  @Test func fullFavoritesAndOtherMoveTexts() {
    #expect(ShellWindowController.errorText(for: .moveNode, error: SidebarMoveError.favoritesFull)
      == "Favorites are full.")
    #expect(ShellWindowController.errorText(for: .moveNode, error: SidebarMoveError.invalid)
      == "Couldn't move the tab.")
    #expect(ShellWindowController.errorText(for: .moveNode, error: CocoaError(.featureUnsupported))
      == "Couldn't move the tab.")
  }
}
