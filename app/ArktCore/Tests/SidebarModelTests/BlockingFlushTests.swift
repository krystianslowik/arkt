import CoreTestSupport
import Foundation
import SidebarModel
import Testing

/// `BlockingFlush` is called on the main thread at a SIGTERM quit start (#298); these tests block the main actor too.
@MainActor
struct BlockingFlushTests {
  @Test(arguments: [true, false])
  func returnsTheOperationsResult(_ result: Bool) {
    #expect(BlockingFlush.run(timeout: .seconds(5)) { result } == result)
  }

  @Test func returnsNilAtTheTimeoutWhileTheOperationHangs() {
    let gate = UncancellableSleeper()
    let start = ContinuousClock.now
    let outcome = BlockingFlush.run(timeout: .milliseconds(100)) {
      await gate.park()
      return true
    }
    #expect(outcome == nil)
    #expect(ContinuousClock.now - start < .seconds(2))
    gate.resumeAll()
  }

  @Test func theOperationNeverNeedsTheBlockedMainActor() {
    let outcome = BlockingFlush.run(timeout: .seconds(5)) {
      // Off the main actor: a main-actor hop here would wait for the timeout and return nil.
      pthread_main_np() == 0
    }
    #expect(outcome == true)
  }
}
