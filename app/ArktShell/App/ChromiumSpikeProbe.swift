#if ARKT_CHROMIUM_SPIKE
import AppKit
import Darwin

// Engine week 3, Task W3-0a: test-only probe of Swift's main-actor executor under
// Chromium's run loop. Spike configuration only; removed with the spike in W3-3.
//
// `startMainActorProbe()` runs before ChromeMain and only schedules work; nothing
// here touches NSApplication until the run loop is Chromium's. With the switch
// `--arkt-probe-nested` it also opens native nested run loops (an NSMenu and an
// NSAlert, each entered once from a run-loop timer callout and once from a
// main-actor job) and counts, for each, which kinds of main-thread work ran
// while it was open. A menu Chromium opens itself (a page context menu, driven
// over CDP) is measured through the menu tracking notifications.

@objc(ArktShellEmbedderProbe)
final class ArktShellEmbedderProbe: NSObject {}

nonisolated func probeLog(_ message: String) {
    var now = timeval()
    gettimeofday(&now, nil)
    var seconds = now.tv_sec
    var local = tm()
    localtime_r(&seconds, &local)
    let stamp = String(
        format: "%02d:%02d:%02d.%03d", local.tm_hour, local.tm_min, local.tm_sec,
        Int(now.tv_usec) / 1000)
    FileHandle.standardError.write(Data("[\(stamp)] ARKT probe: \(message)\n".utf8))
}

func startMainActorProbe() {
    let nested = CommandLine.arguments.contains("--arkt-probe-nested")
    Task { @MainActor in
        try await Task.sleep(for: .milliseconds(500))
        probeLog("main actor resumed")
        if nested {
            await NestedLoopProbe().run()
        }
    }
    DispatchQueue.main.async {
        probeLog("main queue drained")
    }
}

/// Counts main-thread work by source while a nested loop is open.
@MainActor
private final class NestedLoopProbe {
    private var phase: String?
    private var phaseStart = ContinuousClock.now
    private var mainActorTicks = 0
    private var mainQueueTicks = 0
    private var runLoopTicks = 0
    private var menuObservers: [any NSObjectProtocol] = []

    private static let openFor: Duration = .seconds(3)
    private static let tick: Duration = .milliseconds(100)

    func run() async {
        startTickers()
        observeEngineMenus()
        try? await Task.sleep(for: .seconds(20))
        await runPhase("menu-from-runloop-timer") { probe, done in
            probe.fromRunLoopTimer { probe.trackMenu(done: done) }
        }
        await runPhase("alert-from-runloop-timer") { probe, done in
            probe.fromRunLoopTimer { probe.runAlert(done: done) }
        }
        await runPhase("menu-from-main-actor-job") { probe, done in
            Task { @MainActor in probe.trackMenu(done: done) }
        }
        await runPhase("alert-from-main-actor-job") { probe, done in
            Task { @MainActor in probe.runAlert(done: done) }
        }
        probeLog("nested phases done; waiting for an engine context menu")
        try? await Task.sleep(for: .seconds(15))
        if phase == nil { NSApp.deactivate() }
        // Stay alive (this task holds the probe) for a late engine context-menu phase.
        try? await Task.sleep(for: .seconds(600))
    }

    // MARK: Tickers: one per way work reaches the main thread.

    private func startTickers() {
        Task { @MainActor [weak self] in
            while let self {
                try? await Task.sleep(for: Self.tick)
                self.mainActorTicks += 1
            }
        }
        scheduleMainQueueTick()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runLoopTicks += 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleMainQueueTick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.mainQueueTicks += 1
                self.scheduleMainQueueTick()
            }
        }
    }

    // MARK: Phases

    private func begin(_ name: String) {
        phase = name
        phaseStart = .now
        mainActorTicks = 0
        mainQueueTicks = 0
        runLoopTicks = 0
        probeLog("\(name) begin")
    }

    private func end() {
        guard let name = phase else { return }
        let elapsed = ContinuousClock.now - phaseStart
        probeLog(
            "\(name) end after \(elapsed.formatted(.units(allowed: [.milliseconds]))): "
                + "main actor ticks \(mainActorTicks), main queue ticks \(mainQueueTicks), "
                + "run loop timer ticks \(runLoopTicks)")
        phase = nil
    }

    /// Starts a phase, lets `open` enter the nested loop, and waits for it to end
    /// (the end is reported by the loop's own caller, so it does not depend on
    /// main-actor jobs running inside the loop).
    private func runPhase(
        _ name: String,
        open: (NestedLoopProbe, @escaping @MainActor () -> Void) -> Void
    ) async {
        NSApp.activate()
        try? await Task.sleep(for: .milliseconds(500))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            begin(name)
            open(self) { [weak self] in
                self?.end()
                continuation.resume()
            }
        }
        try? await Task.sleep(for: .seconds(2))
    }

    private func fromRunLoopTimer(_ body: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Closes the nested loop from a common-mode run-loop timer, which fires in
    /// tracking and modal modes whatever else is blocked.
    private func afterOpenTime(_ body: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: Self.openFor / .seconds(1), repeats: false) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func trackMenu(done: @escaping @MainActor () -> Void) {
        let menu = NSMenu(title: "Probe")
        menu.addItem(withTitle: "Probe item", action: nil, keyEquivalent: "")
        afterOpenTime { menu.cancelTracking() }
        guard let window = NSApp.windows.first(where: \.isVisible) else {
            probeLog("no visible window; menu not opened")
            done()
            return
        }
        menu.popUp(positioning: nil, at: NSPoint(x: window.frame.midX, y: window.frame.midY), in: nil)
        done()
    }

    private func runAlert(done: @escaping @MainActor () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Probe"
        afterOpenTime {
            NSApp.stopModal()
            // stopModal takes effect once the modal loop handles an event.
            if let wake = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
            {
                NSApp.postEvent(wake, atStart: true)
            }
        }
        alert.runModal()
        done()
    }

    // MARK: Menus the engine opens (page context menu over CDP)

    private func observeEngineMenus() {
        let center = NotificationCenter.default
        menuObservers.append(
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) {
                [weak self] note in
                // Posted on the main thread, where the menu lives.
                nonisolated(unsafe) let menu = note.object as? NSMenu
                MainActor.assumeIsolated {
                    guard let self, self.phase == nil, let menu, menu.supermenu == nil,
                        menu.title != "Probe"
                    else { return }
                    self.begin("engine-context-menu")
                    self.afterOpenTime { menu.cancelTracking() }
                }
            })
        menuObservers.append(
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.phase == "engine-context-menu" else { return }
                    self.end()
                    NSApp.deactivate()
                }
            })
    }
}
#endif
