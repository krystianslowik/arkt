import Foundation
import Testing
@testable import ShellUI

/// `ToastPresenter` state only; time is injected so no test waits on a real clock.
@MainActor
struct ToastPresenterTests {
  /// A sleeper that never returns on its own within a test.
  private static let forever: ToastSleep = { _ in try await Task.sleep(for: .seconds(3600)) }

  /// A sleeper each call of which returns when the gate yields once.
  private static func gated(_ gate: AsyncStream<Void>) -> ToastSleep {
    { _ in for await _ in gate { return } }
  }

  @Test func newToastReplacesCurrent() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "One"))
    presenter.show(Toast(text: "Two"))
    #expect(presenter.current?.text == "Two")
  }

  @Test func transientToastDismissesAfterDuration() async {
    let gate = AsyncStream<Void>.makeStream()
    let presenter = ToastPresenter(sleep: Self.gated(gate.stream))
    presenter.show(Toast(text: "Bye"))
    gate.continuation.yield()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current == nil)
  }

  @Test func replacedToastTimerDoesNotDismissTheNewToast() async {
    let sleeper = ManualSleeper()
    let presenter = ToastPresenter(sleep: { _ in await sleeper.sleep() })
    presenter.show(Toast(text: "One"))
    await sleeper.waitForSleepers(1)
    presenter.show(Toast(text: "Two"))
    await sleeper.waitForSleepers(2)
    await sleeper.wakeOldest()      // the first timer ends its sleep after "Two" replaced "One"
    while presenter.runningTimerCountForTesting > 1 { await Task.yield() }
    #expect(presenter.current?.text == "Two")
    await sleeper.wakeOldest()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current == nil)
  }

  @Test func persistentToastStaysUntilDismissed() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "Recovered", isPersistent: true))
    #expect(presenter.current?.text == "Recovered")
    #expect(!presenter.isTimerArmedForTesting)
    presenter.dismiss()
    #expect(presenter.current == nil)
  }

  @Test func transientOverPersistentRestoresThePersistentToast() async {
    let gate = AsyncStream<Void>.makeStream()
    let presenter = ToastPresenter(sleep: Self.gated(gate.stream))
    presenter.show(Toast(text: "Recovered", isPersistent: true))
    presenter.show(Toast(text: "Couldn't add the tab."))
    #expect(presenter.current?.text == "Couldn't add the tab.")
    gate.continuation.yield()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current?.text == "Recovered")
  }

  @Test func persistentToastReplacesAnotherPersistentToast() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "First", isPersistent: true))
    presenter.show(Toast(text: "Second", isPersistent: true))
    #expect(presenter.current?.text == "Second")
    presenter.dismiss()
    #expect(presenter.current == nil)
  }

  @Test func actionRunsAndDismisses() {
    let presenter = ToastPresenter(sleep: Self.forever)
    var calls = 0
    presenter.show(Toast(text: "Restored", actionTitle: "Show Files", isPersistent: true)) { calls += 1 }
    presenter.performActionForTesting()
    #expect(calls == 1)
    #expect(presenter.current == nil)
    presenter.performActionForTesting()
    #expect(calls == 1)
  }

  @Test func actionMayShowANewToast() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "One", actionTitle: "Next")) { [unowned presenter] in
      presenter.show(Toast(text: "Two"))
    }
    presenter.performActionForTesting()
    #expect(presenter.current?.text == "Two")
  }
}

/// A sleeper whose sleeps end only when the test wakes them, oldest first. It ignores cancellation on purpose, so
/// the presenter's own guard against a replaced toast's timer is what the tests exercise.
private actor ManualSleeper {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var registered = 0

  func sleep() async {
    await withCheckedContinuation { waiters.append($0); registered += 1 }
  }

  /// Returns once `count` sleeps in total have started.
  func waitForSleepers(_ count: Int) async {
    while registered < count { await Task.yield() }
  }

  func wakeOldest() {
    guard !waiters.isEmpty else { return }
    waiters.removeFirst().resume()
  }
}
