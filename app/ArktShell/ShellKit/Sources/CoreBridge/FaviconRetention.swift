import Archive
import Foundation
import SidebarModel

/// Which favicons the launch prune keeps (E5c decision). Archived nodes count as kept: a restore puts a node back
/// under its own id when that id is free, and its favicon file (`<node UUID>.png`) then shows again instead of the
/// letter placeholder. The cost is one off-main read of the whole archive at launch, before the prune; favicon writes
/// already wait for the prune (`FaviconWriter(after:)`), so they wait for this read too.
public enum FaviconRetention {
  /// `snapshot`'s id and the ids of every descendant, depth first.
  public static func ids(in snapshot: NodeSnapshot) -> [UUID] {
    [snapshot.id] + snapshot.children.flatMap(ids(in:))
  }

  /// The sidebar's node ids plus every node of every readable archive entry. Nil when the archive could not be read:
  /// the caller then skips the prune rather than delete favicons of archived nodes. Unreadable rows contribute no
  /// ids; they can be neither shown nor restored.
  @concurrent
  public static func keptIDs(sidebar: Set<UUID>, archive: any ArchiveStoring) async -> Set<UUID>? {
    guard let page = try? await archive.items(matching: ArchiveFilter(), limit: nil) else { return nil }
    return page.items.reduce(into: sidebar) { kept, item in kept.formUnion(ids(in: item.snapshot)) }
  }
}
