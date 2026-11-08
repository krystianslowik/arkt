import AppKit

/// What the Settings window asks the app for: plain values and actions, so ShellUI needs no core module (the app
/// target answers with LaunchServices, the import coordinator and the data folder).
@MainActor
public struct SettingsServices {
  /// Arkt opens http and https links.
  public var isDefaultBrowser: @MainActor () -> Bool = { false }
  /// Asks macOS to make Arkt the default browser; returns when its prompt closed.
  public var makeDefaultBrowser: @MainActor () async -> Void = {}
  /// File > Import Browser Data... is available now.
  public var canImportBrowserData: @MainActor () -> Bool = { false }
  /// The same action as File > Import Browser Data....
  public var importBrowserData: @MainActor () -> Void = {}
  /// Reveals Arkt's data folder in the Finder (the recovery toast's Show Files); the row is disabled while nil.
  public var showDataFolder: (@MainActor () -> Void)?
  /// Crash reports kept on this Mac (#129). Cached by the app; the pane never waits on disk.
  public var crashReportCount: @MainActor () -> Int = { 0 }
  /// Send Crash Report: opens the newest kept report as a prefilled GitHub issue in the browser.
  public var sendCrashReport: @MainActor () -> Void = {}
  /// The menu Settings > Shortcuts lists.
  public var shortcutsMenu: @MainActor () -> NSMenu? = { NSApp.mainMenu }
  /// The Spaces, in sidebar order.
  public var spaces: @MainActor () -> [SettingsSpaceSummary] = { [] }
  /// The system Downloads folder, what the Downloads pop-up calls "Downloads" (#132).
  public var downloadsFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    ?? FileManager.default.temporaryDirectory
  /// The same action as Window > Show Library; the row is disabled while nil (#132).
  public var openLibrary: (@MainActor () -> Void)?
  /// Settings > Spaces and Profiles > Archive (#448); both rows stay planned while nil.
  public var archiveRows: SettingsArchiveRows?

  public init() {}
}

/// The two Archive rows' values as the pop-ups' titles ("12 hours", "Never"; `SettingsWindowController
/// .archiveAfterTitles`). The app maps them to the stored thresholds; ShellUI needs no core module.
@MainActor
public struct SettingsArchiveRows {
  /// "Archive Today tabs after": the Default profile's value until a profile detail pane exists (#448 decision).
  public var tabsAfter: @MainActor () -> String
  public var setTabsAfter: @MainActor (String) -> Void
  /// "Archive Little Arkt windows after": one value for the app (BH-137).
  public var littleArktAfter: @MainActor () -> String
  public var setLittleArktAfter: @MainActor (String) -> Void
  /// Reset all settings (#617): both rows back to their defaults; the window reads the new titles afterwards.
  public var reset: @MainActor () -> Void

  public init(tabsAfter: @escaping @MainActor () -> String, setTabsAfter: @escaping @MainActor (String) -> Void,
              littleArktAfter: @escaping @MainActor () -> String,
              setLittleArktAfter: @escaping @MainActor (String) -> Void,
              reset: @escaping @MainActor () -> Void = {}) {
    self.tabsAfter = tabsAfter
    self.setTabsAfter = setTabsAfter
    self.littleArktAfter = littleArktAfter
    self.setLittleArktAfter = setLittleArktAfter
    self.reset = reset
  }
}

/// One Space as Settings > Spaces and Profiles lists it: its theme swatch, name, counts and profile.
public struct SettingsSpaceSummary: Equatable, Sendable {
  public var id: SpaceID
  public var title: String
  public var profile: String
  /// The theme's gradient stops; the swatch draws them.
  public var gradient: [RGBA]
  public var icon: SpaceIconInfo?
  public var pinned: Int
  public var today: Int

  /// "6 pinned, 4 in Today".
  public var detail: String { "\(pinned) pinned, \(today) in Today" }

  /// The profile as the user reads it: "default" is "Default".
  public var profileName: String { Self.displayName(profile: profile) }

  @MainActor
  public static func list(from source: any SidebarSource) -> [SettingsSpaceSummary] {
    source.spaceOrder.compactMap { id in
      guard let space = source.space(id) else { return nil }
      return SettingsSpaceSummary(id: id, title: space.title, profile: space.profile,
                                  gradient: space.theme.baseColors, icon: space.icon,
                                  pinned: source.children(of: .pinned(id)).count,
                                  today: source.children(of: .today(id)).count)
    }
  }

  /// A profile and the Spaces that use it, in first-use order.
  public struct Profile: Equatable, Sendable {
    public var name: String
    public var spaces: [String]
    /// "Used by Personal and Reading".
    public var detail: String {
      let names = spaces.count > 1
        ? spaces.dropLast().joined(separator: ", ") + " and " + (spaces.last ?? "") : spaces.joined()
      return "Used by \(names)"
    }
  }

  public static func profiles(in spaces: [SettingsSpaceSummary]) -> [Profile] {
    var order: [String] = []
    var users: [String: [String]] = [:]
    for space in spaces {
      if users[space.profile] == nil { order.append(space.profile) }
      users[space.profile, default: []].append(space.title)
    }
    return order.map { Profile(name: displayName(profile: $0), spaces: users[$0] ?? []) }
  }

  static func displayName(profile: String) -> String {
    profile.isEmpty || profile == "default" ? "Default" : profile.prefix(1).uppercased() + profile.dropFirst()
  }
}
