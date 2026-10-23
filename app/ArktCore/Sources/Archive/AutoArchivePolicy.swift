import Foundation
import SidebarModel

/// "Archive tabs after" / "Archive Little Arcs after:" options (BH-081, CF-04). Raw values reuse the threshold strings
/// Arc writes in its settings; `never` is ours (Arc gates it behind an internal flag, BH-082).
public enum AutoArchiveThreshold: String, CaseIterable, Codable, Hashable, Sendable {
  case oneHour, sixHours, twelveHours, twentyFourHours, sevenDays, thirtyDays
  // PARITY(NEEDS-RUNTIME-CHECK BH-082): Arc gates "never" in the picker behind an internal flag. The policy
  // keeps it as a real case; whether the UI shows it is the settings UI's call.
  case never

  /// Fresh-install tab default (BH-080).
  public static let tabsDefault: AutoArchiveThreshold = .twelveHours
  /// Fresh-install Little Arc default (BH-137).
  public static let littleArcDefault: AutoArchiveThreshold = .sixHours

  /// Idle time after which an item is archived; nil for `never`.
  public var interval: TimeInterval? {
    switch self {
    case .oneHour: 3600
    case .sixHours: 6 * 3600
    case .twelveHours: 12 * 3600
    case .twentyFourHours: 24 * 3600
    case .sevenDays: 7 * 86_400
    case .thirtyDays: 30 * 86_400
    case .never: nil
    }
  }
}

public struct AutoArchiveInput: Sendable {
  public var now: Date
  /// When auto-archive started on this install (Arc: `autoArchiveStartTime` in Arc's archive JSON). Idle time
  /// never counts from earlier, so an Arc import or first launch does not archive everything at once.
  /// PARITY(NEEDS-RUNTIME-CHECK [I]): the meaning of Arc's `autoArchiveStartTime` is inferred.
  public var startedAt: Date
  /// Never archived this run: tabs playing media (BH-076) and tabs visible in any window.
  // PARITY(NEEDS-RUNTIME-CHECK [I]): the spec has no BH for "the visible/active tab is never auto-archived" nor for
  // tabs shown in other windows. Assumed: a tab currently shown in any window (including a split pane) is exempt, and
  // the caller passes those ids here together with media-playing tabs.
  public var exempt: Set<NodeID>
  /// The tab threshold for a profile name (BH-083, BH-179). App code passes `ArchiveSettings.tabThreshold(forProfile:)`.
  public var threshold: @Sendable (_ profile: String) -> AutoArchiveThreshold

  public init(
    now: Date, startedAt: Date, exempt: Set<NodeID> = [],
    threshold: @escaping @Sendable (_ profile: String) -> AutoArchiveThreshold
  ) {
    self.now = now
    self.startedAt = startedAt
    self.exempt = exempt
    self.threshold = threshold
  }
}

public struct LittleArcWindowActivity: Hashable, Sendable {
  public var id: UUID
  public var lastActiveAt: Date

  public init(id: UUID, lastActiveAt: Date) {
    self.id = id
    self.lastActiveAt = lastActiveAt
  }
}

/// Which items the idle timer archives. Pure; the caller archives them with reason `.auto` and shows the toast
/// "Auto archived N tabs" (BH-085).
public enum AutoArchivePolicy {
  /// Direct children of each Space's Today section whose idle time reached the Space profile's threshold, in Space
  /// order then Today order. Pinned (BH-054), Favorites (BH-048) and folder contents (BH-084, BH-090) are never
  /// candidates. Idle reference: `lastActiveAt ?? createdAt` (BH-080), clamped to `startedAt`. Idle time equal to the
  /// threshold archives.
  public static func itemsToArchive(in sidebar: Sidebar, _ input: AutoArchiveInput) -> [NodeID] {
    var result: [NodeID] = []
    for spaceID in sidebar.spaceOrder {
      guard let space = sidebar.spaces[spaceID], let interval = input.threshold(space.profile).interval else {
        continue
      }
      for id in sidebar.children(of: .today(spaceID)) {
        guard let lastActive = lastActive(id, in: sidebar, exempt: input.exempt) else { continue }
        if input.now.timeIntervalSince(max(lastActive, input.startedAt)) >= interval { result.append(id) }
      }
    }
    return result
  }

  /// Little Arc windows past their own threshold (BH-137), in input order. Exempt windows (media playing, BH-076)
  /// stay.
  public static func littleArcWindowsToArchive(
    _ windows: [LittleArcWindowActivity], threshold: AutoArchiveThreshold, now: Date, exempt: Set<UUID>
  ) -> [UUID] {
    guard let interval = threshold.interval else { return [] }
    return windows
      .filter { !exempt.contains($0.id) && now.timeIntervalSince($0.lastActiveAt) >= interval }
      .map(\.id)
  }

  /// The idle reference of a direct Today child; nil means "not a candidate".
  static func lastActive(_ id: NodeID, in sidebar: Sidebar, exempt: Set<NodeID>) -> Date? {
    guard !exempt.contains(id), let node = sidebar.nodes[id] else { return nil }
    switch node.kind {
    case .tab(let tab):
      return tab.lastActiveAt ?? node.createdAt
    case .folder:
      // PARITY(NEEDS-RUNTIME-CHECK [I]): Arc keeps folders in Pinned (BH-090) and never archives foldered tabs
      // (BH-084). A folder that sits directly in Today is skipped as a unit, contents included.
      return nil
    case .split:
      // [I] (no BH rule covers auto-archiving splits; related: CF-18, RT-21): a split in Today is one unit. Its most recently active pane is its
      // idle reference, and any exempt pane protects the whole split. An empty split ages from its own createdAt.
      var latest: Date?
      for pane in sidebar.children(of: .split(id)) {
        guard !exempt.contains(pane), let paneNode = sidebar.nodes[pane] else { return nil }
        if case .tab(let tab) = paneNode.kind {
          let paneActive = tab.lastActiveAt ?? paneNode.createdAt
          latest = max(latest ?? paneActive, paneActive)
        }
      }
      return latest ?? node.createdAt
    }
  }
}
