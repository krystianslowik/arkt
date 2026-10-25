import Foundation

public enum SidebarModelVersion { public static let current = 1 }

public typealias NodeID = UUID
public typealias SpaceID = UUID

public struct RGBA: Hashable, Sendable, Codable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}

public struct SpaceTheme: Hashable, Sendable, Codable {
  public var baseColors: [RGBA]
  public var overlayColors: [RGBA]
  public var texture: String?
  public var isDark: Bool

  public init(baseColors: [RGBA], overlayColors: [RGBA] = [], texture: String? = nil, isDark: Bool = false) {
    self.baseColors = baseColors
    self.overlayColors = overlayColors
    self.texture = texture
    self.isDark = isDark
  }
}

/// A Space's icon (BH-034): an SF Symbol name such as "star", or one emoji (a single extended grapheme cluster; the
/// shell validates it before writing). Nil means the dock draws a dot.
///
/// On disk (storage format 2): `{"type": "symbol", "symbol": "star"}` or `{"type": "emoji", "emoji": "..."}`. An
/// unknown `type` fails to decode, like an unknown node type.
public enum SpaceIcon: Hashable, Sendable {
  case symbol(String)
  case emoji(String)
}

extension SpaceIcon: Codable {
  private enum CodingKeys: String, CodingKey { case type, symbol, emoji }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "symbol": self = .symbol(try container.decode(String.self, forKey: .symbol))
    case "emoji": self = .emoji(try container.decode(String.self, forKey: .emoji))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container, debugDescription: "Unknown Space icon type \(type)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .symbol(let name):
      try container.encode("symbol", forKey: .type)
      try container.encode(name, forKey: .symbol)
    case .emoji(let emoji):
      try container.encode("emoji", forKey: .type)
      try container.encode(emoji, forKey: .emoji)
    }
  }
}

public struct Space: Hashable, Sendable, Codable, Identifiable {
  public var id: SpaceID
  public var title: String
  public var profile: String
  public var theme: SpaceTheme?
  public var icon: SpaceIcon?

  public init(
    id: SpaceID = SpaceID(), title: String, profile: String = "default", theme: SpaceTheme? = nil,
    icon: SpaceIcon? = nil
  ) {
    self.id = id
    self.title = title
    self.profile = profile
    self.theme = theme
    self.icon = icon
  }
}

public struct TabItem: Hashable, Sendable, Codable {
  public var url: URL
  public var title: String
  public var customTitle: String?
  public var lastActiveAt: Date?

  public init(url: URL, title: String, customTitle: String? = nil, lastActiveAt: Date? = nil) {
    self.url = url
    self.title = title
    self.customTitle = customTitle
    self.lastActiveAt = lastActiveAt
  }
}

public struct FolderItem: Hashable, Sendable, Codable {
  public var title: String

  public init(title: String) { self.title = title }
}

public enum Orientation: String, Hashable, Sendable, Codable {
  case horizontal
  case vertical
}

public struct SplitItem: Hashable, Sendable, Codable {
  public var orientation: Orientation
  public var widthFactors: [Double]

  public init(orientation: Orientation, widthFactors: [Double]) {
    self.orientation = orientation
    self.widthFactors = widthFactors
  }
}

public enum NodeKind: Hashable, Sendable {
  case tab(TabItem)
  case folder(FolderItem)
  case split(SplitItem)
}

/// Where a node lives: a top-level section of the sidebar or inside a container node.
public enum Location: Hashable, Sendable {
  case favorites(profile: String)
  case pinned(SpaceID)
  case today(SpaceID)
  case folder(NodeID)
  case split(NodeID)

  /// The node that owns this location, if it is a container node.
  public var containerNode: NodeID? {
    switch self {
    case .folder(let id), .split(let id): id
    case .favorites, .pinned, .today: nil
    }
  }
}

public struct Node: Hashable, Sendable, Identifiable {
  public var id: NodeID
  public var kind: NodeKind
  public var parent: Location
  public var createdAt: Date

  public init(id: NodeID = NodeID(), kind: NodeKind, parent: Location, createdAt: Date = .now) {
    self.id = id
    self.kind = kind
    self.parent = parent
    self.createdAt = createdAt
  }
}

public enum SidebarError: Error, Hashable, Sendable {
  case unknownNode(NodeID)
  /// The location does not exist or cannot hold this kind of node: `pinned`/`today` need an existing space,
  /// `folder` needs a folder node, and `split` needs a split node and accepts only tabs.
  case invalidDestination(Location)
  /// The destination is the moved node itself or one of its descendants.
  case cycle
  /// A space or node with this id already exists (or appears twice in an inserted snapshot).
  case duplicateID(UUID)
  /// Placing this node (with its subtree) would nest deeper than `Sidebar.maximumNestingDepth`. For a new node from
  /// `addFolder`/`addTab`/`addSplit` it is the new node's id, for `move` the moved node, for `insert` the first node
  /// of the snapshot that would land too deep.
  case nestingTooDeep(NodeID)
  /// The split already holds `Sidebar.maximumSplitPanes` panes (BH-116, CF-06). Carries the split's id.
  case splitFull(NodeID)
  /// A split operation got input it cannot apply: a wrong pane count, a node that is not a tab (or not a split, or
  /// not a pane), a repeated id, or bad width factors. Carries the offending node, or the split for bad factors.
  case invalidSplit(NodeID)
}

/// Arkt's sidebar: spaces plus a forest of tab, folder and split nodes, as a value type.
public struct Sidebar: Hashable, Sendable {
  /// The deepest a node may sit: a node directly in a section (Favorites, Pinned, Today) has depth 1, its children
  /// depth 2, and so on; tabs inside a split count too. Every mutation enforces it, so any sidebar the model holds can
  /// be stored and loaded again, and recursion over a tree is bounded.
  public static let maximumNestingDepth = 32

  /// The most panes a split holds (CF-06). The split operations and `move` into a split enforce it; `insert` does
  /// not, so stored and imported trees with more panes still load.
  public static let maximumSplitPanes = 4

  public private(set) var spaces: [SpaceID: Space] = [:]
  public private(set) var spaceOrder: [SpaceID] = []
  public private(set) var nodes: [NodeID: Node] = [:]
  public private(set) var childOrder: [Location: [NodeID]] = [:]

  public init() {}

  @discardableResult
  public mutating func addSpace(title: String, profile: String = "default", theme: SpaceTheme? = nil) -> SpaceID {
    let space = Space(title: title, profile: profile, theme: theme)
    spaces[space.id] = space
    spaceOrder.append(space.id)
    return space.id
  }

  /// Adds `space` keeping its id, for decoding and restore. Throws `.duplicateID` if the id is taken.
  public mutating func addSpace(_ space: Space) throws {
    guard spaces[space.id] == nil else { throw SidebarError.duplicateID(space.id) }
    spaces[space.id] = space
    spaceOrder.append(space.id)
  }

  /// Sets Space `id`'s title (BH-038). An unknown `id` is a silent no-op, like `removeSpace(_:)`.
  public mutating func renameSpace(_ id: SpaceID, to title: String) {
    guard spaces[id] != nil else { return }
    spaces[id]?.title = title
  }

  /// Sets Space `id`'s icon (BH-034). Nil clears it. An unknown `id`, or the icon it already has, changes nothing.
  public mutating func setIcon(_ id: SpaceID, to icon: SpaceIcon?) {
    guard var space = spaces[id], space.icon != icon else { return }
    space.icon = icon
    spaces[id] = space
  }

  /// Sets Space `id`'s theme (BH-034). Nil clears it. An unknown `id`, or the theme it already has, changes nothing.
  public mutating func setTheme(_ id: SpaceID, to theme: SpaceTheme?) {
    guard var space = spaces[id], space.theme != theme else { return }
    space.theme = theme
    spaces[id] = space
  }

  /// Moves Space `id` so that it lands at `index`, measured before it is removed (the `move(_:to:at:)` convention),
  /// clamped to the order (BH-039). Its sections go with it. An unknown `id` is a silent no-op.
  public mutating func moveSpace(_ id: SpaceID, to index: Int) {
    guard let old = spaceOrder.firstIndex(of: id) else { return }
    spaceOrder.remove(at: old)
    let target = old < index ? index - 1 : index
    spaceOrder.insert(id, at: min(max(target, 0), spaceOrder.count))
  }

  /// Removes Space `id` with every node in its Pinned and Today sections; Favorites belong to the profile and stay.
  /// An unknown `id` is a silent no-op, like `remove(_:)`. Archiving the Space's items first is the caller's job
  /// (`Archiver.removeSpace`).
  public mutating func removeSpace(_ id: SpaceID) {
    guard spaces.removeValue(forKey: id) != nil else { return }
    spaceOrder.removeAll { $0 == id }
    for section in [Location.pinned(id), .today(id)] {
      for child in childOrder.removeValue(forKey: section) ?? [] { removeSubtree(child) }
    }
  }

  @discardableResult
  public mutating func addFolder(title: String, in location: Location, createdAt: Date = .now) throws -> NodeID {
    try insert(.folder(FolderItem(title: title)), in: location, createdAt: createdAt)
  }

  @discardableResult
  public mutating func addTab(
    url: URL,
    title: String,
    customTitle: String? = nil,
    lastActiveAt: Date? = nil,
    in location: Location,
    createdAt: Date = .now
  ) throws -> NodeID {
    let tab = TabItem(url: url, title: title, customTitle: customTitle, lastActiveAt: lastActiveAt)
    return try insert(.tab(tab), in: location, createdAt: createdAt)
  }

  @discardableResult
  public mutating func addSplit(
    orientation: Orientation,
    widthFactors: [Double],
    in location: Location,
    createdAt: Date = .now
  ) throws -> NodeID {
    let split = SplitItem(orientation: orientation, widthFactors: widthFactors)
    return try insert(.split(split), in: location, createdAt: createdAt)
  }

  public func children(of location: Location) -> [NodeID] {
    childOrder[location] ?? []
  }

  /// Moves `id` into `location` so that it lands at `index`.
  ///
  /// `index` is the proposed position measured BEFORE the node is removed from its current place, the same
  /// convention as `Array.move(fromOffsets:toOffset:)` and `NSOutlineView` drops: in `[x, y, z]`, moving `x` to 2
  /// gives `[y, x, z]` and moving `x` to 3 gives `[y, z, x]`. Out-of-range indexes are clamped.
  ///
  /// Throws `SidebarError.unknownNode` for an unknown `id`, `.invalidDestination` when `location` cannot hold the
  /// node, `.cycle` when `location` is the node itself or inside its subtree, and `.splitFull` when `location` is a
  /// split that already holds `maximumSplitPanes` other panes. The sidebar is unchanged on throw.
  public mutating func move(_ id: NodeID, to location: Location, at index: Int) throws {
    guard let node = nodes[id] else { throw SidebarError.unknownNode(id) }
    try validate(location, accepting: node.kind)
    if case .split(let split) = location, node.parent != location,
      children(of: location).count >= Self.maximumSplitPanes
    {
      throw SidebarError.splitFull(split)
    }
    if isInSubtree(location, of: id) { throw SidebarError.cycle }
    if depth(ofChildIn: location) + height(of: id) - 1 > Self.maximumNestingDepth {
      throw SidebarError.nestingTooDeep(id)
    }
    var target = index
    if node.parent == location, let oldIndex = childOrder[location]?.firstIndex(of: id), oldIndex < index {
      target -= 1
    }
    detach(id, from: node.parent)
    var siblings = childOrder[location] ?? []
    siblings.insert(id, at: min(max(target, 0), siblings.count))
    childOrder[location] = siblings
    nodes[id]?.parent = location
  }

  /// Removes `id` and all of its descendants, and detaches it from its parent.
  /// An unknown `id` is a silent no-op, deliberately, so UI deletes of already-gone nodes need no special casing.
  public mutating func remove(_ id: NodeID) {
    guard let node = nodes[id] else { return }
    detach(id, from: node.parent)
    removeSubtree(id)
  }

  /// Removes a split pane and shrinks its split (user decision 4, PARITY(NEEDS-RUNTIME-CHECK BH-123)): the pane's
  /// width factor goes and the others are rescaled to the old total; a split left with one pane is replaced by that
  /// tab (same id) at the split's position, and a split left with none is removed. For a node that is not a pane this
  /// is `remove(_:)`; an unknown `id` is a no-op.
  public mutating func removePane(_ id: NodeID) {
    guard case .split(let splitID)? = nodes[id]?.parent, case .split? = nodes[splitID]?.kind,
      nodes[splitID]?.parent != nil
    else { return remove(id) }
    let index = children(of: .split(splitID)).firstIndex(of: id)
    remove(id)
    shrinkSplit(splitID, removedIndex: index)
  }

  /// Shrinks `splitID` after one of its panes left it (removed or moved out); `removedIndex` is where that pane was.
  /// A split left with no pane is removed; one left with one pane is replaced by that tab (same id) at the split's
  /// position; otherwise the removed pane's width factor goes and the others are rescaled to the old total.
  mutating func shrinkSplit(_ splitID: NodeID, removedIndex: Int?) {
    guard case .split(var split)? = nodes[splitID]?.kind, let splitParent = nodes[splitID]?.parent else { return }
    let panes = children(of: .split(splitID))
    guard let survivor = panes.first else { return remove(splitID) }
    if panes.count == 1 {
      let position = children(of: splitParent).firstIndex(of: splitID) ?? 0
      // The parent already holds the split, so a tab is valid there and lands shallower: `move` cannot throw here.
      guard (try? move(survivor, to: splitParent, at: position)) != nil else { return }
      return remove(splitID)
    }
    if let removedIndex, split.widthFactors.indices.contains(removedIndex) {
      let total = split.widthFactors.reduce(0, +)
      split.widthFactors.remove(at: removedIndex)
      let rest = split.widthFactors.reduce(0, +)
      if rest > 0 { split.widthFactors = split.widthFactors.map { $0 * total / rest } }
      nodes[splitID]?.kind = .split(split)
    }
  }

  /// Replaces the payload of split `id`; a no-op when `id` is not a split. For the split operations in
  /// `Sidebar+Split.swift`, which cannot write `nodes` from another file.
  mutating func setSplitItem(_ id: NodeID, _ item: SplitItem) {
    guard case .split? = nodes[id]?.kind else { return }
    nodes[id]?.kind = .split(item)
  }

  /// Changes a tab's own fields; nil leaves a field as it is. Throws `.unknownNode` when `id` is not a tab (unknown
  /// ids and folders or splits alike); the sidebar is unchanged on throw. Never moves the node.
  public mutating func updateTab(_ id: NodeID, url: URL? = nil, title: String? = nil, lastActiveAt: Date? = nil) throws {
    guard case .tab(var tab)? = nodes[id]?.kind else { throw SidebarError.unknownNode(id) }
    if let url { tab.url = url }
    if let title { tab.title = title }
    if let lastActiveAt { tab.lastActiveAt = lastActiveAt }
    nodes[id]?.kind = .tab(tab)
  }

  /// The subtree rooted at `id`, in child order, or nil for an unknown id.
  public func snapshot(of id: NodeID) -> NodeSnapshot? {
    guard let node = nodes[id] else { return nil }
    let childLocation: Location? = switch node.kind {
    case .folder: .folder(id)
    case .split: .split(id)
    case .tab: nil
    }
    let children = childLocation.map { self.children(of: $0).compactMap { snapshot(of: $0) } } ?? []
    return NodeSnapshot(id: id, kind: node.kind, createdAt: node.createdAt, children: children)
  }

  /// The top-level section (`.favorites`, `.pinned`, `.today`) that holds `id`, directly or through folders and
  /// splits. Nil for an unknown id, or when the parent chain is dangling (a container id with no node), which the
  /// model's own mutations never produce.
  public func section(of id: NodeID) -> Location? {
    var location = nodes[id]?.parent
    while let current = location, let container = current.containerNode {
      location = nodes[container]?.parent
    }
    return location
  }

  /// Inserts `snapshot` with its whole subtree into `location`, keeping every id and `createdAt`.
  /// `index` follows `Array.insert` (clamped); nil appends.
  /// Throws `.duplicateID` when an id is already used or repeats inside the snapshot, `.invalidDestination` when a
  /// node cannot live where it would land (same rules as `move`; children under a tab report `.folder(tabID)`), and
  /// `.nestingTooDeep` for the first node that would sit deeper than `maximumNestingDepth`.
  /// The sidebar is unchanged on throw.
  public mutating func insert(_ snapshot: NodeSnapshot, in location: Location, at index: Int? = nil) throws {
    var copy = self
    try copy.insertTree(snapshot, in: location, depth: copy.depth(ofChildIn: location))
    if let index, var siblings = copy.childOrder[location] {
      siblings.removeLast()
      siblings.insert(snapshot.id, at: min(max(index, 0), siblings.count))
      copy.childOrder[location] = siblings
    }
    self = copy
  }

  /// `depth` is the depth `snapshot` lands at; checking it per node stops the recursion at the cap.
  private mutating func insertTree(_ snapshot: NodeSnapshot, in location: Location, depth: Int) throws {
    guard nodes[snapshot.id] == nil else { throw SidebarError.duplicateID(snapshot.id) }
    try validate(location, accepting: snapshot.kind)
    guard depth <= Self.maximumNestingDepth else { throw SidebarError.nestingTooDeep(snapshot.id) }
    nodes[snapshot.id] = Node(id: snapshot.id, kind: snapshot.kind, parent: location, createdAt: snapshot.createdAt)
    childOrder[location, default: []].append(snapshot.id)
    // A tab has no child location; `.folder(tabID)` fails validation, which is the error we want.
    let childLocation: Location = if case .split = snapshot.kind { .split(snapshot.id) } else { .folder(snapshot.id) }
    for child in snapshot.children { try insertTree(child, in: childLocation, depth: depth + 1) }
  }

  private func validate(_ location: Location, accepting kind: NodeKind) throws {
    let isValid: Bool
    switch location {
    case .favorites:
      isValid = true
    case .pinned(let space), .today(let space):
      isValid = spaces[space] != nil
    case .folder(let id):
      if case .folder = nodes[id]?.kind { isValid = true } else { isValid = false }
    case .split(let id):
      if case .split = nodes[id]?.kind, case .tab = kind { isValid = true } else { isValid = false }
    }
    if !isValid { throw SidebarError.invalidDestination(location) }
  }

  mutating func insert(_ kind: NodeKind, in location: Location, createdAt: Date) throws -> NodeID {
    try validate(location, accepting: kind)
    let node = Node(kind: kind, parent: location, createdAt: createdAt)
    guard depth(ofChildIn: location) <= Self.maximumNestingDepth else { throw SidebarError.nestingTooDeep(node.id) }
    nodes[node.id] = node
    childOrder[location, default: []].append(node.id)
    return node.id
  }

  private mutating func detach(_ id: NodeID, from location: Location) {
    guard var siblings = childOrder[location] else { return }
    siblings.removeAll { $0 == id }
    childOrder[location] = siblings.isEmpty ? nil : siblings
  }

  private mutating func removeSubtree(_ id: NodeID) {
    for location in [Location.folder(id), .split(id)] {
      for child in childOrder.removeValue(forKey: location) ?? [] {
        removeSubtree(child)
      }
    }
    nodes[id] = nil
  }

  /// The depth a node placed directly in `location` would have: 1 in a section, one more than its container otherwise.
  private func depth(ofChildIn location: Location) -> Int {
    var depth = 1
    var current = location.containerNode
    while let id = current, let node = nodes[id] {
      depth += 1
      current = node.parent.containerNode
    }
    return depth
  }

  /// Levels in the subtree rooted at `id`: 1 for a leaf.
  private func height(of id: NodeID) -> Int {
    let children = children(of: .folder(id)) + children(of: .split(id))
    return 1 + (children.map { height(of: $0) }.max() ?? 0)
  }

  private func isInSubtree(_ location: Location, of root: NodeID) -> Bool {
    var current = location.containerNode
    while let id = current {
      if id == root { return true }
      current = nodes[id]?.parent.containerNode
    }
    return false
  }
}
