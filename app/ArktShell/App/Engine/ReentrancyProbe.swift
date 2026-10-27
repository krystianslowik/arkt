#if ARKT_CHROMIUM_ENGINE && ARKT_TEST_SWITCHES
import AppKit
import ChromiumEngineKit
import EngineAPI

/// The Swift half of the W3-3 re-entrancy gate (`--arkt-reentrancy-probe`;
/// engine half in engine/arkt/api/arkt_reentrancy_probe.{h,mm}). The engine
/// runs the phases from posted Chromium tasks and posts
/// `ArktReentrancyProbePhase` at each phase start and end. Since W3-6 the Swift half drives the facade through
/// `ChromiumEngine` (its calls answer at once: a deferred `createTab` is announced, a deferred close holds).
@MainActor
final class ReentrancyProbe {
    private static let probeURL = URL(string: "data:text/html,<title>W3-3 swift tab</title>")
    private static let mutateAfter: Duration = .milliseconds(300)
    private static let alertOpenFor: TimeInterval = 2.0
    private static let mutateInsideAlertAfter: TimeInterval = 0.4

    private let engine: ChromiumEngine
    private weak var shell: StandInShell?
    private var observer: (any NSObjectProtocol)?
    private var phase = ""
    /// Phase swift-alert-inside-batch: the next batch with a TabCreated opens
    /// an alert inside its handler (the forbidden case).
    private var alertInNextCreatedBatch = false
    private var swiftAlertUp = false

    init(engine: ChromiumEngine, shell: StandInShell) {
        self.engine = engine
        self.shell = shell
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("ArktReentrancyProbePhase"), object: nil, queue: nil
        ) { [weak self] note in
            let phase = note.userInfo?["phase"] as? String ?? ""
            let step = note.userInfo?["step"] as? String ?? ""
            // Posted on the main thread, from a Chromium task.
            MainActor.assumeIsolated {
                self?.phaseChanged(phase, step: step)
            }
        }
    }

    private func phaseChanged(_ phase: String, step: String) {
        guard step == "begin" else {
            logConsistency("\(phase) end")
            return
        }
        self.phase = phase
        switch phase {
        case "menu-in-chromium-task", "menu-in-chromium-task-tasks-allowed", "alert-in-chromium-task":
            // A main-actor job scheduled while the engine's nested loop is up.
            Task { @MainActor in
                try? await Task.sleep(for: Self.mutateAfter)
                shellLog(
                    "probe \(phase): main-actor job ran (run loop mode \(runLoopModeName()), "
                        + "modal window \(NSApp.modalWindow != nil ? "yes" : "no"))")
                self.mutate(during: phase)
            }
        case "swift-alert-inside-batch":
            alertInNextCreatedBatch = true
        case "batch-during-swift-alert":
            // From a run-loop callout, not a main-actor job or a Chromium task
            // (Rules, "No nested loops in engine handlers").
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated {
                    self?.runAlertFromCallout()
                }
            }
        default:
            shellLog("probe: unknown phase \(phase)")
        }
    }

    /// createTab and close through the engine while a nested loop is up.
    private func mutate(during phase: String) {
        guard let window = engine.windowIDs.first else {
            shellLog("probe \(phase): no engine window")
            return
        }
        let tab = engine.createTab(url: Self.probeURL, in: window)
        shellLog("probe \(phase): createTab returned \(tab)")
        engine.closeTab(tab)
        let held = engine.snapshot(of: tab)?.isClosing == true
        shellLog("probe \(phase): close answered \(held ? "held" : "closed")")
    }

    /// Called by the shell after each engine event.
    func didHandle(_ event: EngineEvent) {
        if swiftAlertUp {
            shellLog("probe \(phase): event handled while the Swift alert is up: \(event)")
        }
        guard alertInNextCreatedBatch, case .tabCreated = event else { return }
        alertInNextCreatedBatch = false
        shellLog("probe \(phase): opening an NSAlert inside an engine event handler (the forbidden case)")
        let start = ContinuousClock.now
        runAlert()
        let elapsed = Int((ContinuousClock.now - start) / .milliseconds(1))
        shellLog("probe \(phase): alert inside the batch closed after \(elapsed) ms")
    }

    private func runAlertFromCallout() {
        shellLog("probe \(phase): Swift alert opens from a run-loop callout")
        swiftAlertUp = true
        let insideAlert = Timer(timeInterval: Self.mutateInsideAlertAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                shellLog("probe \(self.phase): inside the Swift alert (run loop mode \(runLoopModeName()))")
                self.mutate(during: self.phase)
            }
        }
        RunLoop.main.add(insideAlert, forMode: .common)
        runAlert()
        swiftAlertUp = false
        logConsistency("\(phase) after the Swift alert")
    }

    /// NSAlert runModal, closed after 2 s by a common-mode timer, which fires in
    /// the modal mode whatever else is blocked.
    private func runAlert() {
        let alert = NSAlert()
        alert.messageText = "W3-3 probe"
        let closer = Timer(timeInterval: Self.alertOpenFor, repeats: false) { _ in
            MainActor.assumeIsolated {
                NSApp.stopModal()
                // stopModal takes effect once the modal loop handles an event.
                if let wake = NSEvent.otherEvent(
                    with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
                {
                    NSApp.postEvent(wake, atStart: true)
                }
            }
        }
        RunLoop.main.add(closer, forMode: .common)
        alert.runModal()
    }

    private func logConsistency(_ label: String) {
        guard let shell else { return }
        let state = shell.tabsConsistent()
        shellLog(
            "probe \(label): shell state consistent \(state.consistent ? "yes" : "no") "
                + "(shell \(state.shell) tab(s), engine \(state.engine))")
    }
}
#endif
