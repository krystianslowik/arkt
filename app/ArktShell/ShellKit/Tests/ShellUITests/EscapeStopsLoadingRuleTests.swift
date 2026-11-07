import Testing
@testable import ShellUI

/// KB-055 (#614): an Esc the page passed on stops a loading page, unless another Esc owner is open in the window.
struct EscapeStopsLoadingRuleTests {
  private static func stops(isLoading: Bool = true, peekOpen: Bool = false, findBarOpen: Bool = false,
                            commandBarVisible: Bool = false, dialogShown: Bool = false, tabFullscreen: Bool = false,
                            sheetAttached: Bool = false) -> Bool {
    ShellWindowController.escapeStopsLoading(
      isLoading: isLoading, peekOpen: peekOpen, findBarOpen: findBarOpen, commandBarVisible: commandBarVisible,
      dialogShown: dialogShown, tabFullscreen: tabFullscreen, sheetAttached: sheetAttached)
  }

  @Test func aLoadingPageWithNoOtherOwnerStops() {
    #expect(Self.stops())
  }

  @Test func anIdlePageDoesNothingNew() {
    #expect(!Self.stops(isLoading: false))
  }

  @Test func everyOtherOwnerKeepsTheKey() {
    #expect(!Self.stops(peekOpen: true), "Peek")
    #expect(!Self.stops(findBarOpen: true), "find bar")
    #expect(!Self.stops(commandBarVisible: true), "command bar, which is also the URL bar's editor")
    #expect(!Self.stops(dialogShown: true), "a page dialog")
    #expect(!Self.stops(tabFullscreen: true), "HTML fullscreen")
    #expect(!Self.stops(sheetAttached: true), "a sheet")
  }
}
