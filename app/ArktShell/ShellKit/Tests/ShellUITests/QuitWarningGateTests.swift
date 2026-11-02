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
}
