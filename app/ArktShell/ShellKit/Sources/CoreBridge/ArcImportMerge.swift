import ArcImport
import Foundation
import SidebarModel

/// What `ArcImportMerge.merge` added to the sidebar, and which Arc ids it handled.
public struct ArcImportMergeCounts: Equatable, Sendable {
  /// Spaces added (Arc Spaces never imported before whose stable id Arkt did not have).
  public var spaces = 0
  /// Arc Spaces already in Arkt (same stable id); left exactly as they are.
  public var existingSpaces = 0
  /// Arc Spaces an earlier import added that are no longer in Arkt (the user deleted them); not restored.
  public var previouslyImportedSpaces = 0
  /// Added Spaces that belonged to a non-default Arc profile and now live in the target profile.
  public var otherProfileSpaces = 0
  /// Nodes added inside the added Spaces (Pinned and Today, nested ones included).
  public var tabs = 0
  public var folders = 0
  public var splits = 0
  /// Top-level Favorites added (tabs, folders and splits).
  public var favorites = 0
  /// Favorite tabs never imported before, not added because a Favorite with the same URL was already there.
  public var duplicateFavorites = 0
  /// Favorites an earlier import handled; skipped whether or not they are still in Arkt, and whatever their URL is
  /// now.
  public var previouslyImportedFavorites = 0
  /// Subtrees the model refused (not expected for an importer-built sidebar); counted, never thrown, not recorded.
  public var refused = 0
  /// Every node id added, for favicons.
  public var addedNodes: Set<NodeID> = []
  /// The Arc ids this merge handled: added, already in Arkt, duplicate URL, or recorded before. Adding them to the
  /// stored `ArcImportRecord` keeps every later import from adding them again.
  public var handled = ArcImportRecord()

  public init() {}
}

/// Merges an imported Arc sidebar into Arkt's sidebar (Track E user decisions 2 and 3, and the re-import rule, all
/// 2026-10-23). Pure.
/// - A re-import adds only Arc items never imported before. `record` holds the Arc ids earlier imports handled; a
///   Space or top-level Favorite (tab, folder or split) whose Arc id is in it is skipped whatever the sidebar holds
///   now, so a Space or Favorite the user deleted in Arkt never comes back, and a Favorite whose URL changed in Arc
///   is not added a second time.
/// - Spaces are also matched by id: `ArcSidebarImporter` gives every Arc Space a stable id (E4a), so a Space already
///   in Arkt is skipped whole and keeps every change the user made; a missing one is added with its Pinned and Today
///   trees. Node ids are the importer's freshly minted ones, so they never collide with existing nodes.
/// - Every Space and every Favorite lands in `profile` (Spaces of other Arc profiles are merged, not hidden).
/// - Favorites from every Arc profile go into `profile`'s Favorites; a tab whose URL is already a Favorite there is
///   skipped, so profiles sharing a Favorite add no duplicates. With an empty `record` (the first import, or the
///   first one after an import that ran before the record existed) the id and URL matches are all there is.
public enum ArcImportMerge {
  public static func merge(
    _ imported: ArcImportResult, into sidebar: inout SidebarModel.Sidebar, profile: String = "default",
    record: ArcImportRecord = ArcImportRecord()
  ) -> ArcImportMergeCounts {
    var counts = ArcImportMergeCounts()
    mergeSpaces(imported, into: &sidebar, profile: profile, record: record, counts: &counts)
    mergeFavorites(imported, into: &sidebar, profile: profile, record: record, counts: &counts)
    return counts
  }

  /// Ids of the Spaces `merge` would add (for deciding on the clock reset before mutating).
  public static func missingSpaces(
    in imported: ArcImportResult, comparedTo sidebar: SidebarModel.Sidebar,
    record: ArcImportRecord = ArcImportRecord()
  ) -> [SpaceID] {
    let arcIDs = arcSpaceIDs(imported)
    return imported.sidebar.spaceOrder.filter { id in
      guard sidebar.spaces[id] == nil else { return false }
      guard let arcID = arcIDs[id] else { return true }
      return !record.spaceIDs.contains(arcID)
    }
  }

  private static func mergeSpaces(
    _ imported: ArcImportResult, into sidebar: inout SidebarModel.Sidebar, profile: String, record: ArcImportRecord,
    counts: inout ArcImportMergeCounts
  ) {
    let arcIDs = arcSpaceIDs(imported)
    let source = imported.sidebar
    for id in source.spaceOrder {
      guard let space = source.spaces[id] else { continue }
      let arcID = arcIDs[id]
      if sidebar.spaces[id] != nil {
        counts.existingSpaces += 1
        if let arcID { counts.handled.spaceIDs.insert(arcID) }
        continue
      }
      if let arcID, record.spaceIDs.contains(arcID) {
        counts.previouslyImportedSpaces += 1
        counts.handled.spaceIDs.insert(arcID)
        continue
      }
      do {
        try sidebar.addSpace(Space(id: id, title: space.title, profile: profile, theme: space.theme))
      } catch {
        counts.refused += 1
        continue
      }
      if let arcID { counts.handled.spaceIDs.insert(arcID) }
      counts.spaces += 1
      if space.profile != profile { counts.otherProfileSpaces += 1 }
      for location in [Location.pinned(id), .today(id)] {
        for child in source.children(of: location) {
          guard let snapshot = source.snapshot(of: child) else { continue }
          if insert(snapshot, in: location, into: &sidebar, counts: &counts) { count(snapshot, in: &counts) }
        }
      }
    }
  }

  private static func mergeFavorites(
    _ imported: ArcImportResult, into sidebar: inout SidebarModel.Sidebar, profile: String, record: ArcImportRecord,
    counts: inout ArcImportMergeCounts
  ) {
    let source = imported.sidebar
    let arcIDs = Dictionary(imported.nodeIDsByArcID.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    let target = Location.favorites(profile: profile)
    var urls = Set(sidebar.children(of: target).compactMap { tabURL(sidebar.nodes[$0]?.kind) })
    // The target profile's own Favorites first, then the other profiles' in name order (deterministic).
    let profiles = source.childOrder.keys.compactMap { location -> String? in
      if case .favorites(let name) = location { return name }
      return nil
    }
    .sorted { ($0 == profile) != ($1 == profile) ? $0 == profile : $0 < $1 }
    for name in profiles {
      for child in source.children(of: .favorites(profile: name)) {
        guard let snapshot = source.snapshot(of: child) else { continue }
        let arcID = arcIDs[child]
        if let arcID, record.favoriteItemIDs.contains(arcID) {
          counts.previouslyImportedFavorites += 1
          counts.handled.favoriteItemIDs.insert(arcID)
          continue
        }
        if let url = tabURL(snapshot.kind) {
          guard urls.insert(url).inserted else {
            counts.duplicateFavorites += 1
            if let arcID { counts.handled.favoriteItemIDs.insert(arcID) }
            continue
          }
        }
        guard insert(snapshot, in: target, into: &sidebar, counts: &counts) else { continue }
        counts.favorites += 1
        if let arcID { counts.handled.favoriteItemIDs.insert(arcID) }
      }
    }
  }

  /// Arc id by Arkt Space id (the importer's `spaceIDsByArcID`, inverted).
  private static func arcSpaceIDs(_ imported: ArcImportResult) -> [SpaceID: String] {
    Dictionary(imported.spaceIDsByArcID.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
  }

  private static func insert(
    _ snapshot: NodeSnapshot, in location: Location, into sidebar: inout SidebarModel.Sidebar,
    counts: inout ArcImportMergeCounts
  ) -> Bool {
    do {
      try sidebar.insert(snapshot, in: location)
    } catch {
      counts.refused += 1
      return false
    }
    counts.addedNodes.formUnion(snapshot.allIDs)
    return true
  }

  private static func count(_ snapshot: NodeSnapshot, in counts: inout ArcImportMergeCounts) {
    switch snapshot.kind {
    case .tab: counts.tabs += 1
    case .folder: counts.folders += 1
    case .split: counts.splits += 1
    }
    for child in snapshot.children { count(child, in: &counts) }
  }

  private static func tabURL(_ kind: NodeKind?) -> URL? {
    if case .tab(let tab)? = kind { return tab.url }
    return nil
  }
}
