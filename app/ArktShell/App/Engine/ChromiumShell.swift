#if ARKT_CHROMIUM_ENGINE
import AppKit
import ChromiumEngineKit
import EngineAPI

// The Engine build's shell (week-3 plan, W3-7 part C): the embedder's seams drive the same AppComposition as the
// FakeEngine build's AppDelegate. Chromium's AppController stays NSApp.delegate, so the menu is installed after its
// launch handler, and Dock reopen, startup URLs and extension windows arrive as engine window requests.

@MainActor
final class ChromiumShell: ChromiumEmbedderDelegate {
  static let shared = ChromiumShell()

  let composition = AppComposition()
  private var launchObserver: (any NSObjectProtocol)?

  // MARK: Menu (W3-7 part D step 7)

  /// Installs Arkt's menu one turn after `NSApplicationDidFinishLaunchingNotification`, after AppController's own
  /// `-applicationDidFinishLaunching:` (which binds Chromium's File menu delegate) ran; never from `engineDidStart`.
  /// Called by `engineMain()` before `ChromeMain`: it only registers an observer and touches no `NSApplication`.
  func installMenuAfterLaunch() {
    launchObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: nil
    ) { [weak self] _ in
      RunLoop.main.perform(inModes: [.common]) {
        MainActor.assumeIsolated { self?.installMenu() }
      }
    }
  }

  private func installMenu() {
    if let launchObserver { NotificationCenter.default.removeObserver(launchObserver) }
    launchObserver = nil
    MainMenu.install(commands: composition.commands)
    shellLog("main menu installed")
  }

  // MARK: ChromiumEmbedderDelegate

  /// The session is built before `embedderReady`; the launch window opens one run-loop turn later, after the engine
  /// replayed the window requests it queued (a startup URL or an extension window opens instead of it).
  func start(engine: ChromiumEngine) async throws {
    shellLog("engineDidStart (embedder class \(ChromiumEmbedding.embedderClassName))")
    #if ARKT_TEST_SWITCHES
    if EngineContractRunner.isRequested {
      // The contract runner (W3-9) needs the engine only: no session, no shell window. It starts one turn after
      // embedderReady, once the engine accepts windows. Not compiled into Distribution (#334).
      RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { EngineContractRunner.start() } }
      return
    }
    if ImportCheckRunner.isRequested {
      // The import check (#512), like the contract runner: the engine only, no session.
      RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { ImportCheckRunner.start() } }
      return
    }
    #endif
    try await composition.start(engine: engine, hostLookup: { [weak engine] id in engine?.host(of: id) },
                                defersWindows: true)
    shellLog("session ready; the embedder calls embedderReady next")
    RunLoop.main.perform(inModes: [.common]) {
      MainActor.assumeIsolated {
        let composition = ChromiumShell.shared.composition
        let queued = composition.session?.windows.controllers.count ?? 0
        composition.finishLaunch(opensWindow: queued == 0)
        shellLog("launch finished (\(queued) window(s) from queued requests)")
      }
    }
  }

  /// `start` threw: the user chose Quit in the launch-failure alert (Try Again runs inside `start`). The engine has
  /// dropped its queue; quit through Chromium's `terminate:`.
  func startFailed(_ error: any Error) {
    shellLog("start failed (\(type(of: error))), quitting")
    composition.quit()
  }

  /// Called inside `Browser` construction: builds the window, calls nothing on the engine.
  func host(for request: EngineWindowRequest, in engine: ChromiumEngine) -> any EngineWindowHosting {
    shellLog("window request kind \(request.kind)")
    return composition.host(for: request)
  }

  /// On SIGTERM (logout, shutdown, an update) this is the last main-actor code that runs: `chrome::SessionEnding()`
  /// blocks the main thread in `EndSession()` right after, then exits without `engineWillTerminate` (#298). So the
  /// pending writes go to disk here, with this thread waiting at most the flush timeouts. On a Cmd-Q quit the later
  /// `engineWillTerminate` flush then finds little or nothing left.
  func engineWillBeginTerminating() {
    shellLog("engineWillBeginTerminating")
    composition.prepareForTermination()  // stamps the visible tabs first (decision 10), so the flush carries them
    let flushed = composition.flushBlocking()
    shellLog("quit-start flush succeeded \(flushed)")
  }

  func engineDidCancelTerminating() {
    shellLog("engineDidCancelTerminating")
    composition.terminationCancelled()
  }

  /// The engine waits for the return (at most 5 s); the flush is bounded by its own timeouts.
  func engineWillTerminate() async {
    shellLog("engineWillTerminate")
    let flushed = await composition.flush()
    shellLog("termination flush succeeded \(flushed)")
  }
}
#endif
