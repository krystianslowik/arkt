import Foundation

/// The two Settings > Appearance switches that decide how Cmd-1 ... Cmd-9 count (BH-014, BH-015). The Settings window
/// does not exist yet; every window uses these defaults until it does.
public struct TabNavigationSettings: Equatable, Sendable {
  /// "Count Favorites in Command-1 to Command-8" (Arc: `excludeFavoritesInSwitchToNthTab` inverted), on by default.
  public var countsFavorites = true
  /// "Command-9 opens the ninth tab" (Arc: `switchToNinthSidebarItemEnabled`), off by default: Cmd-9 opens the last
  /// item (CF-07).
  public var ninthOpensNinth = false

  public init() {}
}

/// The sidebar items the keyboard steps through, in displayed order: Favorites, then the current Space's Pinned, then
/// its Today items (BH-014, BH-016). Folders are not items: an open folder contributes its items in place, a
/// collapsed one none [I]. A split is one item (activating it focuses its last focused pane).
///
/// BH-017 (a collapsed Pinned section is skipped) has nothing to skip yet: Arkt's Pinned section does not collapse.
@MainActor
public struct SidebarTabOrder {
  /// What Cmd-N, Cmd-Opt-Down and Cmd-Opt-Up can land on.
  public let items: [NodeID]
  /// Every tab and split under the same roots, collapsed folders included, by display position. Places a current tab
  /// hidden in a collapsed folder between the items around that folder.
  private let rank: [NodeID: Int]
  private let parent: (NodeID) -> SidebarLocation?

  public init(source: any SidebarSource, profile: String, space: SpaceID?, includeFavorites: Bool,
              collapsedFolders: Set<NodeID>) {
    var roots: [SidebarLocation] = includeFavorites ? [.favorites(profile: profile)] : []
    if let space { roots += [.pinned(space), .today(space)] }
    var items: [NodeID] = []
    var rank: [NodeID: Int] = [:]
    func walk(_ location: SidebarLocation, visible: Bool, depth: Int) {
      guard depth < 64 else { return }                  // depth guard against a malformed source
      for child in source.children(of: location) {
        switch source.node(child) {
        case .tab?, .split?:
          rank[child] = rank.count
          if visible { items.append(child) }
        case .folder?:
          walk(.folder(child), visible: visible && !collapsedFolders.contains(child), depth: depth + 1)
        case nil:
          break
        }
      }
    }
    for root in roots { walk(root, visible: true, depth: 0) }
    self.items = items
    self.rank = rank
    self.parent = { source.parent(of: $0) }
  }

  /// A fixed list of items, for tests of the numbering rules.
  init(items: [NodeID]) {
    self.items = items
    rank = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1, $0) })
    parent = { _ in nil }
  }

  /// Cmd-1 ... Cmd-8 open item `number`; Cmd-9 opens the last item, or the ninth with `ninthOpensNinth`. Nil past the
  /// end (nothing happens).
  public func item(number: Int, settings: TabNavigationSettings) -> NodeID? {
    if number == 9, !settings.ninthOpensNinth { return items.last }
    guard (1...9).contains(number), items.indices.contains(number - 1) else { return nil }
    return items[number - 1]
  }

  /// Cmd-Opt-Down (`forward`) / Cmd-Opt-Up from `current`: the next or previous item, nil at the ends (no wrap,
  /// PARITY(NEEDS-RUNTIME-CHECK): Arc's behavior at the ends). A pane counts as its split. Without a current item,
  /// forward starts at the first item and backward at the last.
  public func neighbour(of current: NodeID?, forward: Bool) -> NodeID? {
    guard let current, let position = position(of: current) else { return forward ? items.first : items.last }
    if forward { return items.first { (rank[$0] ?? -1) > position } }
    return items.last { (rank[$0] ?? Int.max) < position }
  }

  private func position(of node: NodeID) -> Int? {
    if case .split(let split)? = parent(node), let position = rank[split] { return position }
    return rank[node]
  }
}
