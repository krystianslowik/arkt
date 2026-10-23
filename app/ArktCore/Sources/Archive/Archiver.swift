import Foundation
import SidebarModel

public struct RestoredItem: Hashable, Sendable {
  public var nodeID: NodeID
  /// The Space the item landed in; nil when it went back to Favorites.
  public var space: SpaceID?
  public var location: Location

  public init(nodeID: NodeID, space: SpaceID?, location: Location) {
    self.nodeID = nodeID
    self.space = space
    self.location = location
  }
}

/// Moves nodes between the sidebar and archive entries. Pure: callers persist the results.
public enum Archiver {
  /// Removes `id` and its subtree and returns the archive entry, recording the containing Space as source (Favorites
  /// give `.unknown`) and the top-level section it sat in.
  ///
  /// A split root archives as one unit. A single pane archives as a plain tab entry and its split shrinks
  /// (`Sidebar.removePane`: a split left with one pane becomes that tab; user decision 4,
  /// PARITY(NEEDS-RUNTIME-CHECK BH-123)).
  /// Whether an action archives at all (pinned Cmd-W does not, BH-067; pinned and Favorites never auto-archive,
  /// BH-048, BH-054, BH-084) is the caller's decision.
  public static func archive(
    _ id: NodeID, from sidebar: inout Sidebar, reason: ArchiveReason, at date: Date
  ) throws -> ArchivedItem {
    guard let snapshot = sidebar.snapshot(of: id) else { throw SidebarError.unknownNode(id) }
    let (source, section): (ArchiveSource, ArchivedSection?) = switch sidebar.section(of: id) {
    case .pinned(let space)?: (.space(space), .pinned)
    case .today(let space)?: (.space(space), .today)
    case .favorites(let profile)?: (.unknown, .favorites(profile: profile))
    default: (.unknown, nil)
    }
    sidebar.removePane(id)
    return ArchivedItem(reason: reason, archivedAt: date, source: source, section: section, snapshot: snapshot)
  }

  /// Removes Space `id` (decision on #86: its Pinned items, then its Today items, go to the archive with reason
  /// `.manual`, each top-level item as one entry) and returns the entries in sidebar order. Unknown ids archive
  /// nothing. The entries keep `.space(id)` as source, so a later restore uses its default rules in the fallback
  /// Space. Asking for confirmation is the caller's job.
  public static func removeSpace(_ id: SpaceID, from sidebar: inout Sidebar, at date: Date) -> [ArchivedItem] {
    guard sidebar.spaces[id] != nil else { return [] }
    let roots = sidebar.children(of: .pinned(id)) + sidebar.children(of: .today(id))
    let items = roots.compactMap { try? archive($0, from: &sidebar, reason: .manual, at: date) }
    sidebar.removeSpace(id)
    return items
  }

  /// Puts `item` back (BH-086). With a recorded section the item returns to the same kind of section [I]: Pinned
  /// (appended) or the top of Today in its source Space when that Space still exists, or the end of its profile's
  /// Favorites. Otherwise the default rules apply: folders appended to Pinned (BH-090) [I], tabs and splits at the
  /// top of Today [I], in the source Space if it still exists, else in `fallbackSpace`; Little Arc (BH-138) and
  /// unknown sources use `fallbackSpace` [I]. Air Traffic Control routing (BH-157) is applied by the caller when
  /// choosing `fallbackSpace`. Original ids are kept unless any id in the subtree is taken, then the whole subtree
  /// gets fresh ids. Any `SidebarError` from the insert (including `.nestingTooDeep`) is rethrown and the sidebar is
  /// unchanged on throw.
  public static func restore(
    _ item: ArchivedItem, into sidebar: inout Sidebar, fallbackSpace: SpaceID
  ) throws -> RestoredItem {
    var original: SpaceID?
    if case .space(let space) = item.source, sidebar.spaces[space] != nil { original = space }
    let space: SpaceID?
    let location: Location
    let index: Int?
    switch (item.section, original) {
    case (.favorites(let profile)?, _):
      (space, location, index) = (nil, .favorites(profile: profile), nil)
    case (.pinned?, let original?):
      (space, location, index) = (original, .pinned(original), nil)
    case (.today?, let original?):
      (space, location, index) = (original, .today(original), 0)
    default:
      let target = original ?? fallbackSpace
      if case .folder = item.snapshot.kind {
        (space, location, index) = (target, .pinned(target), nil)
      } else {
        (space, location, index) = (target, .today(target), 0)
      }
    }
    let taken = item.snapshot.allIDs.contains { sidebar.nodes[$0] != nil }
    let snapshot = taken ? item.snapshot.withFreshIDs() : item.snapshot
    try sidebar.insert(snapshot, in: location, at: index)
    return RestoredItem(nodeID: snapshot.id, space: space, location: location)
  }
}
