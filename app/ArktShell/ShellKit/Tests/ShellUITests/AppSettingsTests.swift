import Foundation
import Testing
@testable import ShellUI

/// The app-level settings store behind the Settings window (#307): defaults, persistence through a defaults suite
/// (the app passes the `ARKT_DEFAULTS_SUITE` one), observers, and the keys existing users already have.
@MainActor
struct AppSettingsTests {
  /// A fresh suite per test, removed afterwards; never the real defaults.
  private final class Suite {
    let name = "dev.arkt.tests.settings.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
    deinit { UserDefaults().removePersistentDomain(forName: name) }
  }

  private final class Recorder: AppSettingsObserver {
    var count = 0
    func appSettingsDidChange(_ settings: AppSettings) { count += 1 }
  }

  @Test func defaultsWhenNothingIsStored() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    #expect(settings.tabNavigation == TabNavigationSettings())
    #expect(settings.tabNavigation.countsFavorites)
    #expect(!settings.tabNavigation.ninthOpensNinth)
    #expect(settings.peekLinks == PeekLinkSettings())
    #expect(settings.lastPane == .general)
    #expect(!settings.toolbar.isVisible)
    #expect(settings.toolbar.showsFullURL)
  }

  /// Arc's key names: Count Favorites is stored inverted (`excludeFavoritesInSwitchToNthTab`).
  @Test func persistsUnderArcsKeysAndReadsBack() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    settings.tabNavigation.countsFavorites = false
    settings.tabNavigation.ninthOpensNinth = true
    settings.peekLinks.opensCrossSiteLinks = false
    settings.lastPane = .shortcuts

    #expect(suite.defaults.object(forKey: "excludeFavoritesInSwitchToNthTab") as? Bool == true)
    #expect(suite.defaults.object(forKey: "switchToNinthSidebarItemEnabled") as? Bool == true)
    #expect(suite.defaults.object(forKey: PeekLinkSettings.crossSiteKey) as? Bool == false)
    #expect(suite.defaults.string(forKey: "settingsLastPane") == "shortcuts")

    let reread = AppSettings(defaults: suite.defaults)
    #expect(!reread.tabNavigation.countsFavorites)
    #expect(reread.tabNavigation.ninthOpensNinth)
    #expect(!reread.peekLinks.opensCrossSiteLinks)
    #expect(reread.peekLinks.opensShiftClickedLinks)
    #expect(reread.lastPane == .shortcuts)
  }

  /// The Toolbar keys are unchanged, so existing users keep their values.
  @Test func toolbarKeysAreUnchanged() throws {
    let suite = try Suite()
    suite.defaults.set(true, forKey: "topBarURLEnabled")
    suite.defaults.set(false, forKey: "toolbarShowFullURLsEnabledPreference")
    let settings = AppSettings(defaults: suite.defaults)
    #expect(settings.toolbar.isVisible)
    #expect(!settings.toolbar.showsFullURL)
    settings.toolbar.isVisible = false
    #expect(suite.defaults.object(forKey: "topBarURLEnabled") as? Bool == false)
  }

  /// A shared `ToolbarSetting` passed in is the one every window observes.
  @Test func adoptsTheSharedToolbarSetting() throws {
    let suite = try Suite()
    let toolbar = ToolbarSetting(defaults: suite.defaults)
    let settings = AppSettings(defaults: suite.defaults, toolbar: toolbar)
    #expect(settings.toolbar === toolbar)
  }

  /// The window position lives in the suite too, not in AppKit's frame autosave (the standard defaults).
  @Test func windowPositionRoundTrips() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    #expect(settings.windowTopLeft == nil)
    settings.windowTopLeft = CGPoint(x: 120, y: 840)
    #expect(AppSettings(defaults: suite.defaults).windowTopLeft == CGPoint(x: 120, y: 840))
    settings.windowTopLeft = nil
    #expect(AppSettings(defaults: suite.defaults).windowTopLeft == nil)
  }

  @Test func unknownStoredPaneFallsBackToGeneral() throws {
    let suite = try Suite()
    suite.defaults.set("account", forKey: "settingsLastPane")
    #expect(AppSettings(defaults: suite.defaults).lastPane == .general)
  }

  @Test func observersHearEachChangeOnce() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    let recorder = Recorder()
    settings.addObserver(recorder)
    settings.addObserver(recorder)                       // added twice, told once

    settings.tabNavigation.countsFavorites = false
    #expect(recorder.count == 1)
    settings.tabNavigation.countsFavorites = false      // unchanged: no notification
    #expect(recorder.count == 1)
    settings.peekLinks.opensShiftClickedLinks = false
    #expect(recorder.count == 2)
    settings.lastPane = .advanced                        // window state, not a setting other windows apply
    #expect(recorder.count == 2)
  }

  @Test func observersAreHeldWeakly() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    var recorder: Recorder? = Recorder()
    weak var weakRecorder = recorder
    settings.addObserver(try #require(recorder))
    recorder = nil
    #expect(weakRecorder == nil)
    settings.tabNavigation.ninthOpensNinth = true        // no crash, nothing to tell
  }

  @Test func ephemeralNeverWritesDefaults() throws {
    let settings = AppSettings.ephemeral()
    settings.tabNavigation.countsFavorites = false
    #expect(!settings.tabNavigation.countsFavorites, "kept in memory")
    #expect(UserDefaults.standard.object(forKey: "settingsEphemeralProbe") == nil)
  }

  // MARK: Crash reports (#129)

  @Test func crashReportsAreOffAndUnansweredByDefault() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    #expect(!settings.sendsCrashReports)
    #expect(!settings.crashReportAskAnswered)
  }

  @Test func crashReportValuesPersistUnderTheirKeysAndNotifyOnce() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    let recorder = Recorder()
    settings.addObserver(recorder)
    settings.sendsCrashReports = true
    settings.sendsCrashReports = true                    // unchanged: no notification
    settings.crashReportAskAnswered = true
    #expect(recorder.count == 2)
    #expect(suite.defaults.bool(forKey: AppSettings.Key.sendsCrashReports))
    #expect(suite.defaults.bool(forKey: AppSettings.Key.crashReportAskAnswered))
    #expect(AppSettings(defaults: suite.defaults).sendsCrashReports)
  }
}

/// The seven panes, their order (Cmd-1 to Cmd-7), names and symbols (docs/design/settings.md, sections 3 and 4).
struct SettingsPaneTests {
  @Test func panesInOrder() {
    #expect(SettingsPane.allCases.map(\.rawValue) ==
      ["general", "spaces", "appearance", "shortcuts", "extensions", "privacy", "advanced"])
    #expect(SettingsPane.allCases.map(\.label) ==
      ["General", "Spaces", "Appearance", "Shortcuts", "Extensions", "Privacy", "Advanced"])
    #expect(SettingsPane.spaces.title == "Spaces and Profiles")
    #expect(SettingsPane.privacy.title == "Privacy and Security")
    #expect(SettingsPane.general.title == "General")
    #expect(SettingsPane.allCases.map(\.symbolName) == ["gearshape", "square.on.square", "circle.lefthalf.filled",
      "command", "puzzlepiece.extension", "checkmark.shield", "slider.horizontal.3"])
  }

  @Test func commandNumbers() {
    #expect(SettingsPane(commandNumber: 1) == .general)
    #expect(SettingsPane(commandNumber: 7) == .advanced)
    #expect(SettingsPane(commandNumber: 8) == nil)
    #expect(SettingsPane(commandNumber: 0) == nil)
  }
}

/// The download location and the Library's last section (#132, BH-181, BH-182).
@MainActor
struct DownloadSettingsTests {
  private final class Suite {
    let name = "dev.arkt.tests.settings.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
    deinit { UserDefaults().removePersistentDomain(forName: name) }
  }

  private final class Recorder: AppSettingsObserver {
    var count = 0
    func appSettingsDidChange(_ settings: AppSettings) { count += 1 }
  }

  @Test func `the location defaults to saving in the default folder`() throws {
    let settings = AppSettings(defaults: try Suite().defaults)
    #expect(settings.downloadLocation == DownloadLocationSetting())
    let downloads = URL(filePath: "/Users/test/Downloads", directoryHint: .isDirectory)
    #expect(settings.downloadLocation.preference(defaultFolder: downloads) == .folder(downloads))
    #expect(settings.libraryLastSection == .downloads)
  }

  @Test func `the location persists, tells observers and maps to a preference`() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    let recorder = Recorder()
    settings.addObserver(recorder)
    let folder = URL(filePath: "/Users/test/Desktop", directoryHint: .isDirectory)
    settings.downloadLocation = DownloadLocationSetting(asksWhereToSave: false, folder: folder)
    settings.downloadLocation = DownloadLocationSetting(asksWhereToSave: false, folder: folder)   // unchanged
    #expect(recorder.count == 1)
    let reread = AppSettings(defaults: suite.defaults)
    #expect(reread.downloadLocation.folder?.standardizedFileURL == folder.standardizedFileURL)
    #expect(reread.downloadLocation.placeName(defaultFolder: folder) == "Desktop")
    settings.downloadLocation.asksWhereToSave = true
    let downloads = URL(filePath: "/Users/test/Downloads", directoryHint: .isDirectory)
    #expect(settings.downloadLocation.preference(defaultFolder: downloads) == .ask)
    #expect(settings.downloadLocation.placeName(defaultFolder: downloads) == "Ask Where to Save")
  }

  @Test func `the last Library section persists without telling observers`() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    let recorder = Recorder()
    settings.addObserver(recorder)
    settings.libraryLastSection = .history
    #expect(recorder.count == 0)
    #expect(AppSettings(defaults: suite.defaults).libraryLastSection == .history)
  }
}
