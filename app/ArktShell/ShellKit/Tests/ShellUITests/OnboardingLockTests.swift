import Testing
@testable import ShellUI

/// The first run's lock (#879) without a window: which events each lock takes, and the order a run goes through.
struct OnboardingLockTests {
  typealias Lock = OnboardingLock

  @Test func onlyIdleAcceptsNavigation() {
    let locks: [Lock] = [.idle, .promptingDefault, .askingSkip(duringImport: false), .askingSkip(duringImport: true),
                         .importing(skipWhenDone: false), .importing(skipWhenDone: true), .finished]
    #expect(locks.filter(\.acceptsNavigation) == [.idle])
  }

  @Test func thePromptHoldsEverythingButItsAnswerAndTheEnd() {
    let lock = Lock.promptingDefault
    #expect(lock.next(after: .promptDefault) == nil, "one prompt at a time")
    #expect(lock.next(after: .askSkip) == nil, "Skip setup waits for the prompt")
    #expect(lock.next(after: .importStarted) == nil)
    #expect(lock.next(after: .importEnded) == nil)
    #expect(lock.next(after: .skipAnswered(confirmed: true)) == nil)
    #expect(lock.next(after: .promptClosed) == .idle)
    #expect(lock.next(after: .finish) == .finished)
  }

  @Test func aPromptAnswerWithNoPromptIsIgnored() {
    #expect(Lock.idle.next(after: .promptClosed) == nil)
    #expect(Lock.finished.next(after: .promptClosed) == nil)
  }

  @Test func skipSetupWithoutAnImportReturnsToIdle() {
    #expect(Lock.idle.next(after: .askSkip) == .askingSkip(duringImport: false))
    #expect(Lock.askingSkip(duringImport: false).next(after: .skipAnswered(confirmed: false)) == .idle)
    #expect(Lock.askingSkip(duringImport: false).next(after: .skipAnswered(confirmed: true)) == .idle)
    #expect(Lock.askingSkip(duringImport: false).next(after: .askSkip) == nil, "one question at a time")
  }

  @Test func skipSetupDuringAnImportWaitsForItsEnd() {
    #expect(Lock.idle.next(after: .importStarted) == .importing(skipWhenDone: false))
    #expect(Lock.importing(skipWhenDone: false).next(after: .askSkip) == .askingSkip(duringImport: true))
    #expect(Lock.askingSkip(duringImport: true).next(after: .skipAnswered(confirmed: false))
      == .importing(skipWhenDone: false))
    #expect(Lock.askingSkip(duringImport: true).next(after: .skipAnswered(confirmed: true))
      == .importing(skipWhenDone: true))
    #expect(Lock.importing(skipWhenDone: true).skipsWhenImportEnds)
    #expect(Lock.importing(skipWhenDone: true).next(after: .askSkip) == nil, "already skipping")
    #expect(Lock.importing(skipWhenDone: true).next(after: .importEnded) == .idle)
  }

  @Test func anImportThatEndsUnderTheQuestionLeavesThePlainQuestion() {
    #expect(Lock.askingSkip(duringImport: true).next(after: .importEnded) == .askingSkip(duringImport: false))
  }

  @Test func finishedTakesNothing() {
    let events: [Lock.Event] = [.promptDefault, .promptClosed, .askSkip, .skipAnswered(confirmed: true),
                                .importStarted, .importEnded, .finish]
    #expect(events.allSatisfy { Lock.finished.next(after: $0) == nil })
  }

  @Test func theStateLogsOnlyAcceptedTransitions() {
    var state = OnboardingLockState()
    let accepted = [OnboardingLock.Event.promptDefault, .askSkip, .promptDefault, .promptClosed, .finish]
      .map { state.send($0) }
    #expect(accepted == [true, false, false, true, true])
    #expect(state.lock == .finished)
    #if DEBUG
    #expect(state.log == [
      .init(from: .idle, event: .promptDefault, to: .promptingDefault),
      .init(from: .promptingDefault, event: .promptClosed, to: .idle),
      .init(from: .idle, event: .finish, to: .finished),
    ])
    #endif
  }
}
