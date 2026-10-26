import Foundation

/// The four counts the Import step shows (section 6.2). Counts only: no names, titles, URLs or paths.
public struct OnboardingCounts: Equatable, Sendable {
  public enum Kind: CaseIterable, Sendable {
    case pinnedTabs, spaces, favorites, folders
  }

  public var spaces: Int
  public var pinnedTabs: Int
  public var favorites: Int
  public var folders: Int

  public init(spaces: Int = 0, pinnedTabs: Int = 0, favorites: Int = 0, folders: Int = 0) {
    self.spaces = spaces; self.pinnedTabs = pinnedTabs; self.favorites = favorites; self.folders = folders
  }

  public subscript(kind: Kind) -> Int {
    switch kind {
    case .pinnedTabs: pinnedTabs
    case .spaces: spaces
    case .favorites: favorites
    case .folders: folders
    }
  }
}

/// Every string of the first run (onboarding spec, section 6; announcements of section 11). Final copy: sentence
/// case, "Arkt" in sentences. Decision 9: nothing here names Arc; "your browser data" and "your other browser" stand
/// for it (`OnboardingCopyTests.noStringNamesArc`).
public enum OnboardingCopy {
  // MARK: Footer and group

  public static let groupLabel = "Welcome to Arkt"
  public static let back = "Back"
  public static let skipSetup = "Skip setup"
  public static func progress(_ index: Int, of total: Int) -> String { "\(index) of \(total)" }
  public static func stepValue(_ index: Int, of total: Int) -> String { "Step \(index) of \(total)" }

  // MARK: Welcome (6.1)

  public static let welcomeTitle = "Keep the way you browse."
  public static let welcomeLede = "A native macOS browser."
  public static let getStarted = "Get started"
  /// The Welcome and Done stage.
  public static let markLabel = "Arkt"

  // MARK: Import (6.2)

  public static func importEyebrow(_ phase: OnboardingImportPhase, mode: OnboardingMode) -> String {
    switch phase {
    case .counting: "Looking for your browser data"
    case .ready: "We found your browser data"
    case .importing: "Importing your browser data"
    case .imported: "Imported"
    case .failed: "Your browser data"
    }
  }

  public static func importTitle(_ phase: OnboardingImportPhase) -> String {
    switch phase {
    case .counting, .ready: "Bring your stuff over."
    case .importing: "Bringing it over."
    case .imported: "Your setup is here."
    case .failed: "Couldn't import your data."
    }
  }

  /// Re-entry (section 12): "Arkt adds what's new." before the import; Imported and Failed read as on the first run.
  public static func importNote(_ phase: OnboardingImportPhase, mode: OnboardingMode) -> String {
    switch phase {
    case .counting, .ready, .importing:
      mode == .reentry ? "Arkt adds what's new. Spaces already in Arkt stay as they are."
        : "Your other browser stays as it is."
    case .imported(let skipped): importedNote(skipped: skipped)
    case .failed: "Arkt couldn't read it. Try again, or import later from File > Import Browser Data."
    }
  }

  /// "All of it" only when nothing failed (#375), so the note never contradicts itself.
  public static func importedNote(skipped: Int) -> String {
    guard skipped > 0 else { return "All of it came over. Your other browser stays as it is." }
    return "Most of it came over. \(skipped) \(skipped == 1 ? "item" : "items") couldn't be imported."
  }

  public static let importButton = "Import"
  public static let importingButton = "Importing..."
  public static let startFresh = "Start fresh"
  public static let tryAgain = "Try again"
  public static let continueButton = "Continue"

  /// The primary button's title in each import state.
  public static func importPrimaryTitle(_ phase: OnboardingImportPhase) -> String {
    switch phase {
    case .counting, .ready: importButton
    case .importing: importingButton
    case .imported: continueButton
    case .failed: tryAgain
    }
  }

  public static func countLabel(_ kind: OnboardingCounts.Kind, _ value: Int) -> String {
    let one = value == 1
    return switch kind {
    case .pinnedTabs: one ? "pinned tab" : "pinned tabs"
    case .spaces: one ? "Space" : "Spaces"
    case .favorites: one ? "Favorite" : "Favorites"
    case .folders: one ? "folder" : "folders"
    }
  }

  public enum CountState: Sendable { case counting, ready, imported }

  /// "37 pinned tabs"; "Pinned tabs, counting"; "37 pinned tabs, imported".
  public static func countAccessibility(_ kind: OnboardingCounts.Kind, value: Int, state: CountState) -> String {
    switch state {
    case .counting:
      let label = countLabel(kind, 2)
      return label.prefix(1).uppercased() + label.dropFirst() + ", counting"
    case .ready: return "\(value) \(countLabel(kind, value))"
    case .imported: return "\(value) \(countLabel(kind, value)), imported"
    }
  }

  // MARK: Make it yours (6.3)

  public static let themeEyebrow = "Your first Space"
  public static let themeLedeFresh = "Pick a look. You can change it later."
  public static let themeLedeImported = "It keeps the look it came with. Pick another if you like."
  public static let skip = "Skip"
  public static let nameLabel = "Name"
  public static let themeGroupLabel = "Theme"
  public static let appearanceLabel = "Appearance"
  public static let light = "Light"
  public static let dark = "Dark"
  public static let importedSwatch = "Imported"
  /// Re-entry: the current Space's own gradient when it is none of the families.
  public static let currentSwatch = "Current"

  // MARK: Default browser (6.4)

  public static let defaultTitle = "Open links in Arkt."
  public static let defaultLede =
    "Links from other apps open here. macOS asks you to confirm, and System Settings can change it later."
  public static let defaultPrompting = "macOS is asking you to confirm. Arkt continues either way."
  public static let notNow = "Not now"
  public static let makeDefault = "Make default"

  // MARK: Extensions (6.5)

  public static let extensionsTitle = "Your extensions work here."
  public static let extensionsLede =
    "Arkt installs them from the Chrome Web Store. Your password manager's extension is there too."
  public static let webStoreOption = "Open the Chrome Web Store when setup ends"

  // MARK: Tour (6.6)

  public static func tipEyebrow(_ tip: Int) -> String { "Tip \(tip) of \(OnboardingStep.tipCount)" }
  public static let skipTour = "Skip tour"
  public static let next = "Next"
  public static let done = "Done"

  public struct Tip: Sendable {
    public var title: String
    public var lede: String
    /// The parts of the lede set in the primary colour and DemiBold (the keys).
    public var keys: [String]
    /// The stage's accessibility label; nil hides the stage (the lede says it).
    public var stageLabel: String?
  }

  public static let tips: [Tip] = [
    Tip(title: "Open a tab.",
        lede: "Press Command-T to search or type an address. Command-L edits the address of the current tab.",
        keys: ["Command-T", "Command-L"], stageLabel: "Command T, Command L"),
    Tip(title: "Close by archiving.",
        lede: "Command-W closes a tab and keeps it in the Archive, so you can find it again.",
        keys: ["Command-W"], stageLabel: "Command W"),
    Tip(title: "Switch Spaces.",
        lede: "Swipe left or right with two fingers on the sidebar to move between Spaces.", keys: [], stageLabel: nil),
    Tip(title: "Split the view.",
        lede: "Drag a tab from the sidebar onto the page to see two tabs side by side.", keys: [], stageLabel: nil),
    Tip(title: "Keep Favorites close.",
        lede: "Drag a tab to the top of the sidebar to make it a Favorite.", keys: [], stageLabel: nil),
  ]

  // MARK: Done (6.7, section 12)

  public static let doneTitle = "You're all set."
  public static let doneLede = "To see this again, choose Help > Welcome to Arkt."
  public static let doneLedeReentry = "Nothing else changed."
  public static let startBrowsing = "Start browsing"
  public static let backToBrowsing = "Back to browsing"

  // MARK: Skip setup (6.9)

  public static let skipTitle = "Skip setup?"
  public static let skipMessage =
    "You can set things up later with Help > Welcome to Arkt. You can import your browser data later from the File menu."
  public static let skipConfirm = "Skip setup"
  public static let cancel = "Cancel"

  // MARK: Announcements (section 11)

  public static func foundAnnouncement(_ counts: OnboardingCounts) -> String {
    func part(_ kind: OnboardingCounts.Kind) -> String { "\(counts[kind]) \(countLabel(kind, counts[kind]))" }
    return "Found \(part(.spaces)), \(part(.pinnedTabs)), \(part(.favorites)) and \(part(.folders))."
  }

  public static let importStartedAnnouncement = "Importing your browser data."
  public static let importFinishedAnnouncement = "Import finished."
  public static let finishedAnnouncement = "Setup finished. The command bar is open."
  public static let finishedReentryAnnouncement = "Setup finished."

  /// Every fixed string, for the no-"Arc" check.
  public static var allStaticStrings: [String] {
    [groupLabel, back, skipSetup, welcomeTitle, welcomeLede, getStarted, markLabel, importButton, importingButton,
     startFresh, tryAgain, continueButton, themeEyebrow, themeLedeFresh, themeLedeImported, skip, nameLabel,
     themeGroupLabel, appearanceLabel, light, dark, importedSwatch, currentSwatch, defaultTitle, defaultLede,
     defaultPrompting, notNow, makeDefault, extensionsTitle, extensionsLede, webStoreOption, skipTour, next, done,
     doneTitle, doneLede, doneLedeReentry, startBrowsing, backToBrowsing, skipTitle, skipMessage, skipConfirm,
     cancel, importStartedAnnouncement, importFinishedAnnouncement, finishedAnnouncement,
     finishedReentryAnnouncement, progress(2, of: 6), stepValue(2, of: 6)]
      + (1...OnboardingStep.tipCount).map(tipEyebrow)
      + tips.flatMap { [$0.title, $0.lede] + $0.keys + [$0.stageLabel].compactMap { $0 } }
      + SpaceThemeCatalog.families.map(\.title)
  }
}
