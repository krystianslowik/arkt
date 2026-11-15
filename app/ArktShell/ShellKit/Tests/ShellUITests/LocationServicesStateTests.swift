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

  /// Refreshes asked for while a task is running join it: no second task, and one more read after the running one.
  @Test func refreshesJoinTheRunningRead() async {
    let reader = Reader()
    let state = LocationServicesState(read: { reader.read() })
    let first = state.refresh()
    #expect(state.refresh() == nil, "a read is already running")
    #expect(state.refresh() == nil, "still one task")
    await first?.value
    #expect(reader.ranOnMain.count == 2, "the running read, then one more for both refreshes")
    #expect(state.isEnabled == true)
  }

  /// Location Services is turned off while a read is running: the refresh that asks for it is not lost. The running
  /// task reads once more when its read ends, and the cache ends up off.
  @Test func aRefreshDuringAReadReadsOnceMore() async throws {
    let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    let reader = Reader()
    let gated = Mutex(true)
    let state = LocationServicesState(read: {
      let value = reader.read()
      if gated.withLock({ let first = $0; $0 = false; return first }) {
        enteredContinuation.yield()
        release.wait()                                  // the first read stays in flight until the test lets it go
      }
      return value
    })
    var changes: [Bool?] = []
    state.onChange = { changes.append(state.isEnabled) }
    let first = try #require(state.refresh())
    for await _ in entered { break }                    // the first read has read "on" and is still running
    reader.value = false
    #expect(state.refresh() == nil, "joins the running task")
    release.signal()
    await first.value
    #expect(reader.ranOnMain == [false, false], "read once more, off the main thread")
    #expect(state.isEnabled == false, "the change during the read is not lost")
    #expect(changes == [true, false])
    await state.refresh()?.value
    #expect(reader.ranOnMain.count == 3, "the flag was cleared: a later refresh starts a new read")
  }
}
