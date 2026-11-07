import EngineAPI
import Foundation

/// Where the tab a link was activated in sits.
public enum PeekSourceSection: Sendable, Equatable {
  case pinned, favorites, today
  /// The Peek itself.
  case peek
  /// No sidebar row (a tab the window does not map).
  case other
}

/// What the window does with a link activation.
public enum LinkRoute: Sendable, Equatable {
  /// The engine navigates as it would.
  case navigate
  /// The link opens in a Peek over the source tab.
  case peek
  /// The link opens as a new Today tab, selected.
  case newTab
}

/// Settings > Links (docs/design/peek.md): both on by default. Stored in the defaults suite the window is given.
public struct PeekLinkSettings: Equatable, Sendable {
  /// "Open a Peek window when clicking on links to other sites" ("Only affects Favorites and pinned tabs").
  public var opensCrossSiteLinks: Bool
  /// "Open a Peek window when clicking on links with Shift held".
  public var opensShiftClickedLinks: Bool

  public static let crossSiteKey = "peekOpensCrossSiteLinks"
  public static let shiftClickKey = "peekOpensShiftClickedLinks"

  public init(opensCrossSiteLinks: Bool = true, opensShiftClickedLinks: Bool = true) {
    self.opensCrossSiteLinks = opensCrossSiteLinks
    self.opensShiftClickedLinks = opensShiftClickedLinks
  }

  /// The stored values; a missing key keeps its default (on).
  public init(defaults: UserDefaults) {
    self.init(opensCrossSiteLinks: defaults.object(forKey: Self.crossSiteKey) as? Bool ?? true,
              opensShiftClickedLinks: defaults.object(forKey: Self.shiftClickKey) as? Bool ?? true)
  }

  public func save(to defaults: UserDefaults) {
    defaults.set(opensCrossSiteLinks, forKey: Self.crossSiteKey)
    defaults.set(opensShiftClickedLinks, forKey: Self.shiftClickKey)
  }
}

/// The Peek link rules (docs/design/peek.md, "When a Peek opens").
public enum PeekRouting {
  /// - A link inside the Peek navigates the Peek; Shift-click there opens a Today tab (one Peek per source tab).
  /// - Shift-click opens a Peek from any tab (BH-145, GS-027), a meeting link a Today tab.
  /// - Command, Option and Control clicks, and a middle-click (a background tab), are the engine's.
  /// - Without modifiers, a pinned tab or a Favorite opens a meeting link as a Today tab (BH-146) and a link to
  ///   another site in a Peek (BH-144, BH-056); a same-site link and every Today tab link navigate.
  public static func route(_ activation: EngineLinkActivation, section: PeekSourceSection,
                           settings: PeekLinkSettings = PeekLinkSettings()) -> LinkRoute {
    let modifiers = activation.modifiers
    // A middle-click carries no modifier flags, only the background-tab disposition (BH-163): the engine's, like a
    // Command-click.
    if activation.disposition == .newBackgroundTab { return .navigate }
    if modifiers.contains(.shift), modifiers.isDisjoint(with: [.command, .option, .control]) {
      if section == .peek { return .newTab }
      guard settings.opensShiftClickedLinks else { return .navigate }
      return isMeetingLink(activation.url) ? .newTab : .peek
    }
    guard modifiers.isEmpty, section == .pinned || section == .favorites else { return .navigate }
    if isMeetingLink(activation.url) { return .newTab }
    guard settings.opensCrossSiteLinks else { return .navigate }
    if let source = activation.sourceURL, isSameSite(source, activation.url) { return .navigate }
    return .peek
  }

  /// A tab the engine opened on its own from another tab (#345): a `target=_blank` link, or `window.open` without
  /// window features, which "follow the normal tab rules, and therefore the Peek rules when the opener is a pinned tab
  /// or a Favorite" (docs/design/peek.md, Popups). `.peek` takes the engine's tab into a Peek; every other answer
  /// leaves it the engine's tab, a Today row. A background tab (a Command-click) and a tab without a web URL yet stay
  /// the engine's.
  public static func routeOpenedTab(url: URL?, openerURL: URL?, section: PeekSourceSection, isActive: Bool,
                                    settings: PeekLinkSettings = PeekLinkSettings()) -> LinkRoute {
    guard isActive, let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return .navigate
    }
    // The rules read the URLs and the section only; the source tab's id plays no part.
    let link = EngineLinkActivation(url: url, sourceTab: TabID(), sourceURL: openerURL,
                                    disposition: .newForegroundTab)
    return route(link, section: section, settings: settings) == .peek ? .peek : .navigate
  }

  /// Meet, Zoom and Teams meeting links (BH-146).
  public static func isMeetingLink(_ url: URL) -> Bool {
    guard let host = url.host()?.lowercased() else { return false }
    let path = url.path().lowercased()
    if host == "meet.google.com" { return path.count > 1 }
    if host == "zoom.us" || host.hasSuffix(".zoom.us") {
      return path.hasPrefix("/j/") || path.hasPrefix("/my/") || path.hasPrefix("/wc/")
    }
    if host == "teams.microsoft.com" || host == "teams.live.com" {
      return path.hasPrefix("/l/meetup-join") || path.hasPrefix("/meet/")
    }
    return false
  }

  /// Same registrable domain. Without a public suffix list this takes the last two labels, or three when the
  /// second-level label is one of the common generic ones under a country code (`co.uk`, `com.au`). IP addresses and
  /// single-label hosts compare whole; ports and schemes are ignored.
  public static func isSameSite(_ a: URL, _ b: URL) -> Bool {
    guard let hostA = a.host()?.lowercased(), let hostB = b.host()?.lowercased() else { return false }
    return registrableDomain(hostA) == registrableDomain(hostB)
  }

  private static let genericSecondLevels: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or"]

  static func registrableDomain(_ host: String) -> String {
    let labels = host.split(separator: ".").map(String.init)
    let isIPv4 = labels.count == 4 && labels.allSatisfy { Int($0) != nil }
    guard labels.count > 2, !isIPv4, !host.contains(":") else { return host }
    let tld = labels[labels.count - 1]
    let second = labels[labels.count - 2]
    let take = tld.count == 2 && genericSecondLevels.contains(second) ? 3 : 2
    return labels.suffix(take).joined(separator: ".")
  }
}
