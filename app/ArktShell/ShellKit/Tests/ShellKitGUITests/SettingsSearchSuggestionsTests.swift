import AppKit
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// Exercises the real Settings controls, shared command-bar setting and query path. AppSession's composition is
/// app-target work and is not exercised by this ShellKit fixture.
@MainActor
final class SettingsSearchSuggestionsTests: XCTestCase {
  private var suiteName = ""
  private var defaults = UserDefaults.standard
  private var settingsWindows: [SettingsWindowController] = []
  private var shells: [ShellWindowController] = []
  private var bars: [CommandBarController] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    suiteName = "dev.arkt.tests.suggestions.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() async throws {
    bars.forEach { $0.invalidate() }
    settingsWindows.forEach { $0.window?.close() }
    shells.forEach { $0.close() }
    UserDefaults().removePersistentDomain(forName: suiteName)
  }

  private func makeSettings(_ setting: CommandBarSettings) -> SettingsWindowController {
    var services = SettingsServices()
    services.searchSuggestionsEnabled = { setting.searchSuggestionsEnabled }
    services.setSearchSuggestionsEnabled = { setting.setSearchSuggestionsEnabled($0) }
    let window = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
    settingsWindows.append(window)
    window.show(pane: .spaces)
    return window
  }

  private func makeBar(_ setting: CommandBarSettings) throws -> CommandBarController {
    let shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    shells.append(shell)
    let window = try XCTUnwrap(shell.window)
    shell.showWindow(nil)
    let bar = CommandBarController(parent: window)
    bars.append(bar)
    bar.settings = setting
    bar.dismissFinisher = { $0() }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.barView.widthMotion.drivesFramesItself = false
    bar.show(.newTab)
    return bar
  }

  private func find(_ identifier: String, in view: NSView) -> NSView? {
    if view.accessibilityIdentifier() == identifier { return view }
    for child in view.subviews {
      if let match = find(identifier, in: child) { return match }
    }
    return nil
  }

  private func suggestionsSwitch(_ window: SettingsWindowController) throws -> SettingsSwitch {
    let root = try XCTUnwrap(window.window?.contentView)
    let control = try XCTUnwrap(find(AXID.Settings.control("spaces", "searchSuggestions"), in: root))
    return try XCTUnwrap(control as? SettingsSwitch)
  }

  func testLoadedValueAndChangesReachBothOpenBarsAndPersist() throws {
    defaults.set(false, forKey: CommandBarSettings.searchSuggestionsDefaultsKey)
    let setting = CommandBarSettings(defaults: defaults)
    let first = try makeBar(setting)
    let second = try makeBar(setting)
    let window = makeSettings(setting)
    let control = try suggestionsSwitch(window)
    XCTAssertTrue(control.isEnabled)
    XCTAssertEqual(control.state, .off)
    first.setQueryForTesting("first query")
    second.setQueryForTesting("second query")
    XCTAssertFalse(first.results.contains { $0.kind.name == "search" })
    XCTAssertFalse(second.results.contains { $0.kind.name == "search" })

    control.performClick(nil)
    XCTAssertTrue(setting.searchSuggestionsEnabled)
    XCTAssertTrue(first.results.contains { $0.kind.name == "search" })
    XCTAssertTrue(second.results.contains { $0.kind.name == "search" })
    first.setQueryForTesting("another query")
    XCTAssertTrue(first.results.contains { $0.kind.name == "search" })
    XCTAssertTrue(CommandBarSettings(defaults: defaults).searchSuggestionsEnabled)

    control.performClick(nil)
    XCTAssertFalse(setting.searchSuggestionsEnabled)
    XCTAssertFalse(first.results.contains { $0.kind.name == "search" })
    XCTAssertFalse(second.results.contains { $0.kind.name == "search" })
    first.setQueryForTesting("new query")
    XCTAssertFalse(first.results.contains { $0.kind.name == "search" })
    let reopenedSetting = CommandBarSettings(defaults: defaults)
    XCTAssertFalse(reopenedSetting.searchSuggestionsEnabled)
    window.window?.close()
    let reopened = makeSettings(reopenedSetting)
    XCTAssertEqual(try suggestionsSwitch(reopened).state, .off)
  }
}
