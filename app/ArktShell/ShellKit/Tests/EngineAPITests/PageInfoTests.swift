import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// Page info and per-site permissions (#582, part of #122): InMemoryEngine's page info for each kind of page, the
/// per-site calls, the reload infobar a change raises, and Settings' per-site list (#133).
@MainActor
struct PageInfoTests {
  private func tab(_ engine: InMemoryEngine, _ address: String) throws -> TabID {
    let url = try #require(URL(string: address))
    let tab = engine.createTab(url: url, in: engine.createWindow(host: StubWindowHost()))
    engine.finishLoad(tab, title: "Page")
    return tab
  }

  private func settings(_ engine: InMemoryEngine) throws -> any EngineSiteSettings {
    try #require(engine.siteSettings)
  }

  private func reloadInfobars(_ recorder: EventRecorder, _ tab: TabID) -> [[Infobar]] {
    recorder.events(for: tab).compactMap {
      if case .infobarsChanged(_, let list) = $0 { list.filter { $0.kind == .reload } } else { nil }
    }
  }

  // MARK: What each page reports

  @Test func secureSiteReportsHostConnectionAndTheCommonPermissionsAtTheirDefaults() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://fieldguide.example/trails")
    let info = try #require(try settings(engine).pageInfo(of: id))

    #expect(info.tab == id)
    #expect(info.origin == "https://fieldguide.example")
    #expect(info.host == "fieldguide.example")
    #expect(info.connection == .secure)
    #expect(info.hasSiteSettings)
    #expect(info.siteData == SiteData.none)
    #expect(info.permissions.map(\.kind) == [.location, .camera, .microphone, .notifications])
    #expect(info.permissions.map(\.title) == ["Location", "Camera", "Microphone", "Notifications"])
    #expect(info.permissions.allSatisfy { $0.setting == .ask && $0.isDefault && $0.options == [.allow, .ask, .block] })
  }

  @Test func httpPageIsNotSecure() throws {
    let engine = InMemoryEngine()
    let info = try #require(try settings(engine).pageInfo(of: tab(engine, "http://old-mirror.fieldguide.example/")))
    #expect(info.connection == .notSecure)
    #expect(info.certificate == nil)
    #expect(info.hasSiteSettings)
  }

  @Test func localFileHasNoSiteSettings() throws {
    let engine = InMemoryEngine()
    let info = try #require(try settings(engine).pageInfo(of: tab(engine, "file:///tmp/trail-notes.html")))
    #expect(info.connection == .localFile)
    #expect(info.host == "trail-notes.html")
    #expect(info.permissions.isEmpty)
    #expect(info.siteData == nil)
    #expect(!info.hasSiteSettings)
  }

  @Test(arguments: ["chrome://settings/", "about:blank", "arkt://newtab/"])
  func internalPageHasNoSiteSettings(_ address: String) throws {
    let engine = InMemoryEngine()
    let info = try #require(try settings(engine).pageInfo(of: tab(engine, address)))
    #expect(info.connection == .internalPage)
    #expect(info.permissions.isEmpty)
    #expect(!info.hasSiteSettings)
  }

  @Test func idnHostKeepsTheEngineForm() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://xn--bergfhrer-verband-kartenarchiv-q9b.example/")
    let info = try #require(try settings(engine).pageInfo(of: id))
    #expect(info.host == "xn--bergfhrer-verband-kartenarchiv-q9b.example")
  }

  @Test func unknownClosedOrBlankTabHasNoPageInfo() throws {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let blank = engine.createTab(url: nil, in: window)
    let closed = try tab(engine, "https://fieldguide.example/")
    engine.closeTab(closed)
    #expect(try settings(engine).pageInfo(of: TabID()) == nil)
    #expect(try settings(engine).pageInfo(of: blank) == nil)
    #expect(try settings(engine).pageInfo(of: closed) == nil)
  }

  @Test func connectionCertificateAndSiteDataComeFromTheDrivers() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://fieldguide.example/")
    let certificate = CertificateSummary(issuedTo: "fieldguide.example", issuedBy: "Example Trust CA")
    engine.setConnection(id, .dangerous, certificate: certificate)
    engine.setSiteData(SiteData(cookies: 1_284, bytes: 312_000_000), forOrigin: "https://fieldguide.example")
    let info = try #require(try settings(engine).pageInfo(of: id))
    #expect(info.connection == .dangerous)
    #expect(info.certificate == certificate)
    #expect(info.siteData == SiteData(cookies: 1_284, bytes: 312_000_000))
  }

  @Test func tenPermissionsAreListedChangedOnesAfterTheCommonOnes() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://fieldguide.example/")
    let site = try settings(engine)
    let changes: [(SitePermissionKind, PermissionSetting)] = [
      (.popups, .allow), (.sound, .block), (.clipboard, .allow), (.midiDevices, .allow), (.automaticDownloads, .block),
      (.javascript, .block),
    ]
    for (kind, setting) in changes { site.setPermission(kind, to: setting, forOrigin: "https://fieldguide.example") }
    let info = try #require(site.pageInfo(of: id))
    #expect(info.permissions.count == 10)
    #expect(info.permissions.map(\.kind) == [.location, .camera, .microphone, .notifications, .popups, .sound,
                                              .javascript, .automaticDownloads, .clipboard, .midiDevices])
    #expect(info.permissions.dropFirst(4).allSatisfy { !$0.isDefault })
    #expect(info.permissions.first { $0.kind == .popups }?.options == [.allow, .block], "pop-ups have no Ask")
  }

  // MARK: Per-site calls

  @Test func setPermissionChangesTheSiteOnlyAndIsReadBackAtOnce() throws {
    let engine = InMemoryEngine()
    let alpha = try tab(engine, "https://alpha.example/a")
    let beta = try tab(engine, "https://beta.example/b")
    let site = try settings(engine)

    site.setPermission(.camera, to: .block, forOrigin: "https://alpha.example")

    let camera = try #require(site.pageInfo(of: alpha)?.permissions.first { $0.kind == .camera })
    #expect(camera.setting == .block && !camera.isDefault)
    #expect(site.pageInfo(of: beta)?.permissions.first { $0.kind == .camera }?.isDefault == true)
  }

  @Test func settingTheDefaultValueAgainClearsTheException() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://alpha.example/")
    let site = try settings(engine)
    site.setPermission(.location, to: .allow, forOrigin: "https://alpha.example")
    site.setPermission(.location, to: .ask, forOrigin: "https://alpha.example")
    let location = try #require(site.pageInfo(of: id)?.permissions.first { $0.kind == .location })
    #expect(location.setting == .ask && location.isDefault)
    #expect(site.sitesWithPermissions().isEmpty)
  }

  @Test func aChangeRaisesOneReloadInfobarOnEveryTabOfTheSite() throws {
    let engine = InMemoryEngine()
    let first = try tab(engine, "https://alpha.example/a")
    let second = try tab(engine, "https://alpha.example/b")
    let other = try tab(engine, "https://beta.example/")
    let recorder = EventRecorder(engine)
    let site = try settings(engine)

    site.setPermission(.camera, to: .block, forOrigin: "https://alpha.example")
    site.setPermission(.microphone, to: .allow, forOrigin: "https://alpha.example")

    for id in [first, second] {
      let lists = reloadInfobars(recorder, id)
      #expect(lists.count == 1, "one infobarsChanged for \(id)")
      let bar = try #require(lists.first?.first)
      #expect(bar.kind == .reload)
      #expect(bar.message == "To apply your updated settings to this site, reload this page")
      #expect(bar.ok?.title == "Reload")
    }
    #expect(reloadInfobars(recorder, other).isEmpty)
  }

  @Test func reloadOnTheReloadInfobarReloadsThePage() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://alpha.example/")
    try settings(engine).setPermission(.camera, to: .block, forOrigin: "https://alpha.example")
    let bar = try #require(engine.infobars(of: id).first { $0.kind == .reload })
    let recorder = EventRecorder(engine)

    engine.act(on: bar.id, action: .ok)

    #expect(recorder.events(for: id) == [.infobarsChanged(id, []), .loadingChanged(id, isLoading: true)])
  }

  @Test func unchangedOrUnofferedSettingRaisesNothing() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://alpha.example/")
    let recorder = EventRecorder(engine)
    let site = try settings(engine)

    site.setPermission(.location, to: .ask, forOrigin: "https://alpha.example")       // already the default
    site.setPermission(.popups, to: .ask, forOrigin: "https://alpha.example")         // not offered

    #expect(recorder.events(for: id).isEmpty)
    #expect(site.sitesWithPermissions().isEmpty)
  }

  @Test func resetPutsEveryPermissionBackAndKeepsSiteData() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://alpha.example/")
    let site = try settings(engine)
    engine.setSiteData(SiteData(cookies: 14, bytes: 2_400_000), forOrigin: "https://alpha.example")
    site.setPermission(.camera, to: .block, forOrigin: "https://alpha.example")
    site.setPermission(.popups, to: .allow, forOrigin: "https://alpha.example")
    engine.act(on: try #require(engine.infobars(of: id).first?.id), action: .close)
    let recorder = EventRecorder(engine)

    site.resetPermissions(forOrigin: "https://alpha.example")
    site.resetPermissions(forOrigin: "https://alpha.example")

    let info = try #require(site.pageInfo(of: id))
    #expect(info.permissions.map(\.kind) == [.location, .camera, .microphone, .notifications])
    #expect(info.permissions.allSatisfy { $0.isDefault })
    #expect(info.siteData == SiteData(cookies: 14, bytes: 2_400_000))
    #expect(reloadInfobars(recorder, id).count == 1, "the first reset raises the reload infobar, the second nothing")
  }

  @Test func sitesWithPermissionsListsChangedSitesByHost() throws {
    let engine = InMemoryEngine()
    let site = try settings(engine)
    site.setPermission(.notifications, to: .allow, forOrigin: "https://zeta.example")
    site.setPermission(.camera, to: .block, forOrigin: "https://alpha.example")
    site.setPermission(.sound, to: .block, forOrigin: "https://alpha.example")

    let list = site.sitesWithPermissions()
    #expect(list.map(\.host) == ["alpha.example", "zeta.example"])
    #expect(list.first?.permissions.map(\.kind) == [.camera, .sound])
    #expect(list.first?.permissions.allSatisfy { !$0.isDefault } == true)
  }

  @Test func openSiteSettingsIsRecorded() throws {
    let engine = InMemoryEngine()
    let id = try tab(engine, "https://alpha.example/")
    try settings(engine).openSiteSettings(forOrigin: "https://alpha.example", from: id)
    #expect(engine.openedSiteSettings.count == 1)
    #expect(engine.openedSiteSettings.first?.origin == "https://alpha.example")
    #expect(engine.openedSiteSettings.first?.tab == id)
  }
}

/// Rule 26 of the shared contract on InMemoryEngine.
@MainActor
struct InMemoryPageInfoContractTests {
  let harness = EngineHarness.inMemory()

  @Test func pageInfoNamesTheSiteItShows() async throws {
    try await EngineContract.pageInfoNamesTheSiteItShows(harness)
  }
  @Test func permissionChangeIsReadBackAndResetRestoresTheDefault() async throws {
    try await EngineContract.permissionChangeIsReadBackAndResetRestoresTheDefault(harness)
  }
  @Test func permissionChangeRaisesTheReloadInfobarOnce() async throws {
    try await EngineContract.permissionChangeRaisesTheReloadInfobarOnce(harness)
  }
}
