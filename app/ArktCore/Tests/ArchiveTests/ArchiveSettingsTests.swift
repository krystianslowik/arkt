import Archive
import Foundation
import Testing
import SidebarModel

struct ArchiveSettingsTests {
  /// BH-080, BH-137: Arc's fresh-install defaults.
  @Test func defaultsMatchArc() {
    let settings = ArchiveSettings()
    #expect(settings.tabThreshold(forProfile: "default") == .twelveHours)
    #expect(settings.tabThreshold(forProfile: "anything") == .twelveHours)
    #expect(settings.littleArcThreshold == .sixHours)
  }

  /// BH-081: seven options in picker order, `never` included (BH-082: whether the picker shows it is the UI's call).
  @Test func optionsAreArcsSevenInOrder() {
    #expect(AutoArchiveThreshold.allCases == [
      .oneHour, .sixHours, .twelveHours, .twentyFourHours, .sevenDays, .thirtyDays, .never,
    ])
    #expect(AutoArchiveThreshold.allCases.compactMap(\.interval) == [
      3600, 21_600, 43_200, 86_400, 604_800, 2_592_000,
    ])
  }

  /// BH-081, BH-082: `never` is a selectable value for tabs and Little Arc.
  @Test func neverIsAnOption() {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.never, forProfile: "work", scope: .thisProfile)
    settings.littleArcThreshold = .never
    #expect(settings.tabThreshold(forProfile: "work") == .never)
    #expect(settings.littleArcThreshold.interval == nil)
  }

  /// BH-083: a profile without its own value follows the Default profile, resolved at lookup.
  @Test func newProfilesInheritTheDefaultProfile() {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.sevenDays, forProfile: "default", scope: .thisProfile)
    #expect(settings.tabThreshold(forProfile: "brand-new") == .sevenDays)
    settings.setTabThreshold(.oneHour, forProfile: "default", scope: .thisProfile)
    #expect(settings.tabThreshold(forProfile: "brand-new") == .oneHour)  // lookup time, not a copy
  }

  /// BH-083, BH-179: "only this Profile".
  @Test func thisProfileScopeChangesOnlyThatProfile() {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "work", scope: .thisProfile)
    #expect(settings.tabThreshold(forProfile: "work") == .oneHour)
    #expect(settings.tabThreshold(forProfile: "default") == .twelveHours)
  }

  /// BH-083: "apply to all Profiles".
  @Test func allProfilesScopeChangesEveryKnownProfile() {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "work", scope: .thisProfile)
    settings.setTabThreshold(.thirtyDays, forProfile: "home", scope: .allProfiles, knownProfiles: ["work", "home"])
    for profile in ["work", "home", "default", "later"] {
      #expect(settings.tabThreshold(forProfile: profile) == .thirtyDays)
    }
  }

  @Test func lossyDecodingKeepsGoodValuesAndDefaultsBadOnes() throws {
    let json = Data("""
      {"tabThresholdsByProfile": {"default": "sevenDays", "work": "fortnight", "home": 42, "kid": "oneHour"},
       "littleArcThreshold": 42}
      """.utf8)
    let settings = try JSONDecoder().decode(ArchiveSettings.self, from: json)
    #expect(settings.tabThreshold(forProfile: "default") == .sevenDays)
    #expect(settings.tabThreshold(forProfile: "work") == .sevenDays)  // bad entry dropped, inherits default
    #expect(settings.tabThreshold(forProfile: "home") == .sevenDays)
    #expect(settings.tabThreshold(forProfile: "kid") == .oneHour)
    #expect(settings.littleArcThreshold == .sixHours)
    #expect(try JSONDecoder().decode(ArchiveSettings.self, from: Data("{}".utf8)) == ArchiveSettings())
    let wrongShape = Data(#"{"tabThresholdsByProfile": [1, 2], "littleArcThreshold": "oneHour"}"#.utf8)
    #expect(try JSONDecoder().decode(ArchiveSettings.self, from: wrongShape)
      == ArchiveSettings(littleArcThreshold: .oneHour))
  }

  @Test func settingsRoundTrip() throws {
    var settings = ArchiveSettings()
    settings.setTabThreshold(.never, forProfile: "work", scope: .thisProfile)
    settings.littleArcThreshold = .oneHour
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(ArchiveSettings.self, from: data) == settings)
  }

  @Test func stateRoundTripsAndDecodesLossily() throws {
    let state = ArchiveState(
      autoArchiveStartedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.5), educationBannerDismissed: true)
    #expect(try JSONDecoder().decode(ArchiveState.self, from: JSONEncoder().encode(state)) == state)
    #expect(try JSONDecoder().decode(ArchiveState.self, from: Data("{}".utf8)) == ArchiveState())
    let bad = Data(#"{"autoArchiveStartedAt": "soon", "educationBannerDismissed": true}"#.utf8)
    #expect(try JSONDecoder().decode(ArchiveState.self, from: bad)
      == ArchiveState(autoArchiveStartedAt: nil, educationBannerDismissed: true))
  }

  /// The auto-archive start is set once (first resolve) and then kept, so `AutoArchiveInput.startedAt` is stable.
  @Test func autoArchiveStartIsResolvedOnce() {
    var state = ArchiveState()
    let first = Date(timeIntervalSinceReferenceDate: 800_000_000)
    #expect(state.resolveAutoArchiveStart(now: first) == first)
    #expect(state.autoArchiveStartedAt == first)
    #expect(state.resolveAutoArchiveStart(now: first.addingTimeInterval(3600)) == first)
    #expect(state.autoArchiveStartedAt == first)
  }

  /// BH-179 end to end: the policy uses the settings lookup per Space profile.
  @Test func policyHonorsPerProfileSettings() throws {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "work", scope: .thisProfile)
    var sidebar = Sidebar()
    let home = sidebar.addSpace(title: "Home")
    let work = sidebar.addSpace(title: "Work", profile: "work")
    _ = try sidebar.addTab(
      url: URL(string: "https://example.com/h")!, title: "H", lastActiveAt: now.addingTimeInterval(-7200),
      in: .today(home))
    let workTab = try sidebar.addTab(
      url: URL(string: "https://example.com/w")!, title: "W", lastActiveAt: now.addingTimeInterval(-7200),
      in: .today(work))
    let lookup = settings  // a let: @Sendable closures cannot capture a var
    let input = AutoArchiveInput(now: now, startedAt: .distantPast) { lookup.tabThreshold(forProfile: $0) }
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input) == [workTab])
  }
}
