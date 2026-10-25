import Archive
import Foundation
import ShellUI
import SidebarModel

/// `SidebarSource` over Arkt's value-type `Sidebar`. The value is the single source of truth; every change goes
/// through `mutate`, which emits the exact `SidebarChange`s (diffed) and then reports the new value through
/// `onDidChange` (the app wires it to `SidebarAutosaver.scheduleSave`). Errors from the model are rethrown and leave
/// the value, the observers and `onDidChange` untouched.
@MainActor
public final class ModelSidebarSource: SidebarSource {
  public private(set) var sidebar: SidebarModel.Sidebar
  /// Called once per mutation that changed the value, after the changes were emitted.
  public var onDidChange: (@MainActor (SidebarModel.Sidebar) -> Void)?
  /// The profile `addSpace(title:)` creates Spaces in.
  public let defaultProfile: String
  private let hub = SidebarChangeHub()
  private let now: @MainActor () -> Date

  public init(
    sidebar: SidebarModel.Sidebar = .init(), defaultProfile: String = "default",
    now: @escaping @MainActor () -> Date = { Date() }
  ) {
    self.sidebar = sidebar
    self.defaultProfile = defaultProfile
    self.now = now
  }

  // MARK: - SidebarSource (reads)

  public var spaceOrder: [UUID] { sidebar.spaceOrder }

  public func space(_ id: UUID) -> SidebarSpaceInfo? { sidebar.spaces[id].map(BridgeMapping.spaceInfo) }

  public func children(of location: SidebarLocation) -> [UUID] {
    sidebar.children(of: BridgeMapping.location(location))
  }

  public func node(_ id: UUID) -> SidebarNodeInfo? { sidebar.nodes[id].map(BridgeMapping.nodeInfo) }

  public func parent(of id: UUID) -> SidebarLocation? { sidebar.nodes[id].map { BridgeMapping.location($0.parent) } }

  public func observe(_ handler: @escaping @MainActor (SidebarChange) -> Void) -> SidebarObservation {
    hub.observe(handler)
  }

  // MARK: - SidebarSource (writes)

  /// A new tab whose idle clock starts now (`lastActiveAt == createdAt`). Throws the model's `SidebarError`.
  /// `index` is the position in the location's child order, clamped; nil appends.
  @discardableResult
  public func addTab(url: URL, title: String, in location: SidebarLocation, at index: Int? = nil) throws -> UUID {
    let createdAt = now()
    return try mutate {
      try $0.addTab(
        url: url, title: title, lastActiveAt: createdAt, in: BridgeMapping.location(location), at: index,
        createdAt: createdAt)
    }
  }

  @discardableResult
  public func addSpace(title: String) throws -> UUID {
    mutate { $0.addSpace(title: title, profile: defaultProfile) }
  }

  /// One mutation: the Space is appended, then moved right after `space`, so observers see `.spaceAdded` only.
  @discardableResult
  public func addSpace(title: String, after space: UUID?) throws -> UUID {
    mutate { sidebar in
      let id = sidebar.addSpace(title: title, profile: defaultProfile)
      if let space, let index = sidebar.spaceOrder.firstIndex(of: space) { sidebar.moveSpace(id, to: index + 1) }
      return id
    }
  }

  public func renameSpace(_ id: UUID, to title: String) {
    mutate { $0.renameSpace(id, to: title) }
  }

  public func moveSpace(_ id: UUID, to index: Int) {
    mutate { $0.moveSpace(id, to: index) }
  }

  public func setIcon(_ id: UUID, to icon: SpaceIconInfo?) {
    mutate { $0.setIcon(id, to: BridgeMapping.modelIcon(icon)) }
  }

  public func setTheme(_ id: UUID, to theme: SpaceThemeInfo?) {
    mutate { $0.setTheme(id, to: theme.map(BridgeMapping.modelTheme)) }
  }

  /// Engine-driven title / URL changes. Unknown or non-tab ids are ignored, like `StubSidebar`.
  public func updateTab(_ id: UUID, url: URL?, title: String?) {
    _ = try? mutate { try $0.updateTab(id, url: url, title: title) }
  }

  /// D4b contract: stamps tabs that stopped being visible. Non-tabs and unknown ids are skipped.
  public func markInactive(_ ids: some Sequence<UUID>, at date: Date) {
    mutate { sidebar in
      for id in ids { try? sidebar.updateTab(id, lastActiveAt: date) }
    }
  }

  // MARK: - Split writes

  /// One mutation: a new tab is created next to the target (or next to the split, never inside it, so the pane cap
  /// is checked when it moves in) and then joins the split, so a refused edit leaves no orphan tab. The new tab's
  /// idle clock starts now, as in `addTab`.
  @discardableResult
  public func addToSplit(_ pane: SplitPaneSource, target: UUID, at index: Int, orientation: SplitOrientation)
    throws -> (split: UUID, pane: UUID)
  {
    let stamp = now()
    return try mapSplitErrors {
      try mutate { sidebar in
        let (existingSplit, newTabLocation) = try Self.splitTarget(target, in: sidebar)
        let paneID: UUID
        switch pane {
        case .existing(let id): paneID = id
        case .new(let url, let title):
          paneID = try sidebar.addTab(
            url: url, title: title, lastActiveAt: stamp, in: newTabLocation, createdAt: stamp)
        }
        if let existingSplit {
          try sidebar.addPane(paneID, to: existingSplit, at: index)
          return (existingSplit, paneID)
        }
        let split = try sidebar.createSplit(
          of: [target, paneID], orientation: BridgeMapping.orientation(orientation), createdAt: stamp)
        if index <= 0 { try sidebar.movePane(paneID, to: 0) }
        return (split, paneID)
      }
    }
  }

  public func separatePane(_ pane: UUID) throws {
    try mapSplitErrors { try mutate { try $0.separatePane(pane) } }
  }

  @discardableResult
  public func separateSplit(_ split: UUID) throws -> [UUID] {
    try mapSplitErrors { try mutate { try $0.separateSplit(split) } }
  }

  public func expandPane(_ pane: UUID) throws {
    try mapSplitErrors { try mutate { try $0.expandPane(pane) } }
  }

  public func movePane(_ pane: UUID, to index: Int) throws {
    try mapSplitErrors { try mutate { try $0.movePane(pane, to: index) } }
  }

  public func setSplitWidthFactors(_ split: UUID, _ factors: [Double]) throws {
    try mapSplitErrors { try mutate { try $0.setSplitWidthFactors(split, factors) } }
  }

  public func setSplitOrientation(_ split: UUID, _ orientation: SplitOrientation) throws {
    try mapSplitErrors { try mutate { try $0.setSplitOrientation(split, BridgeMapping.orientation(orientation)) } }
  }

  /// The copy is new: fresh ids, and it and its panes are created now with their idle clocks starting now [I], so
  /// auto-archive does not take it for an old split.
  @discardableResult
  public func duplicateSplit(_ split: UUID) throws -> UUID {
    let stamp = now()
    return try mapSplitErrors {
      try mutate { sidebar in
        guard let node = sidebar.nodes[split], let snapshot = sidebar.snapshot(of: split) else {
          throw SidebarError.unknownNode(split)
        }
        guard case .split = node.kind else { throw SidebarError.invalidSplit(split) }
        let copy = Self.restamped(snapshot.withFreshIDs(), at: stamp)
        let position = sidebar.children(of: node.parent).firstIndex(of: split) ?? 0
        try sidebar.insert(copy, in: node.parent, at: position + 1)
        return copy.id
      }
    }
  }

  /// The split that `target` adds to (itself, or the split holding it) and where a new tab is created first: the
  /// location holding that split, or the target tab's own location when a new split is made. Throws
  /// `SplitEditError.invalid` for unknown ids and folders.
  private static func splitTarget(_ target: UUID, in sidebar: SidebarModel.Sidebar) throws
    -> (split: UUID?, newTabLocation: SidebarModel.Location)
  {
    guard let node = sidebar.nodes[target] else { throw SplitEditError.invalid }
    switch (node.kind, node.parent) {
    case (.split, _): return (target, node.parent)
    case (.tab, .split(let split)):
      guard let splitParent = sidebar.nodes[split]?.parent else { throw SplitEditError.invalid }
      return (split, splitParent)
    case (.tab, _): return (nil, node.parent)
    case (.folder, _): throw SplitEditError.invalid
    }
  }

  /// `snapshot` with every node created at `date` and every tab's idle clock starting then. A split's children are
  /// tabs, so the recursion is one level deep for the snapshots this is used on.
  private static func restamped(_ snapshot: NodeSnapshot, at date: Date) -> NodeSnapshot {
    var kind = snapshot.kind
    if case .tab(var tab) = kind {
      tab.lastActiveAt = date
      kind = .tab(tab)
    }
    return NodeSnapshot(
      id: snapshot.id, kind: kind, createdAt: date, children: snapshot.children.map { restamped($0, at: date) })
  }

  /// BH-116 and the plan's error surface (decision 13): `.splitFull` becomes `SplitEditError.splitFull`,
  /// `.invalidSplit` becomes `.invalid`; every other error passes through unchanged.
  private func mapSplitErrors<T>(_ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch SidebarError.splitFull {
      throw SplitEditError.splitFull
    } catch SidebarError.invalidSplit {
      throw SplitEditError.invalid
    }
  }

  // MARK: - Archive

  /// Archives nodes through `Archiver` and returns the entries in the order of `ids`; all of them leave the value in
  /// one mutation (one `onDidChange`). Unknown ids are skipped. Which nodes may be archived is the caller's decision.
  /// Production callers go through `ArchiveCoordinator.archive(_:reason:)` so the entries are queued to the archive
  /// outbox before the sidebar save (#213).
  public func archive(_ ids: [UUID], reason: ArchiveReason, at date: Date) -> [ArchivedItem] {
    archive(ids, reason: reason, at: date, beforeDidChange: { _ in })
  }

  func archive(
    _ ids: [UUID], reason: ArchiveReason, at date: Date, beforeDidChange: ([ArchivedItem]) -> Void
  ) -> [ArchivedItem] {
    mutate(
      { sidebar in ids.compactMap { try? Archiver.archive($0, from: &sidebar, reason: reason, at: date) } },
      beforeDidChange: beforeDidChange)
  }

  /// Removes Space `id` through `Archiver.removeSpace` (its pinned and Today items are archived) in one mutation, which
  /// reports `.spaceRemoved` only. Returns the entries; an unknown id changes nothing. Asking first is the caller's job.
  /// Internal so production callers go through `ArchiveCoordinator.removeSpace(_:)`, which queues the entries to the
  /// archive outbox before the sidebar save (#213).
  func removeSpace(
    _ id: UUID, at date: Date, beforeDidChange: ([ArchivedItem]) -> Void = { _ in }
  ) -> [ArchivedItem] {
    mutate({ Archiver.removeSpace(id, from: &$0, at: date) }, beforeDidChange: beforeDidChange)
  }

  /// Puts `item` back through `Archiver.restore` (its placement rules and fresh ids when an id is taken). Throws the
  /// model's `SidebarError` and leaves the value untouched on throw.
  public func restore(_ item: ArchivedItem, fallbackSpace: UUID) throws -> RestoredItem {
    try mutate { try Archiver.restore(item, into: &$0, fallbackSpace: fallbackSpace) }
  }

  // MARK: - Mutation

  /// Runs `body` on a copy; when it returns and the value changed, stores it, emits the diffed changes and calls
  /// `onDidChange` once. A throw leaves everything untouched. Observers and `onDidChange` must not call `mutate`
  /// synchronously while a change is being delivered (the remaining changes would describe a stale value); defer it.
  @discardableResult
  public func mutate<T>(_ body: (inout SidebarModel.Sidebar) throws -> T) rethrows -> T {
    try mutate(body, beforeDidChange: { _ in })
  }

  @discardableResult
  func mutate<T>(
    _ body: (inout SidebarModel.Sidebar) throws -> T, beforeDidChange: (T) -> Void
  ) rethrows -> T {
    var copy = sidebar
    let result = try body(&copy)
    guard copy != sidebar else { return result }
    let old = sidebar
    sidebar = copy
    for change in SidebarDiff.changes(from: old, to: copy) { hub.emit(change) }
    beforeDidChange(result)
    onDidChange?(copy)
    return result
  }
}
