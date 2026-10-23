import Foundation
import Testing
import ShellUI

/// The Delete Space confirmation's wording (#206), PARITY(NEEDS-RUNTIME-CHECK).
struct SpaceRemovalPromptTests {
  @Test func namesTheSpaceAndSaysWhereItsTabsGo() {
    let space = UUID()
    let prompt = SpaceRemovalPrompt(space: space, title: "Work", hasItems: true)
    #expect(prompt.space == space)
    #expect(prompt.message == "Delete the Space \u{201C}Work\u{201D}?")
    #expect(prompt.information
      == "Its pinned tabs, folders and Today tabs move to the Archive, where you can restore them.")
    #expect(SpaceRemovalPrompt.confirmTitle == "Delete Space")
  }

  @Test func anUntitledSpaceIsThisSpace() {
    #expect(SpaceRemovalPrompt(space: UUID(), title: "", hasItems: true).message == "Delete this Space?")
  }

  @Test func anEmptySpaceSaysItCannotBeUndone() {
    #expect(SpaceRemovalPrompt(space: UUID(), title: "Work", hasItems: false).information == "This cannot be undone.")
  }
}
