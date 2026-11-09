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

  /// The panel's host reads as the address bar's (#697): a real internationalized host in Unicode, a look-alike in
  /// its encoded form, whichever form the engine gave.
  @Test func theHostFollowsTheSharedDisplayRule() throws {
    #expect(try #require(PageInfoModel(info(.secure, host: "xn--mnchen-3ya.de"))).host == "m\u{00FC}nchen.de")
    #expect(try #require(PageInfoModel(info(.secure, host: "xn--80ak6aa92e.com"))).host == "xn--80ak6aa92e.com")
    #expect(try #require(PageInfoModel(info(.secure, host: "\u{0430}pple.com"))).host == "xn--pple-43d.com")
    let model = try #require(PageInfoModel(info(.secure, host: "xn--mnchen-3ya.de")))
    #expect(model.accessibilityLabel == "Site controls for m\u{00FC}nchen.de")
    #expect(model.origin == "https://xn--mnchen-3ya.de", "the per-site calls keep the engine's origin")
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

  @Test(arguments: [
    (PageConnection.secure, "Connection is secure", "lock", nil, false),
    (.notSecure, "Not secure: this site has no encrypted connection", "exclamationmark.triangle", "Not secure", true),
    (.notFullySecure, "Not fully secure: parts of this page are not encrypted", "exclamationmark.triangle",
     "Not fully secure", true),
    (.certificateError, "Not secure: this site's connection is not private", "exclamationmark.triangle", "Not secure",
     true),
    (.flagged, "Dangerous: this site may try to steal your information", "exclamationmark.triangle", "Dangerous", true),
  ])
  func connectionWordsGlyphAndSpokenState(_ connection: PageConnection, _ text: String, _ symbol: String,
                                          _ spoken: String?, _ warning: Bool) throws {
    let model = try #require(PageInfoModel(info(connection)))
    #expect(model.connectionText == text)
    #expect(model.connectionSymbol == symbol)
    #expect(model.siteDescription == spoken)
    #expect(model.connectionIsWarning == warning, "a warning keeps primary text with a warning glyph, never red")
    #expect(PageInfoModel.pill(for: info(connection))?.symbol == symbol)
    #expect(PageInfoModel.pill(for: info(connection))?.description == spoken)
  }

  @Test func privateWindowIsReadOnly() throws {
    let model = try #require(PageInfoModel(info(.secure), isReadOnly: true))
    #expect(model.isReadOnly)
    #expect(!model.canResetPermissions, "nothing can be reset")
    #expect(model.readOnlyNote == "Site settings can't be changed in this window.")
    #expect(try #require(PageInfoModel(info(.secure))).readOnlyNote == nil)
    #expect(model.contentHeight == (try #require(PageInfoModel(info(.secure)))).contentHeight
            + PageInfoMetrics.readOnlyNoteHeight)
  }

  // MARK: Turned off in macOS (#786)

  /// macOS denied Arkt location access: the location row says so under its title, keeps the stored setting in its
  /// pop-up, and VoiceOver hears both. The other rows are as they were.
  @Test func locationDeniedInMacOSAddsTheNoteToItsRowOnly() throws {
    let model = try #require(PageInfoModel(info(.secure), deniedInMacOS: [.location: .appAccess]))
    let location = try #require(model.rows.first { $0.kind == .location })
    #expect(location.systemNote == "Turned off in macOS")
    #expect(location.setting == .ask, "the pop-up keeps the stored setting")
    #expect(location.options.map(\.setting) == [.allow, .ask, .block], "the setting can still be changed")
    #expect(location.accessibilityLabel == "Location, turned off in macOS")
    #expect(location.height == PageInfoMetrics.notedRowHeight)
    for row in model.rows where row.kind != .location {
      #expect(row.systemNote == nil)
      #expect(row.accessibilityLabel == row.title)
      #expect(row.height == PageInfoMetrics.rowHeight)
    }
    let plain = try #require(PageInfoModel(info(.secure)))
    #expect(model.contentHeight == plain.contentHeight + PageInfoMetrics.notedRowHeight - PageInfoMetrics.rowHeight)
  }

  /// The note says what macOS does, so it shows whatever the site's stored setting is.
  @Test(arguments: PermissionSetting.allCases)
  func theNoteShowsWhateverTheStoredSetting(_ setting: PermissionSetting) throws {
    let permissions = [SitePermission(kind: .location, title: "Location", setting: setting, isDefault: false)]
    let model = try #require(PageInfoModel(info(.secure, permissions: permissions),
                                           deniedInMacOS: [.location: .appAccess]))
    #expect(model.rows.first?.systemNote == "Turned off in macOS")
    #expect(model.rows.first?.setting == setting)
  }

  /// While macOS has not decided (or allows access), nothing is added: macOS still asks on first use.
  @Test func noNoteUntilMacOSDenies() throws {
    let model = try #require(PageInfoModel(info(.secure)))
    #expect(model.rows.allSatisfy { $0.systemNote == nil })
    #expect(try #require(PageInfoModel(info(.secure), deniedInMacOS: [:])).rows.allSatisfy { $0.systemNote == nil })
  }

  // MARK: Location Services off for the whole Mac (#856)

  /// Location Services is off for the whole Mac: the location row says so in words that differ from Arkt's own
  /// permission being off, keeps the stored setting, and VoiceOver keeps "Location Services" capitalized.
  @Test func locationServicesOffAddsItsOwnNoteToTheLocationRow() throws {
    let model = try #require(PageInfoModel(info(.secure), deniedInMacOS: [.location: .locationServices]))
    let location = try #require(model.rows.first { $0.kind == .location })
    #expect(location.systemNote == "Location Services off")
    #expect(location.systemNote != SystemPermissionBlock.appAccess.note, "the two states read differently")
    #expect(location.setting == .ask, "the pop-up keeps the stored setting")
    #expect(location.options.map(\.setting) == [.allow, .ask, .block], "the setting can still be changed")
    #expect(location.accessibilityLabel == "Location, Location Services off")
    #expect(location.height == PageInfoMetrics.notedRowHeight)
    #expect(model.rows.filter { $0.kind != .location }.allSatisfy { $0.systemNote == nil })
  }

  /// Location Services off wins over Arkt's own state: whatever the app's status, no site gets the location while the
  /// whole Mac has it off.
  @Test func locationServicesOffWinsOverTheAppsOwnState() {
    for access in [SystemPermissionAccess.notDetermined, .allowed, .denied, .restricted] {
      #expect(SystemPermissions.blocks(location: access, locationServicesEnabled: false)
                == [.location: .locationServices], "\(access)")
    }
    #expect(SystemPermissions.blocks(location: .denied, locationServicesEnabled: true) == [.location: .appAccess])
    #expect(SystemPermissions.blocks(location: .allowed, locationServicesEnabled: true).isEmpty)
    #expect(SystemPermissions.blocks(location: .notDetermined, locationServicesEnabled: nil).isEmpty,
            "not read yet: nothing is assumed")
  }

  /// Before the first read of Location Services lands, a denied app shows no note: macOS reports `.denied` for both
  /// causes, so "Turned off in macOS" would flash and then switch to "Location Services off". Once the read lands,
  /// the right note shows. Restricted is never Location Services, so it shows at once.
  @Test func deniedShowsNoNoteUntilTheFirstReadLands() {
    #expect(SystemPermissions.blocks(location: .denied, locationServicesEnabled: nil).isEmpty, "not read yet")
    #expect(SystemPermissions.blocks(location: .denied, locationServicesEnabled: false)
              == [.location: .locationServices])
    #expect(SystemPermissions.blocks(location: .denied, locationServicesEnabled: true) == [.location: .appAccess])
    #expect(SystemPermissions.blocks(location: .restricted, locationServicesEnabled: nil) == [.location: .appAccess])
  }

  /// The macOS state maps to the note only when access was denied or is restricted.
  @Test func systemAccessMapsToDeniedOnlyForDeniedAndRestricted() {
    #expect(SystemPermissionAccess.notDetermined.isDenied == false)
    #expect(SystemPermissionAccess.allowed.isDenied == false)
    #expect(SystemPermissionAccess.denied.isDenied)
    #expect(SystemPermissionAccess.restricted.isDenied)
  }

  @Test func localFileShowsOnlyTheNote() throws {
    let file = PageInfo(tab: tab, origin: "file://", host: "trail-notes.html", connection: .localFile)
    let model = try #require(PageInfoModel(file))
    #expect(model.state == .localFile)
    #expect(model.host == "trail-notes.html")
    #expect(model.connectionText == "Local file on this Mac")
    #expect(model.connectionSymbol == "doc")
    #expect(model.note == "Local files have no site settings.")
    #expect(model.siteDescription == nil, "VoiceOver reads the file name alone")
    #expect(PageInfoModel.pill(for: file)?.symbol == "doc")
    #expect(model.rows.isEmpty)
    #expect(!model.canResetPermissions)
  }

  @Test func internalPageOpensNothing() {
    let page = PageInfo(tab: tab, origin: "chrome://settings", host: "chrome://settings/", connection: .internalPage)
    #expect(PageInfoModel(page) == nil)
    #expect(PageInfoModel.pill(for: page) == nil)
    #expect(PageInfoModel.pill(for: nil) == nil)
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
