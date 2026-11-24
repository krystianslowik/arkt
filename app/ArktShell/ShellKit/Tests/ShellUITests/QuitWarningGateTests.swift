import Testing
@testable import ShellUI

/// Cmd-Q asks only while "Warn before quitting" is on, and does not quit until the injected reply (#487, BH-177).
@MainActor
struct QuitWarningGateTests {
  @Test func warningOffProceedsWithoutAsking() {
    let gate = QuitWarningGate()
    #expect(gate.begin(warns: false) == .proceed)
    #expect(!gate.isAsking)
    #expect(gate.reply(confirmed: true) == .wait, "a reply with no ask does not quit")
    #expect(!gate.isAsking)
  }

  @Test func warningOnAsksAndDoesNotProceedUntilConfirmed() {
    let gate = QuitWarningGate()
    #expect(gate.begin(warns: true) == .ask)
    #expect(gate.isAsking)
    #expect(gate.begin(warns: true) == .wait, "a second quit waits on the same ask")
    #expect(gate.isAsking)

    #expect(gate.reply(confirmed: false) == .stop)
    #expect(!gate.isAsking)
    #expect(gate.begin(warns: true) == .ask, "declining leaves the next quit asking again")

    #expect(gate.reply(confirmed: true) == .proceed)
    #expect(!gate.isAsking)
    #expect(gate.begin(warns: false) == .proceed)
  }

  // MARK: - The Engine build's Quit item (#560)

  /// Records what `requestQuit` did: the asks it showed (each with its reply handler) and the terminate calls.
  private final class QuitProbe {
    var replies: [@MainActor (Bool) -> Void] = []
    var terminated = 0
  }

  private func request(_ gate: QuitWarningGate, warns: Bool, _ probe: QuitProbe) {
    gate.requestQuit(warns: warns, ask: { probe.replies.append($0) }, terminate: { probe.terminated += 1 })
  }

  @Test func requestWithTheWarningOffTerminatesAtOnceWithoutAsking() {
    let gate = QuitWarningGate(), probe = QuitProbe()
    request(gate, warns: false, probe)
    #expect(probe.terminated == 1, "inside the same call, as the Quit item did before")
    #expect(probe.replies.isEmpty)
  }

  @Test func requestWithTheWarningOnAsksOnceAndCancelKeepsTheAppRunning() throws {
    let gate = QuitWarningGate(), probe = QuitProbe()
    request(gate, warns: true, probe)
    request(gate, warns: true, probe)
    #expect(probe.replies.count == 1, "a second Cmd-Q while the ask is up shows no second ask")
    #expect(probe.terminated == 0)

    let cancel = try #require(probe.replies.first)
    cancel(false)
    #expect(probe.terminated == 0, "Cancel does not terminate")
    #expect(!gate.isAsking)

    request(gate, warns: true, probe)
    #expect(probe.replies.count == 2, "the next Cmd-Q asks again")
    probe.replies[1](true)
    #expect(probe.terminated == 1, "Quit terminates once")
    probe.replies[1](true)
    #expect(probe.terminated == 1, "a repeated answer does not terminate again")
  }
}
