import AppKit
import EngineAPI
import EngineAPITestSupport
import Testing
@testable import FakeEngineKit

/// FakeEngine's page info (#582): the connection from the scheme and WebKit's secure-content flag, camera and
/// microphone kept per site and applied to WebKit's media capture requests. No page loads, so the required lane stays
/// deterministic.
@MainActor
struct FakeEnginePageInfoTests {
  init() { _ = NSApplication.shared }

  private let tab = TabID()

  private func info(_ address: String, secure: Bool = true, _ table: FakeSitePermissions = FakeSitePermissions())
    -> PageInfo? {
    table.pageInfo(tab: tab, url: URL(string: address), hasOnlySecureContent: secure)
  }

  @Test func connectionFollowsTheSchemeAndSecureContent() {
    #expect(info("https://fieldguide.example/")?.connection == .secure)
    #expect(info("https://fieldguide.example/", secure: false)?.connection == .notSecure)
    #expect(info("http://fieldguide.example/")?.connection == .notSecure)
    #expect(info("file:///tmp/trail-notes.html")?.connection == .localFile)
    #expect(info("file:///tmp/trail-notes.html")?.host == "trail-notes.html")
    #expect(info("about:blank")?.connection == .internalPage)
    #expect(info("data:text/html,x")?.connection == .internalPage)
    #expect(info("https://fieldguide.example/")?.siteData == nil, "WebKit counts site data asynchronously")
    #expect(FakeSitePermissions().pageInfo(tab: tab, url: nil, hasOnlySecureContent: false) == nil)
  }

  @Test func aSiteListsCameraAndMicrophoneAtAsk() throws {
    let page = try #require(info("https://fieldguide.example:8443/trails"))
    #expect(page.origin == "https://fieldguide.example:8443")
    #expect(page.host == "fieldguide.example")
    #expect(page.permissions.map(\.kind) == [.camera, .microphone])
    #expect(page.permissions.allSatisfy { $0.setting == .ask && $0.isDefault })
    #expect(info("file:///tmp/a.html")?.permissions.isEmpty == true)
  }

  @Test func settingsArePerSiteAndResetClearsThem() throws {
    var table = FakeSitePermissions()
    let blocked = table.set(.camera, to: .block, forOrigin: "https://alpha.example")
    let again = table.set(.camera, to: .block, forOrigin: "https://alpha.example")
    let location = table.set(.location, to: .block, forOrigin: "https://alpha.example")
    let microphone = table.set(.microphone, to: .allow, forOrigin: "https://alpha.example")
    #expect(blocked && microphone)
    #expect(!again, "unchanged")
    #expect(!location, "WebKit has no location seam")

    let alpha = try #require(info("https://alpha.example/", table))
    #expect(alpha.permissions.map(\.setting) == [.block, .allow])
    #expect(alpha.permissions.allSatisfy { !$0.isDefault })
    #expect(info("https://beta.example/", table)?.permissions.allSatisfy { $0.isDefault } == true)
    #expect(table.sites().map(\.host) == ["alpha.example"])

    let reset = table.reset(forOrigin: "https://alpha.example")
    let resetAgain = table.reset(forOrigin: "https://alpha.example")
    #expect(reset && !resetAgain)
    #expect(table.sites().isEmpty)
  }

  @Test func mediaCaptureDecisionFollowsTheSetting() {
    var table = FakeSitePermissions()
    let origin = "https://alpha.example"
    #expect(table.mediaDecision(origin: origin, camera: true, microphone: false) == .ask)
    _ = table.set(.camera, to: .allow, forOrigin: origin)
    #expect(table.mediaDecision(origin: origin, camera: true, microphone: false) == .allow)
    #expect(table.mediaDecision(origin: origin, camera: true, microphone: true) == .ask, "the microphone still asks")
    _ = table.set(.microphone, to: .block, forOrigin: origin)
    #expect(table.mediaDecision(origin: origin, camera: true, microphone: true) == .block, "a block wins")
  }

  @Test func engineOffersSiteSettings() throws {
    let engine = FakeEngine()
    let site = try #require(engine.siteSettings)
    let blank = engine.createTab(url: nil, in: engine.createWindow(host: StubWindowHost()))
    #expect(site.pageInfo(of: blank) == nil, "a tab without a page")
    site.setPermission(.camera, to: .block, forOrigin: "https://alpha.example")
    #expect(site.sitesWithPermissions().map(\.origin) == ["https://alpha.example"])
    site.resetPermissions(forOrigin: "https://alpha.example")
    #expect(site.sitesWithPermissions().isEmpty)
    engine.closeTab(blank)
  }
}
