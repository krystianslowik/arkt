import EngineAPI
import Foundation

// MARK: - Rule 25 (#576): zoom, crash and recovery

extension EngineContract {
  static func zoomChanges(_ recorder: EventRecorder, _ id: TabID) -> [(TabZoom, Bool)] {
    recorder.events(for: id).compactMap {
      if case .zoomChanged(_, let zoom, let user) = $0 { (zoom, user) } else { nil }
    }
  }

  static func crashes(_ recorder: EventRecorder, _ id: TabID) -> [TabTerminationStatus] {
    recorder.events(for: id).compactMap { if case .tabCrashed(_, let status) = $0 { status } else { nil } }
  }

  /// Walks the zoom to `step`'s end; every step reports once and is user initiated. Returns the number of steps.
  private static func zoomToEnd(_ engine: any EngineClient, _ recorder: EventRecorder, _ id: TabID,
                                _ step: (TabID) -> Void, _ what: String) throws -> Int {
    var steps = 0
    while steps < 64 {
      let before = zoomChanges(recorder, id).count
      step(id)
      let after = zoomChanges(recorder, id)
      if after.count == before { return steps }
      try require(after.count == before + 1, "one \(what) step reported \(after.count - before) zoom changes")
      try require(after.last?.1 == true, "a \(what) step must be user initiated")
      try require(engine.snapshot(of: id)?.zoom == after.last?.0, "the snapshot must carry the reported zoom")
      steps += 1
    }
    throw ContractViolation(description: "\(what) never reached the end of the steps")
  }

  public static func zoomStepIsReportedOnceAndNothingAtTheEnds(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let window = engine.createWindow(host: h.makeWindowHost())
    let id = engine.createTab(url: try h.pageURL("Zoom"), in: window)
    try await h.settle(engine, id)
    try require(engine.snapshot(of: id)?.zoom.isDefault == true, "a new tab starts at the default zoom")
    let recorder = EventRecorder(engine)

    try require(try zoomToEnd(engine, recorder, id, engine.zoomIn, "zoom in") > 0, "zoom in changed nothing")
    try require(try zoomToEnd(engine, recorder, id, engine.zoomOut, "zoom out") > 0, "zoom out changed nothing")
    let before = zoomChanges(recorder, id).count
    engine.resetZoom(id)
    engine.resetZoom(id)
    let resets = zoomChanges(recorder, id).dropFirst(before)
    try require(resets.count == 1, "reset reported \(resets.count) changes, want 1")
    try require(resets.first?.0.isDefault == true && resets.first?.1 == true, "reset returns to the default zoom")
    try require(engine.snapshot(of: id)?.zoom.isDefault == true, "the snapshot is at the default zoom")
  }

  public static func crashedTabStaysListed(_ h: EngineHarness) async throws {
    let crash = try driver(h.crashTab, "crashTab")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Crash"), in: engine.createWindow(host: h.makeWindowHost()))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)

    try await crash(engine, id)
    try await wait("a crash of \(id)") { engine.snapshot(of: id)?.crash != nil }

    try require(crashes(recorder, id).count == 1, "crash reported \(crashes(recorder, id).count) times, want 1")
    try require(engine.snapshot(of: id)?.crash == crashes(recorder, id).first, "the snapshot carries the status")
    try require(engine.tabIDs.contains(id), "a crashed tab stays listed")
    try require(closes(recorder, id).isEmpty, "a crash does not close the tab")
    try require(engine.snapshot(of: id)?.isLoading == false, "a crashed tab is not loading")
  }

  public static func reloadRecoversACrashedTabOnce(_ h: EngineHarness) async throws {
    let crash = try driver(h.crashTab, "crashTab")
    let engine = h.makeEngine()
    let id = engine.createTab(url: try h.pageURL("Recover"), in: engine.createWindow(host: h.makeWindowHost()))
    try await h.settle(engine, id)
    let recorder = EventRecorder(engine)
    try await crash(engine, id)
    try await wait("a crash of \(id)") { engine.snapshot(of: id)?.crash != nil }

    engine.reload(id)
    try await wait("the recovery of \(id)") { engine.snapshot(of: id)?.crash == nil }
    try await h.settle(engine, id)
    try await wait("the end of the reload of \(id)") { engine.snapshot(of: id)?.isLoading == false }

    let events = recorder.events(for: id)
    let recoveries = events.indices.filter { events[$0] == .tabRecovered(id) }
    try require(recoveries.count == 1, "recovery reported \(recoveries.count) times, want 1")
    let crashed = try requireValue(events.firstIndex { if case .tabCrashed = $0 { true } else { false } }, "crash")
    let finished = try requireValue(events.lastIndex(of: .loadingChanged(id, isLoading: false)), "end of the reload")
    try require(crashed < recoveries[0], "recovery must follow the crash")
    try require(recoveries[0] < finished, "recovery must come no later than the reload's loadingChanged(false)")
    try require(crashes(recorder, id).count == 1, "a reload must not report another crash")
  }
}
