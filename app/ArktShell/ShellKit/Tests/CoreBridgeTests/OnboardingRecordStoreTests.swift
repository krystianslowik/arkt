import CoreBridge
import CoreTestSupport
import ShellUI
import Testing

@MainActor
struct OnboardingRecordStoreTests {
  /// A deadline these tests never mean to reach: a busy CI runner can take over a second to run the opened write.
  private static let waitsForTheWrite = Duration.seconds(60)

  /// #344: a quit immediately after a step change waits for the queued record write, including earlier queued saves.
  @Test func terminationFlushPersistsTheLatestProgress() async {
    let gate = Gate()
    let storage = Storage()
    let (starts, started) = AsyncStream.makeStream(of: Void.self)
    let store = OnboardingRecordStore(record: OnboardingRecord()) { record in
      started.yield()
      await gate.wait()
      await storage.store(record)
    }
    var writeStarts = starts.makeAsyncIterator()
    let first = OnboardingFlow.Snapshot(step: "theme", imported: false, importSkipped: 0)
    let last = OnboardingFlow.Snapshot(step: "default", imported: false, importSkipped: 0)

    store.saveProgress(first)
    store.saveProgress(last)
    let terminationFlush = Task { await store.flush(atMost: Self.waitsForTheWrite) }
    _ = await writeStarts.next()
    #expect(store.needsFlush)

    await gate.open()
    #expect(await terminationFlush.value)
    #expect(await storage.record?.progress == last)
    #expect(!store.needsFlush)
  }

  /// #344: the quit reply has a real deadline; a stuck database write continues in the background instead.
  @Test func terminationFlushTimesOutWithoutWaitingForTheWrite() async {
    let gate = Gate()
    let storage = Storage()
    let sleeper = ManualSleeper()
    let (starts, started) = AsyncStream.makeStream(of: Void.self)
    let store = OnboardingRecordStore(record: OnboardingRecord()) { record in
      started.yield()
      await gate.wait()
      await storage.store(record)
    }
    var writeStarts = starts.makeAsyncIterator()
    let timeout = Duration.milliseconds(250)

    store.markCompleted()
    let terminationFlush = Task { await store.flush(atMost: timeout, sleep: sleeper.sleep) }
    _ = await writeStarts.next()
    for _ in 0..<20_000 where sleeper.parkedDurations != [timeout] { await Task.yield() }
    #expect(sleeper.parkedDurations == [timeout])
    sleeper.resume(timeout)
    #expect(await terminationFlush.value == false)
    #expect(await storage.record == nil)

    await gate.open()
    #expect(await store.flush(atMost: Self.waitsForTheWrite))
    #expect(await storage.record?.isCompleted == true)
  }

  /// #344: Start browsing and confirmed Skip setup cannot lose their completed record to an immediate quit.
  @Test func terminationFlushPersistsCompletion() async {
    let gate = Gate()
    let storage = Storage()
    let (starts, started) = AsyncStream.makeStream(of: Void.self)
    let store = OnboardingRecordStore(record: OnboardingRecord()) { record in
      started.yield()
      await gate.wait()
      await storage.store(record)
    }
    var writeStarts = starts.makeAsyncIterator()

    store.markCompleted()
    let terminationFlush = Task { await store.flush(atMost: Self.waitsForTheWrite) }
    _ = await writeStarts.next()
    #expect(store.needsFlush)

    await gate.open()
    #expect(await terminationFlush.value)
    let stored = await storage.record
    #expect(stored?.onboardingCompletedVersion == OnboardingRecord.currentVersion)
    #expect(stored?.progress == nil)
    #expect(!store.needsFlush)
  }
}

/// Holds the test write until the quit path is already waiting for it.
private actor Gate {
  private var isOpen = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiting.append($0) }
  }

  func open() {
    isOpen = true
    waiting.forEach { $0.resume() }
    waiting = []
  }
}

private actor Storage {
  private(set) var record: OnboardingRecord?

  func store(_ record: OnboardingRecord) { self.record = record }
}
