---
name: arkt-flaky-tests
description: Use when an Arkt test passes locally but fails on CI or under load, or when writing a test that involves time, animation, display links or async waits - remove the wall-clock dependency, then prove the fix with 20 runs under load and a deliberate break.
---

# Arkt flaky tests

A flaky test almost always races wall time: a deadline, a display link or a sleep against main-actor work that a
busy runner delays. CI runs the whole ShellKit suite in one process, so the main actor can stall for seconds. Take
real time out of the test; never raise a timeout. Pattern from #396, #409, #414 and #436.

## 0. Gate: write it down before changing code

1. The failing test, the CI run, and the issue (`type:bug`; open one if none exists).
2. The exact assertion that fails and the value it saw.
3. The clock the test depends on (see step 2), with the file and line.
4. The fix from the table in step 3, and why it removes the clock instead of widening it.

**STOP** if you cannot name item 3. Reproduce first; do not change code on a guess.

## 1. Reproduce

Run the test filter repeatedly next to a build or other busy work, and record `uptime`. Note the failure count.

## 2. Find the clock

- a flush, save or retry deadline on a real sleeper,
- a spring or animation driven by the display link while the test asserts a mid-flight value,
- a fixed `waitUntil` deadline of a few seconds,
- a `sleep` or `Task.sleep` in a fake.

## 3. Remove it

Use the seams that already exist before adding new ones:

| Dependency | Fix | Example |
|---|---|---|
| Real deadline in production code | Inject a `ManualSleeper` that never fires on the success path; keep a separate test for the real timeout | #396, #436 |
| Display-link animation | Turn off `drivesDisplayLink`, step the motion by hand (`tick(at:)`, `settleNow`) | #409, #436 |
| Fixed wall-clock wait | Wait on the condition with a bounded main-actor turn driver (`ScriptedWait.until`), failing after N turns | #414 |
| Sleep in a fake | Replace it with `Task.yield()` | #414 |

New switches are internal and default to the production behavior. The product keeps its real bounds.

## 4. Verify before you claim

Both checks go in the pull request, with numbers copied from the output:

1. **20 runs under load.** Run the test 20 times in a row while the machine is busy; report passes and `uptime`:

   ```zsh
   cd app/ArktShell/ShellKit
   for i in {1..20}; do swift test --filter <Suite> || break; done
   ```

   For UI tests: `-test-iterations 20 -run-tests-until-failure` (`CONTRIBUTING.md`, section 12).
2. **It still fails when the code is broken.** Break the behavior the test guards (remove the guard, drop the call),
   run it, confirm it fails, restore. Name the line you broke.
3. Run the full suites from `CONTRIBUTING.md`, section 7, and report the counts.

**STOP** if any of the 20 runs fails. The fix is incomplete.

## Common mistakes we made

- Raising a wall-clock deadline to 60 s to turn `main` green; replaced by a `ManualSleeper` in #396.
- Freezing the reflow clock while the display link still advanced the spring (#436).
- Asserting a spring's start value while it kept running in wall time (#409).
- A 20 ms sleep left in a fake after the waits were fixed (#414).
