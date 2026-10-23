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
  @discardableResult
  public func addTab(url: URL, title: String, in location: SidebarLocation) throws -> UUID {
    let createdAt = now()
    return try mutate {
      try $0.addTab(
        url: url, title: title, lastActiveAt: createdAt, in: BridgeMapping.location(location), createdAt: createdAt)
    }
  }

  @discardableResult
  public func addSpace(title: String) throws -> UUID {
    mutate { $0.addSpace(title: title, profile: defaultProfile) }
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

  // MARK: - Archive

  /// Archives nodes through `Archiver` and returns the entries in the order of `ids`; all of them leave the value in
  /// one mutation (one `onDidChange`). Unknown ids are skipped. Which nodes may be archived is the caller's decision.
  public func archive(_ ids: [UUID], reason: ArchiveReason, at date: Date) -> [ArchivedItem] {
    mutate { sidebar in ids.compactMap { try? Archiver.archive($0, from: &sidebar, reason: reason, at: date) } }
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
    var copy = sidebar
    let result = try body(&copy)
    guard copy != sidebar else { return result }
    let old = sidebar
    sidebar = copy
    for change in SidebarDiff.changes(from: old, to: copy) { hub.emit(change) }
    onDidChange?(copy)
    return result
  }
}
