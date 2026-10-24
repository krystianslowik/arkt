#if ARKT_CHROMIUM_ENGINE
import AppKit

/// The embedder the engine's in-process hook looks up by name (week-3 plan,
/// Decision 1): `NSClassFromString(@"ArktShellEmbedder")`, then
/// `+sharedEmbedder` and `-engineDidStart:`.
///
/// W3-3 stand-in. It implements every `ArktEngineEmbedder` selector without
/// declaring the protocol (the header is ChromiumEngineKit's alone, see
/// FacadeStandIn.swift), logs each callback, and stands in for the shell's
/// start with a 2 s asynchronous delay before `embedderReady`. W3-7 part C and
/// W3-9 replace the delay with `AppComposition.start` and the logs with the
/// quit seams' real work (`prepareForTermination()`, `flush()`).
@MainActor
@objc(ArktShellEmbedder)
final class ArktShellEmbedder: NSObject {
    private static let shared = ArktShellEmbedder()

    /// Stands in for `AppComposition.start`.
    private static let simulatedStart: Duration = .seconds(2)
    /// Stands in for `flush()` at terminate.
    private static let simulatedFlush: Duration = .milliseconds(300)

    private var engine: EngineFacade?
    private var hosts: [StandInWindowHost] = []
    private var probe: ReentrancyProbe?
    /// The shell's view of the engine's tabs, kept only from facade events.
    private(set) var knownTabs: [ObjectIdentifier: NSObject] = [:]

    @objc static func sharedEmbedder() -> ArktShellEmbedder {
        shared
    }

    @objc(engineDidStart:)
    func engineDidStart(_ engineObject: NSObject) {
        shellLog("engineDidStart (facade \(type(of: engineObject)))")
        let engine = EngineFacade(object: engineObject)
        self.engine = engine
        engine.addEventSink { [weak self] batch in
            self?.handle(batch)
        }
        if CommandLine.arguments.contains("--arkt-reentrancy-probe") {
            probe = ReentrancyProbe(engine: engine, embedder: self)
        }
        let fails = CommandLine.arguments.contains("--arkt-embedder-fail")
        Task { @MainActor in
            try? await Task.sleep(for: Self.simulatedStart)
            if fails {
                shellLog("simulated start failed, calling embedderFailed")
                engine.embedderFailed()
            } else {
                shellLog("simulated start finished, calling embedderReady")
                engine.embedderReady()
            }
        }
    }

    /// Called inside Browser construction: build the window, return its host,
    /// never call the engine here.
    @objc(hostForEngineWindowRequest:)
    func host(for request: NSObject) -> NSObject {
        let kind = (request.value(forKey: "kind") as? NSNumber)?.intValue ?? -1
        let url = (request.value(forKey: "initialURL") as? URL)?.absoluteString ?? "none"
        shellLog("hostForEngineWindowRequest kind \(kind) initial URL \(url)")
        let host = StandInWindowHost()
        hosts.append(host)
        return host
    }

    @objc func engineWillBeginTerminating() {
        let visible = NSApp.windows.filter(\.isVisible).count
        shellLog("engineWillBeginTerminating (\(visible) visible window(s))")
    }

    @objc func engineDidCancelTerminating() {
        shellLog("engineDidCancelTerminating")
    }

    @objc(engineWillTerminate:)
    func engineWillTerminate(_ completion: @escaping @convention(block) () -> Void) {
        shellLog("engineWillTerminate")
        Task { @MainActor in
            try? await Task.sleep(for: Self.simulatedFlush)
            shellLog("simulated flush done, calling the completion")
            completion()
        }
    }

    // MARK: Events

    private func handle(_ batch: [FacadeEvent]) {
        for event in batch {
            guard let tab = event.tab else { continue }
            switch event.kind {
            case .tabCreated: knownTabs[ObjectIdentifier(tab)] = tab
            case .tabClosed: knownTabs[ObjectIdentifier(tab)] = nil
            default: break
            }
        }
        shellLog(
            "batch \(batch.map(\.summary).joined(separator: ", ")) "
                + "(run loop mode \(runLoopModeName()), modal window \(NSApp.modalWindow != nil ? "yes" : "no"), "
                + "known tabs \(knownTabs.count))")
        probe?.didHandle(batch)
    }

    /// Whether the shell's tab table equals the facade's tab lists.
    func tabsConsistent() -> (consistent: Bool, shell: Int, engine: Int) {
        let engineTabs = (engine?.browsers ?? []).flatMap(\.tabs).map { ObjectIdentifier($0.object) }
        let shellTabs = Set(knownTabs.keys)
        return (Set(engineTabs) == shellTabs && engineTabs.count == shellTabs.count, shellTabs.count, engineTabs.count)
    }
}
#endif
