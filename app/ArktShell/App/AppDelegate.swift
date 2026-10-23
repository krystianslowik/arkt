import AppKit
import FakeEngineKit
import Persistence
import ShellUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var session: AppSession?
  /// True while a `.terminateLater` reply is outstanding; a second quit request then waits for the same flush.
  private var terminationPending = false
  #if DEBUG || ARKT_SMOKE_BUILD
  /// The in-memory window the scripted smoke drives (`-ArktSmoke YES`, Debug and Profile builds only); nil on a
  /// normal launch.
  private var smokeController: ShellWindowController?
  #endif

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.make()
    NSApp.activate()
    #if DEBUG || ARKT_SMOKE_BUILD
    // Only the command line counts (`-ArktSmoke YES`), never a persisted default.
    if SmokeArguments.isEnabled {
      startSmoke()
      return
    }
    #endif
    Task { await launch() }
  }

  #if DEBUG || ARKT_SMOKE_BUILD
  /// The smoke runs against the in-memory sample sidebar, never the database: its swipes need two populated Spaces
  /// and a smoke run must not create or autosave a data folder.
  private func startSmoke() {
    let controller = ShellWindowController(engine: FakeEngine(), sidebar: StubSidebar.sample())   // composition root only
    controller.window?.center()
    controller.showWindow(nil)
    NSApp.activate()
    smokeController = controller
    SmokeWatchdog.start()
    let runner = SmokeRunner(controller: controller)
    Task { @MainActor in
      let code = await runner.run()
      fflush(stdout)
      exit(code)
    }
  }
  #endif

  /// All disk work (resolving the data folder, `openAndLoad`) runs in `@concurrent` functions; the main actor only
  /// awaits. The window is built after the load (milliseconds), so the sidebar never flashes empty.
  private func launch() async {
    do {
      let location = try await AppEnvironment.databaseLocation()
      let state = try await ArktLaunch.openAndLoad(location, now: .now)
      let favicons = await AppEnvironment.faviconStore(in: location)
      // FakeEngine: composition root only.
      let session = AppSession(state: state, location: location, engine: FakeEngine(), faviconStore: favicons)
      self.session = session
      session.start(outcome: state.outcome)
    } catch {
      presentLaunchFailure(error)
    }
  }

  /// No database is created or autosaved in this state (decision 4).
  private func presentLaunchFailure(_ error: any Error) {
    AppSession.log.error("launch failed \(String(describing: type(of: error)), privacy: .public)")
    let alert = NSAlert()
    alert.alertStyle = .critical
    let canRetry: Bool
    if case ArktDatabaseError.newerSchema = error {
      alert.messageText = "This data was saved by a newer version of Arkt."
      alert.informativeText = "Update Arkt to open it. Nothing was changed."
      alert.addButton(withTitle: "Quit")
      canRetry = false
    } else {
      alert.messageText = "Arkt couldn't open its data."
      alert.informativeText = "Nothing was changed. (\(type(of: error)) \((error as NSError).code))"
      alert.addButton(withTitle: "Try Again")
      alert.addButton(withTitle: "Quit")
      canRetry = true
    }
    if alert.runModal() == .alertFirstButtonReturn, canRetry {
      Task { await launch() }
    } else {
      NSApp.terminate(nil)
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationPending else { return .terminateLater }   // the pending flush replies for both
    guard let session else { return .terminateNow }
    session.prepareForTermination()                   // stamps visible tabs first (decision 10)
    guard session.needsFlush else { return .terminateNow }
    terminationPending = true
    Task { @MainActor in
      let flushed = await session.flush()             // bounded by the flush timeout
      AppSession.log.notice("termination flush succeeded \(flushed, privacy: .public)")
      sender.reply(toApplicationShouldTerminate: true) // always true: never block quitting on a failed save
    }
    return .terminateLater
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  /// File > Import from Arc... (nil-targeted; the app delegate ends the responder chain).
  @objc func importFromArc(_ sender: Any?) { session?.importFromArc() }

  /// Window > Show Archive (E5c, unbound by default, KB-043).
  @objc func showArchive(_ sender: Any?) { session?.showArchive() }
}

extension AppDelegate: NSMenuItemValidation {
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(importFromArc(_:)) {
      session?.refreshArcImportAvailability()           // off main; applies from the next validation
      return session?.canImportFromArc ?? false
    }
    if menuItem.action == #selector(showArchive(_:)) { return session != nil }
    return true
  }
}
