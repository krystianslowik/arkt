import AppKit
import ArktEngineABI
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import ChromiumEngineKit

/// Page info and per-site permissions (#583, the engine side of #582), mapped by ChromiumEngine from the facade's
/// page info values and `PageInfoChanged` events.
@MainActor
struct ChromiumPageInfoTests {
  let facade = ScriptedFacade()

  private func makeEngine(_ url: String = "https://fieldguide.example/trail") -> (ChromiumEngine, TabID, ScriptedTab) {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let id = engine.createTab(url: URL(string: url)!, in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    let tab = engine.handle(of: id) as! ScriptedTab
    tab.finishLoad()
    facade.flush()
    return (engine, id, tab)
  }

  @Test func theEngineHasSiteSettings() {
    let (engine, _, _) = makeEngine()
    #expect(engine.siteSettings === engine)
  }

  @Test func pageInfoCarriesTheFacadeValues() throws {
    let (engine, id, _) = makeEngine()
    let validUntil = Date(timeIntervalSince1970: 1_900_000_000)
    facade.siteSettings.certificate = ("fieldguide.example", "Example Trust", validUntil)
    facade.siteSettings.siteData["https://fieldguide.example"] = (cookies: 3, bytes: 4096)
    facade.siteSettings.exceptions["https://fieldguide.example"] = [.popups: .allow, .usbDevices: .block]

    let info = try #require(engine.pageInfo(of: id))

    #expect(info.tab == id)
    #expect(info.origin == "https://fieldguide.example" && info.host == "fieldguide.example")
    #expect(info.connection == .secure)
    #expect(info.certificate == CertificateSummary(issuedTo: "fieldguide.example", issuedBy: "Example Trust",
                                                   validUntil: validUntil))
    #expect(info.siteData == SiteData(cookies: 3, bytes: 4096))
    #expect(info.permissions.map(\.kind) == [.location, .camera, .microphone, .notifications, .popups, .usbDevices])
    let popups = try #require(info.permissions.first { $0.kind == .popups })
    #expect(popups == SitePermission(kind: .popups, title: "Pop-ups and redirects", setting: .allow, isDefault: false,
                                     options: [.allow, .block]))
    let location = try #require(info.permissions.first { $0.kind == .location })
    #expect(location.setting == .ask && location.isDefault && location.options == [.allow, .ask, .block])
    #expect(info.permissions.first { $0.kind == .usbDevices }?.options == [.ask, .block])
  }

  @Test func siteDataIsNilWhileTheFacadeCounts() throws {
    let (engine, id, _) = makeEngine()
    #expect(try #require(engine.pageInfo(of: id)).siteData == nil)
  }

  @Test(arguments: [(ArktPageConnection.secure, PageConnection.secure), (.notSecure, .notSecure),
                    (.notFullySecure, .notFullySecure), (.certificateError, .certificateError),
                    (.flagged, .flagged)])
  func everyConnectionMaps(_ facadeConnection: ArktPageConnection, _ connection: PageConnection) throws {
    let (engine, id, tab) = makeEngine()
    facade.siteSettings.connections[ObjectIdentifier(tab)] = facadeConnection
    #expect(try #require(engine.pageInfo(of: id)).connection == connection)
  }

  @Test func aLocalFileAndAnInternalPageHaveNoSiteSettings() throws {
    let (engine, file, _) = makeEngine("file:///private/tmp/Notes%20Draft.html")
    let local = try #require(engine.pageInfo(of: file))
    #expect(local.connection == .localFile && local.origin == "file://" && local.host == "Notes Draft.html")
    #expect(!local.hasSiteSettings && local.permissions.isEmpty && local.siteData == nil)

    let (other, settings, _) = makeEngine("chrome://settings/")
    let page = try #require(other.pageInfo(of: settings))
    #expect(page.connection == .internalPage && !page.hasSiteSettings && page.permissions.isEmpty)
  }

  @Test func anUnknownOrClosedTabHasNoPageInfo() async throws {
    let (engine, id, _) = makeEngine()
    #expect(engine.pageInfo(of: TabID()) == nil)
    engine.closeTab(id)
    facade.flush()
    #expect(engine.pageInfo(of: id) == nil)
  }

  @Test func everyPermissionKindRoundTrips() {
    for kind in SitePermissionKind.allCases {
      #expect(SitePermissionKind(facade: kind.facade) == kind)
    }
    #expect(Set(SitePermissionKind.allCases.map(\.facade.rawValue)) == Set(0...21))
    for setting in PermissionSetting.allCases {
      #expect(PermissionSetting(facade: setting.facade) == setting)
    }
  }

  @Test func aKindTheBuildDoesNotKnowIsLeftOut() throws {
    let (engine, id, tab) = makeEngine()
    let info = try #require(tab.pageInfo as? ScriptedPageInfo)
    info.permissions.append(ScriptedSitePermission(kind: ArktSitePermissionKind(rawValue: 99)!, title: "New",
                                                   setting: .ask, isDefault: true, options: [.ask]))
    let mapped = SitePermission(facade: info.permissions.last!)
    #expect(mapped == nil)
    #expect(try #require(engine.pageInfo(of: id)).permissions.count == 4)
  }

  @Test func setPermissionChangesTheSiteAndIsAnnouncedOnItsTabs() throws {
    let (engine, id, tab) = makeEngine()
    let sameSite = engine.createTab(url: URL(string: "https://fieldguide.example/maps")!,
                                    in: try #require(engine.snapshot(of: id)?.window))
    let otherSite = engine.createTab(url: URL(string: "https://other.example/")!,
                                     in: try #require(engine.snapshot(of: id)?.window))
    facade.flush()
    for other in [sameSite, otherSite] { (engine.handle(of: other) as! ScriptedTab).finishLoad() }
    facade.flush()
    let recorder = EventRecorder(engine)

    engine.setPermission(.camera, to: .block, forOrigin: "https://fieldguide.example", from: id)
    facade.flush()

    let camera = engine.pageInfo(of: id)?.permissions.first { $0.kind == .camera }
    #expect(camera?.setting == .block && camera?.isDefault == false)
    #expect(recorder.events.filter { $0 == .pageInfoChanged(id) }.count == 1)
    #expect(recorder.events.contains(.pageInfoChanged(sameSite)))
    #expect(!recorder.events.contains(.pageInfoChanged(otherSite)))
    #expect(facade.siteSettings.pendingReloads.contains(ObjectIdentifier(tab)))
  }

  @Test func resetPermissionsRestoresTheDefaults() throws {
    let (engine, id, _) = makeEngine()
    facade.siteSettings.exceptions["https://fieldguide.example"] = [.location: .allow, .popups: .allow]
    let recorder = EventRecorder(engine)

    engine.resetPermissions(forOrigin: "https://fieldguide.example", from: id)
    facade.flush()

    let info = try #require(engine.pageInfo(of: id))
    #expect(info.permissions.allSatisfy(\.isDefault) && info.permissions.count == 4)
    #expect(recorder.events == [.pageInfoChanged(id)])
    #expect(engine.sitesWithPermissions().isEmpty)
  }

  @Test func openingThePanelTellsTheFacade() {
    let (engine, id, tab) = makeEngine()
    engine.pageInfoDidOpen(tab: id)
    #expect(facade.siteSettings.opened == [tab.sessionId])
    engine.pageInfoDidClose(tab: id)
    #expect(facade.siteSettings.opened.isEmpty, "the close ends it")
  }

  @Test func closingThePanelAfterAChangeRaisesTheReloadInfobarOnce() throws {
    let (engine, id, _) = makeEngine()
    let recorder = EventRecorder(engine)
    engine.setPermission(.location, to: .allow, forOrigin: "https://fieldguide.example", from: id)
    engine.pageInfoDidClose(tab: id)
    engine.pageInfoDidClose(tab: id)
    facade.flush()

    let lists = recorder.events.compactMap { if case .infobarsChanged(_, let list) = $0 { list } else { nil } }
    #expect(lists.count == 1)
    let reload = try #require(lists.last?.first)
    #expect(reload.kind == .reload && reload.ok?.title == "Reload")
    #expect(facade.siteSettings.closes == 2)
  }

  @Test func aNewPageEndsThePanelsChangesSoACloseRaisesNoInfobar() throws {
    let (engine, id, tab) = makeEngine()
    let recorder = EventRecorder(engine)
    engine.setPermission(.location, to: .allow, forOrigin: "https://fieldguide.example", from: id)
    engine.navigate(id, to: URL(string: "https://fieldguide.example/maps")!)  // same site, a new page
    facade.flush()
    tab.finishLoad()
    engine.pageInfoDidClose(tab: id)
    facade.flush()

    #expect(!recorder.events.contains { if case .infobarsChanged = $0 { true } else { false } })
    #expect(engine.pageInfo(of: id)?.permissions.first { $0.kind == .location }?.setting == .allow)
  }

  @Test func theConnectionIsSeededWhenTheTabIsBound() throws {
    facade.holdsBatches = true
    let engine = ChromiumEngine(facade: facade)
    let id = engine.createTab(url: URL(string: "https://fieldguide.example/trail")!,
                              in: engine.createWindow(host: StubWindowHost()))
    facade.flush()
    let tab = try #require(engine.handle(of: id) as? ScriptedTab)
    tab.finishLoad()
    facade.flush()
    let recorder = EventRecorder(engine)

    // Bound on the initial empty document (a page of the browser itself), so the first report, at the commit, is a
    // change and is announced; without the seed it would only set the baseline.
    tab.securityStateChanged()
    tab.securityStateChanged()                 // the same connection again: nothing
    facade.siteSettings.connections[ObjectIdentifier(tab)] = .notFullySecure
    tab.securityStateChanged()                 // mixed content arrived: once
    facade.flush()

    #expect(recorder.events == [.pageInfoChanged(id), .pageInfoChanged(id)])
    #expect(engine.pageInfo(of: id)?.connection == .notFullySecure)
  }

  @Test func openSiteSettingsNamesTheSiteAndTheTab() {
    let (engine, id, tab) = makeEngine()
    engine.openSiteSettings(forOrigin: "https://fieldguide.example", from: id)
    #expect(facade.siteSettings.openedSiteSettings.map(\.origin) == ["https://fieldguide.example"])
    #expect(facade.siteSettings.openedSiteSettings.map(\.tab) == [tab.sessionId])
  }

  @Test func callsForAnUnknownTabDoNothing() {
    let (engine, _, _) = makeEngine()
    let stranger = TabID()
    engine.setPermission(.camera, to: .block, forOrigin: "https://fieldguide.example", from: stranger)
    engine.resetPermissions(forOrigin: "https://fieldguide.example", from: stranger)
    engine.pageInfoDidOpen(tab: stranger)
    engine.pageInfoDidClose(tab: stranger)
    engine.openSiteSettings(forOrigin: "https://fieldguide.example", from: stranger)
    #expect(facade.siteSettings.exceptions.isEmpty && facade.siteSettings.closes == 0)
    #expect(facade.siteSettings.opened.isEmpty)
    #expect(facade.siteSettings.openedSiteSettings.isEmpty)
  }

  @Test func sitesWithPermissionsCarriesEverySite() {
    let (engine, _, _) = makeEngine()
    facade.siteSettings.exceptions = ["https://b.example": [.camera: .allow],
                                      "https://a.example": [.notifications: .block, .sound: .block]]

    let sites = engine.sitesWithPermissions()

    #expect(sites.map(\.origin) == ["https://a.example", "https://b.example"])
    #expect(sites.map(\.host) == ["a.example", "b.example"])
    #expect(sites.first?.permissions.map(\.kind) == [.notifications, .sound])
    #expect(sites.first?.permissions.allSatisfy { !$0.isDefault } == true)
  }

  @Test func aFacadeAnnouncementIsReported() {
    let (engine, id, tab) = makeEngine()
    let recorder = EventRecorder(engine)
    tab.pageInfoUpdated()
    facade.flush()
    #expect(recorder.events == [.pageInfoChanged(id)])
  }

  @Test func anAnnouncementForATabThatClosedIsDropped() {
    let (engine, id, tab) = makeEngine()
    let recorder = EventRecorder(engine)
    engine.closeTab(id)
    tab.pageInfoUpdated()
    facade.flush()
    #expect(!recorder.events.contains(.pageInfoChanged(id)))
  }
}
