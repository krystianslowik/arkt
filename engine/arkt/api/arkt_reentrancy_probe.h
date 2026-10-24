#ifndef ARKT_API_ARKT_REENTRANCY_PROBE_H_
#define ARKT_API_ARKT_REENTRANCY_PROBE_H_

namespace arkt {

// The W3-3 re-entrancy gate (week-3 plan, Decision 3), behind
// --arkt-reentrancy-probe. Runs phases from posted Chromium tasks and posts
// the notification "ArktReentrancyProbePhase" (userInfo: phase, step) to the
// embedder at each phase start, which runs the Swift half:
//
//   menu-in-chromium-task         NSMenu tracking entered from a Chromium task
//                                 (Chromium bans its own tasks inside); Swift
//                                 calls createTab and close from a main-actor
//                                 job 300 ms in.
//   menu-in-chromium-task-tasks-allowed
//                                 the same with application tasks allowed, as
//                                 Chromium's page context menu shows its menu
//                                 (ui::ShowContextMenu, allow_nested_tasks).
//   alert-in-chromium-task        NSAlert runModal entered from a Chromium
//                                 task; same Swift calls.
//   swift-alert-inside-batch      the forbidden case: the engine adds a tab and
//                                 a Swift event handler runs NSAlert runModal
//                                 inside that batch.
//   batch-during-swift-alert      Swift opens an NSAlert from a run-loop
//                                 callout; the engine adds a tab while it is
//                                 up, so a batch arrives under the alert.
//
// A heartbeat timer on the UI thread measures how long Chromium tasks stall
// in each phase. Menus and alerts the engine opens close after 2 s from a
// common-mode run-loop timer.
void StartReentrancyProbe();

}  // namespace arkt

#endif  // ARKT_API_ARKT_REENTRANCY_PROBE_H_
