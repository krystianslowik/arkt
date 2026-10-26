import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// Tab mute and audible state (#364, BH-126): `setMuted(_:muted:)` changes the snapshot and reports each change once,
/// the page's audible state is reported the same way, both reach per-window observers, and a duplicate starts
/// unmuted and silent.
@MainActor
struct MuteTests {
  private let page = URL(string: "arkt-test://page/Tone")!

  @Test func newTabIsNeitherMutedNorAudible() throws {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    let snapshot = try #require(engine.snapshot(of: tab))
    #expect(!snapshot.isMuted)
    #expect(!snapshot.isAudible)
  }

  @Test func muteAndUnmuteAreReportedOnceEach() throws {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    let recorder = EventRecorder(engine)

    engine.setMuted(tab, muted: true)
    engine.setMuted(tab, muted: true)
    #expect(engine.snapshot(of: tab)?.isMuted == true)
    engine.setMuted(tab, muted: false)

    #expect(recorder.events(for: tab) == [.mutedChanged(tab, isMuted: true), .mutedChanged(tab, isMuted: false)])
    #expect(engine.snapshot(of: tab)?.isMuted == false)
  }

  @Test func audibleStateIsReportedAndKeptWhileMuted() throws {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    let recorder = EventRecorder(engine)

    engine.setAudible(tab, true)
    engine.setAudible(tab, true)
    engine.setMuted(tab, muted: true)

    // Chromium keeps reporting a muted page as audible (the stream monitor ignores mute); the shell decides the glyph.
    #expect(recorder.events(for: tab) == [.audibleChanged(tab, isAudible: true), .mutedChanged(tab, isMuted: true)])
    let snapshot = try #require(engine.snapshot(of: tab))
    #expect(snapshot.isAudible && snapshot.isMuted)
  }

  @Test func muteEventsReachTheTabsWindowOnly() {
    let engine = InMemoryEngine()
    let main = engine.createWindow(host: StubWindowHost())
    let other = engine.createWindow(host: StubWindowHost())
    let tab = engine.createTab(url: page, in: main)
    var inMain: [EngineEvent] = []
    var inOther: [EngineEvent] = []
    let first = engine.observe(window: main) { inMain.append($0) }
    let second = engine.observe(window: other) { inOther.append($0) }
    defer { first.cancel(); second.cancel() }

    engine.setMuted(tab, muted: true)
    engine.setAudible(tab, true)

    #expect(inMain == [.mutedChanged(tab, isMuted: true), .audibleChanged(tab, isAudible: true)])
    #expect(inOther.isEmpty)
  }

  @Test func unknownOrClosedTabIsANoOp() {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    engine.closeTab(tab)
    let recorder = EventRecorder(engine)
    engine.setMuted(tab, muted: true)
    engine.setMuted(TabID(), muted: true)
    #expect(recorder.log.isEmpty)
  }

  @Test func duplicateStartsUnmutedAndSilent() throws {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: page, in: engine.createWindow(host: StubWindowHost()))
    engine.setMuted(tab, muted: true)
    engine.setAudible(tab, true)
    let copy = try #require(engine.duplicateTab(tab))
    let snapshot = try #require(engine.snapshot(of: copy))
    #expect(!snapshot.isMuted && !snapshot.isAudible)
  }

  @Test func muteEventsCarryTheirTabID() {
    let tab = TabID()
    #expect(EngineEvent.mutedChanged(tab, isMuted: true).tabID == tab)
    #expect(EngineEvent.audibleChanged(tab, isAudible: false).tabID == tab)
  }
}
