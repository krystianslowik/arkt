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

  // MARK: - Developer mode and Load unpacked

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
