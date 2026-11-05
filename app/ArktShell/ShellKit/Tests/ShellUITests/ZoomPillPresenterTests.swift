import EngineAPI
import EngineAPITestSupport
import Foundation
import Testing
@testable import ShellUI

/// The zoom pill's state (#579, design/extensions `surf-zoom`), against `InMemoryEngine`'s zoom. The auto-close timer
/// sleeps on a sleeper the test resumes, so no test waits on a real clock.
@MainActor
struct ZoomPillPresenterTests {
  @MainActor
  private final class Rig {
    let engine = InMemoryEngine()
    let sleeper = ParkingSleeper()
    let presenter: ZoomPillPresenter
    let tab: TabID
    let other: TabID
    private var observation: EngineObservation?
    var changes = 0
    var announcements: [String] = []

    init() {
      let sleeper = sleeper
      presenter = ZoomPillPresenter(engine: engine, sleep: { try await sleeper.sleep($0) })
      tab = engine.createTab(url: URL(string: "https://example.com/a")!)
      other = engine.createTab(url: URL(string: "https://example.com/b")!)
      observation = engine.observe { [presenter] in presenter.handle($0) }
      presenter.onChange = { [unowned self] in changes += 1 }
      presenter.onAnnouncement = { [unowned self] in announcements.append($0) }
      presenter.shownTabChanged(tab)
    }

    var percentText: String? { presenter.display?.percentText }
  }

  /// A sleeper whose sleeps end only when the test resumes them, oldest first, or throw when their task is cancelled.
  actor ParkingSleeper {
    private struct Parked {
      let id: Int
      let duration: Duration
      let continuation: CheckedContinuation<Void, any Error>
    }

    private var parked: [Parked] = []
    private var nextID = 0

    func sleep(_ duration: Duration) async throws {
      let id = nextID
      nextID += 1
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          parked.append(Parked(id: id, duration: duration, continuation: continuation))
        }
      } onCancel: {
        Task { await self.cancel(id) }
      }
    }

    private func cancel(_ id: Int) {
      guard let index = parked.firstIndex(where: { $0.id == id }) else { return }
      parked.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    var parkedCount: Int { parked.count }
    var durations: [Duration] { parked.map(\.duration) }

    func resumeNext() {
      guard !parked.isEmpty else { return }
      parked.removeFirst().continuation.resume()
    }
  }

  /// Takes main-actor turns until `condition` holds; a bounded turn driver, never a clock.
  private static func until(_ what: String, turns: Int = 5000, _ condition: () async -> Bool) async {
    for _ in 0..<turns {
      if await condition() { return }
      await Task.yield()
    }
    Issue.record("never reached: \(what)")
  }

  // MARK: Showing

  @Test func `a zoom the user asked for shows the pill with the percent`() {
    let rig = Rig()
    #expect(rig.presenter.display == nil, "nothing shows before a zoom change")
    rig.engine.zoomIn(rig.tab)
    #expect(rig.percentText == "110%")
    #expect(rig.presenter.display?.tab == rig.tab)
    #expect(rig.announcements == ["Zoom 110%"], "VoiceOver reads the percent")
  }

  @Test func `a zoom the engine made on its own does not show the pill`() {
    let rig = Rig()
    rig.engine.setZoom(rig.tab, percent: 150, userInitiated: false)
    #expect(rig.presenter.display == nil, "a site's saved zoom, or another tab on the same site, shows nothing")
    #expect(rig.announcements.isEmpty)
  }

  @Test func `a zoom of a tab that is not on screen does not show the pill`() {
    let rig = Rig()
    rig.engine.zoomIn(rig.other)
    #expect(rig.presenter.display == nil)
  }

  @Test func `each step updates the percent without replaying the entrance`() {
    let rig = Rig()
    var openings: [Bool] = []
    rig.presenter.onChange = { [presenter = rig.presenter] in openings.append(presenter.isOpening) }
    rig.engine.zoomIn(rig.tab)
    rig.engine.zoomIn(rig.tab)
    rig.engine.zoomOut(rig.tab)
    #expect(rig.percentText == "110%")
    #expect(openings == [true, false, false], "only the first change opens the pill")
    #expect(rig.announcements == ["Zoom 110%", "Zoom 125%", "Zoom 110%"])
  }

  @Test func `an engine change while the pill is up updates the percent quietly`() async {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    await Self.until("the timer is parked") { await rig.sleeper.parkedCount == 1 }
    rig.engine.setZoom(rig.tab, percent: 150, userInitiated: false)
    #expect(rig.percentText == "150%")
    #expect(rig.announcements == ["Zoom 110%"], "only the user's own changes are spoken")
    for _ in 0..<50 { await Task.yield() }
    #expect(await rig.sleeper.parkedCount == 1, "the timer is not restarted")
  }

  // MARK: The buttons

  @Test func `minus and plus step the shown tab's zoom`() {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    rig.presenter.zoomIn()
    #expect(rig.engine.snapshot(of: rig.tab)?.zoom.percent == 125)
    #expect(rig.percentText == "125%")
    rig.presenter.zoomOut()
    rig.presenter.zoomOut()
    #expect(rig.engine.snapshot(of: rig.tab)?.zoom.percent == 100)
    #expect(rig.presenter.display == nil, "back at the default zoom there is nothing to show")
  }

  @Test func `Reset returns to the default zoom and hides the pill`() {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    rig.engine.zoomIn(rig.tab)
    rig.presenter.reset()
    #expect(rig.engine.snapshot(of: rig.tab)?.zoom == .default)
    #expect(rig.presenter.display == nil)
  }

  @Test func `zooming out below the default shows the pill too`() {
    let rig = Rig()
    rig.engine.zoomOut(rig.tab)
    #expect(rig.percentText == "90%")
  }

  // MARK: Auto-close

  @Test func `the pill closes two seconds after it showed`() async {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    await Self.until("the timer is parked") { await rig.sleeper.parkedCount == 1 }
    #expect(await rig.sleeper.durations == [.seconds(2)])
    #expect(ZoomPillPresenter.autoClose == .seconds(2))
    await rig.sleeper.resumeNext()
    await Self.until("the pill closed") { rig.presenter.display == nil }
    #expect(rig.engine.snapshot(of: rig.tab)?.zoom.percent == 110, "closing keeps the zoom")
  }

  @Test func `another step starts the two seconds again`() async {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    await Self.until("the first timer is parked") { await rig.sleeper.parkedCount == 1 }
    rig.engine.zoomIn(rig.tab)
    await Self.until("the first timer was cancelled and a new one parked") {
      await rig.sleeper.parkedCount == 1 && rig.presenter.isTimerArmed
    }
    await rig.sleeper.resumeNext()
    await Self.until("the pill closed") { rig.presenter.display == nil }
  }

  @Test func `the pointer over the pill holds it open; leaving starts the two seconds`() async {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    await Self.until("the timer is parked") { await rig.sleeper.parkedCount == 1 }
    rig.presenter.setHovering(true)
    #expect(!rig.presenter.isTimerArmed)
    await Self.until("the timer was cancelled") { await rig.sleeper.parkedCount == 0 }

    rig.presenter.zoomIn()
    #expect(rig.percentText == "125%")
    for _ in 0..<50 { await Task.yield() }
    #expect(await rig.sleeper.parkedCount == 0, "a step under the pointer does not arm the timer")

    rig.presenter.setHovering(false)
    await Self.until("the timer is parked again") { await rig.sleeper.parkedCount == 1 }
    #expect(await rig.sleeper.durations == [.seconds(2)], "full length after the pointer leaves")
    await rig.sleeper.resumeNext()
    await Self.until("the pill closed") { rig.presenter.display == nil }
  }

  @Test func `a stale timer does not close a pill shown again`() async {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    await Self.until("the timer is parked") { await rig.sleeper.parkedCount == 1 }
    rig.presenter.reset()
    #expect(rig.presenter.display == nil)
    rig.engine.zoomIn(rig.tab)
    #expect(rig.percentText == "110%")
    await Self.until("one live timer") { await rig.sleeper.parkedCount == 1 && rig.presenter.isTimerArmed }
    #expect(rig.presenter.display != nil)
  }

  // MARK: Tabs

  @Test func `switching tabs closes the pill`() {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    rig.presenter.shownTabChanged(rig.other)
    #expect(rig.presenter.display == nil)
    rig.presenter.shownTabChanged(rig.tab)
    #expect(rig.presenter.display == nil, "it does not come back with the tab")
    #expect(!rig.presenter.isTimerArmed)
  }

  @Test func `a closed tab is forgotten`() {
    let rig = Rig()
    rig.engine.zoomIn(rig.tab)
    rig.presenter.forget(rig.tab)
    #expect(rig.presenter.display == nil)
    #expect(rig.presenter.visibleTab == nil)
    rig.presenter.zoomIn()
    #expect(rig.engine.snapshot(of: rig.tab)?.zoom.percent == 110, "the buttons act on nothing once it closed")
  }
}
