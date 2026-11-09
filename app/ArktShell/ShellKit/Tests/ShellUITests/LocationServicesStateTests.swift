import Foundation
import Synchronization
import Testing
@testable import ShellUI

/// Whether Location Services is on for the whole Mac (#856), read off the main thread and cached. Every test injects
/// the reader: none reads the real setting.
@MainActor
struct LocationServicesStateTests {
  /// What the injected reader saw: the threads it ran on and how often.
  private final class Reader: Sendable {
    private let state = Mutex((value: true, onMain: [Bool]()))
    var value: Bool {
      get { state.withLock { $0.value } }
      set { state.withLock { $0.value = newValue } }
    }
    var ranOnMain: [Bool] { state.withLock { $0.onMain } }
    func read() -> Bool {
      state.withLock {
        $0.onMain.append(Thread.isMainThread)
        return $0.value
      }
    }
  }

  @Test func nothingIsKnownBeforeTheFirstRead() {
    let reader = Reader()
    let state = LocationServicesState(read: { reader.read() })
    #expect(state.isEnabled == nil)
    #expect(reader.ranOnMain.isEmpty, "creating the cache reads nothing")
  }

  /// The read runs off the main thread, as Apple asks, and its result is cached for the main actor.
  @Test func aRefreshReadsOffTheMainThreadAndCaches() async {
    let reader = Reader()
    reader.value = false
    let state = LocationServicesState(read: { reader.read() })
    await state.refresh()?.value
    #expect(reader.ranOnMain == [false], "never on the main thread")
    #expect(state.isEnabled == false)
    reader.value = true
    await state.refresh()?.value
    #expect(state.isEnabled == true)
  }

  /// `onChange` runs only when the cached value changes, the first read included.
  @Test func onChangeRunsOnlyWhenTheValueChanges() async {
    let reader = Reader()
    let state = LocationServicesState(read: { reader.read() })
    var changes = 0
    state.onChange = { changes += 1 }
    await state.refresh()?.value
    #expect(changes == 1, "unknown to on")
    await state.refresh()?.value
    #expect(changes == 1, "on again: no change")
    reader.value = false
    await state.refresh()?.value
    #expect(changes == 2, "on to off")
  }

  /// Refreshes asked for while a read is running join it: one read at a time.
  @Test func refreshesJoinTheRunningRead() async {
    let reader = Reader()
    let state = LocationServicesState(read: { reader.read() })
    let first = state.refresh()
    let second = state.refresh()
    #expect(second == nil, "a read is already running")
    await first?.value
    #expect(reader.ranOnMain.count == 1)
    #expect(state.isEnabled == true)
  }
}
