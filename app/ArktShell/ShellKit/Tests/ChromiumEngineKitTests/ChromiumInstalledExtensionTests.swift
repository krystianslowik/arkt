import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Settings > Extensions through the facade (#964, the engine side of #600): the installed list independent of any
/// window, enable and disable with the facade's answer, developer mode, Load unpacked and the options page. Every call
/// goes through `any EngineExtensions`, so a ChromiumEngine that falls back to the protocol's defaults fails here.
@MainActor
struct ChromiumInstalledExtensionTests {
  let facade = ScriptedFacade()
  let alpha = String(repeating: "a", count: 32)
  let beta = String(repeating: "b", count: 32)

  private func makeEngine() -> any EngineExtensions { ChromiumEngine(facade: facade) }

  // MARK: - Listing

  @Test func theListingCarriesEveryFieldInTheFacadesOrder() {
    let icon = Data([0x89, 0x50, 0x4E, 0x47])
    facade.installedList = [
      ScriptedInstalledExtension(extensionID: alpha, name: "Alpha Clips", version: "8.11",
                                 shortDescription: "Clips pages.", iconPNG: icon, isEnabled: true,
                                 mayChangeEnabled: true, source: .webStore, hasOptionsPage: true, canUninstall: true,
                                 canReportAbuse: true),
      ScriptedInstalledExtension(extensionID: beta, name: "Beta Probe", version: "0.9", isEnabled: false,
                                 mayChangeEnabled: false, source: .unpacked, canUninstall: true,
                                 canReportAbuse: false),
    ]
    let engine = makeEngine()
    #expect(engine.installedExtensions == [
      InstalledExtensionInfo(id: alpha, name: "Alpha Clips", version: "8.11", description: "Clips pages.",
                             iconPNG: icon, isEnabled: true, canDisable: true, canUninstall: true, origin: .webStore,
                             hasOptionsPage: true),
      InstalledExtensionInfo(id: beta, name: "Beta Probe", version: "0.9", description: "", iconPNG: nil,
                             isEnabled: false, canDisable: false, canUninstall: true, origin: .unpacked,
                             hasOptionsPage: false),
    ])
  }

  @Test(arguments: [
    (ArktExtensionSource.webStore, ExtensionOrigin.webStore), (.unpacked, .unpacked), (.policy, .policy),
    (.other, .other),
  ])
  func everySourceMapsToItsOrigin(source: ArktExtensionSource, origin: ExtensionOrigin) throws {
    facade.installedList = [ScriptedInstalledExtension(extensionID: alpha, name: "A", version: "1", source: source)]
    let listed = try #require(makeEngine().installedExtensions.first)
    #expect(listed.origin == origin)
  }

  @Test func aPolicyExtensionCanNeitherBeTurnedOffNorRemoved() throws {
    facade.installedList = [ScriptedInstalledExtension(extensionID: alpha, name: "Managed", version: "2",
                                                       mayChangeEnabled: false, source: .policy,
                                                       canUninstall: false, canReportAbuse: false)]
    let listed = try #require(makeEngine().installedExtensions.first)
    #expect(!listed.canDisable && !listed.canUninstall && listed.origin == .policy)
  }

  // MARK: - Enable and disable

  @Test(arguments: [
    (ArktExtensionEnableResult.applied, ExtensionEnableResult.applied), (.unknownExtension, .unknownExtension),
    (.notAllowed, .refused), (.needsPermissionApproval, .refused),
  ])
  func theFacadesAnswerMapsOntoTheResult(answer: ArktExtensionEnableResult, expected: ExtensionEnableResult) {
    facade.enableAnswer = answer
    let engine = makeEngine()
    #expect(engine.setExtensionEnabled(alpha, enabled: false) == expected)
    #expect(facade.enableCalls.map(\.extensionID) == [alpha])
    #expect(facade.enableCalls.map(\.enabled) == [false])
  }

  @Test func disableThenEnableReachTheFacadeInOrder() {
    let engine = makeEngine()
    _ = engine.setExtensionEnabled(alpha, enabled: false)
    _ = engine.setExtensionEnabled(alpha, enabled: true)
    #expect(facade.enableCalls.map(\.enabled) == [false, true])
  }

  // MARK: - Developer mode

  @Test func developerModeIsReadFromAndSetThroughTheFacade() {
    let engine = makeEngine()
    #expect(!engine.isExtensionDeveloperModeEnabled)
    engine.setExtensionDeveloperModeEnabled(true)
    #expect(engine.isExtensionDeveloperModeEnabled)
    engine.setExtensionDeveloperModeEnabled(false)
    #expect(!engine.isExtensionDeveloperModeEnabled)
    #expect(facade.developerModeCalls == [true, false])
  }

  // MARK: - Load unpacked

  @Test func loadUnpackedWhileDeveloperModeIsOffLoadsNothing() async {
    let engine = makeEngine()
    let result = await engine.loadUnpackedExtension(at: URL(fileURLWithPath: "/tmp/arkt-964/site-probe"))
    #expect(result == .developerModeOff)
    #expect(facade.loadUnpackedPaths.isEmpty, "the engine is not asked")
  }

  @Test func loadUnpackedAnswersTheLoadedId() async {
    let engine = makeEngine()
    engine.setExtensionDeveloperModeEnabled(true)
    facade.loadUnpackedAnswer = (beta, nil)
    let result = await engine.loadUnpackedExtension(at: URL(fileURLWithPath: "/tmp/arkt-964/site-probe"))
    #expect(result == .loaded(extensionID: beta))
    #expect(facade.loadUnpackedPaths == ["/tmp/arkt-964/site-probe"])
  }

  @Test func aFailedLoadCarriesTheEnginesSentence() async {
    let engine = makeEngine()
    engine.setExtensionDeveloperModeEnabled(true)
    facade.loadUnpackedAnswer = (nil, "Manifest file is missing or unreadable")
    let result = await engine.loadUnpackedExtension(at: URL(fileURLWithPath: "/tmp/arkt-964/empty"))
    #expect(result == .failed(reason: "Manifest file is missing or unreadable"))
  }

  @Test func developerModeTurnedOffMeanwhileIsDeveloperModeOff() async {
    let engine = makeEngine()
    engine.setExtensionDeveloperModeEnabled(true)
    facade.loadUnpackedAnswer = (nil, "developer mode is off")
    let result = await engine.loadUnpackedExtension(at: URL(fileURLWithPath: "/tmp/arkt-964/site-probe"))
    #expect(result == .developerModeOff)
  }

  // MARK: - Options page

  @Test func theOptionsPageGoesToTheEnginesLastActiveWindow() {
    let engine = makeEngine()
    engine.openExtensionOptionsPage(alpha)
    #expect(facade.optionsPageCalls.map(\.extensionID) == [alpha])
    #expect(facade.optionsPageCalls.map(\.window) == [nil])
  }

  // MARK: - Changes

  @Test func theFacadesChangeArrivesAsInstalledExtensionsChanged() async throws {
    let engine = ChromiumEngine(facade: facade)
    var events: [EngineExtensionEvent] = []
    let observation = engine.observeExtensions { events.append($0) }
    defer { observation.cancel() }

    facade.recordInstalledExtensionsChanged()
    try await ScriptedHarness.delivered(engine)

    #expect(events == [.installedExtensionsChanged])
  }
}
