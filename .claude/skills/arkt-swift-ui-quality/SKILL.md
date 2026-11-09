---
name: arkt-swift-ui-quality
description: Use when writing or reviewing Arkt Swift code, UI, animation or performance-sensitive paths - Swift 6 concurrency, deterministic tests, motion with a purpose and a Reduce Motion variant, the 120 Hz frame budget, one primary action per surface, and worst-case data.
---

# Arkt Swift and UI quality

Practices the team follows for Swift, motion, UI polish and performance, applied to this repo. The hard rules
are in `CONTRIBUTING.md`, section 7 and section 6, Pass 2; this skill is how to meet them.

## 0. Gate: write it down before editing

1. Which actor each new type and function runs on, and why.
2. Whether the change runs per frame or on a hot path (sidebar, command bar, window chrome, toasts, Archive table).
3. For any animation: what it tells the user. If nothing, it does not animate.
4. The worst-case data you will test with (see UI polish).
5. How you will measure, if the change is about speed.

## Swift 6 concurrency

- [ ] Swift 6 mode, complete checking, no new warnings. Fix diagnostics at the root.
- [ ] No `@unchecked Sendable` and no `nonisolated(unsafe)` in production code.
- [ ] UI and model state on the main actor. Disk, database and import work in `@concurrent` functions or the
      database queue; main-actor code only `await`s, never blocks or waits synchronously.
- [ ] Time is injected: clocks and sleepers are parameters, so tests can drive them.
- [ ] Tests never `sleep` and never assert against a wall-clock deadline (see `arkt-flaky-tests`).
- [ ] GUI tests close every window they open in `tearDown` (`arkt-flaky-tests`, "GUI test hygiene").

## Explicit state

When one behaviour's state is spread over several flags, optionals or tokens that must change together (#877):

- [ ] One `enum` holds the phase; data that only exists in a phase (tasks, timers, sessions, tokens) is its
      associated value.
- [ ] One transition entry point (`send(_:)`, `handle(_:)` or `step(_:)`) switches on `(state, event)`. Side
      effects come back as values or run in one place. Unknown pairs are no-ops.
- [ ] Async replies carry the token or session they started under and are dropped if it no longer matches.
- [ ] A debug-only transition log (`#if DEBUG`, as the command bar counters in #876), and the phase readable by
      tests (`internal` or `ForTesting`), so a test asserts one value and a transition sequence.
- [ ] One machine per pull request: first a test that reproduces the bad sequence and fails, then the conversion.
- [ ] Do not convert two-flag cases, single debounce tokens, re-entrancy guards, or code that already has a phase
      enum and tests.

Templates: `ShellUI/Onboarding/OnboardingFlow.swift`, `ShellUI/Window/QuitWarningGate.swift`,
`CrashReporting/CrashReportPolicy.swift`, `ShellWindow.TrafficLightPlacement` in `ShellUI/Window/ShellWindow.swift`,
and `Batch::Phase` with `Settle()` in `engine/arkt/browser/arkt_extension_batch_install.mm`.

## Motion

- [ ] Animate only when it has a purpose: show where something came from or went, confirm an action, or keep
      continuity. Otherwise change state instantly.
- [ ] Springs for movement, driven by the shared motion code, not ad hoc timers.
- [ ] Interruptible: a new gesture or state change retargets the running animation from its current value; it never
      jumps or waits for the old one to finish.
- [ ] Animate transform and opacity only. No per-frame layout, path or frame-size changes on hot paths.
- [ ] A Reduce Motion variant (a fade or an instant change), with a test that covers it.
- [ ] Stays inside the 120 Hz frame budget (about 8 ms per frame). Frame-time gates assert when their class
      runs alone at a load below the core count and only report otherwise (`CONTRIBUTING.md`, section 7, "Speed
      gates", which also covers the CPU gates).

## UI polish

- [ ] One primary action per surface; secondaries stay quiet.
- [ ] System font for everyday chrome; the Hero style only for moment surfaces (`arkt-design-first`).
- [ ] Hot paths are AppKit and Core Animation with frames set directly; no SwiftUI lists or Auto Layout there.
- [ ] Test worst-case data: very long titles and URLs, empty lists, one item, huge counts, missing favicons,
      non-Latin text, the smallest window. Nothing clips, overlaps or scrolls the window sideways.
- [ ] Light and dark, keyboard only, VoiceOver labels, no user-facing "Arc".

## Performance

- [ ] No work per frame on the main thread beyond setting layer properties.
- [ ] Measure before optimizing: a test, a timing gate or an Instruments trace, with the number before and after in
      the pull request. No speed claim without a number.

## Verify before you claim

The pull request lists the commands run and their counts, the worst-case data tried, Reduce Motion checked, and,
for speed work, the before and after numbers. **STOP** and say "not checked" for anything you did not run.

## Common mistakes we made

- A spring asserted mid-flight while the display link kept advancing it (#409, #436).
- Main-actor work starving a real-clock deadline on a busy runner (#396, #414).
- Space titles not drawn on pages the moving strip showed during a swipe (#422).
- A truncated Space title and an empty Space page (#323).
- Loading a page a second time instead of moving the live one between windows (#300, #360).
