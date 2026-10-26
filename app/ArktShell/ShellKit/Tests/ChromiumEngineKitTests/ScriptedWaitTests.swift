import Testing

/// The bounded main-actor driver the scripted tests use instead of a wall-clock deadline (#412).
@MainActor
struct ScriptedWaitTests {
  /// The driver returns as soon as the condition holds.
  @Test func returnsOnceTheConditionHolds() async throws {
    var checks = 0
    try await ScriptedWait.until("a condition that turns true on the fourth check") {
      checks += 1
      return checks == 4
    }
    #expect(checks == 4)
  }

  /// Yielding lets work queued on the main actor run, which is what the facade's one-turn-later batches need.
  @Test func letsScheduledMainActorWorkRun() async throws {
    var ran = false
    Task { @MainActor in ran = true }
    try await ScriptedWait.until("the queued main-actor task") { ran }
    #expect(ran)
  }

  /// A condition that never holds fails after the turn bound, not after a duration.
  @Test func failsAfterTheTurnBound() async {
    var checks = 0
    await #expect(throws: ScriptedHarness.HarnessError.self) {
      try await ScriptedWait.until("a condition that never holds", maxTurns: 25) {
        checks += 1
        return false
      }
    }
    #expect(checks == 26, "one check per turn plus the check after the last yield")
  }
}
