import AppKit
import Testing
@testable import ShellUI

/// BH-024: one alignment tick when a reorder settles on a new slot, none when the setting is off.
@MainActor
struct ReorderHapticTests {
  @Test func aNewSlotPlaysAlignmentNow() {
    let performer = RecordingReorderPerformer()
    ReorderHaptic.play(enabled: true, slotChanged: true, hasSlot: true, performer: performer)
    #expect(performer.patterns == [.alignment])
    #expect(performer.times == [.now])
  }

  @Test func theSameSlotPlaysNothing() {
    let performer = RecordingReorderPerformer()
    ReorderHaptic.play(enabled: true, slotChanged: false, hasSlot: true, performer: performer)
    #expect(performer.patterns.isEmpty)
  }

  @Test func leavingEverySlotPlaysNothing() {
    let performer = RecordingReorderPerformer()
    ReorderHaptic.play(enabled: true, slotChanged: true, hasSlot: false, performer: performer)
    #expect(performer.patterns.isEmpty)
  }

  @Test func theSettingOffPlaysNothing() {
    let performer = RecordingReorderPerformer()
    ReorderHaptic.play(enabled: false, slotChanged: true, hasSlot: true, performer: performer)
    #expect(performer.patterns.isEmpty)
  }

  @Test func theGateFollowsTheSetting() throws {
    let name = "dev.arkt.tests.reorder-haptics.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { UserDefaults().removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    ReorderHapticGate.bind(settings)
    defer { ReorderHapticGate.enabled = { true } }
    #expect(ReorderHapticGate.enabled())
    settings.playsReorderHaptics = false
    #expect(!ReorderHapticGate.enabled())
  }
}

final class RecordingReorderPerformer: NSObject, NSHapticFeedbackPerformer {
  var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []
  var times: [NSHapticFeedbackManager.PerformanceTime] = []

  func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern,
               performanceTime: NSHapticFeedbackManager.PerformanceTime) {
    patterns.append(pattern)
    times.append(performanceTime)
  }
}
