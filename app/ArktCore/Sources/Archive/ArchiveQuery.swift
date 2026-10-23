import SidebarModel

/// What the Archive view asks for (BH-087, BH-088). Empty fields do not filter.
public struct ArchiveFilter: Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    case space(SpaceID)
    case littleArc
  }

  public var source: Source?
  public var reason: ArchiveReason?
  /// Case-insensitive (ASCII) substring of the title or URL. LIKE wildcards in it are matched literally.
  public var text: String?

  public init(source: Source? = nil, reason: ArchiveReason? = nil, text: String? = nil) {
    self.source = source
    self.reason = reason
    self.text = text
  }
}

/// What `ArchiveStore.add` does with an id that is already stored.
public enum ArchiveConflictPolicy: Hashable, Sendable {
  /// Keep the stored entry and ignore the incoming one. For Arc re-imports: the same file imported twice must not
  /// rewrite entries.
  case keepExisting
  /// Overwrite every column with the incoming entry. For the app's own archive events: the newest archive of a node
  /// wins (for example a node archived again while a stale entry for it is still stored).
  case replace
}

/// One `items(matching:limit:)` result.
public struct ArchivePage: Hashable, Sendable {
  /// Readable items, newest first.
  public var items: [ArchivedItem]
  /// Matching rows that were skipped because they could not be read back (see `items(matching:limit:)`).
  public var unreadable: Int

  public init(items: [ArchivedItem], unreadable: Int) {
    self.items = items
    self.unreadable = unreadable
  }
}
