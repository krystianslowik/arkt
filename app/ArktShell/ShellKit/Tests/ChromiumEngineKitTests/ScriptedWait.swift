/// Waits for a scripted test's condition by giving the main actor turns, never by reading a clock. The scripted facade
/// delivers its batch one main-actor turn after the call that caused it, so a handful of turns is enough; the bound
/// keeps a condition that never holds a test failure instead of a hang, and a busy machine cannot shorten it.
@MainActor
enum ScriptedWait {
  /// How many main-actor turns a wait may take. Far above what a scripted delivery needs, and independent of wall time.
  static let maxTurns = 10_000

  /// Checks `condition` until it holds, yielding the main actor between checks. Throws after `maxTurns` yields when a
  /// final check still sees it false.
  static func until(_ label: String, maxTurns: Int = ScriptedWait.maxTurns,
                    _ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<maxTurns {
      if condition() { return }
      await Task.yield()
    }
    if condition() { return }
    throw ScriptedHarness.HarnessError("\(label) did not settle after \(maxTurns) main-actor turns")
  }
}
