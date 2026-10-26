import AppKit
import XCTest
@testable import ShellUI

/// Settings > Privacy > Crash reports (#129): one switch, off by default, and the Send Crash Report button that is
/// offered only while the switch is on and a report is stored.
@MainActor
final class CrashReportSettingsTests: XCTestCase {
  private var controllers: [SettingsWindowController] = []
  private var suites: [String] = []

  override func tearDown() {
    for controller in controllers { controller.window?.close() }
    controllers = []
    for name in suites { UserDefaults().removePersistentDomain(forName: name) }
    suites = []
    super.tearDown()
  }

  private func makeSettings() throws -> AppSettings {
    let name = "dev.arkt.tests.crashsettings.\(UUID().uuidString)"
    suites.append(name)
    return AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: name)))
  }

  private final class Services {
    var count = 0
    var sent = 0
  }

  private func make(_ settings: AppSettings, services: Services = Services()) -> SettingsWindowController {
    var env = SettingsServices()
    env.crashReportCount = { services.count }
    env.sendCrashReport = { services.sent += 1 }
    let controller = SettingsWindowController(settings: settings, services: env)
    controllers.append(controller)
    controller.show(pane: .privacy)
    return controller
  }

  private static func view(_ identifier: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == identifier { return root }
    for child in root.subviews {
      if let hit = view(identifier, in: child) { return hit }
    }
    return nil
  }

  private func control<T: NSView>(_ setting: String, in controller: SettingsWindowController,
                                  as type: T.Type = T.self) throws -> T {
    let root = try XCTUnwrap(controller.window?.contentView)
    return try XCTUnwrap(Self.view(AXID.Settings.control("privacy", setting), in: root) as? T, setting)
  }

  func testTheSwitchIsOffByDefaultAndWritesTheSetting() throws {
    let settings = try makeSettings()
    let controller = make(settings)
    let toggle: SettingsSwitch = try control("sendCrashReports", in: controller)
    XCTAssertEqual(toggle.state, .off)
    XCTAssertEqual(toggle.enclosingSettingsRow?.labelText, "Send crash reports")
    toggle.onChange?(true)
    XCTAssertTrue(settings.sendsCrashReports)
  }

  func testTheSendButtonIsOfferedOnlyWithTheSwitchOnAndAStoredReport() throws {
    let settings = try makeSettings()
    let services = Services()
    services.count = 2
    let controller = make(settings, services: services)
    let button: ArchivePillButton = try control("sendCrashReport", in: controller)
    XCTAssertFalse(button.isEnabled, "the switch is off: nothing is offered")

    settings.sendsCrashReports = true
    XCTAssertTrue(button.isEnabled)
    XCTAssertEqual(button.title, "Send Crash Report")
    button.performClick(nil)
    XCTAssertEqual(services.sent, 1)

    settings.sendsCrashReports = false
    XCTAssertFalse(button.isEnabled)
  }

  func testNoStoredReportDisablesTheButtonAndSaysSo() throws {
    let settings = try makeSettings()
    settings.sendsCrashReports = true
    let controller = make(settings)
    let button: ArchivePillButton = try control("sendCrashReport", in: controller)
    XCTAssertFalse(button.isEnabled)
    XCTAssertEqual(button.enclosingSettingsRow?.captionText, "No crash reports on this Mac.")
  }

  func testTheCaptionCountsTheStoredReports() throws {
    let settings = try makeSettings()
    settings.sendsCrashReports = true
    let services = Services()
    services.count = 1
    let one: ArchivePillButton = try control("sendCrashReport", in: make(settings, services: services))
    XCTAssertEqual(one.enclosingSettingsRow?.captionText,
                   "1 crash report on this Mac. Sending opens a GitHub issue for you to review.")
    services.count = 3
    let three: ArchivePillButton = try control("sendCrashReport", in: make(settings, services: services))
    XCTAssertTrue(three.enclosingSettingsRow?.captionText.hasPrefix("3 crash reports on this Mac.") == true)
  }

  func testPrivacyStillHasAtMostOneMustardPrimary() throws {
    let controller = make(try makeSettings())
    XCTAssertLessThanOrEqual(controller.primaryActionCount(in: .privacy), 1)
  }
}
