#if ARKT_CHROMIUM_ENGINE
import AppKit
import ChromiumEngineKit
import Darwin
import EngineAPI

// The engine lane's stand-in shell, for its probes only (--arkt-reentrancy-probe, --arkt-embedder-fail); every
// other Engine launch runs ChromiumShell over AppComposition (W3-7 part C). A simulated 2 s start before
// embedderReady (or a failure with --arkt-embedder-fail), plain windows for the engine's own window requests that
// mount the active tab's container, logged quit seams and a simulated flush. W3-9 decides whether the probes move to
// the Arkt shell.

nonisolated func shellLog(_ message: String) {
    var now = timeval()
    gettimeofday(&now, nil)
    var seconds = now.tv_sec
    var local = tm()
    localtime_r(&seconds, &local)
    let stamp = String(
        format: "%02d:%02d:%02d.%03d", local.tm_hour, local.tm_min, local.tm_sec,
        Int(now.tv_usec) / 1000)
    FileHandle.standardError.write(Data("[\(stamp)] ARKT engine shell: \(message)\n".utf8))
}

/// The main run loop's current mode, for logs ("none" outside any run loop).
@MainActor
func runLoopModeName() -> String {
    RunLoop.current.currentMode?.rawValue ?? "none"
}

@MainActor
final class StandInShell: ChromiumEmbedderDelegate {
    static let shared = StandInShell()

    /// The launch asks for the stand-in: one of the engine lane's probe switches is present.
    static var isRequested: Bool {
        let arguments = CommandLine.arguments
        return arguments.contains("--arkt-reentrancy-probe") || arguments.contains("--arkt-embedder-fail")
    }

    /// Stands in for `AppComposition.start`.
    private static let simulatedStart: Duration = .seconds(2)
    /// Stands in for `flush()` at terminate.
    private static let simulatedFlush: Duration = .milliseconds(300)

    private(set) var engine: ChromiumEngine?
    private var observation: EngineObservation?
    private var windowObservation: EngineObservation?
    private var probe: ReentrancyProbe?
    /// The tabs the shell has seen announced and not closed, from events only.
    private(set) var knownTabs: Set<TabID> = []
    /// Called after every tab event (the re-entrancy probe).
    var onEvent: ((EngineEvent) -> Void)?

    struct StartFailure: Error {}

    func start(engine: ChromiumEngine) async throws {
        shellLog("engineDidStart (embedder class \(ChromiumEmbedding.embedderClassName))")
        self.engine = engine
        observation = engine.observe { [weak self] event in self?.handle(event) }
        windowObservation = engine.observeWindows { event in shellLog("window event \(event)") }
        if CommandLine.arguments.contains("--arkt-reentrancy-probe") {
            let probe = ReentrancyProbe(engine: engine, shell: self)
            self.probe = probe
            onEvent = { [weak probe] event in probe?.didHandle(event) }
        }
        try await Task.sleep(for: Self.simulatedStart)
        if CommandLine.arguments.contains("--arkt-embedder-fail") {
            shellLog("simulated start failed, calling embedderFailed")
            throw StartFailure()
        }
        shellLog("simulated start finished, calling embedderReady")
    }

    func startFailed(_ error: any Error) {
        // W3-7 part C shows the launch-failure alert here and quits through the engine.
        shellLog("start failed: \(error)")
    }

    /// Called inside Browser construction: build the window, return its host, never call the engine here.
    func host(for request: EngineWindowRequest, in engine: ChromiumEngine) -> any EngineWindowHosting {
        shellLog(
            "hostForEngineWindowRequest kind \(request.kind) initial URL \(request.initialURL?.absoluteString ?? "none")")
        return StandInWindowHost(bounds: request.bounds)
    }

    func engineWillBeginTerminating() {
        let visible = NSApp.windows.filter(\.isVisible).count
        shellLog("engineWillBeginTerminating (\(visible) visible window(s))")
    }

    func engineDidCancelTerminating() {
        shellLog("engineDidCancelTerminating")
    }

    func engineWillTerminate() async {
        shellLog("engineWillTerminate")
        try? await Task.sleep(for: Self.simulatedFlush)
        shellLog("simulated flush done, calling the completion")
    }

    // MARK: Events

    private func handle(_ event: EngineEvent) {
        switch event {
        case .tabCreated(let id): knownTabs.insert(id)
        case .tabClosed(let id, let reason):
            knownTabs.remove(id)
            shellLog("tab closed reason \(reason)")
        case .activeTabChanged(let id): mount(id)
        default: break
        }
        onEvent?(event)
    }

    /// The stand-in host shows its window's active tab, as the self-test embedder does (Decision 6: the host mounts).
    private func mount(_ id: TabID) {
        guard let engine, let window = engine.snapshot(of: id)?.window,
            let host = engine.host(of: window) as? StandInWindowHost, let view = engine.contentView(for: id)
        else { return }
        host.show(view)
    }

    /// Whether the shell's tab table equals the engine's.
    func tabsConsistent() -> (consistent: Bool, shell: Int, engine: Int) {
        let engineTabs = Set(engine?.tabIDs ?? [])
        return (engineTabs == knownTabs, knownTabs.count, engineTabs.count)
    }
}

/// A plain window for an engine-initiated window request. Its close button asks the engine
/// (`onCloseRequested`); it never closes the window itself.
@MainActor
final class StandInWindowHost: NSObject, EngineWindowHosting, NSWindowDelegate {
    let window: NSWindow
    let cardView: NSView
    var forward: EngineCommandForwarding?
    var onCloseRequested: (@MainActor () -> Void)?

    init(bounds: CGRect?) {
        window = NSWindow(
            contentRect: bounds ?? NSRect(x: 200, y: 200, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        cardView = NSView(frame: window.contentLayoutRect)
        cardView.autoresizingMask = [.width, .height]
        super.init()
        window.contentView = cardView
        window.delegate = self
    }

    func claim(_ command: EngineCommand) -> CommandClaim? { nil }

    func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool { false }

    func show(_ view: NSView) {
        guard view.superview !== cardView else { return }
        cardView.subviews.forEach { $0.removeFromSuperview() }
        view.frame = cardView.bounds
        view.autoresizingMask = [.width, .height]
        cardView.addSubview(view)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCloseRequested?()
        return false
    }
}
#endif
