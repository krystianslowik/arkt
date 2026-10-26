import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ShellUI

/// The quick lookup bar's copy and geometry, its Settings switch, and the system-wide hotkey's state machine
/// (#354, KB-044, KB-045; docs/design/little-arkt.md, "Quick lookup").
@MainActor
struct LittleArktLookupTests {
  /// A fresh suite per test, removed afterwards; never the real defaults.
  private final class Suite {
    let name = "dev.arkt.tests.lookup.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
    deinit { UserDefaults().removePersistentDomain(forName: name) }
  }

  // MARK: Copy

  /// The design's copy table: the tag, the placeholder, the field's label and the settings row.
  @Test func copyMatchesTheDesign() {
    #expect(LittleArktLookup.tag == "Little Arkt")
    #expect(LittleArktLookup.placeholder == "Search or Enter URL...")
    #expect(LittleArktLookup.fieldLabel == "Little Arkt: Search or Enter URL")
    #expect(LittleArktLookup.menuTitle == "New Little Arkt Window")
    #expect(LittleArktLookup.settingLabel == "Open Little Arkt when I press \u{2325}\u{2318}N")
  }

  /// The conflict line is exactly the design's sentence, with the glyphs.
  @Test func theConflictLineNamesTheCombination() {
    #expect(LittleArktLookup.conflictMessage == "\u{2325}\u{2318}N is used by another app.")
  }

  // MARK: Geometry

  /// The bar is the command bar panel: 766 pt wide (narrower on small screens), 60 pt input, 50 pt rows, at 34 % of
  /// the screen, top edge pinned.
  @Test func theBarIsTheCommandBarPanelOnTheCurrentScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let frame = LittleArktLookup.frame(in: screen, rowCount: 3)
    #expect(frame.width == CommandBarGeometry.preferredWidth)
    #expect(frame.height == CommandBarGeometry.contentHeight(rowCount: 3))
    #expect(abs(frame.maxY - (screen.maxY - CommandBarGeometry.topFraction * screen.height)) < 0.001)
    #expect(frame.midX == screen.midX)
  }

  @Test func aNarrowScreenNarrowsTheBar() {
    let screen = CGRect(x: 0, y: 0, width: 700, height: 900)
    #expect(LittleArktLookup.frame(in: screen, rowCount: 0).width
      == 700 - 2 * CommandBarGeometry.sideMargin)
  }

  // MARK: Settings

  /// Off by default (decision 2026-10-25), stored under Arc's key, on again for a new store over the same suite.
  @Test func theHotKeySwitchIsOffByDefaultAndPersists() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    #expect(!settings.opensLittleArktWithHotKey)
    settings.opensLittleArktWithHotKey = true
    #expect(suite.defaults.bool(forKey: AppSettings.Key.globalLittleBrowserHotkeyEnabled))
    #expect(AppSettings(defaults: suite.defaults).opensLittleArktWithHotKey)
  }

  /// The conflict is runtime state: it reaches the Settings window through the observers and is never persisted.
  @Test func theConflictIsRuntimeState() throws {
    let suite = try Suite()
    let settings = AppSettings(defaults: suite.defaults)
    let recorder = Recorder()
    settings.addObserver(recorder)
    #expect(!settings.littleArktHotKeyTaken)
    settings.setLittleArktHotKeyTaken(true)
    #expect(settings.littleArktHotKeyTaken)
    #expect(recorder.count == 1)
    #expect(!suite.defaults.bool(forKey: AppSettings.Key.globalLittleBrowserHotkeyEnabled),
            "reported to the window, not written as a setting")
    settings.setLittleArktHotKeyTaken(true)
    #expect(recorder.count == 1, "the same answer tells nobody twice")
  }

  private final class Recorder: AppSettingsObserver {
    var count = 0
    func appSettingsDidChange(_ settings: AppSettings) { count += 1 }
  }

  // MARK: System-wide hotkey

  /// Starts off, so a fresh launch registers nothing (the decision of 2026-10-25).
  @Test func theMonitorStartsOff() {
    let registrar = FakeRegistrar()
    let monitor = LittleArktHotKeyMonitor(registrar: registrar)
    #expect(monitor.state == .off)
    #expect(!monitor.isEnabled)
    #expect(registrar.registerCount == 0)
  }

  /// The setting is applied once per change; a repeated sync does not register twice.
  @Test func enablingRegistersOnceAndDisablingUnregisters() {
    let registrar = FakeRegistrar()
    let monitor = LittleArktHotKeyMonitor(registrar: registrar)
    monitor.setEnabled(true)
    monitor.setEnabled(true)
    #expect(monitor.state == .active)
    #expect(registrar.registerCount == 1)
    monitor.setEnabled(false)
    #expect(monitor.state == .off)
    #expect(registrar.unregisterCount == 1)
  }

  /// Another app holds the combination: the state says so and the setting stays on, so toggling it retries.
  @Test func theCombinationTakenByAnotherAppIsATakenState() {
    let registrar = FakeRegistrar()
    registrar.status = OSStatus(eventHotKeyExistsErr)
    let monitor = LittleArktHotKeyMonitor(registrar: registrar)
    monitor.setEnabled(true)
    #expect(monitor.state == .taken)
    #expect(monitor.isEnabled, "the switch stays on; the in-app menu item still works")
    monitor.setEnabled(false)
    monitor.setEnabled(true)
    #expect(registrar.registerCount == 2, "turning it off and on tries again")
  }

  /// Any other Carbon failure keeps its status, so the log can name it.
  @Test func anotherFailureKeepsItsStatus() {
    let registrar = FakeRegistrar()
    registrar.status = OSStatus(-50)
    let monitor = LittleArktHotKeyMonitor(registrar: registrar)
    monitor.setEnabled(true)
    #expect(monitor.state == .failed(OSStatus(-50)))
  }

  /// The press reaches the app's handler: the lookup bar.
  @Test func thePressReachesTheHandler() {
    let registrar = FakeRegistrar()
    let monitor = LittleArktHotKeyMonitor(registrar: registrar)
    var pressed = 0
    monitor.onPress = { pressed += 1 }
    monitor.setEnabled(true)
    registrar.action?()
    #expect(pressed == 1)
  }

  /// Every registration answer changes the state once, and the app hears it (the Settings conflict line).
  @Test func theStateChangeIsReportedOnce() {
    let registrar = FakeRegistrar()
    let monitor = LittleArktHotKeyMonitor(registrar: registrar)
    var states: [LittleArktHotKeyMonitor.State] = []
    monitor.onStateChange = { states.append($0) }
    monitor.setEnabled(true)
    monitor.setEnabled(false)
    #expect(states == [.active, .off])
  }

  /// A stand-in for Carbon: records the calls and holds the action, so a test can press the combination.
  private final class FakeRegistrar: LittleArktHotKeyRegistering {
    var status: OSStatus = noErr
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var action: (@MainActor () -> Void)?

    func register(action: @escaping @MainActor () -> Void) -> OSStatus {
      registerCount += 1
      self.action = status == noErr ? action : nil
      return status
    }

    func unregister() {
      unregisterCount += 1
      action = nil
    }
  }
}
