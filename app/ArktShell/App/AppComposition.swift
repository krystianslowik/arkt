import AppKit
import EngineAPI
import Persistence
import ShellUI

/// Composition root for both engines (week-3 plan, W3-7 part C): opens the data folder, builds the session and its
/// windows, answers the engine's window requests, and runs the two quit seams. FakeEngine: `AppDelegate` drives it.
/// Chromium: the composition's `ChromiumEmbedderDelegate` conformance (`App/Engine/`, Engine configuration only)
/// drives it from the embedder's seams.
@MainActor
final class AppComposition {
  /// The user chose Quit after a failed launch.
  struct LaunchCancelled: Error {}

  /// The open data and windows; nil until `start` finished.
  private(set) var session: AppSession?
  /// The main menu's app-level target.
  let commands = AppCommands()
  /// How the app quits: `NSApp.terminate` in both builds. In the Engine build `NSApp` is Chromium's
  /// `BrowserCrApplication`, whose `terminate:` takes Chromium's quit path (the quit seams run as for the Quit item,
  /// week-3 results W3-8 run B); the facade has no `chrome::AttemptExit()` call of its own.
  let quit: @MainActor () -> Void

  init(quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
    self.quit = quit
    commands.composition = self
  }

  // MARK: - Start

  /// Opens the data folder and builds the session; all disk work runs in `@concurrent` functions and the main actor
  /// only awaits. The window is built after the load (milliseconds), so the sidebar never flashes empty. A failure
  /// asks the user (no database is created or autosaved meanwhile, decision 4): Try Again starts over, Quit throws
  /// `LaunchCancelled`.
  ///
  /// `hostLookup` pairs the engine's own windows with the windows built for them; `defersWindows` leaves the launch
  /// window to `finishLaunch(opensWindow:)` (Chromium, after `embedderReady`).
  func start(engine: any EngineClient, hostLookup: ShellWindowSet.HostLookup? = nil,
             defersWindows: Bool = false) async throws {
    while true {
      do {
        let location = try await AppEnvironment.databaseLocation()
        let state = try await ArktLaunch.openAndLoad(location, now: .now)
        let favicons = await AppEnvironment.faviconStore(in: location)
        let session = AppSession(state: state, location: location, engine: engine, faviconStore: favicons,
                                 hostLookup: hostLookup)
        self.session = session
        session.start(outcome: state.outcome, defersWindows: defersWindows)
        return
      } catch {
        guard await Self.askAfterLaunchFailure(error) else { throw LaunchCancelled() }
      }
    }
  }

  /// The launch window and auto-archive when `start` deferred them.
  func finishLaunch(opensWindow: Bool) { session?.finishLaunch(opensWindow: opensWindow) }

  /// The launch-failure alert; true for Try Again. Shown from a run-loop callout, never from inside this main-actor
  /// job: a modal session there would starve the main actor (week-3 W3-0a), and the engine forbids nested loops in
  /// its callbacks.
  private static func askAfterLaunchFailure(_ error: any Error) async -> Bool {
    AppSession.log.error("launch failed \(String(describing: type(of: error)), privacy: .public)")
    let text = LaunchFailureText(error)
    return await withCheckedContinuation { (answer: CheckedContinuation<Bool, Never>) in
      RunLoop.main.perform(inModes: [.common]) {
        MainActor.assumeIsolated { answer.resume(returning: text.runAlert()) }
      }
    }
  }

  // MARK: - Windows

  /// The engine's host provider: a window for the engine's own request (`ShellWindowSet.host(for:)`). The engine
  /// queues its requests until the session exists (Decision 2), so `start` has finished by now.
  func host(for request: EngineWindowRequest) -> any EngineWindowHosting {
    guard let session else {
      preconditionFailure("AppComposition: a window request before the session exists (the engine queues them)")
    }
    return session.windows.host(for: request)
  }

  /// FakeEngine's Dock reopen (#241).
  func reopenWindow() { session?.reopenWindow() }

  // MARK: - Quit

  /// True while something is unsaved (sidebar, archive outbox, favicons).
  var needsFlush: Bool { session?.needsFlush ?? false }

  /// Quit started: stop auto-archive and stamp the visible tabs (decision 10), while the windows still exist.
  func prepareForTermination() { session?.prepareForTermination() }

  /// The quit was cancelled: auto-archive runs again.
  func terminationCancelled() { session?.terminationCancelled() }

  /// Writes what is pending, bounded by the flush timeouts; true when everything was written.
  func flush() async -> Bool { await session?.flush() ?? true }

  /// Writes the pending sidebar and archive outbox while the calling (main) thread waits, bounded by the flush
  /// timeouts (#298: the engine's SIGTERM path never runs a main-actor job after quit start).
  func flushBlocking() -> Bool { session?.flushBlocking() ?? true }
}

/// What the launch-failure alert says; plain values, so the alert can be built in a run-loop callout.
private struct LaunchFailureText: Sendable {
  let message: String
  let information: String
  let canRetry: Bool

  init(_ error: any Error) {
    if case ArktDatabaseError.newerSchema = error {
      message = "This data was saved by a newer version of Arkt."
      information = "Update Arkt to open it. Nothing was changed."
      canRetry = false
    } else {
      message = "Arkt couldn't open its data."
      information = "Nothing was changed. (\(type(of: error)) \((error as NSError).code))"
      canRetry = true
    }
  }

  /// Runs the alert modally; true for Try Again.
  @MainActor
  func runAlert() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = message
    alert.informativeText = information
    if canRetry { alert.addButton(withTitle: "Try Again") }
    alert.addButton(withTitle: "Quit")
    let response = alert.runModal()
    return canRetry && response == .alertFirstButtonReturn
  }
}
