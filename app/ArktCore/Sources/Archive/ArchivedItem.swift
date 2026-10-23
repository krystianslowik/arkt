import Foundation
import SidebarModel

/// Why an item is in the archive (Arc: `reason`).
public enum ArchiveReason: String, Codable, Hashable, Sendable, CaseIterable {
  /// Closed by the user (Cmd-W, Clear, Archive Below): BH-071, BH-075, BH-077.
  case manual
  /// Archived by the idle policy: BH-080.
  case auto
}

/// Where an archived item came from (Arc: `source`). Drives the Archive filters (BH-088).
public enum ArchiveSource: Hashable, Sendable {
  case space(SpaceID)
  case littleArc
  case unknown
}

/// The top-level section an item was archived from, so restore can put it back into the same kind of section [I].
/// The Space for `pinned`/`today` is the entry's `source`.
public enum ArchivedSection: Hashable, Sendable {
  case pinned
  case today
  case favorites(profile: String)
}

/// One archive entry: a full snapshot of the archived node and its subtree. Not `Codable` on purpose: the archive
/// store persists its fields as columns plus the snapshot in the D1 storage format.
public struct ArchivedItem: Identifiable, Hashable, Sendable {
  public var reason: ArchiveReason
  public var archivedAt: Date
  public var source: ArchiveSource
  /// Nil when unknown (for example an entry imported from Arc); restore then uses its default rules.
  public var section: ArchivedSection?
  public var snapshot: NodeSnapshot

  public init(
    reason: ArchiveReason,
    archivedAt: Date,
    source: ArchiveSource,
    section: ArchivedSection? = nil,
    snapshot: NodeSnapshot
  ) {
    self.reason = reason
    self.archivedAt = archivedAt
    self.source = source
    self.section = section
    self.snapshot = snapshot
  }

  /// The archived root node's id; one entry per root, as Arc keys its archive by item id.
  public var id: NodeID { snapshot.id }

  /// Display and search title: a tab's custom title or page title, a folder's title, a split's pane titles.
  public var title: String {
    switch snapshot.kind {
    case .tab(let tab): tab.customTitle ?? tab.title
    case .folder(let folder): folder.title
    case .split:
      snapshot.children.compactMap { child -> String? in
        if case .tab(let tab) = child.kind { return tab.customTitle ?? tab.title }
        return nil
      }.joined(separator: " | ")
    }
  }

  /// The tab URL, nil for folders and splits.
  public var url: URL? {
    if case .tab(let tab) = snapshot.kind { return tab.url }
    return nil
  }
}
