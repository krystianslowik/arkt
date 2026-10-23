import CoreTestSupport
import SidebarModel
import Testing

struct FlushRaceTests {
  @Test func finishesWithAttemptOutcomeBeforeTimeout() async {
    let sleeper = ManualSleeper()
    let outcome = await FlushRace.run(
      timeout: .seconds(1), sleep: sleeper.sleep, attempt: Task { true })
    #expect(outcome == true)
  }

  @Test func finishesFalseWhenTimeoutWinsAndIgnoresSecondFinish() async {
    let sleeper = ManualSleeper()
    let gate = UncancellableSleeper()
    let race = Task {
      await FlushRace.run(
        timeout: .seconds(1), sleep: sleeper.sleep,
        attempt: Task {
          await gate.park()
          return true
        })
    }
    while sleeper.parkedCount == 0 { await Task.yield() }
    sleeper.resume(.seconds(1))
    #expect(await race.value == false)
    gate.resumeAll()
  }
}
