# Engine Week 3 Results

Plan: `docs/plans/2026-10-24-engine-week3.md` (pull request #220). Issue: #33. Variables as in the plan's Rules
(`$CHROMIUM_ROOT`, `$CR`, `$OUT` = `$CR/out/Spike`, `$PROF` = `$CHROMIUM_ROOT/profiles`, `$EMB` =
`$CHROMIUM_ROOT/embed-week3`). W3-0 adds the header, task table and baselines above this section.

## W3-0a: main-actor probe on the `Spike` configuration

Date 2026-10-23. Branch `engine/33-w3-0a-mainactor-probe` off `main` at `3c8294b`. No Chromium build and no engine
worktree: `out/Spike` was only read and copied from (APFS clones, `cp -c`), `$CR/arkt` was not touched.

**Verdict: GO for the threading model, with one correction to Decision 3 and the Rules (below).** Swift's main-actor
executor runs under Chromium's run loop: a `Task { @MainActor }` and a `DispatchQueue.main.async` block scheduled
before `ChromeMain` both run as soon as Chromium's `MessagePumpNSApplication` spins, `Task.sleep` resumes on the main
actor, and main-actor jobs keep running inside native nested loops (menu tracking, `NSAlert` modal) entered from a
run-loop callout. They do **not** run inside a nested loop entered from a main-actor job itself. Chromium's own tasks
kept running in every Swift-opened nested loop.

### Probe

- `app/ArktShell/App/ChromiumSpikeProbe.swift` (new, only under `ARKT_CHROMIUM_SPIKE`): the `@objc(ArktShellEmbedderProbe)`
  class, `startMainActorProbe()` and, behind the switch `--arkt-probe-nested`, `NestedLoopProbe`. The plan put the
  probe inline in `ChromiumSpikeMain.swift`; it is a separate file so the nested-loop part stays out of the entry
  point. `ChromiumSpikeMain.swift` gains two statements before `ChromeMain`: `_ = ArktShellEmbedderProbe.self` and
  `startMainActorProbe()`. Nothing touches `NSApplication` before `ChromeMain`.
- Plan step 1: `Task { @MainActor in try await Task.sleep(for: .milliseconds(500)); log("main actor resumed") }` and
  `DispatchQueue.main.async { log("main queue drained") }`.
- Nested loops (extension of step 1, critic finding M6). Three tickers count main-thread work every 100 ms: a
  main-actor `Task.sleep` loop, a `DispatchQueue.main.asyncAfter` chain and a `Timer` in `.common` modes (the
  control). 20 s after the main actor first runs, four phases each open one nested loop for 3 s, with the app
  activated just before each: an `NSMenu` (`popUp(positioning:at:in:)`) and an `NSAlert` (`runModal`), each entered
  once from a `.common` run-loop timer callout and once from a main-actor job (`Task { @MainActor }`). Each loop is
  closed by a `.common` timer (`cancelTracking`, or `stopModal` plus a posted application-defined event), so closing
  never depends on main-actor jobs. A phase's end is logged by the loop's own caller.
- Chromium tasks: a Node CDP client on the probe's own port sends `Browser.getVersion` (handled on the browser UI
  thread) every 50 ms for the whole run and logs any reply slower than 150 ms.
- Build: `xcodegen generate`, then `nice -n 10 xcodebuild -project ArktShell.xcodeproj -scheme ArktShell
  -configuration Spike -derivedDataPath <scratch derived data> -jobs 2 build`.
- Layout (Task WE Run B): `cp -Rp` of the built `ArktShell.app` to `$EMB`, `cp -c -Rp` of
  `$OUT/Chromium.app/Contents/Frameworks/Chromium Framework.framework` into its `Contents/Frameworks`, and
  `cp -c -p $OUT/*.dylib $EMB/` (518 dylibs). The executable was later replaced in place for the warm run.
- Launch: `$EMB/ArktShell.app/Contents/MacOS/ArktShell --user-data-dir=$PROF/w3-0a-run<n> --use-mock-keychain
  --no-first-run --no-default-browser-check --enable-logging=stderr --remote-debugging-port=9373
  --arkt-probe-nested 'data:text/html,<title>W3-0a probe</title><h1>W3-0a probe</h1>'`, PID from `$!`, killed by
  that PID.

### Results

Plan step 3 (dead-strip safeguard). The plan's `grep 'OBJC_CLASS_$_ArktShellEmbedderProbe'` prints nothing because
`$` is a regular-expression anchor; use `grep -F`:

```
$ nm -m ArktShell.app/Contents/MacOS/ArktShell | grep -F 'OBJC_CLASS_$_ArktShellEmbedderProbe'
000000010043c918 (__DATA,__objc_data) external _OBJC_CLASS_$_ArktShellEmbedderProbe
```

Acceptance (both probe lines within 3 s of the hook, alive 30 s, class defined): **pass** in both runs.

| Run | Launch | `in-process hook alive` | `main queue drained` | `main actor resumed` | Alive | `FATAL` |
|---|---|---|---|---|---|---|
| 1 (fresh copy) | 21:35:16 | 21:36:52.818 | 21:36:52.909 (+0.09 s) | 21:36:53.434 (+0.62 s) | 3 min 42 s, then killed | 0 |
| 2 (warm) | 21:39:22 | 21:39:27.395 | 21:39:27.460 (+0.07 s) | 21:39:27.984 (+0.59 s) | 1 min 44 s, then killed | 0 |

`main actor resumed` includes the probe's own 500 ms sleep. The first launch after the copy spent about 95 s in
`dlopen` (system scanning, as in Task WE).

Nested loops. Counts are ticks during the 3 s the loop was open (about 30 expected per ticker); the durations print
as `3.246 ms` in the log because the formatter used the system locale's grouping separator (3246 ms).

| Phase (entered from) | Run 1 main actor / main queue / run-loop timer | Run 2 | Slowest `Browser.getVersion` |
|---|---|---|---|
| `NSMenu` tracking, run-loop timer callout | 31 / 31 / 32 | 31 / 31 / 32 | under 150 ms |
| `NSAlert` modal, run-loop timer callout | 29 / 29 / 30 | 29 / 29 / 31 | under 150 ms |
| `NSMenu` tracking, main-actor job | **0 / 0** / 32 | **0 / 0** / 32 | under 150 ms |
| `NSAlert` modal, main-actor job | **0 / 0** / 30 | **0 / 0** / 30 | under 150 ms |

CDP over each whole run, covering all four phases: run 1 `1715 calls, 0 over 150 ms, max 33 ms`; run 2
`1430 calls, 0 over 150 ms, max 15 ms`.

Log lines (run 2):

```
[21:39:48.509] ARKT probe: menu-from-runloop-timer begin
[21:39:51.758] ARKT probe: menu-from-runloop-timer end after 3.242 ms: main actor ticks 31, main queue ticks 31, run loop timer ticks 32
[21:39:54.281] ARKT probe: alert-from-runloop-timer begin
[21:39:57.305] ARKT probe: alert-from-runloop-timer end after 3.024 ms: main actor ticks 29, main queue ticks 29, run loop timer ticks 31
[21:39:59.894] ARKT probe: menu-from-main-actor-job begin
[21:40:03.134] ARKT probe: menu-from-main-actor-job end after 3.239 ms: main actor ticks 0, main queue ticks 0, run loop timer ticks 32
[21:40:05.711] ARKT probe: alert-from-main-actor-job begin
[21:40:08.722] ARKT probe: alert-from-main-actor-job end after 3.011 ms: main actor ticks 0, main queue ticks 0, run loop timer ticks 30
```

Engine-opened menu: not measured. A CDP right click (`Input.dispatchMouseEvent`, `mouseMoved` then right
`mousePressed` / `mouseReleased`) reached the page (`contextmenu` listener count 1) but no native menu began tracking
in the spike's Arkt window host, so the case "nested loop entered by Chromium from inside a Chromium task" stays with
the W3-3 gate, which drives it from a posted Chromium task as the plan already says.

Errors: run 1 has only the known teardown pair (`bootstrap_look_up dev.arkt.ArktShell.MachPortRendezvousServer.1:
Permission denied` and `No rendezvous client`, one helper, after the kill; week-2 results, "Teardown rendezvous
lines"); run 2 has no `ERROR` line. No probe process left afterwards.

### What this means for the plan

1. **Risk 1 is retired.** `MessagePumpNSApplication` drains the main dispatch queue, so `Task.sleep` on the main
   actor, async `AppComposition.start` and the contract runner's waits work under `ChromeMain`. W3-2 and W3-6 can
   proceed on the threading model as written.
2. **Decision 3, "Nested run loops", needs a qualifier.** The main queue drains in every common-mode spin *except*
   inside a nested loop entered from a main-queue callout (measured above; it matches CFRunLoop's rule of not servicing
   the main queue port while a main-queue block, here a main-actor job, is on the stack). Swift's main executor is the main queue, so a
   menu or modal opened synchronously from a main-actor job freezes every other main-actor job (timers, `Task.sleep`
   resumptions, async completions) until it closes. Nested loops entered from a run-loop callout (AppKit event
   dispatch, timers, and Chromium's work source, which is a run-loop source) do drain main-actor jobs, so the
   facade's nesting guard for Chromium-entered loops stays necessary.
3. **Rules, "No nested loops in engine handlers", is wrong in its last sentence.** "Present modals from a fresh
   main-actor turn" is exactly the case that starves the main actor. Replace with: present menus and alerts from an
   AppKit action or event callout, or non-blocking (`beginSheetModal(for:)`, `NSMenu.popUp` from an action), or
   schedule the synchronous call on the run loop (`RunLoop.main.perform(inModes: [.common])`), never synchronously
   from a `Task` or `DispatchQueue.main.async`.
4. **Chromium tasks keep running inside Swift-opened nested loops**, even one entered from a main-actor job
   (`Browser.getVersion` never slower than 33 ms). This is consistent with Chromium banning its tasks only in native
   loops entered while one of its own tasks runs (`thread_controller_with_message_pump_impl.cc:389`, `:448`). So while a Swift menu or modal is open, facade event batches (posted Chromium tasks)
   still run and call Swift handlers on the same stack. Decision 3 should state it: handlers must not assume the
   shell is idle when they run, and the W3-3 gate should add "facade batch arrives while a Swift-opened `NSAlert` is
   up" next to its existing "Swift modal inside a batch" case.
5. Plan step 3's `grep` needs `-F` (above); W3-3's `nm -u` check has the same `$` and should also use `-F`.
