---
name: arkt-flaky-tests
description: Use when an Arkt test passes locally but fails on CI or under load, or when writing a test that involves time, animation, display links or async waits - remove the wall-clock dependency, then prove the fix with 20 runs under load and a deliberate break.
---

# Arkt flaky tests

A flaky test almost always races wall time: a deadline, a display link or a sleep against main-actor work that a
busy runner delays. CI runs the whole ShellKit suite in one process, so the main actor can stall for seconds. The
fix is to take real time out of the test, not to raise a timeout. Pattern from #396, #409, #414 and #436.

## 1. Reproduce

- Open or find the issue for the flake (`type:bug`), with the failing test and the CI run.
- Reproduce under load: run the test filter repeatedly next to a build or other busy work, and record `uptime`.

## 2. Find the clock

Look for the real-time dependency in the test path:

- a flush, save or retry deadline on a real sleeper,
- a spring or animation driven by the display link while the test asserts a mid-flight value,
- a fixed `waitUntil` deadline of a few seconds,
- a `sleep` or `Task.sleep` in a fake.

## 3. Remove it

Use the seams that already exist before adding new ones:

| Dependency | Fix | Example |
|---|---|---|
| Real deadline in production code | Inject a `ManualSleeper` that never fires on the success path; keep a separate test for the real timeout | #396, #436 |
| Display-link animation | Turn off `drivesDisplayLink` and step the motion by hand (`tick(at:)`, `settleNow`) | #409 (`PeekAnimator`), #436 (`SpringDriver`) |
| Fixed wall-clock wait | Wait on the condition with a bounded main-actor turn driver (`ScriptedWait.until`), failing after N turns, not N seconds | #414 |
| Sleep in a fake | Replace it with `Task.yield()` | #414 |

New switches are internal and default to the production behavior. Do not raise the timeout instead; that only
moves the race.

## 4. Prove it

Both checks go in the pull request, with numbers:

- **20 runs under load.** Run the test 20 times in a row while the machine is busy (a concurrent build, or every core
  loaded), and report the pass count and `uptime`:

  ```zsh
  cd app/ArktShell/ShellKit
  for i in {1..20}; do swift test --filter <Suite> || break; done
  ```

  For UI tests use `-test-iterations 20 -run-tests-until-failure` (`CONTRIBUTING.md`, section 12).
- **It still fails when the code is broken.** Break the behavior the test guards (remove the guard, drop the call)
  and confirm the test fails, then restore it. Name the line you broke.

Then run the full suites from `CONTRIBUTING.md`, section 7, and report the counts.
