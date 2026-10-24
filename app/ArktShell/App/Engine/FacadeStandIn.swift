#if ARKT_CHROMIUM_ENGINE
import AppKit
import Darwin

// Stand-in access to the engine facade for the W3-3 gate.
//
// The facade header (engine/arkt/api/arkt_engine.h) is visible to Swift only as
// the ShellKit module ArktEngineABI, which only ChromiumEngineKit may import
// (EngineABIIsolationTests). ChromiumEngineKit is Task W3-6 and needs the W3-1
// EngineAPI additions, so until then the app reaches the facade the way the
// engine reaches the embedder: through the Objective-C runtime, by selector
// name. Only the calls the gate needs are here; W3-6 and W3-9 replace this file
// with ChromiumEngine and a typed ArktShellEmbedder in ChromiumEngineKit.

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

/// `ArktEngineEventKind` values the gate looks at (arkt_engine.h).
enum FacadeEventKind: Int {
    case tabCreated = 0
    case tabClosed = 1
    case activeTabChanged = 2
    case closeCancelled = 3
    case windowOpened = 11
    case windowClosed = 12
}

/// `id<ArktEngine>`.
@MainActor
struct EngineFacade {
    let object: NSObject

    func embedderReady() {
        _ = object.perform(NSSelectorFromString("embedderReady"))
    }

    func embedderFailed() {
        _ = object.perform(NSSelectorFromString("embedderFailed"))
    }

    var browsers: [FacadeBrowser] {
        (object.value(forKey: "browsers") as? [NSObject] ?? []).map(FacadeBrowser.init)
    }

    /// `-addEventSink:`. The sink runs on the main thread, from a posted
    /// Chromium task.
    @discardableResult
    func addEventSink(_ sink: @escaping @MainActor ([FacadeEvent]) -> Void) -> NSObject? {
        let block: @convention(block) (NSArray) -> Void = { batch in
            MainActor.assumeIsolated {
                sink(batch.compactMap { $0 as? NSObject }.map(FacadeEvent.init))
            }
        }
        let token = object.perform(
            NSSelectorFromString("addEventSink:"), with: unsafeBitCast(block, to: AnyObject.self))
        return token?.takeUnretainedValue() as? NSObject
    }
}

/// `id<ArktBrowserHandle>`.
@MainActor
struct FacadeBrowser {
    let object: NSObject

    var windowId: Int32 {
        (object.value(forKey: "windowId") as? NSNumber)?.int32Value ?? -1
    }

    var tabs: [FacadeTab] {
        (object.value(forKey: "tabs") as? [NSObject] ?? []).map(FacadeTab.init)
    }

    /// `-createTabWithURL:active:`: the handle at once, inserted now or, inside
    /// a nested run loop, when the engine's posted task runs.
    func createTab(url: URL?, active: Bool) -> FacadeTab? {
        typealias Call = @convention(c) (NSObject, Selector, NSURL?, ObjCBool) -> Unmanaged<NSObject>?
        let selector = NSSelectorFromString("createTabWithURL:active:")
        let call = unsafeBitCast(object.method(for: selector), to: Call.self)
        return call(object, selector, url as NSURL?, ObjCBool(active))
            .map { FacadeTab(object: $0.takeUnretainedValue()) }
    }
}

/// `id<ArktTabHandle>`.
@MainActor
struct FacadeTab {
    let object: NSObject

    var sessionId: Int32 {
        (object.value(forKey: "sessionId") as? NSNumber)?.int32Value ?? -1
    }

    /// `-closeWithMode:` with `ArktCloseModeHonourUnloadHandlers`. True when
    /// the engine answered `ArktCloseResultHeld`.
    func closeHonouringUnloadHandlers() -> Bool {
        typealias Call = @convention(c) (NSObject, Selector, Int) -> Int
        let selector = NSSelectorFromString("closeWithMode:")
        let call = unsafeBitCast(object.method(for: selector), to: Call.self)
        return call(object, selector, 0) == 1
    }
}

/// `id<ArktEngineEvent>`.
@MainActor
struct FacadeEvent {
    let object: NSObject

    var rawKind: Int { (object.value(forKey: "kind") as? NSNumber)?.intValue ?? -1 }
    var kind: FacadeEventKind? { FacadeEventKind(rawValue: rawKind) }
    var tab: NSObject? { object.value(forKey: "tab") as? NSObject }
    var closeReason: Int { (object.value(forKey: "closeReason") as? NSNumber)?.intValue ?? -1 }
    var origin: Int { (object.value(forKey: "origin") as? NSNumber)?.intValue ?? -1 }

    var summary: String {
        switch kind {
        case .tabCreated: "TabCreated(origin \(origin == 0 ? "client" : "engine"))"
        case .tabClosed: "TabClosed(reason \(closeReason))"
        case .activeTabChanged: "ActiveTabChanged"
        case .closeCancelled: "CloseCancelled"
        case .windowOpened: "WindowOpened"
        case .windowClosed: "WindowClosed"
        case nil: "kind \(rawKind)"
        }
    }
}

/// The host object the stand-in hands back for an engine window request.
/// Until host mode (Task W3-4) the engine only logs its class and keeps its
/// placeholder host, so this window is never shown.
@MainActor
@objc(ArktShellStandInWindowHost)
final class StandInWindowHost: NSObject {
    @objc let window: NSWindow
    @objc let cardView: NSView

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        cardView = NSView(frame: window.contentLayoutRect)
        super.init()
    }
}
#endif
