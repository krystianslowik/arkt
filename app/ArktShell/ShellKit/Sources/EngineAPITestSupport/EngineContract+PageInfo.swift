import EngineAPI
import Foundation

// MARK: - Rule 26 (#582): page info and per-site permissions

extension EngineContract {
  static func siteSettings(_ engine: any EngineClient) throws -> any EngineSiteSettings {
    guard let settings = engine.siteSettings else { throw ContractNotApplicable(driver: "siteSettings") }
    return settings
  }

  /// The tab's reload infobars as the last `.infobarsChanged` reported them.
  static func reloadInfobars(_ recorder: EventRecorder, _ id: TabID) -> [Infobar] {
    let lists = recorder.events(for: id).compactMap { if case .infobarsChanged(_, let list) = $0 { list } else { nil } }
    return (lists.last ?? []).filter { $0.kind == .reload }
  }

  /// Opens a settled tab on each of the two hosts.
  private static func twoSites(_ h: EngineHarness, _ engine: any EngineClient) async throws -> (TabID, TabID) {
    let (first, second) = try h.pagesOnTwoHosts()
    let window = engine.createWindow(host: h.makeWindowHost())
    let a = engine.createTab(url: first, in: window)
    let b = engine.createTab(url: second, in: window)
    try await h.settle(engine, a)
    try await h.settle(engine, b)
    return (a, b)
  }

  public static func pageInfoNamesTheSiteItShows(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let site = try siteSettings(engine)
    let (a, b) = try await twoSites(h, engine)

    let first = try requireValue(site.pageInfo(of: a), "page info of \(a)")
    let second = try requireValue(site.pageInfo(of: b), "page info of \(b)")
    try require(first.tab == a && second.tab == b, "page info names its tab")
    try require(first.hasSiteSettings && second.hasSiteSettings, "a site's page has site settings")
    try require(!first.host.isEmpty && !first.origin.isEmpty, "page info names the site")
    try require(first.origin != second.origin, "two hosts are two sites")
    try require(!first.permissions.isEmpty, "a site lists its permissions")
    try require(first.permissions.allSatisfy { $0.options.contains($0.setting) }, "a setting is one of its options")
    try require(Set(first.permissions.map(\.kind)).count == first.permissions.count, "each permission is listed once")
    try require(site.pageInfo(of: TabID()) == nil, "an unknown tab has no page info")
    engine.closeTab(a)
    try await wait("the close of \(a)") { !engine.tabIDs.contains(a) }
    try require(site.pageInfo(of: a) == nil, "a closed tab has no page info")
  }

  public static func permissionChangeIsReadBackAndResetRestoresTheDefault(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let site = try siteSettings(engine)
    let (a, b) = try await twoSites(h, engine)
    let info = try requireValue(site.pageInfo(of: a), "page info of \(a)")
    let permission = try requireValue(info.permissions.first { $0.isDefault }, "a permission at its default")
    let other = try requireValue(permission.options.first { $0 != permission.setting }, "another setting")

    site.setPermission(permission.kind, to: other, forOrigin: info.origin)

    let changed = site.pageInfo(of: a)?.permissions.first { $0.kind == permission.kind }
    try require(changed?.setting == other && changed?.isDefault == false, "the change is read back at once")
    let untouched = site.pageInfo(of: b)?.permissions.first { $0.kind == permission.kind }
    try require(untouched == nil || untouched?.isDefault == true, "another site keeps its setting")
    let listed = site.sitesWithPermissions().first { $0.origin == info.origin }
    try require(listed?.permissions.contains { $0.kind == permission.kind && $0.setting == other } == true,
                "the per-site list carries the change")

    site.resetPermissions(forOrigin: info.origin)

    let reset = site.pageInfo(of: a)?.permissions.first { $0.kind == permission.kind }
    try require(reset == nil || (reset?.isDefault == true && reset?.setting == permission.setting),
                "reset restores the default")
    try require(!site.sitesWithPermissions().contains { $0.origin == info.origin }, "reset leaves the per-site list")
  }

  public static func permissionChangeRaisesTheReloadInfobarOnce(_ h: EngineHarness) async throws {
    let engine = h.makeEngine()
    let site = try siteSettings(engine)
    let (a, b) = try await twoSites(h, engine)
    let recorder = EventRecorder(engine)
    let info = try requireValue(site.pageInfo(of: a), "page info of \(a)")
    let changes = info.permissions.compactMap { p in p.options.first { $0 != p.setting }.map { (p.kind, $0) } }
    try require(changes.count >= 2, "two permissions to change")

    site.setPermission(changes[0].0, to: changes[0].1, forOrigin: info.origin)
    site.setPermission(changes[1].0, to: changes[1].1, forOrigin: info.origin)
    try await wait("the reload infobar on \(a)") { !reloadInfobars(recorder, a).isEmpty }

    try require(reloadInfobars(recorder, a).count == 1, "one reload infobar however many changes")
    try require(reloadInfobars(recorder, a).first?.ok != nil, "the reload infobar has a Reload button")
    try require(reloadInfobars(recorder, b).isEmpty, "another site's tab gets no reload infobar")
  }
}
