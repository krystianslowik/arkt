import AppKit
import Foundation
import Testing
@testable import ShellUI

/// The sidebar banner's model (#648, design/sidebar-banner): one notice at a time from a notice source, dismissal
/// stored per notice id, and one VoiceOver announcement per notice.
@MainActor
struct SidebarBannerModelTests {
  private static let update = SidebarNotice.update(version: "1.4.2")
  private static let announcement = SidebarNotice.announcement(
    id: "archive-search", title: "Archived tabs can now be searched by what was on the page",
    body: "Open the Archive and type a few words you remember.", actionTitle: "Open Archive")

  private func defaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "SidebarBannerModelTests.\(UUID().uuidString)"))
  }

  private final class Spoken {
    var words: [String] = []
  }

  private func model(_ source: FakeSidebarNoticeSource, dismissals: SidebarNoticeDismissals = .ephemeral(),
                     spoken: Spoken = Spoken()) -> SidebarBannerModel {
    SidebarBannerModel(source: source, dismissals: dismissals) { text, _ in spoken.words.append(text) }
  }

  @Test func showsNothingWithoutANotice() {
    let model = model(FakeSidebarNoticeSource())
    #expect(model.current == nil)
  }

  @Test func showsTheSourcesFirstNotice() {
    let source = FakeSidebarNoticeSource(notices: [Self.update, Self.announcement])
    #expect(model(source).current == Self.update)
  }

  @Test func followsTheSourceAndTellsObservers() {
    let source = FakeSidebarNoticeSource()
    let model = model(source)
    var seen: [SidebarNotice?] = []
    let observation = model.addObserver { seen.append($0) }
    source.notices = [Self.announcement]
    source.notices = []
    #expect(seen == [Self.announcement, nil])
    observation.cancel()
    source.notices = [Self.update]
    #expect(seen.count == 2, "a cancelled observer hears nothing")
  }

  @Test func dismissingShowsTheNextNoticeAndStoresTheID() throws {
    let store = try defaults()
    let source = FakeSidebarNoticeSource(notices: [Self.update, Self.announcement])
    let model = model(source, dismissals: SidebarNoticeDismissals(defaults: store))
    model.dismiss()
    #expect(model.current == Self.announcement)
    #expect(SidebarNoticeDismissals(defaults: store).contains(Self.update.id))
  }

  @Test func aDismissedNoticeNeverComesBackForTheSameVersion() throws {
    let store = try defaults()
    model(FakeSidebarNoticeSource(notices: [Self.update]), dismissals: SidebarNoticeDismissals(defaults: store))
      .dismiss()
    let relaunched = model(FakeSidebarNoticeSource(notices: [Self.update]),
                           dismissals: SidebarNoticeDismissals(defaults: store))
    #expect(relaunched.current == nil)
    let next = model(FakeSidebarNoticeSource(notices: [.update(version: "1.4.3")]),
                     dismissals: SidebarNoticeDismissals(defaults: store))
    #expect(next.current?.id == "update-1.4.3", "a newer version is a new notice")
  }

  @Test func theDismissalListIsCapped() throws {
    let store = try defaults()
    let dismissals = SidebarNoticeDismissals(defaults: store)
    for index in 0..<(SidebarNoticeDismissals.limit + 5) { dismissals.insert("notice-\(index)") }
    let stored = try #require(store.stringArray(forKey: SidebarNoticeDismissals.defaultsKey))
    #expect(stored.count == SidebarNoticeDismissals.limit)
    #expect(!SidebarNoticeDismissals(defaults: store).contains("notice-0"), "the oldest go first")
    #expect(SidebarNoticeDismissals(defaults: store).contains("notice-\(SidebarNoticeDismissals.limit + 4)"))
  }

  @Test func theEphemeralStoreNeverTouchesDefaults() {
    let dismissals = SidebarNoticeDismissals.ephemeral()
    dismissals.insert("x")
    #expect(dismissals.contains("x"))
    #expect(!SidebarNoticeDismissals.ephemeral().contains("x"))
  }

  @Test func restartGoesToTheSourceAndKeepsTheNotice() {
    let source = FakeSidebarNoticeSource(notices: [Self.update])
    let model = model(source)
    model.performAction()
    #expect(source.performed == [Self.update])
    #expect(model.current == Self.update, "the update stays until the source withdraws it")
  }

  @Test func anAnnouncementsActionGoesToTheSourceAndRetiresIt() {
    let source = FakeSidebarNoticeSource(notices: [Self.announcement])
    let model = model(source)
    model.performAction()
    #expect(source.performed == [Self.announcement])
    #expect(model.current == nil)
  }

  @Test func voiceOverHearsEachNoticeOnce() {
    let spoken = Spoken()
    let source = FakeSidebarNoticeSource(notices: [Self.update])
    let model = model(source, spoken: spoken)
    source.notices = [Self.update]                    // the same notice again
    source.notices = []
    source.notices = [Self.update]                    // back after a gap: still the same notice
    source.notices = [Self.announcement]
    #expect(spoken.words == ["Update ready. Restart", Self.announcement.title])
    _ = model
  }

  @Test func theUpdateNoticeReadsAsDesigned() {
    #expect(Self.update.id == "update-1.4.2")
    #expect(Self.update.rowLabel == "Update")
    #expect(Self.update.actionTitle == "Restart")
    #expect(Self.update.isUpdate)
    #expect(Self.update.spokenText == "Update ready. Restart")
    #expect(Self.announcement.rowLabel == Self.announcement.title)
    #expect(!Self.announcement.isUpdate)
  }
}

/// The banner's motion (design/sidebar-banner, Motion) as data.
struct SidebarBannerMotionTests {
  @Test func appearRisesEightPointsOnFirmAndRowsMakeRoom() {
    let step = SidebarBannerMotion.appear(reduceMotion: false)
    #expect(step.offset == 8)
    #expect(step.duration == 0.24)
    #expect(step.curve == SidebarBannerMotion.firm)
    #expect(step.movesRows)
  }

  @Test func reduceMotionFadesOnlyAndRowsJump() {
    for step in [SidebarBannerMotion.appear(reduceMotion: true), SidebarBannerMotion.dismiss(reduceMotion: true)] {
      #expect(step.offset == 0)
      #expect(step.scale == 1)
      #expect(!step.movesRows)
    }
    let popover = SidebarBannerMotion.popover(reduceMotion: true)
    #expect(popover.scale == 1)
    #expect(popover.offset == 0)
  }

  @Test func dismissFadesAndRowsSettle() {
    let step = SidebarBannerMotion.dismiss(reduceMotion: false)
    #expect(step.duration == 0.15)
    #expect(step.offset == 0)
    #expect(step.movesRows)
  }

  @Test func thePopoverScalesFromNinetySevenPercentOnFirmFast() {
    let step = SidebarBannerMotion.popover(reduceMotion: false)
    #expect(step.scale == 0.97)
    #expect(step.duration == 0.22)
    #expect(step.curve == SidebarBannerMotion.firmFast)
  }
}

/// Row geometry (design/sidebar-banner, The row): 34 pt, padding 9 leading and 5 trailing, gap 8.
struct SidebarBannerLayoutTests {
  @Test func anUpdateRowFitsGlyphLabelAndPill() {
    let layout = SidebarBannerLayout(rowWidth: 224, isUpdate: true, labelWidth: 50, pillWidth: 62)
    #expect(!layout.isCompact)
    #expect(layout.glyph == CGRect(x: 9, y: 9, width: 16, height: 16))
    #expect(layout.label.minX == 33)
    #expect(layout.pill == CGRect(x: 224 - 5 - 62, y: 6, width: 62, height: 22))
    #expect(layout.label.maxX <= layout.pill.minX - 8)
    #expect(layout.chevron == nil)
  }

  @Test func theSmallestSidebarHidesTheLabelAndTheRestartPillTakesTheRest() {
    // 150 pt sidebar, 8 pt padding each side.
    let layout = SidebarBannerLayout(rowWidth: 134, isUpdate: true, labelWidth: 50, pillWidth: 62)
    #expect(layout.isCompact)
    #expect(layout.label.width == 0)
    #expect(layout.pill.minX == 33)
    #expect(abs(layout.pill.maxX - CGFloat(129)) < 0.001)
  }

  @Test func anAnnouncementTruncatesItsTitleBeforeTheChevron() {
    let layout = SidebarBannerLayout(rowWidth: 224, isUpdate: false, labelWidth: 600, pillWidth: 0)
    let chevron = try! #require(layout.chevron)
    #expect(chevron.maxX <= 224 - 5)
    #expect(layout.label.maxX <= chevron.minX - 8)
    #expect(layout.label.minX == 33)
    #expect(layout.pill == .zero)
  }

  @Test func nothingIsNegativeInAZeroWidthRow() {
    for isUpdate in [true, false] {
      let layout = SidebarBannerLayout(rowWidth: 0, isUpdate: isUpdate, labelWidth: 80, pillWidth: 62)
      #expect(layout.label.width >= 0)
      #expect(layout.pill.width >= 0)
    }
  }
}
