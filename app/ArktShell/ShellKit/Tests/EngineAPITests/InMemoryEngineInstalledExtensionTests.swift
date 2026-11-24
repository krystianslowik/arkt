import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// The installed list, enable / disable, developer mode, Load unpacked and options pages (#600; engine side #964): the
/// `EngineExtensions` defaults and the InMemoryEngine behaviour Settings > Extensions builds against.
@MainActor
struct InMemoryEngineInstalledExtensionTests {
  private func info(_ id: String, _ name: String, enabled: Bool = true, canDisable: Bool = true,
                    canUninstall: Bool = true, origin: ExtensionOrigin = .webStore) -> InstalledExtensionInfo {
    InstalledExtensionInfo(id: id, name: name, version: "1.0", isEnabled: enabled, canDisable: canDisable,
                           canUninstall: canUninstall, origin: origin)
  }

  private func observe(_ engine: InMemoryEngine) -> (EngineObservation, () -> [EngineExtensionEvent]) {
    final class Box { var events: [EngineExtensionEvent] = [] }
    let box = Box()
    let token = engine.observeExtensions { box.events.append($0) }
    return (token, { box.events })
  }

  // MARK: - Defaults

  @Test func defaultsRefuseForAnEngineWithoutTheList() async {
    let engine = ListlessEngine()
    #expect(engine.installedExtensions.isEmpty)
    #expect(engine.setExtensionEnabled("a", enabled: false) == .unknownExtension)
    #expect(engine.isExtensionDeveloperModeEnabled == false)
    engine.setExtensionDeveloperModeEnabled(true)
    #expect(engine.isExtensionDeveloperModeEnabled == false)
    let result = await engine.loadUnpackedExtension(at: URL(fileURLWithPath: "/tmp/x"))
    #expect(result == .failed(reason: UnpackedExtensionResult.unsupportedReason))
    engine.openExtensionOptionsPage("a")
  }

  @Test func infoDefaultsAreAWebStoreExtensionTheUserControls() {
    let plain = InstalledExtensionInfo(id: "a", name: "A", version: "2")
    #expect(plain.description.isEmpty && plain.iconPNG == nil)
    #expect(plain.isEnabled && plain.canDisable && plain.canUninstall && !plain.hasOptionsPage)
    #expect(plain.origin == .webStore)
  }

  // MARK: - The list

  @Test func setInstalledExtensionsReportsOneChange() {
    let engine = InMemoryEngine()
    let (token, events) = observe(engine)
    engine.setInstalledExtensions([info("a", "A"), info("b", "B")])
    #expect(engine.installedExtensions.map(\.id) == ["a", "b"])
    #expect(events() == [.installedExtensionsChanged])
    token.cancel()
  }

  @Test func installAddsTheExtensionToTheListBeforeTheInstallEvent() {
    let engine = InMemoryEngine()
    let (token, events) = observe(engine)
    let installed = InstalledExtension(id: "q", name: "Quiet Reader", iconPNG: Data([1]))
    engine.installExtension(installed)
    #expect(engine.installedExtensions == [
      InstalledExtensionInfo(id: "q", name: "Quiet Reader", version: "1.0", iconPNG: Data([1])),
    ])
    #expect(events() == [.installedExtensionsChanged, .installed(installed)])
    token.cancel()
  }

  @Test func uninstallRemovesTheListedExtension() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("a", "A"), info("b", "B")])
    let (token, events) = observe(engine)
    engine.uninstallExtension("a", reportAbuse: false)
    #expect(engine.installedExtensions.map(\.id) == ["b"])
    #expect(events() == [.installedExtensionsChanged])
    token.cancel()
  }

  @Test func uninstallRefusesAPolicyExtensionAndAFailingOne() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("p", "Policy", canUninstall: false), info("f", "Fails")])
    engine.failingUninstallIDs = ["f"]
    let (token, events) = observe(engine)
    engine.uninstallExtension("p", reportAbuse: false)
    engine.uninstallExtension("f", reportAbuse: true)
    #expect(engine.installedExtensions.map(\.id) == ["p", "f"])
    #expect(events().isEmpty)
    #expect(engine.uninstalledExtensions.map(\.extensionID) == ["p", "f"], "the calls are recorded")
    token.cancel()
  }

  // MARK: - Enable and disable

  @Test func setEnabledChangesTheListOnceAndAnswers() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("a", "A")])
    let (token, events) = observe(engine)
    #expect(engine.setExtensionEnabled("a", enabled: false) == .applied)
    #expect(engine.installedExtensions.first?.isEnabled == false)
    #expect(events() == [.installedExtensionsChanged])
    #expect(engine.setExtensionEnabled("a", enabled: false) == .applied, "already off")
    #expect(events() == [.installedExtensionsChanged], "no change, no event")
    #expect(engine.setExtensionEnabled("zz", enabled: true) == .unknownExtension)
    token.cancel()
  }

  @Test func setEnabledRefusesAPolicyLockedExtension() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("p", "Policy", canDisable: false, origin: .policy)])
    let (token, events) = observe(engine)
    #expect(engine.setExtensionEnabled("p", enabled: false) == .refused)
    #expect(engine.installedExtensions.first?.isEnabled == true)
    #expect(events().isEmpty)
    token.cancel()
  }

  @Test func turningOnAnExtensionThatNeedsNewPermissionsAnswersSo() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("p", "Updated", enabled: false)])
    engine.permissionApprovalIDs = ["p"]
    let (token, events) = observe(engine)
    #expect(engine.setExtensionEnabled("p", enabled: true) == .needsPermissionApproval)
    #expect(engine.installedExtensions.first?.isEnabled == false)
    #expect(events().isEmpty)
    token.cancel()
  }

  @Test func anExtensionNeedingNewPermissionsCanStillBeToggled() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("p", "Updated", enabled: false)])
    engine.permissionApprovalIDs = ["p"]
    #expect(engine.installedExtensions.first?.canDisable == true, "the toggle is actionable: it answers why")
  }

  @Test func siteAccessDefaultsToNoHostAccess() {
    #expect(InstalledExtensionInfo(id: "a", name: "A", version: "1").siteAccess == .noHostAccess)
    let some = InstalledExtensionInfo(id: "b", name: "B", version: "1", siteAccess: .someSites(count: 3))
    #expect(some.siteAccess == .someSites(count: 3))
  }

  @Test func turningOffRemovesTheActionsAndTurningOnRestoresThem() {
    let engine = InMemoryEngine()
    let first = engine.createWindow(host: StubWindowHost())
    let second = engine.createWindow(host: StubWindowHost())
    for window in [first, second] {
      engine.setExtensionActions([ExtensionAction(id: "a", name: "A"), ExtensionAction(id: "b", name: "B")],
                                 in: window)
    }
    engine.setInstalledExtensions([info("a", "A"), info("b", "B")])
    let recorder = EventRecorder(engine)
    #expect(engine.setExtensionEnabled("a", enabled: false) == .applied)
    #expect(engine.extensionActions(in: first).map(\.id) == ["b"])
    #expect(engine.extensionActions(in: second).map(\.id) == ["b"])
    #expect(recorder.windowEvents == [.extensionActionsChanged(first), .extensionActionsChanged(second)])
    #expect(engine.setExtensionEnabled("a", enabled: true) == .applied)
    #expect(engine.extensionActions(in: first).map(\.id).sorted() == ["a", "b"])
    #expect(recorder.windowEvents.count == 4)
  }

  // MARK: - Developer mode and Load unpacked

  @Test func developerModeOffLocksTheUnpackedExtensionsItTurnedOff() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("u", "Unpacked", origin: .unpacked),
                                   info("v", "Off already", enabled: false, origin: .unpacked)])
    engine.setExtensionDeveloperModeEnabled(true)
    engine.setExtensionDeveloperModeEnabled(false)
    let u = engine.installedExtensions.first { $0.id == "u" }
    #expect(u?.isEnabled == false && u?.canDisable == false, "listed as off and locked while developer mode is off")
    #expect(engine.installedExtensions.first { $0.id == "v" }?.canDisable == true, "one the user turned off stays theirs")
    #expect(engine.setExtensionEnabled("u", enabled: true) == .refused)
  }

  @Test func developerModeOnTurnsThemBackOnWithOneEvent() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("u", "Unpacked", origin: .unpacked),
                                   info("v", "Off already", enabled: false, origin: .unpacked)])
    engine.setExtensionDeveloperModeEnabled(true)
    engine.setExtensionDeveloperModeEnabled(false)
    let (token, events) = observe(engine)
    engine.setExtensionDeveloperModeEnabled(true)
    let u = engine.installedExtensions.first { $0.id == "u" }
    #expect(u?.isEnabled == true && u?.canDisable == true)
    #expect(engine.installedExtensions.first { $0.id == "v" }?.isEnabled == false, "only the ones it turned off")
    #expect(events() == [.installedExtensionsChanged])
    engine.setExtensionDeveloperModeEnabled(true)
    #expect(events() == [.installedExtensionsChanged], "already on: no event")
    token.cancel()
  }

  @Test func developerModeOffTurnsOffUnpackedExtensions() {
    let engine = InMemoryEngine()
    engine.setInstalledExtensions([info("u", "Unpacked", origin: .unpacked), info("w", "Store")])
    engine.setExtensionDeveloperModeEnabled(true)
    let (token, events) = observe(engine)
    engine.setExtensionDeveloperModeEnabled(false)
    #expect(engine.installedExtensions.map(\.isEnabled) == [false, true])
    #expect(events() == [.installedExtensionsChanged])
    engine.setExtensionDeveloperModeEnabled(false)
    #expect(events() == [.installedExtensionsChanged], "nothing left to turn off, no event")
    token.cancel()
  }

  @Test func loadUnpackedTakesOnlyAnAbsoluteFileURL() async throws {
    let engine = InMemoryEngine()
    engine.setExtensionDeveloperModeEnabled(true)
    let web = try #require(URL(string: "https://example.com/extension"))
    #expect(await engine.loadUnpackedExtension(at: web) == .failed(reason: InMemoryEngine.notAFolderReason))
    #expect(engine.loadedUnpackedFolders.isEmpty)
  }

  @Test func developerModeIsAProfileSwitch() {
    let engine = InMemoryEngine()
    #expect(engine.isExtensionDeveloperModeEnabled == false)
    engine.setExtensionDeveloperModeEnabled(true)
    #expect(engine.isExtensionDeveloperModeEnabled)
  }

  @Test func loadUnpackedNeedsDeveloperMode() async {
    let engine = InMemoryEngine()
    let (token, events) = observe(engine)
    let result = await engine.loadUnpackedExtension(at: URL(fileURLWithPath: "/tmp/Tidy Clips"))
    #expect(result == .developerModeOff)
    #expect(engine.installedExtensions.isEmpty)
    #expect(events().isEmpty)
    #expect(engine.loadedUnpackedFolders.isEmpty)
    token.cancel()
  }

  @Test func loadUnpackedListsTheFolderAsAnUnpackedExtension() async {
    let engine = InMemoryEngine()
    engine.setExtensionDeveloperModeEnabled(true)
    let (token, events) = observe(engine)
    let folder = URL(fileURLWithPath: "/tmp/Tidy Clips", isDirectory: true)
    let result = await engine.loadUnpackedExtension(at: folder)
    guard case .loaded(let id) = result else { Issue.record("not loaded: \(result)"); return }
    let listed = engine.installedExtensions.first { $0.id == id }
    #expect(listed?.name == "Tidy Clips")
    #expect(listed?.origin == .unpacked)
    #expect(events() == [.installedExtensionsChanged])
    #expect(engine.loadedUnpackedFolders == [folder])

    // The same folder again reloads it: one entry, same id.
    let again = await engine.loadUnpackedExtension(at: folder)
    #expect(again == .loaded(extensionID: id))
    #expect(engine.installedExtensions.count == 1)
    token.cancel()
  }

  @Test func loadUnpackedFailsWithTheScriptedReason() async {
    let engine = InMemoryEngine()
    engine.setExtensionDeveloperModeEnabled(true)
    engine.unpackedLoadFailure = "Manifest file is missing or unreadable."
    let (token, events) = observe(engine)
    let result = await engine.loadUnpackedExtension(at: URL(fileURLWithPath: "/tmp/empty"))
    #expect(result == .failed(reason: "Manifest file is missing or unreadable."))
    #expect(engine.installedExtensions.isEmpty)
    #expect(events().isEmpty)
    token.cancel()
  }

  // MARK: - Options pages

  @Test func optionsPagesOpenOnlyForExtensionsThatHaveOne() {
    let engine = InMemoryEngine()
    var withOptions = info("o", "Options")
    withOptions.hasOptionsPage = true
    engine.setInstalledExtensions([withOptions, info("n", "None")])
    engine.openExtensionOptionsPage("o")
    engine.openExtensionOptionsPage("n")
    engine.openExtensionOptionsPage("zz")
    #expect(engine.openedOptionsPages == ["o"])
  }
}

/// An engine that adopts `EngineExtensions` with only the required members: everything else is the default.
@MainActor
private final class ListlessEngine: EngineExtensions {
  func extensionActions(in window: EngineWindowID) -> [ExtensionAction] { [] }
  func runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView) {}
}
