import Archive
import CoreBridge
import Foundation
import ShellUI
import Testing

/// Settings > Spaces and Profiles > Archive (#448): the two threshold rows read and write `ArchiveSettings` through
/// `ArchiveSettingsModel`, which tells the auto-archive timer at once and stores the change.
@MainActor
struct ArchiveSettingsModelTests {
  private static let date = Date(timeIntervalSinceReferenceDate: 900_000_000)

  // MARK: Titles

  @Test func everyPopUpTitleNamesOneThreshold() {
    let titles = SettingsWindowController.archiveAfterTitles
    #expect(titles == ["1 hour", "6 hours", "12 hours", "24 hours", "7 days", "30 days", "Never"])
    #expect(titles.compactMap(AutoArchiveThreshold.init(settingsTitle:)) == AutoArchiveThreshold.allCases)
    #expect(AutoArchiveThreshold.allCases.map(\.settingsTitle) == titles)
    #expect(AutoArchiveThreshold(settingsTitle: "2 hours") == nil)
  }

  // MARK: Model

  @Test func defaultsUntilLoadedThenTheStoredValues() async {
    let state = FakeArchiveState()
    var stored = ArchiveSettings()
    stored.setTabThreshold(.sevenDays, forProfile: ArchiveSettings.defaultProfile, scope: .thisProfile)
    stored.littleArcThreshold = .oneHour
    await state.setSettings(stored)
    let model = ArchiveSettingsModel(state: state, now: { Self.date })
    #expect(model.tabThreshold == .tabsDefault)
    #expect(model.littleArktThreshold == .littleArcDefault)

    await model.load()

    #expect(model.settings == stored)
    #expect(model.tabThreshold == .sevenDays)
    #expect(model.littleArktThreshold == .oneHour)
  }

  @Test func changingTheTabThresholdTellsTheListenerAtOnceAndStoresIt() async {
    let state = FakeArchiveState()
    let model = ArchiveSettingsModel(state: state, now: { Self.date })
    await model.load()
    var heard: [ArchiveSettings] = []
    model.onChange = { heard.append($0) }

    model.setTabThreshold(.thirtyDays)

    #expect(model.tabThreshold == .thirtyDays)
    #expect(heard.map { $0.tabThreshold(forProfile: ArchiveSettings.defaultProfile) } == [.thirtyDays])
    await model.flush()
    let stored = await state.storedSettings
    #expect(stored.tabThresholdsByProfile == [ArchiveSettings.defaultProfile: .thirtyDays])
    #expect(stored.littleArcThreshold == .littleArcDefault)
  }

  @Test func changingTheLittleArktThresholdKeepsTheTabThreshold() async {
    let state = FakeArchiveState()
    var stored = ArchiveSettings()
    stored.setTabThreshold(.twentyFourHours, forProfile: ArchiveSettings.defaultProfile, scope: .thisProfile)
    await state.setSettings(stored)
    let model = ArchiveSettingsModel(state: state, now: { Self.date })
    await model.load()

    model.setLittleArktThreshold(.never)
    await model.flush()

    #expect(model.littleArktThreshold == .never)
    #expect(model.tabThreshold == .twentyFourHours)
    let saved = await state.storedSettings
    #expect(saved.littleArcThreshold == .never)
    #expect(saved.tabThreshold(forProfile: ArchiveSettings.defaultProfile) == .twentyFourHours)
  }

  @Test func settingTheSameValueAgainDoesNothing() async {
    let state = FakeArchiveState()
    let model = ArchiveSettingsModel(state: state, now: { Self.date })
    await model.load()
    var heard = 0
    model.onChange = { _ in heard += 1 }

    model.setLittleArktThreshold(.littleArcDefault)
    await model.flush()

    #expect(heard == 0)
    #expect(await state.settingsUpdateCount == 0)
  }

  /// A change made before the stored values arrive wins over them, and the other stored field still arrives.
  @Test func aChangeBeforeTheLoadIsKeptAndTheOtherStoredFieldArrives() async {
    let state = FakeArchiveState()
    var stored = ArchiveSettings()
    stored.littleArcThreshold = .thirtyDays
    await state.setSettings(stored)
    let model = ArchiveSettingsModel(state: state, now: { Self.date })

    model.setTabThreshold(.oneHour)
    await model.load()
    await model.flush()

    #expect(model.tabThreshold == .oneHour)
    #expect(model.littleArktThreshold == .thirtyDays)
  }

  @Test func aFailedLoadKeepsTheDefaults() async {
    let state = FakeArchiveState()
    await state.setFailsLoads(true)
    let model = ArchiveSettingsModel(state: state, now: { Self.date })
    await model.load()
    #expect(model.settings == ArchiveSettings())
  }

  // MARK: Settings services

  @Test func theRowsReadAndWriteTitles() async {
    let state = FakeArchiveState()
    let model = ArchiveSettingsModel(state: state, now: { Self.date })
    await model.load()
    let rows = model.settingsRows

    #expect(rows.tabsAfter() == "12 hours")
    #expect(rows.littleArktAfter() == "6 hours")
    rows.setTabsAfter("7 days")
    rows.setLittleArktAfter("Never")
    rows.setTabsAfter("not a duration")

    #expect(model.tabThreshold == .sevenDays)
    #expect(model.littleArktThreshold == .never)
    #expect(rows.tabsAfter() == "7 days")
    #expect(rows.littleArktAfter() == "Never")
  }
}
