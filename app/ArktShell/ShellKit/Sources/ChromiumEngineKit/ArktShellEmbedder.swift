import AppKit
internal import ArktEngineABI
import EngineAPI

/// What the app's engine composition root does at each embedder seam (week-3 plan, Decisions 2 and 13). The shell
/// sees only `ChromiumEngine` and `EngineAPI` types; the facade stays inside this module.
@MainActor
public protocol ChromiumEmbedderDelegate: AnyObject {
  /// The engine started (`-engineDidStart:`, before `-applicationDidFinishLaunching:`). Start the shell on `engine`
  /// and return once its session exists; the embedder then calls `embedderReady`, and the engine replays the window
  /// requests it queued. Throwing calls `embedderFailed` instead.
  func start(engine: ChromiumEngine) async throws
  /// `start(engine:)` threw and the engine dropped its queue. Called from a run-loop callout, so the shell may show its
  /// launch-failure alert modally here, then quit through the engine.
  func startFailed(_ error: any Error)
  /// A host for a window the engine creates on its own (Chromium is inside `Browser` construction). Build the window
  /// and return its host; never call the engine before the window's `.windowOpened`.
  func host(for request: EngineWindowRequest, in engine: ChromiumEngine) -> any EngineWindowHosting
  /// Quit started; the windows still exist (stamp visible tabs). On SIGTERM (session end) this is the last call: the
  /// engine then blocks the main thread and exits without `engineWillTerminate`, so write what must survive here,
  /// synchronously (#298).
  func engineWillBeginTerminating()
  /// The quit was cancelled (a held `beforeunload`, or the user).
  func engineDidCancelTerminating()
  /// The application is terminating: flush. The engine waits for the return, at most 5 s.
  func engineWillTerminate() async
}

/// The embedder the engine's in-process hook finds by name (Decision 1): `NSClassFromString(@"ArktShellEmbedder")`,
/// then `+sharedEmbedder` and `-engineDidStart:`. It must be in the main executable; `ChromiumEmbedding.install`
/// references the class, so dead stripping can never drop it.
@MainActor
@objc(ArktShellEmbedder)
final class ArktShellEmbedder: NSObject, ArktEngineEmbedder {
  static let shared = ArktShellEmbedder()

  /// Strong: the embedder lives for the process, and so does its delegate.
  var delegate: (any ChromiumEmbedderDelegate)?
  private(set) var facade: (any ArktEngine)?
  /// The engine instance that gets the engine's own window requests.
  private(set) var engine: ChromiumEngine?

  static func sharedEmbedder() -> any ArktEngineEmbedder { shared }

  func engineDidStart(_ facade: any ArktEngine) {
    guard let delegate else {
      preconditionFailure("ArktShellEmbedder: ChromiumEmbedding.install was not called before ChromeMain")
    }
    self.facade = facade
    let engine = ChromiumEngine(facade: facade)
    engine.windowHostProvider = { [unowned engine] request in delegate.host(for: request, in: engine) }
    self.engine = engine
    Task { @MainActor in
      do {
        try await delegate.start(engine: engine)
        facade.embedderReady()
      } catch {
        facade.embedderFailed()
        // Never a modal from inside a main-actor job: it would starve the main actor (W3-0a).
        RunLoop.main.perform(inModes: [.common]) {
          MainActor.assumeIsolated { ArktShellEmbedder.shared.delegate?.startFailed(error) }
        }
      }
    }
  }

  func host(for request: any ArktWindowRequest) -> any ArktWindowHost {
    guard let engine else { preconditionFailure("ArktShellEmbedder: a window request before engineDidStart") }
    return engine.host(for: request)
  }

  func engineWillBeginTerminating() { delegate?.engineWillBeginTerminating() }

  func engineDidCancelTerminating() { delegate?.engineDidCancelTerminating() }

  func engineWillTerminate(_ completion: @escaping () -> Void) {
    guard let delegate else {
      completion()
      return
    }
    Task { @MainActor in
      await delegate.engineWillTerminate()
      completion()
    }
  }

  /// Another engine instance over the same facade: it lists only its own windows and tabs (the contract runner).
  func makeEngine() -> ChromiumEngine? { facade.map(ChromiumEngine.init(facade:)) }
}

/// The app's entry to the embedder. Call `install` in the engine entry point, before `ChromeMain`.
@MainActor
public enum ChromiumEmbedding {
  /// Keeps `delegate` for the engine's seams, and references the embedder class so the linker keeps it.
  public static func install(_ delegate: any ChromiumEmbedderDelegate) {
    ArktShellEmbedder.shared.delegate = delegate
  }

  /// The Objective-C runtime name the engine's hook looks up.
  public static var embedderClassName: String { NSStringFromClass(ArktShellEmbedder.self) }

  /// The engine instance the embedder made at `-engineDidStart:`; nil before.
  public static var engine: ChromiumEngine? { ArktShellEmbedder.shared.engine }

  /// A further engine instance over the same facade (scoped to its own windows); nil before `-engineDidStart:`.
  public static func makeEngine() -> ChromiumEngine? { ArktShellEmbedder.shared.makeEngine() }
}
