import Foundation
import Testing
@testable import ShellUI

/// Make it yours (onboarding spec, section 6.3) as a value: swatches, selection, appearance, the name and Skip.
struct OnboardingThemeTests {
  static let imported = SpaceThemeInfo(baseColors: [.srgb(hex: 0xF4E4EC), .srgb(hex: 0xEFA8C4)], isDark: false)

  @Test func freshStartsOnDuneWithSpace1() {
    let theme = OnboardingTheme.fresh(appearance: .light)
    #expect(theme.swatches.map(\.title) == ["Dune", "Mist", "Paper", "Sage", "Blossom", "Indigo"])
    #expect(theme.selectedTitle == "Dune")
    #expect(theme.placeholder == "Space 1")
    #expect(theme.isAppearanceEnabled)
    #expect(theme.resolvedTheme == SpaceThemeCatalog.defaultFamily.light)
    #expect(theme.resolvedName == "Space 1")
  }

  @Test func freshFollowsTheSystemAppearance() {
    #expect(OnboardingTheme.fresh(appearance: .dark).resolvedTheme == SpaceThemeCatalog.defaultFamily.dark)
  }

  @Test func importPathStartsOnTheImportedSwatch() {
    let theme = OnboardingTheme.imported(theme: Self.imported, name: "Personal", appearance: .dark)
    #expect(theme.swatches.count == 7)
    #expect(theme.swatches.first?.title == "Imported")
    #expect(theme.selectedTitle == "Imported")
    #expect(theme.placeholder == "Personal")
    #expect(!theme.isAppearanceEnabled, "Appearance is disabled while Imported is selected")
    #expect(theme.resolvedTheme == Self.imported)
  }

  @Test func pickingAFamilyEnablesAppearance() {
    var theme = OnboardingTheme.imported(theme: Self.imported, name: "Personal", appearance: .dark)
    theme.select(3)
    #expect(theme.selectedTitle == "Paper")
    #expect(theme.isAppearanceEnabled)
    #expect(theme.resolvedTheme == SpaceThemeCatalog.families[2].dark)
    theme.appearance = .light
    #expect(theme.resolvedTheme == SpaceThemeCatalog.families[2].light)
  }

  @Test func arrowsMoveTheSelectionAndWrap() {
    var theme = OnboardingTheme.fresh(appearance: .light)
    theme.moveSelection(by: -1)
    #expect(theme.selectedTitle == "Indigo")
    theme.moveSelection(by: 1)
    #expect(theme.selectedTitle == "Dune")
  }

  @Test func nameIsAtMostFortyCharactersAndFallsBackToThePlaceholder() {
    var theme = OnboardingTheme.fresh(appearance: .light)
    theme.name = String(repeating: "x", count: 50)
    #expect(theme.name.count == 40)
    theme.name = "   "
    #expect(theme.resolvedName == "Space 1")
    theme.name = "  Work "
    #expect(theme.resolvedName == "Work")
  }

  @Test func skipRestoresWhatTheStepOpenedWith() {
    var theme = OnboardingTheme.fresh(appearance: .light)
    let opened = theme
    theme.select(4)
    theme.appearance = .dark
    theme.name = "Home"
    theme.restore(opened)
    #expect(theme == opened)
  }

  @Test func reentryMatchesAFamilyOfTheCurrentSpace() {
    let theme = OnboardingTheme.current(theme: SpaceThemeCatalog.families[4].dark, name: "Home", appearance: .light)
    #expect(theme.selectedTitle == "Blossom")
    #expect(theme.appearance == .dark)
    #expect(theme.swatches.count == 6)
    #expect(theme.placeholder == "Home")
  }

  @Test func reentryKeepsAnOwnThemeAsTheFirstSwatch() {
    let theme = OnboardingTheme.current(theme: Self.imported, name: "Home", appearance: .light)
    #expect(theme.swatches.count == 7)
    #expect(theme.selectedTitle == "Current")
    #expect(!theme.isAppearanceEnabled)
  }
}

/// Copy of section 6, plural rules and announcements of section 11.
struct OnboardingCopyTests {
  typealias C = OnboardingCopy

  @Test func countLabelsUseSingularAndPlural() {
    #expect(C.countLabel(.pinnedTabs, 1) == "pinned tab")
    #expect(C.countLabel(.pinnedTabs, 37) == "pinned tabs")
    #expect(C.countLabel(.spaces, 1) == "Space")
    #expect(C.countLabel(.spaces, 0) == "Spaces")
    #expect(C.countLabel(.favorites, 1) == "Favorite")
    #expect(C.countLabel(.folders, 9) == "folders")
  }

  @Test func countAccessibilityLabels() {
    #expect(C.countAccessibility(.pinnedTabs, value: 37, state: .ready) == "37 pinned tabs")
    #expect(C.countAccessibility(.pinnedTabs, value: 3, state: .counting) == "Pinned tabs, counting")
    #expect(C.countAccessibility(.spaces, value: 1, state: .imported) == "1 Space, imported")
  }

  @Test func foundAnnouncement() {
    let counts = OnboardingCounts(spaces: 4, pinnedTabs: 37, favorites: 12, folders: 9)
    #expect(C.foundAnnouncement(counts) == "Found 4 Spaces, 37 pinned tabs, 12 Favorites and 9 folders.")
    let one = OnboardingCounts(spaces: 1, pinnedTabs: 1, favorites: 1, folders: 1)
    #expect(C.foundAnnouncement(one) == "Found 1 Space, 1 pinned tab, 1 Favorite and 1 folder.")
  }

  /// Decision of #375: "All of it came over." only when nothing failed; otherwise "Most of it came over." and the
  /// count, so the note never contradicts itself.
  @Test func importedNoteSaysAllOnlyWhenNothingFailed() {
    #expect(C.importedNote(skipped: 0) == "All of it came over. Your other browser stays as it is.")
    #expect(C.importNote(.imported(skipped: 0), mode: .firstRun)
            == "All of it came over. Your other browser stays as it is.")
  }

  @Test(arguments: [(1, "Most of it came over. 1 item couldn't be imported."),
                    (4, "Most of it came over. 4 items couldn't be imported.")])
  func importedNoteSaysMostWhenSomeFailed(skipped: Int, note: String) {
    #expect(C.importedNote(skipped: skipped) == note)
    #expect(C.importNote(.imported(skipped: skipped), mode: .firstRun) == note)
    #expect(C.importNote(.imported(skipped: skipped), mode: .reentry) == note)
    #expect(!note.contains("All of it"))
  }

  @Test func progressAndTips() {
    #expect(C.progress(2, of: 6) == "2 of 6")
    #expect(C.tipEyebrow(1) == "Tip 1 of 5")
    #expect(C.stepValue(3, of: 5) == "Step 3 of 5")
  }

  @Test func importCopyPerState() {
    #expect(C.importEyebrow(.counting, mode: .firstRun) == "Looking for your browser data")
    #expect(C.importEyebrow(.ready, mode: .firstRun) == "We found your browser data")
    #expect(C.importEyebrow(.importing, mode: .firstRun) == "Importing your browser data")
    #expect(C.importEyebrow(.imported(skipped: 0), mode: .firstRun) == "Imported")
    #expect(C.importEyebrow(.failed, mode: .firstRun) == "Your browser data")
    #expect(C.importTitle(.ready) == "Bring your stuff over.")
    #expect(C.importTitle(.importing) == "Bringing it over.")
    #expect(C.importTitle(.imported(skipped: 0)) == "Your setup is here.")
    #expect(C.importTitle(.failed) == "Couldn't import your data.")
    #expect(C.importNote(.ready, mode: .firstRun) == "Your other browser stays as it is.")
    #expect(C.importNote(.ready, mode: .reentry) == "Arkt adds what's new. Spaces already in Arkt stay as they are.")
    #expect(C.importNote(.failed, mode: .firstRun)
            == "Arkt couldn't read it. Try again, or import later from File > Import Browser Data.")
  }

  @Test func skipAlert() {
    #expect(C.skipTitle == "Skip setup?")
    #expect(C.skipMessage
            == "You can set things up later with Help > Welcome to Arkt. You can import your browser data later from the File menu.")
    #expect(C.skipConfirm == "Skip setup")
    #expect(C.cancel == "Cancel")
  }

  /// Decision 9: no visible string or accessibility label names Arc.
  @Test func noStringNamesArc() throws {
    let word = try Regex("\\bArc\\b")
    let counts = OnboardingCounts(spaces: 2, pinnedTabs: 3, favorites: 4, folders: 5)
    var strings = C.allStaticStrings
    for mode in [OnboardingMode.firstRun, .reentry] {
      for phase in [OnboardingImportPhase.counting, .ready, .importing, .imported(skipped: 2), .failed] {
        strings += [C.importEyebrow(phase, mode: mode), C.importTitle(phase), C.importNote(phase, mode: mode),
                    C.importPrimaryTitle(phase)]
      }
    }
    strings += [C.foundAnnouncement(counts), C.importedNote(skipped: 2)]
    for kind in OnboardingCounts.Kind.allCases {
      strings += [C.countLabel(kind, 2), C.countAccessibility(kind, value: 2, state: .counting)]
    }
    strings += OnboardingTheme.imported(theme: OnboardingThemeTests.imported, name: "x", appearance: .light)
      .swatches.map(\.title)
    #expect(strings.count > 60)
    for string in strings {
      #expect(string.firstMatch(of: word) == nil, "\(string)")
    }
  }
}
