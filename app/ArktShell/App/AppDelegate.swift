import AppKit
import FakeEngineKit
import ShellUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var controller: ShellWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.make()
    let engine = FakeEngine()                         // composition root only
    let controller = ShellWindowController(engine: engine)
    controller.window?.center()
    controller.showWindow(nil)
    self.controller = controller
    NSApp.activate()
    // -ArktSmoke YES on the command line lands in UserDefaults via the argument domain.
    if UserDefaults.standard.bool(forKey: "ArktSmoke") {
      SmokeWatchdog.start()
      let runner = SmokeRunner(controller: controller)
      Task { @MainActor in
        let code = await runner.run()
        fflush(stdout)
        exit(code)
      }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
