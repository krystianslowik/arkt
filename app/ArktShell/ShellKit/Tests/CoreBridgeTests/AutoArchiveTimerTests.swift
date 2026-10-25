import Archive
import CoreBridge
import Foundation
import SidebarModel
import Testing

/// The auto-archive timer with a manual clock and sleeper: no test waits for real time.
@MainActor
struct AutoArchiveTimerTests {
  private static let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
  private static let url = URL(string: "https://a.example")!
  private static let hour: TimeInterval = 3600

  @MainActor
  private final class Harness {
    let clock = TestClock(AutoArchiveTimerTests.start)
    let source: ModelSidebarSource
    let state = FakeArchiveState()
    let sleeper = ManualSleeper()
    let coordinator: ArchiveCoordinator
    let timer: AutoArchiveTimer
    let space: UUID
    var exempt: Set<UUID> = []
    var reports: [[ArchivedItem]] = []

    init() {
      let clock = clock
      source = ModelSidebarSource(now: { clock.now })
      space = source.mutate { $0.addSpace(title: "Work") }
      coordinator = ArchiveCoordinator(source: source, store: FakeArchiveStore(), now: { clock.now })
      timer = AutoArchiveTimer(
        coordinator: coordinator, state: state, now: { clock.now }, sleep: sleeper.sleep)
      timer.exempt = { [unowned self] in self.exempt }
      timer.onArchived = { [unowned self] in self.reports.append($0) }
    }

    /// A Today tab last active `hours` before the clock's current time.
    func addTodayTab(idleHours hours: Double) throws -> UUID {
      let lastActive = clock.now.addingTimeInterval(-hours * AutoArchiveTimerTests.hour)
      return try source.mutate {
        try $0.addTab(
          url: AutoArchiveTimerTests.url, title: "T", lastActiveAt: lastActive, in: .today(space),
          createdAt: lastActive)
      }
    }

    var today: [UUID] { source.sidebar.children(of: .today(space)) }
  }

  @Test func startResolvesTheClockTicksAtOnceThenEveryInterval() async throws {  // BH-080, BH-085
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-100 * Self.hour))
    let idle = try harness.addTodayTab(idleHours: 13)
    let fresh = try harness.addTodayTab(idleHours: 2)

    try await harness.timer.start()

    #expect(harness.reports.map { $0.map(\.id) } == [[idle]])
    #expect(harness.reports.joined().allSatisfy { $0.reason == .auto })
    #expect(harness.today == [fresh])
    await eventually { harness.sleeper.parkedDurations == [AutoArchiveTimer.defaultInterval] }

    harness.clock.now = harness.clock.now.addingTimeInterval(11 * Self.hour)
    harness.sleeper.resume(AutoArchiveTimer.defaultInterval)
    await eventually { harness.reports.count == 2 }
    #expect(harness.reports.last?.map(\.id) == [fresh])
    #expect(harness.today.isEmpty)
    await eventually { harness.sleeper.parkedCount == 1 }
    harness.timer.stop()
  }

  @Test func aTickThatArchivesNothingReportsNothing() async throws {
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-100 * Self.hour))
    _ = try harness.addTodayTab(idleHours: 1)

    try await harness.timer.start()

    #expect(harness.reports.isEmpty)
    #expect(harness.today.count == 1)
    harness.timer.stop()
  }

  @Test func visibleTabsAreExempt() async throws {  // exempt ids come from the window on every tick
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-100 * Self.hour))
    let visible = try harness.addTodayTab(idleHours: 40)
    harness.exempt = [visible]

    try await harness.timer.start()
    #expect(harness.reports.isEmpty)

    harness.exempt = []
    #expect(harness.timer.tick().map(\.id) == [visible])
    #expect(harness.reports.map { $0.map(\.id) } == [[visible]])
    harness.timer.stop()
  }

  /// Plan S8 step 4, timer and policy side (decision 10). The exempt set here stands in for what the window
  /// publishes for a shown split, every pane; that the window really publishes every pane is asserted in
  /// `SplitArchiveTests.testAutoArchiveExemptsEveryShownPane`. With one pane idle past the threshold the split stays
  /// with nothing exempt (a split ages from its most recent pane). Once both panes are idle, the exempt panes keep it,
  /// one exempt pane is enough (the split-as-a-unit rule), and dropping the exemption archives the split as one item.
  @Test func autoArchiveExemptsEveryVisiblePane() async throws {
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-100 * Self.hour))
    let idle = harness.clock.now.addingTimeInterval(-40 * Self.hour)
    let recent = harness.clock.now.addingTimeInterval(-2 * Self.hour)
    let (split, panes) = try harness.source.mutate { sidebar -> (UUID, [UUID]) in
      let split = try sidebar.addSplit(
        orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(harness.space), createdAt: idle)
      let left = try sidebar.addTab(
        url: Self.url, title: "L", lastActiveAt: idle, in: .split(split), createdAt: idle)
      let right = try sidebar.addTab(
        url: Self.url, title: "R", lastActiveAt: recent, in: .split(split), createdAt: recent)
      return (split, [left, right])
    }
    harness.exempt = Set(panes)

    try await harness.timer.start()

    #expect(harness.reports.isEmpty)
    #expect(harness.today == [split])
    harness.exempt = []
    #expect(harness.timer.tick().isEmpty, "one pane idle past the threshold does not archive the split")
    #expect(harness.today == [split])

    harness.clock.now = harness.clock.now.addingTimeInterval(11 * Self.hour)  // both panes now idle past 12 hours
    harness.exempt = Set(panes)
    #expect(harness.timer.tick().isEmpty)
    harness.exempt = [panes[1]]
    #expect(harness.timer.tick().isEmpty, "any exempt pane protects the whole split")
    #expect(harness.reports.isEmpty)
    harness.exempt = []
    #expect(harness.timer.tick().map(\.id) == [split])
    #expect(harness.reports.map { $0.map(\.id) } == [[split]])
    #expect(harness.today.isEmpty)
    harness.timer.stop()
  }

  @Test func freshStartProtectsOldTabs() async throws {  // first launch: the clock starts now
    let harness = Harness()
    _ = try harness.addTodayTab(idleHours: 400)

    try await harness.timer.start()

    #expect(harness.timer.startedAt == Self.start)
    #expect(harness.reports.isEmpty)
    #expect(harness.today.count == 1)
    harness.timer.stop()
  }

  @Test func clockResetAppliesToTheNextTickAndNeverMovesBack() async throws {  // plan decision 7
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-500 * Self.hour))
    try await harness.timer.start()
    let imported = try harness.addTodayTab(idleHours: 400)

    harness.timer.clockDidReset(to: Self.start)
    harness.timer.clockDidReset(to: Self.start.addingTimeInterval(-50 * Self.hour))  // older: ignored
    #expect(harness.timer.startedAt == Self.start)
    #expect(harness.timer.tick().isEmpty)

    harness.clock.now = Self.start.addingTimeInterval(12 * Self.hour)  // one full threshold after the import
    #expect(harness.timer.tick().map(\.id) == [imported])
    harness.timer.stop()
  }

  @Test func aResetBeforeTheStartResolvesWins() async throws {
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-500 * Self.hour))
    _ = try harness.addTodayTab(idleHours: 400)

    harness.timer.clockDidReset(to: Self.start)
    try await harness.timer.start()

    #expect(harness.timer.startedAt == Self.start)
    #expect(harness.reports.isEmpty)
    harness.timer.stop()
  }

  @Test func settingsComeFromTheStore() async throws {  // BH-083: per-profile threshold
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-100 * Self.hour))
    var settings = ArchiveSettings()
    settings.setTabThreshold(.oneHour, forProfile: "default", scope: .thisProfile)
    await harness.state.setSettings(settings)
    let tab = try harness.addTodayTab(idleHours: 2)

    try await harness.timer.start()

    #expect(harness.reports.map { $0.map(\.id) } == [[tab]])
    harness.timer.stop()
  }

  @Test func aFailedLoadThrowsAndNeverTicks() async throws {
    let harness = Harness()
    await harness.state.setFailsLoads(true)
    _ = try harness.addTodayTab(idleHours: 400)

    await #expect(throws: FakeStoreError.self) { try await harness.timer.start() }

    #expect(harness.timer.startedAt == nil)
    #expect(harness.timer.tick().isEmpty)
    for _ in 0..<100 { await Task.yield() }
    #expect(harness.sleeper.parkedCount == 0)
  }

  @Test func stopEndsTheLoop() async throws {
    let harness = Harness()
    try await harness.timer.start()
    await eventually { harness.sleeper.parkedCount == 1 }

    harness.timer.stop()

    await eventually { harness.sleeper.parkedCount == 0 }
    #expect(!harness.timer.isRunning)
  }

  @Test func noTickRunsAfterStop() async throws {  // quit: nothing archives during the termination flush
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-100 * Self.hour))
    try await harness.timer.start()
    await eventually { harness.sleeper.parkedCount == 1 }
    let tab = try harness.addTodayTab(idleHours: 40)

    harness.timer.stop()
    harness.sleeper.resume(AutoArchiveTimer.defaultInterval)  // a wake-up racing the stop
    for _ in 0..<100 { await Task.yield() }

    #expect(harness.timer.tick().isEmpty)
    #expect(harness.reports.isEmpty)
    #expect(harness.today == [tab])
  }

  @Test func stopWhileStartIsLoadingKeepsItStopped() async throws {
    let harness = Harness()
    await harness.state.setStarted(Self.start.addingTimeInterval(-100 * Self.hour))
    await harness.state.holdLoads()
    let tab = try harness.addTodayTab(idleHours: 40)
    let starting = Task { try await harness.timer.start() }
    await eventually { await harness.state.heldLoadCount == 1 }

    harness.timer.stop()
    await harness.state.releaseLoads()
    try await starting.value
    for _ in 0..<100 { await Task.yield() }

    #expect(!harness.timer.isRunning)
    #expect(harness.sleeper.parkedCount == 0)
    #expect(harness.timer.tick().isEmpty)
    #expect(harness.reports.isEmpty)
    #expect(harness.today == [tab])
  }

  @Test func startTwiceRunsOneLoop() async throws {
    let harness = Harness()
    try await harness.timer.start()
    try await harness.timer.start()
    for _ in 0..<100 { await Task.yield() }
    #expect(harness.sleeper.parkedCount == 1)
    harness.timer.stop()
  }
}

/// Yields until `condition` holds; records an issue if it never does.
@MainActor
private func eventually(
  _ condition: @MainActor () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<20_000 {
    if await condition() { return }
    await Task.yield()
  }
  Issue.record("condition never became true", sourceLocation: sourceLocation)
}
