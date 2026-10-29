import AppKit
import FakeEngineKit
import ShellUI

/// The FakeEngine build's application delegate: installs the menu, drives `AppComposition` and answers the AppKit
/// quit and reopen callbacks. (The Engine build's delegate is Chromium's `AppController`; there the composition is
/// driven from the embedder's seams, `App/Engine/`.)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let composition = AppComposition()
  /// True while a `.terminateLater` reply is outstanding; a second quit request then waits for the same flush.
  private var terminationPending = false
  /// Cmd-Q asks only while Settings > Warn before quitting is on (#487, BH-177).
  private let quitWarning = QuitWarningGate()
  #if DEBUG || ARKT_SMOKE_BUILD
  /// The in-memory window the scripted smoke drives (`-ArktSmoke YES`, Debug and Profile builds only); nil on a
  /// normal launch.
  private var smokeController: ShellWindowController?
  #endif

  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
    // Strict UI-test mode: refuse to start, before any disk access, unless every override points away from the real
    // data and defaults.
    if AppEnvironment.isUITest {
      let missing = AppEnvironment.missingUITestOverrides()
      if !missing.isEmpty {
        AppSession.log.error("uitest missing overrides \(missing.joined(separator: " "), privacy: .public)")
        exit(64)
      }
    }
    #endif
    MainMenu.install(commands: composition.commands)
    #if DEBUG
    switch EnvironmentOverrides(environment: ProcessInfo.processInfo.environment).appearance {
    case .light?: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark?: NSApp.appearance = NSAppearance(named: .darkAqua)
    case nil: break
    }
    #endif
    NSApp.activate()
    #if DEBUG || ARKT_SMOKE_BUILD
    // Only the command line counts (`-ArktSmoke YES`), never a persisted default.
    if SmokeArguments.isEnabled {
      startSmoke()
      return
    }
    #endif
    Task { [composition] in
      do {
        try await composition.start(engine: FakeEngine())        // FakeEngine: composition root only
      } catch {
        composition.quit()                                       // Quit in the launch-failure alert
      }
    }
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

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationPending else { return .terminateLater }   // the pending flush replies for both
    let warns = composition.session?.settings.warnsBeforeQuitting ?? false
    switch quitWarning.begin(warns: warns) {
    case .ask:
      // The alert runs on the next turn. A modal inside this callback would nest under the terminate reply.
      RunLoop.main.perform(inModes: [.common]) { [weak self] in
        MainActor.assumeIsolated { self?.presentQuitWarning() }
      }
      return .terminateLater
    case .wait:
      return .terminateLater
    case .stop:
      return .terminateCancel
    case .proceed:
      return finishTermination(sender)
    }
  }

  /// The existing alert. Quit continues into the flush; Cancel leaves the app running and unsaved state unstamped.
  private func presentQuitWarning() {
    let confirmed = DialogAlert(content: .quitWarning).runModal() == .primary
    switch quitWarning.reply(confirmed: confirmed) {
    case .proceed:
      let reply = finishTermination(NSApp)
      if reply != .terminateLater { NSApp.reply(toApplicationShouldTerminate: reply == .terminateNow) }
    case .stop:
      NSApp.reply(toApplicationShouldTerminate: false)
    case .ask, .wait:
      break
    }
  }

  /// The quit path used when the warning is off, and after the user confirms. A failed save never blocks quitting.
  private func finishTermination(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard composition.session != nil else { return .terminateNow }
    composition.prepareForTermination()               // stamps visible tabs first (decision 10)
    guard composition.needsFlush else { return .terminateNow }
    terminationPending = true
    Task { @MainActor [composition] in
      let flushed = await composition.flush()         // bounded by the flush timeout
      AppSession.log.notice("termination flush succeeded \(flushed, privacy: .public)")
      sender.reply(toApplicationShouldTerminate: true) // always true: never block quitting on a failed save
    }
    return .terminateLater
  }

  /// A link or file another app opened with Arkt (it can be the default browser, onboarding section 6.4).
  func application(_ application: NSApplication, open urls: [URL]) {
    composition.session?.openFromOtherApp(urls)
  }

  /// Closing the last window keeps the app running, as the engine build does (Chromium's keep-alive) and as macOS
  /// apps do (maintainer decision on #241); Quit is the way out.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  /// Dock click (or `open`) with no browser window on screen: one comes back (#241), also when only the Archive window
  /// is open.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard let windows = composition.session?.windows,
          !windows.controllers.contains(where: { $0.window?.isVisible == true }) else { return true }
    composition.reopenWindow()
    return false
  }
}
