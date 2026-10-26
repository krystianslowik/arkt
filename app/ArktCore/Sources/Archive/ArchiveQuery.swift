import SidebarModel

/// What the Archive view asks for (BH-087, BH-088). Empty fields do not filter.
public struct ArchiveFilter: Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    case space(SpaceID)
    case littleArc
  }

  public var source: Source?
  public var reason: ArchiveReason?
  /// A substring of the title or URL of the item or of any node inside it (folder children, split panes), matched
  /// without case, diacritics or width (`ArchiveSearch.fold`) after trimming whitespace. Matched literally: no
  /// wildcards. Empty or blank text does not filter.
  public var text: String?

  public init(source: Source? = nil, reason: ArchiveReason? = nil, text: String? = nil) {
    self.source = source
    self.reason = reason
    self.text = text
  }
}

extension ArchiveFilter {
  /// The store's matching rule, in memory: for test stores and for entries not yet written (the outbox).
  public func matches(_ item: ArchivedItem) -> Bool {
    switch source {
    case .space(let id)?: guard item.source == .space(id) else { return false }
    case .littleArc?: guard item.source == .littleArc else { return false }
    case nil: break
    }
    if let reason, item.reason != reason { return false }
    if let query = ArchiveSearch.query(text), !ArchiveSearch.matches(item.snapshot, query: query) { return false }
    return true
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
