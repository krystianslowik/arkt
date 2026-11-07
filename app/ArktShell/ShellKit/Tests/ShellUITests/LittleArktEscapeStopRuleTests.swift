import Testing
@testable import ShellUI

/// KB-055 (#757): in a Little Arkt window an Esc the page passed on stops a loading page, unless one of the window's
/// own Esc owners is open.
struct LittleArktEscapeStopRuleTests {
  private static func stops(isLoading: Bool = true, dialogShown: Bool = false, tabFullscreen: Bool = false,
                            sheetAttached: Bool = false, menuOpen: Bool = false) -> Bool {
    LittleArktWindowController.escapeStopsLoading(
      isLoading: isLoading, dialogShown: dialogShown, tabFullscreen: tabFullscreen, sheetAttached: sheetAttached,
      menuOpen: menuOpen)
  }

  @Test func aLoadingPageWithNoOtherOwnerStops() {
    #expect(Self.stops())
  }

  @Test func anIdlePageDoesNothingNew() {
    #expect(!Self.stops(isLoading: false))
  }

  @Test func everyOtherOwnerKeepsTheKey() {
    #expect(!Self.stops(dialogShown: true), "a page dialog")
    #expect(!Self.stops(tabFullscreen: true), "HTML fullscreen")
    #expect(!Self.stops(sheetAttached: true), "a sheet")
    #expect(!Self.stops(menuOpen: true), "the top bar's Space chooser")
  }
}
