import Foundation
import Testing
import EngineAPI
@testable import ShellUI

/// The page info panel's content as data (#582, design/extensions `surf-pageinfo`, laid out as the Site Control
/// Center direction A it grows into): which state a page gets, the words, the glyphs and the panel's size.
struct PageInfoModelTests {
  private let tab = TabID()

  private func info(_ connection: PageConnection, host: String = "fieldguide.example",
                    siteData: SiteData? = SiteData(cookies: 14, bytes: 2_400_000),
                    permissions: [SitePermission]? = nil) -> PageInfo {
    PageInfo(tab: tab, origin: "https://\(host)", host: host, connection: connection, siteData: siteData,
             permissions: permissions ?? [
               SitePermission(kind: .location, title: "Location", setting: .ask, isDefault: true),
               SitePermission(kind: .camera, title: "Camera", setting: .block, isDefault: false),
               SitePermission(kind: .notifications, title: "Notifications", setting: .allow, isDefault: false),
             ])
  }

  // MARK: States

  @Test func secureSiteShowsTheHostTheConnectionAndEveryPermission() throws {
    let model = try #require(PageInfoModel(info(.secure), locale: Locale(identifier: "en_US")))
    #expect(model.host == "fieldguide.example")
    #expect(model.connectionText == "Connection is secure")
    #expect(model.connectionSymbol == "lock")
    #expect(model.state == .site)
    #expect(model.rows.map(\.title) == ["Location", "Camera", "Notifications"])
    #expect(model.rows.map(\.setting) == [.ask, .block, .allow])
    #expect(model.siteDataText == "14 cookies, 2.4 MB")
    #expect(model.canResetPermissions, "two permissions are not at their default")
    #expect(model.accessibilityLabel == "Site controls for fieldguide.example")
  }

  @Test func insecureAndDangerousSitesSayItInPrimaryWordsWithAWarningGlyph() throws {
    let insecure = try #require(PageInfoModel(info(.notSecure)))
    #expect(insecure.connectionText == "Not secure: this site has no encrypted connection")
    #expect(insecure.connectionSymbol == "exclamationmark.triangle")
    #expect(insecure.connectionIsWarning)
    let dangerous = try #require(PageInfoModel(info(.dangerous)))
    #expect(dangerous.connectionText == "Not secure: this site's connection is not private")
    #expect(dangerous.connectionIsWarning)
    #expect(try !#require(PageInfoModel(info(.secure))).connectionIsWarning)
  }

  @Test func localFileShowsOnlyTheNote() throws {
    let file = PageInfo(tab: tab, origin: "file://", host: "trail-notes.html", connection: .localFile)
    let model = try #require(PageInfoModel(file))
    #expect(model.state == .localFile)
    #expect(model.host == "trail-notes.html")
    #expect(model.connectionText == "Local file on this Mac")
    #expect(model.connectionSymbol == "doc")
    #expect(model.note == "Local files have no site settings. Permissions apply to this file only while it is open.")
    #expect(model.rows.isEmpty)
    #expect(!model.canResetPermissions)
  }

  @Test func internalPageOpensNothing() {
    let page = PageInfo(tab: tab, origin: "chrome://settings", host: "chrome://settings/", connection: .internalPage)
    #expect(PageInfoModel(page) == nil)
  }

  @Test func resetIsOffWhileEveryPermissionIsAtItsDefault() throws {
    let model = try #require(PageInfoModel(info(.secure, permissions: [
      SitePermission(kind: .location, title: "Location", setting: .ask, isDefault: true),
    ])))
    #expect(!model.canResetPermissions)
  }

  // MARK: Words

  @Test(arguments: [
    (SiteData(cookies: 0, bytes: 0), "None"),
    (SiteData(cookies: 1, bytes: 0), "1 cookie"),
    (SiteData(cookies: 0, bytes: 2_400_000), "2.4 MB"),
    (SiteData(cookies: 1_284, bytes: 312_000_000), "1,284 cookies, 312 MB"),
  ])
  func siteDataSummary(_ data: SiteData, _ text: String) throws {
    #expect(PageInfoModel.siteDataText(data, locale: Locale(identifier: "en_US")) == text)
  }

  @Test func siteDataStillCountingShowsNothing() throws {
    #expect(try #require(PageInfoModel(info(.secure, siteData: nil))).siteDataText == "")
  }

  @Test func popUpOffersTheEngineOptionsInItsOrder() {
    let popups = SitePermission(kind: .popups, title: "Pop-ups and redirects", setting: .block, isDefault: true,
                                options: [.allow, .block])
    let row = PageInfoModel.Row(popups)
    #expect(row.options.map(\.title) == ["Allow", "Block"])
    #expect(row.accessibilityLabel == "Pop-ups and redirects")
    #expect(PermissionSetting.allCases.map(PageInfoModel.title(of:)) == ["Allow", "Ask", "Block"])
  }

  @Test func everyPermissionHasAGlyph() {
    for kind in SitePermissionKind.allCases { #expect(!PageInfoModel.symbol(for: kind).isEmpty) }
    #expect(PageInfoModel.symbol(for: .location) == "location")
    #expect(PageInfoModel.symbol(for: .camera) == "video")
    #expect(PageInfoModel.symbol(for: .microphone) == "mic")
    #expect(PageInfoModel.symbol(for: .notifications) == "bell")
  }

  // MARK: Size

  @Test func widthIsTheDesignsAndNarrowsInASmallWindow() {
    #expect(PageInfoMetrics.width == 330)
    #expect(PageInfoModel.panelWidth(available: 1200) == 330)
    #expect(PageInfoModel.panelWidth(available: 300) == 300)
    #expect(PageInfoModel.panelWidth(available: 100) == 260, "never under 260")
  }

  @Test func heightFollowsTheContentUpTo552ThenScrolls() {
    #expect(PageInfoModel.panelHeight(content: 300, available: 800) == .init(height: 300, scrolls: false))
    #expect(PageInfoModel.panelHeight(content: 700, available: 800) == .init(height: 552, scrolls: true))
    #expect(PageInfoModel.panelHeight(content: 500, available: 400) == .init(height: 400, scrolls: true))
    #expect(PageInfoModel.panelHeight(content: 500, available: 50).height == 120, "never under 120")
  }

  @Test func tenPermissionsFitAndSixteenOverflowTheCap() throws {
    func model(_ count: Int) throws -> PageInfoModel {
      try #require(PageInfoModel(info(.secure, permissions: SitePermissionKind.allCases.prefix(count).map {
        SitePermission(kind: $0, title: "\($0)", setting: .ask, isDefault: true)
      })))
    }
    #expect(try model(10).contentHeight <= PageInfoMetrics.maxHeight)
    #expect(try model(16).contentHeight > PageInfoMetrics.maxHeight)
    let kinds = Array(SitePermissionKind.allCases.prefix(10))
    let model = try #require(PageInfoModel(info(.secure, permissions: kinds.map {
      SitePermission(kind: $0, title: "\($0)", setting: .ask, isDefault: true)
    })))
    #expect(model.rows.count == 10)
  }
}
