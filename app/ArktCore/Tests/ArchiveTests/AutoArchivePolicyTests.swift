import Archive
import Foundation
import Testing
import SidebarModel

struct AutoArchivePolicyTests {
  static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
  static let hour: TimeInterval = 3600
  static func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
  static func url(_ path: String) -> URL { URL(string: "https://example.com/\(path)")! }

  static func input(
    threshold: AutoArchiveThreshold = .twelveHours,
    perProfile: [String: AutoArchiveThreshold] = [:],
    exempt: Set<NodeID> = [],
    startedAt: Date = .distantPast
  ) -> AutoArchiveInput {
    AutoArchiveInput(now: now, startedAt: startedAt, exempt: exempt) { perProfile[$0] ?? threshold }
  }

  /// Space "Work" with one Today tab last active `idle` seconds ago.
  static func oneTodayTab(idle: TimeInterval) throws -> (Sidebar, NodeID) {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let tab = try sidebar.addTab(
      url: url("t"), title: "T", lastActiveAt: ago(idle), in: .today(space), createdAt: ago(100 * hour))
    return (sidebar, tab)
  }

  // MARK: Thresholds (BH-080, BH-081, CF-04)

  /// BH-081, CF-04: exactly the seven options, in Arc's picker order.
  @Test func thresholdOptionsMatchArc() {
    #expect(AutoArchiveThreshold.allCases == [
      .oneHour, .sixHours, .twelveHours, .twentyFourHours, .sevenDays, .thirtyDays, .never,
    ])
  }

  /// BH-081: each option's interval.
  @Test(arguments: [
    (AutoArchiveThreshold.oneHour, 3600.0 as TimeInterval?),
    (.sixHours, 21_600),
    (.twelveHours, 43_200),
    (.twentyFourHours, 86_400),
    (.sevenDays, 604_800),
    (.thirtyDays, 2_592_000),
    (.never, nil),
  ])
  func thresholdIntervals(_ threshold: AutoArchiveThreshold, _ expected: TimeInterval?) {
    #expect(threshold.interval == expected)
  }

  /// BH-080, BH-137: fresh-install defaults.
  @Test func defaults() {
    #expect(AutoArchiveThreshold.tabsDefault == .twelveHours)
    #expect(AutoArchiveThreshold.littleArcDefault == .sixHours)
  }

  /// Raw values reuse the threshold strings Arc writes in its settings, where known.
  @Test func rawValuesUseArcCaseNames() {
    #expect(AutoArchiveThreshold.twelveHours.rawValue == "twelveHours")
    #expect(AutoArchiveThreshold.twentyFourHours.rawValue == "twentyFourHours")
    #expect(AutoArchiveThreshold.sevenDays.rawValue == "sevenDays")
    #expect(AutoArchiveThreshold.thirtyDays.rawValue == "thirtyDays")
  }

  // MARK: Today tabs (BH-080)

  /// BH-080: fresh install, a Today tab unviewed for 12 hours is auto-archived (boundary included).
  @Test func todayTabIdleForTwelveHoursIsArchivedByDefault() throws {
    let (sidebar, tab) = try Self.oneTodayTab(idle: 12 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [tab])
  }

  /// BH-080
  @Test func todayTabJustUnderTheThresholdStays() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 12 * Self.hour - 1)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()).isEmpty)
  }

  /// BH-080: viewing a tab resets its timer (lastActiveAt wins over an old createdAt).
  @Test func viewingResetsTheTimer() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 60)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)).isEmpty)
  }

  /// BH-081: "never" archives nothing.
  @Test func neverArchivesNothing() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 1000 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .never)).isEmpty)
  }

  /// BH-081: every finite option archives at exactly its interval and not one second before.
  @Test(arguments: AutoArchiveThreshold.allCases.filter { $0 != .never })
  func everyOptionUsesItsInterval(_ threshold: AutoArchiveThreshold) throws {
    let interval = try #require(threshold.interval)
    let (atLimit, tab) = try Self.oneTodayTab(idle: interval)
    #expect(AutoArchivePolicy.itemsToArchive(in: atLimit, Self.input(threshold: threshold)) == [tab])
    let (over, overTab) = try Self.oneTodayTab(idle: interval + 1)
    #expect(AutoArchivePolicy.itemsToArchive(in: over, Self.input(threshold: threshold)) == [overTab])
    let (under, _) = try Self.oneTodayTab(idle: interval - 1)
    #expect(AutoArchivePolicy.itemsToArchive(in: under, Self.input(threshold: threshold)).isEmpty)
  }

  /// BH-080: a never-opened tab (no lastActiveAt) ages from its createdAt.
  @Test func tabWithoutLastActiveUsesCreatedAt() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let old = try sidebar.addTab(url: Self.url("o"), title: "O", in: .today(space), createdAt: Self.ago(13 * Self.hour))
    try sidebar.addTab(url: Self.url("n"), title: "N", in: .today(space), createdAt: Self.ago(Self.hour))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [old])
  }

  // MARK: Never-archived placements (BH-048, BH-054, BH-084, BH-090)

  enum Placement: String, CaseIterable, Sendable {
    case pinnedTab, favoriteTab, tabInPinnedFolder, tabInTodayFolder, todayFolder, nestedTodayFolderTab
    case splitInPinned, splitInFolder, splitInFavorites
  }

  /// BH-048 (Favorites), BH-054 (Pinned), BH-084 (pinned, Favorite, foldered), BH-090 (folder contents):
  /// no item in these placements is a candidate, however long it has been idle.
  @Test(arguments: Placement.allCases)
  func neverArchivedPlacements(_ placement: Placement) throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let stale = Self.ago(400 * Self.hour)
    func tab(in location: Location) throws {
      try sidebar.addTab(url: Self.url("x"), title: "X", lastActiveAt: stale, in: location, createdAt: stale)
    }
    func split(in location: Location) throws {
      let split = try sidebar.addSplit(
        orientation: .horizontal, widthFactors: [0.5, 0.5], in: location, createdAt: stale)
      try tab(in: .split(split))
      try tab(in: .split(split))
    }
    switch placement {
    case .pinnedTab: try tab(in: .pinned(space))
    case .favoriteTab: try tab(in: .favorites(profile: "default"))
    case .tabInPinnedFolder: try tab(in: .folder(sidebar.addFolder(title: "P", in: .pinned(space), createdAt: stale)))
    case .tabInTodayFolder: try tab(in: .folder(sidebar.addFolder(title: "T", in: .today(space), createdAt: stale)))
    case .todayFolder: try sidebar.addFolder(title: "Empty", in: .today(space), createdAt: stale)
    case .nestedTodayFolderTab:
      let outer = try sidebar.addFolder(title: "O", in: .today(space), createdAt: stale)
      let inner = try sidebar.addFolder(title: "I", in: .folder(outer), createdAt: stale)
      try tab(in: .folder(inner))
    case .splitInPinned: try split(in: .pinned(space))
    case .splitInFolder: try split(in: .folder(sidebar.addFolder(title: "F", in: .today(space), createdAt: stale)))
    case .splitInFavorites: try split(in: .favorites(profile: "default"))
    }
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)).isEmpty)
  }

  /// BH-054, BH-048, BH-084: in a mixed sidebar only the Today tab is picked.
  @Test func onlyTodayItemsAreCandidates() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let stale = Self.ago(400 * Self.hour)
    try sidebar.addTab(url: Self.url("p"), title: "P", lastActiveAt: stale, in: .pinned(space))
    try sidebar.addTab(url: Self.url("f"), title: "F", lastActiveAt: stale, in: .favorites(profile: "default"))
    let folder = try sidebar.addFolder(title: "D", in: .today(space), createdAt: stale)
    try sidebar.addTab(url: Self.url("d"), title: "D", lastActiveAt: stale, in: .folder(folder))
    let today = try sidebar.addTab(url: Self.url("t"), title: "T", lastActiveAt: stale, in: .today(space))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)) == [today])
  }

  // MARK: Profiles (BH-083, BH-179)

  /// BH-083, BH-179: each profile has its own threshold; a Space uses its profile's.
  @Test func perProfileThresholds() throws {
    var sidebar = Sidebar()
    let personal = sidebar.addSpace(title: "Home", profile: "default")
    let work = sidebar.addSpace(title: "Work", profile: "work")
    try sidebar.addTab(url: Self.url("h"), title: "H", lastActiveAt: Self.ago(2 * Self.hour), in: .today(personal))
    let workTab = try sidebar.addTab(
      url: Self.url("w"), title: "W", lastActiveAt: Self.ago(2 * Self.hour), in: .today(work))
    let input = Self.input(threshold: .twelveHours, perProfile: ["work": .oneHour])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input) == [workTab])
  }

  /// BH-179, BH-081: "never" on one profile leaves its Spaces alone while another profile still archives.
  @Test func neverOnOneProfileOnly() throws {
    var sidebar = Sidebar()
    let home = sidebar.addSpace(title: "Home", profile: "default")
    let work = sidebar.addSpace(title: "Work", profile: "work")
    let homeTab = try sidebar.addTab(
      url: Self.url("h"), title: "H", lastActiveAt: Self.ago(400 * Self.hour), in: .today(home))
    try sidebar.addTab(url: Self.url("w"), title: "W", lastActiveAt: Self.ago(400 * Self.hour), in: .today(work))
    let input = Self.input(threshold: .twelveHours, perProfile: ["work": .never])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input) == [homeTab])
  }

  /// BH-083: two Spaces of the same profile share its threshold.
  @Test func spacesOfOneProfileShareItsThreshold() throws {
    var sidebar = Sidebar()
    let a = sidebar.addSpace(title: "A", profile: "work")
    let b = sidebar.addSpace(title: "B", profile: "work")
    let tabA = try sidebar.addTab(url: Self.url("a"), title: "A", lastActiveAt: Self.ago(2 * Self.hour), in: .today(a))
    let tabB = try sidebar.addTab(url: Self.url("b"), title: "B", lastActiveAt: Self.ago(2 * Self.hour), in: .today(b))
    let input = Self.input(threshold: .twelveHours, perProfile: ["work": .oneHour])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input) == [tabA, tabB])
  }

  // MARK: Exemptions (BH-076, visible tabs [I])

  /// BH-076: a Today tab playing media is not archived. Also covers a tab visible in any window [I]: both arrive
  /// through `exempt`.
  @Test func exemptTabsStay() throws {
    let (sidebar, tab) = try Self.oneTodayTab(idle: 400 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(exempt: [tab])).isEmpty)
  }

  /// BH-076: exempting one tab leaves its idle siblings archivable.
  @Test func exemptionIsPerItem() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let stale = Self.ago(400 * Self.hour)
    let playing = try sidebar.addTab(url: Self.url("m"), title: "M", lastActiveAt: stale, in: .today(space))
    let idle = try sidebar.addTab(url: Self.url("i"), title: "I", lastActiveAt: stale, in: .today(space))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(exempt: [playing])) == [idle])
  }

  // MARK: Start time

  /// Arc's autoArchiveStartTime: idle time never counts from before auto-archive started.
  @Test func idleTimeCountsFromStartedAt() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 400 * Self.hour)
    let input = Self.input(startedAt: Self.ago(Self.hour))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, input).isEmpty)
  }

  /// Once the threshold has passed since startedAt, the clamped tab archives (boundary included).
  @Test func startedAtClampArchivesAtTheBoundary() throws {
    let (sidebar, tab) = try Self.oneTodayTab(idle: 400 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(startedAt: Self.ago(12 * Self.hour))) == [tab])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(startedAt: Self.ago(12 * Self.hour - 1))).isEmpty)
  }

  /// startedAt earlier than the tab's activity does not change anything.
  @Test func earlierStartedAtHasNoEffect() throws {
    let (sidebar, _) = try Self.oneTodayTab(idle: 2 * Self.hour)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(startedAt: Self.ago(400 * Self.hour))).isEmpty)
  }

  // MARK: Splits in Today (BH-122, BH-123: NEEDS-RUNTIME-CHECK, [I])

  /// [I] A split in Today is one unit: archived only when its most recent pane is idle and no pane is exempt.
  @Test func splitInTodayIsArchivedAsAUnit() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(
      orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space), createdAt: Self.ago(100 * Self.hour))
    let oldPane = try sidebar.addTab(
      url: Self.url("a"), title: "A", lastActiveAt: Self.ago(20 * Self.hour), in: .split(split))
    let recentPane = try sidebar.addTab(
      url: Self.url("b"), title: "B", lastActiveAt: Self.ago(Self.hour), in: .split(split))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()).isEmpty)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour)) == [split])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour, exempt: [oldPane])).isEmpty)
    #expect(AutoArchivePolicy.itemsToArchive(
      in: sidebar, Self.input(threshold: .oneHour, exempt: [recentPane])).isEmpty)
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .oneHour, exempt: [split])).isEmpty)
  }

  /// [I] Never-opened panes age from their own createdAt; the newest pane decides.
  @Test func splitPanesWithoutLastActiveUseTheirCreatedAt() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(
      orientation: .vertical, widthFactors: [0.5, 0.5], in: .today(space), createdAt: Self.ago(100 * Self.hour))
    try sidebar.addTab(url: Self.url("a"), title: "A", in: .split(split), createdAt: Self.ago(50 * Self.hour))
    try sidebar.addTab(url: Self.url("b"), title: "B", in: .split(split), createdAt: Self.ago(13 * Self.hour))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [split])
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input(threshold: .twentyFourHours)).isEmpty)
  }

  /// [I] A split with no panes ages from its own createdAt.
  @Test func emptySplitUsesItsCreatedAt() throws {
    var sidebar = Sidebar()
    let space = sidebar.addSpace(title: "Work")
    let split = try sidebar.addSplit(
      orientation: .horizontal, widthFactors: [], in: .today(space), createdAt: Self.ago(12 * Self.hour))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [split])
  }

  // MARK: Ordering

  @Test func resultFollowsSpaceThenTodayOrder() throws {
    var sidebar = Sidebar()
    let first = sidebar.addSpace(title: "1")
    let second = sidebar.addSpace(title: "2")
    let stale = Self.ago(99 * Self.hour)
    let b = try sidebar.addTab(url: Self.url("b"), title: "B", lastActiveAt: stale, in: .today(second))
    let a1 = try sidebar.addTab(url: Self.url("a1"), title: "A1", lastActiveAt: stale, in: .today(first))
    let a2 = try sidebar.addTab(url: Self.url("a2"), title: "A2", lastActiveAt: stale, in: .today(first))
    #expect(AutoArchivePolicy.itemsToArchive(in: sidebar, Self.input()) == [a1, a2, b])
  }

  @Test func emptySidebarArchivesNothing() {
    #expect(AutoArchivePolicy.itemsToArchive(in: Sidebar(), Self.input(threshold: .oneHour)).isEmpty)
  }

  // MARK: Little Arc (BH-137)

  /// BH-137: Little Arc windows idle for 6 hours (their own default) are closed and archived.
  @Test func littleArcWindowsUseTheirOwnSixHourDefault() {
    let idle = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(6 * Self.hour))
    let fresh = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(6 * Self.hour - 1))
    let result = AutoArchivePolicy.littleArcWindowsToArchive(
      [idle, fresh], threshold: AutoArchiveThreshold.littleArcDefault, now: Self.now, exempt: [])
    #expect(AutoArchiveThreshold.littleArcDefault == .sixHours)
    #expect(result == [idle.id])
  }

  /// BH-137, BH-081: every finite option applies to Little Arc at exactly its interval.
  @Test(arguments: AutoArchiveThreshold.allCases.filter { $0 != .never })
  func littleArcEveryOptionUsesItsInterval(_ threshold: AutoArchiveThreshold) throws {
    let interval = try #require(threshold.interval)
    let atLimit = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(interval))
    let under = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(interval - 1))
    #expect(AutoArchivePolicy.littleArcWindowsToArchive(
      [under, atLimit], threshold: threshold, now: Self.now, exempt: []) == [atLimit.id])
  }

  /// BH-137, BH-076: "never" and exempt windows stay.
  @Test func littleArcNeverAndExemptWindowsStay() {
    let idle = LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(100 * Self.hour))
    #expect(AutoArchivePolicy.littleArcWindowsToArchive([idle], threshold: .never, now: Self.now, exempt: []).isEmpty)
    #expect(AutoArchivePolicy.littleArcWindowsToArchive(
      [idle], threshold: .oneHour, now: Self.now, exempt: [idle.id]).isEmpty)
  }

  /// BH-137: result keeps input order.
  @Test func littleArcResultKeepsInputOrder() {
    let windows = (0..<3).map { _ in LittleArcWindowActivity(id: UUID(), lastActiveAt: Self.ago(100 * Self.hour)) }
    #expect(AutoArchivePolicy.littleArcWindowsToArchive(
      windows, threshold: .sixHours, now: Self.now, exempt: []) == windows.map(\.id))
  }
}
