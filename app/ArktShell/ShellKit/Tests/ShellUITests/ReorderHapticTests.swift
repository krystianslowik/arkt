import AppKit
import Testing
@testable import ShellUI

/// BH-024: a light alignment tick when a tab reorder settles on a new slot, and none when the setting is off.
@MainActor
struct ReorderHapticTests {
  @Test func aNewSlotPlaysAlignment() {
    #expect(ReorderHaptic.cue(enabled: true, slotChanged: true, hasSlot: true) == .alignment)
  }

  @Test func theSameSlotPlaysNothing() {
    #expect(ReorderHaptic.cue(enabled: true, slotChanged: false, hasSlot: true) == nil)
  }

  @Test func leavingEverySlotPlaysNothing() {
    #expect(ReorderHaptic.cue(enabled: true, slotChanged: true, hasSlot: false) == nil)
  }

  @Test func theSettingOffPlaysNothing() {
    #expect(ReorderHaptic.cue(enabled: false, slotChanged: true, hasSlot: true) == nil)
  }

  @Test func theTickIsPlayedNow() {
    #expect(ReorderHaptic.performanceTime == .now)
  }
}
