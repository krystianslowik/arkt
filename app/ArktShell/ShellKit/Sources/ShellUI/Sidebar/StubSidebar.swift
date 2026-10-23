import Foundation

/// In-memory `SidebarSource` until Track B's `ArktCore` lands. Same storage shape as Track B's `Sidebar`:
/// `spaces`, `nodes`, `childOrder` keyed by location.
@MainActor
public final class StubSidebar: SidebarSource {
  private struct Node {
    var info: SidebarNodeInfo
    var parent: SidebarLocation
  }

  public private(set) var spaceOrder: [SpaceID] = []
  private var spaces: [SpaceID: SidebarSpaceInfo] = [:]
  private var nodes: [NodeID: Node] = [:]
  private var childOrder: [SidebarLocation: [NodeID]] = [:]
  private let hub = SidebarChangeHub()

  public init() {}

  public func space(_ id: SpaceID) -> SidebarSpaceInfo? { spaces[id] }
  public func children(of location: SidebarLocation) -> [NodeID] { childOrder[location] ?? [] }
  public func node(_ id: NodeID) -> SidebarNodeInfo? { nodes[id]?.info }
  public func parent(of id: NodeID) -> SidebarLocation? { nodes[id]?.parent }

  public func observe(_ handler: @escaping @MainActor (SidebarChange) -> Void) -> SidebarObservation {
    hub.observe(handler)
  }

  @discardableResult
  public func addSpace(title: String, profile: String = "default", theme: SpaceThemeInfo) -> SpaceID {
    let id = SpaceID()
    spaces[id] = SidebarSpaceInfo(id: id, title: title, profile: profile, theme: theme)
    spaceOrder.append(id)
    hub.emit(.spaces)
    return id
  }

  /// A Space with an empty light theme in the default profile (the `SidebarSource` requirement).
  @discardableResult
  public func addSpace(title: String) -> SpaceID {
    addSpace(title: title, theme: SpaceThemeInfo(baseColors: [], isDark: false))
  }

  /// Renames a Space. Emits `.spaces`.
  public func renameSpace(_ id: SpaceID, to title: String) {
    guard spaces[id] != nil else { return }
    spaces[id]?.title = title
    hub.emit(.spaces)
  }

  /// Replaces a Space's theme. Emits `.spaces`.
  public func setTheme(_ theme: SpaceThemeInfo, of id: SpaceID) {
    guard spaces[id] != nil else { return }
    spaces[id]?.theme = theme
    hub.emit(.spaces)
  }

  /// Removes a Space and every node under its pinned and Today sections. Emits only `.spaces`: the Space's pages
  /// go away with it, so no structure change is needed.
  public func removeSpace(_ id: SpaceID) {
    guard spaces.removeValue(forKey: id) != nil else { return }
    spaceOrder.removeAll { $0 == id }
    for section in [SidebarLocation.pinned(id), .today(id)] { removeSubtrees(at: section) }
    hub.emit(.spaces)
  }

  private func removeSubtrees(at location: SidebarLocation) {
    for child in childOrder.removeValue(forKey: location) ?? [] {
      if let inner = nodes.removeValue(forKey: child)?.info.childLocation { removeSubtrees(at: inner) }
    }
  }

  /// Removes a node and its subtree. Emits `.structure` for the location it was in.
  public func removeNode(_ id: NodeID) {
    guard let node = nodes.removeValue(forKey: id) else { return }
    if let inner = node.info.childLocation { removeSubtrees(at: inner) }
    childOrder[node.parent]?.removeAll { $0 == id }
    hub.emit(.structure(node.parent))
  }

  @discardableResult
  public func addTab(url: URL, title: String, in location: SidebarLocation) -> NodeID {
    let id = NodeID()
    insert(.tab(id: id, url: url, title: title), id: id, in: location)
    return id
  }

  @discardableResult
  public func addFolder(title: String, in location: SidebarLocation) -> NodeID {
    let id = NodeID()
    insert(.folder(id: id, title: title), id: id, in: location)
    return id
  }

  /// An empty split; add panes with `addTab(in: .split(id))`. Like the model's `insert`, that leaves `layout` as it
  /// is, so the default fits a two-pane split.
  @discardableResult
  public func addSplit(
    in location: SidebarLocation,
    layout: SplitLayoutInfo = SplitLayoutInfo(orientation: .horizontal, widthFactors: [0.5, 0.5])
  ) -> NodeID {
    let id = NodeID()
    insert(.split(id: id, layout: layout), id: id, in: location)
    return id
  }

  public func updateTab(_ id: NodeID, url: URL?, title: String?) {
    guard let node = nodes[id], case .tab(_, let oldURL, let oldTitle) = node.info else { return }
    nodes[id]?.info = .tab(id: id, url: url ?? oldURL, title: title ?? oldTitle)
    hub.emit(.node(id))
  }

  private func insert(_ info: SidebarNodeInfo, id: NodeID, in location: SidebarLocation) {
    nodes[id] = Node(info: info, parent: location)
    childOrder[location, default: []].append(id)
    hub.emit(.structure(location))
  }
}

// MARK: - Split writes

/// The same semantics as `ModelSidebarSource` over `Sidebar+Split`, with plain array operations. Every write runs in
/// `edit`, which restores the previous state on throw and emits the changed locations and nodes once.
extension StubSidebar {
  @discardableResult
  public func addToSplit(_ pane: SplitPaneSource, target: NodeID, at index: Int, orientation: SplitOrientation)
    throws -> (split: NodeID, pane: NodeID)
  {
    try edit {
      guard let targetNode = nodes[target] else { throw SplitEditError.invalid }
      let existingSplit: NodeID?
      switch (targetNode.info, targetNode.parent) {
      case (.split, _): existingSplit = target
      case (.tab, .split(let split)): existingSplit = split
      case (.tab, _): existingSplit = nil
      case (.folder, _): throw SplitEditError.invalid
      }
      let paneID: NodeID
      switch pane {
      case .existing(let id): paneID = id
      case .new(let url, let title):
        paneID = NodeID()
        // Next to the split (or the target), never inside it: the cap is checked when it moves in.
        let location = existingSplit.flatMap { nodes[$0]?.parent } ?? targetNode.parent
        nodes[paneID] = Node(info: .tab(id: paneID, url: url, title: title), parent: location)
        childOrder[location, default: []].append(paneID)
      }
      if let existingSplit {
        try addPane(paneID, to: existingSplit, at: index)
        return (existingSplit, paneID)
      }
      let split = try createSplit(of: [target, paneID], orientation: orientation)
      if index <= 0 { try movePane(paneID, toIndex: 0) }
      return (split, paneID)
    }
  }

  public func separatePane(_ pane: NodeID) throws {
    try edit {
      let (split, index) = try paneContext(pane)
      guard let splitParent = nodes[split]?.parent else { throw SplitEditError.invalid }
      let position = children(of: splitParent).firstIndex(of: split) ?? 0
      move(pane, to: splitParent, at: position + 1)
      shrinkSplit(split, removedIndex: index)
    }
  }

  @discardableResult
  public func separateSplit(_ split: NodeID) throws -> [NodeID] {
    try edit {
      _ = try layout(of: split)
      let panes = children(of: .split(split))
      dissolve(split, order: panes)
      return panes
    }
  }

  public func expandPane(_ pane: NodeID) throws {
    try edit {
      let (split, _) = try paneContext(pane)
      dissolve(split, order: [pane] + children(of: .split(split)).filter { $0 != pane })
    }
  }

  public func movePane(_ pane: NodeID, to index: Int) throws {
    try edit { try movePane(pane, toIndex: index) }
  }

  public func setSplitWidthFactors(_ split: NodeID, _ factors: [Double]) throws {
    try edit {
      var layout = try layout(of: split)
      let total = factors.reduce(0, +)
      guard factors.count == children(of: .split(split)).count, factors.allSatisfy({ $0.isFinite && $0 > 0 }),
        total.isFinite
      else { throw SplitEditError.invalid }
      layout.widthFactors = factors.map { $0 / total }
      setLayout(layout, of: split)
    }
  }

  public func setSplitOrientation(_ split: NodeID, _ orientation: SplitOrientation) throws {
    try edit {
      var layout = try layout(of: split)
      layout.orientation = orientation
      setLayout(layout, of: split)
    }
  }

  @discardableResult
  public func duplicateSplit(_ split: NodeID) throws -> NodeID {
    try edit {
      let layout = try layout(of: split)
      guard let parent = nodes[split]?.parent else { throw SplitEditError.invalid }
      let copy = NodeID()
      nodes[copy] = Node(info: .split(id: copy, layout: layout), parent: parent)
      let position = children(of: parent).firstIndex(of: split) ?? 0
      childOrder[parent, default: []].insert(copy, at: position + 1)
      for pane in children(of: .split(split)) {
        guard case .tab(_, let url, let title)? = nodes[pane]?.info else { continue }
        let id = NodeID()
        nodes[id] = Node(info: .tab(id: id, url: url, title: title), parent: .split(copy))
        childOrder[.split(copy), default: []].append(id)
      }
      return copy
    }
  }

  // MARK: Split helpers

  /// Runs `body`; on throw restores the nodes and child lists, otherwise emits every changed child list (sections
  /// first, then containers that still exist) and every node whose drawn fields changed.
  private func edit<T>(_ body: () throws -> T) throws -> T {
    let oldNodes = nodes
    let oldOrder = childOrder
    let result: T
    do { result = try body() } catch {
      nodes = oldNodes
      childOrder = oldOrder
      throw error
    }
    var sections: [SidebarChange] = []
    var containers: [SidebarChange] = []
    for location in Set(oldOrder.keys).union(childOrder.keys) where oldOrder[location] != childOrder[location] {
      if let container = location.containerNode {
        if nodes[container] != nil { containers.append(.structure(location)) }
      } else {
        sections.append(.structure(location))
      }
    }
    let changedNodes = nodes.compactMap { id, node in
      oldNodes[id].flatMap { $0.info != node.info ? SidebarChange.node(id) : nil }
    }
    for change in sections + containers + changedNodes { hub.emit(change) }
    return result
  }

  private func layout(of split: NodeID) throws -> SplitLayoutInfo {
    guard case .split(_, let layout)? = nodes[split]?.info else { throw SplitEditError.invalid }
    return layout
  }

  private func setLayout(_ layout: SplitLayoutInfo, of split: NodeID) {
    nodes[split]?.info = .split(id: split, layout: layout)
  }

  private static func equalShares(_ count: Int) -> [Double] {
    Array(repeating: 1 / Double(count), count: count)
  }

  /// The split holding `pane` and the pane's index in it.
  private func paneContext(_ pane: NodeID) throws -> (split: NodeID, index: Int) {
    guard case .split(let split)? = nodes[pane]?.parent, case .split? = nodes[split]?.info,
      let index = children(of: .split(split)).firstIndex(of: pane)
    else { throw SplitEditError.invalid }
    return (split, index)
  }

  /// `Sidebar.move`'s convention: `index` is measured before `id` leaves its place, and clamped.
  private func move(_ id: NodeID, to location: SidebarLocation, at index: Int) {
    guard let parent = nodes[id]?.parent else { return }
    var target = index
    if parent == location, let old = children(of: location).firstIndex(of: id), old < index { target -= 1 }
    childOrder[parent]?.removeAll { $0 == id }
    var siblings = childOrder[location] ?? []
    siblings.insert(id, at: min(max(target, 0), siblings.count))
    childOrder[location] = siblings
    nodes[id]?.parent = location
  }

  /// A new split at `tabs[0]`'s place holding `tabs` in order with equal shares (`Sidebar.createSplit`, for a first
  /// tab outside any split).
  private func createSplit(of tabs: [NodeID], orientation: SplitOrientation) throws -> NodeID {
    guard let first = tabs.first, let anchor = nodes[first]?.parent, Set(tabs).count == tabs.count,
      tabs.allSatisfy({ if case .tab? = nodes[$0]?.info { true } else { false } })
    else { throw SplitEditError.invalid }
    let split = NodeID()
    let layout = SplitLayoutInfo(orientation: orientation, widthFactors: Self.equalShares(tabs.count))
    nodes[split] = Node(info: .split(id: split, layout: layout), parent: anchor)
    let position = children(of: anchor).firstIndex(of: first) ?? 0
    childOrder[anchor, default: []].insert(split, at: position)
    for tab in tabs { takeTab(tab, into: split, at: children(of: .split(split)).count) }
    return split
  }

  /// `Sidebar.addPane`: a tab that is not yet a pane of `split` moves in at `index`; all shares become equal.
  private func addPane(_ tab: NodeID, to split: NodeID, at index: Int) throws {
    var layout = try layout(of: split)
    guard case .tab? = nodes[tab]?.info, nodes[tab]?.parent != .split(split) else { throw SplitEditError.invalid }
    guard children(of: .split(split)).count < SplitLayoutInfo.maximumPanes else { throw SplitEditError.splitFull }
    takeTab(tab, into: split, at: index)
    layout.widthFactors = Self.equalShares(children(of: .split(split)).count)
    setLayout(layout, of: split)
  }

  /// Moves `tab` into `split`; a tab leaving another split shrinks that split.
  private func takeTab(_ tab: NodeID, into split: NodeID, at index: Int) {
    var origin: (split: NodeID, index: Int?)?
    if case .split(let other)? = nodes[tab]?.parent, other != split {
      origin = (other, children(of: .split(other)).firstIndex(of: tab))
    }
    move(tab, to: .split(split), at: index)
    if let origin { shrinkSplit(origin.split, removedIndex: origin.index) }
  }

  private func movePane(_ pane: NodeID, toIndex index: Int) throws {
    let (split, oldIndex) = try paneContext(pane)
    var layout = try layout(of: split)
    move(pane, to: .split(split), at: index)
    guard let newIndex = children(of: .split(split)).firstIndex(of: pane),
      layout.widthFactors.indices.contains(oldIndex)
    else { return }
    let factor = layout.widthFactors.remove(at: oldIndex)
    layout.widthFactors.insert(factor, at: min(newIndex, layout.widthFactors.count))
    setLayout(layout, of: split)
  }

  /// `Sidebar.shrinkSplit`: a split left with no pane goes, one left with one pane is replaced by it, otherwise the
  /// removed pane's share goes and the others are rescaled to the old total.
  private func shrinkSplit(_ split: NodeID, removedIndex: Int?) {
    guard var layout = try? layout(of: split), let parent = nodes[split]?.parent else { return }
    let panes = children(of: .split(split))
    if panes.count <= 1 {
      if let survivor = panes.first {
        move(survivor, to: parent, at: children(of: parent).firstIndex(of: split) ?? 0)
      }
      return removeSplit(split)
    }
    guard let removedIndex, layout.widthFactors.indices.contains(removedIndex) else { return }
    let total = layout.widthFactors.reduce(0, +)
    layout.widthFactors.remove(at: removedIndex)
    let rest = layout.widthFactors.reduce(0, +)
    if rest > 0 { layout.widthFactors = layout.widthFactors.map { $0 * total / rest } }
    setLayout(layout, of: split)
  }

  /// The panes of `split` take its place in `order`; the split goes.
  private func dissolve(_ split: NodeID, order: [NodeID]) {
    guard let parent = nodes[split]?.parent else { return }
    let position = children(of: parent).firstIndex(of: split) ?? 0
    for (offset, pane) in order.enumerated() { move(pane, to: parent, at: position + offset) }
    removeSplit(split)
  }

  /// Removes an emptied split node and its child list.
  private func removeSplit(_ split: NodeID) {
    guard let parent = nodes.removeValue(forKey: split)?.parent else { return }
    childOrder[parent]?.removeAll { $0 == split }
    childOrder[.split(split)] = nil
  }
}

extension StubSidebar {
  /// Three Spaces (Arc-like palettes; Personal and Dev with grain), six shared favorites, per Space pinned tabs plus
  /// one folder with two tabs, and Today tabs (Work also holds a two-pane split). Titles are invented.
  public static func sample() -> StubSidebar {
    let s = StubSidebar()
    func url(_ string: String) -> URL { URL(string: string)! }
    let favorites: [(String, String)] = [
      ("https://example.com", "Example"),
      ("https://www.wikipedia.org", "Wikipedia"),
      ("https://news.ycombinator.com", "Hacker News"),
      ("https://github.com", "GitHub"),
      ("https://developer.apple.com", "Apple Developer"),
      ("https://www.swift.org", "Swift"),
    ]
    for (link, title) in favorites { s.addTab(url: url(link), title: title, in: .favorites(profile: "default")) }

    let personal = s.addSpace(title: "Personal", theme: SpaceThemeInfo(
      baseColors: [.p3(hex: 0xF2EAE4, alpha: 1), .p3(hex: 0xF29BBB, alpha: 1)], texture: "grain", noiseFactor: 0.5,
      isDark: false))
    let work = s.addSpace(title: "Work", theme: SpaceThemeInfo(
      baseColors: [.p3(hex: 0xE0F2FB, alpha: 1), .p3(hex: 0xC5C6E2, alpha: 1)], isDark: false))
    let dev = s.addSpace(title: "Dev", theme: SpaceThemeInfo(
      baseColors: [.p3(hex: 0x2D4468, alpha: 1), .p3(hex: 0x120F2E, alpha: 1)], texture: "grain", noiseFactor: 1,
      isDark: true))

    // Personal
    s.addTab(url: url("https://example.com/calendar"), title: "Family Calendar", in: .pinned(personal))
    s.addTab(url: url("https://example.com/mail"), title: "Inbox", in: .pinned(personal))
    let trips = s.addFolder(title: "Trips", in: .pinned(personal))
    s.addTab(url: url("https://example.com/lisbon"), title: "Lisbon Itinerary", in: .folder(trips))
    s.addTab(url: url("https://example.com/flights"), title: "Flight Options", in: .folder(trips))
    s.addTab(url: url("https://example.org"), title: "Weekend Recipes", in: .today(personal))
    s.addTab(url: url("https://example.net"), title: "Reading List", in: .today(personal))
    s.addTab(url: url("https://www.swift.org/blog"), title: "Swift Blog", in: .today(personal))

    // Work
    s.addTab(url: url("https://example.com/board"), title: "Sprint Board", in: .pinned(work))
    s.addTab(url: url("https://example.com/docs"), title: "Team Docs", in: .pinned(work))
    s.addTab(url: url("https://example.com/chat"), title: "Team Chat", in: .pinned(work))
    let specs = s.addFolder(title: "Specs", in: .pinned(work))
    s.addTab(url: url("https://example.com/spec-a"), title: "Sidebar Spec", in: .folder(specs))
    s.addTab(url: url("https://example.com/spec-b"), title: "Command Bar Spec", in: .folder(specs))
    s.addTab(url: url("https://example.com/review"), title: "Design Review", in: .today(work))
    let split = s.addSplit(in: .today(work))
    s.addTab(url: url("https://example.com/left"), title: "Notes", in: .split(split))
    s.addTab(url: url("https://example.com/right"), title: "Preview", in: .split(split))

    // Dev
    s.addTab(url: url("https://github.com/notifications"), title: "Notifications", in: .pinned(dev))
    s.addTab(url: url("https://developer.apple.com/documentation/appkit"), title: "AppKit Docs", in: .pinned(dev))
    let refs = s.addFolder(title: "References", in: .pinned(dev))
    s.addTab(url: url("https://www.swift.org/documentation"), title: "Swift Docs", in: .folder(refs))
    s.addTab(url: url("https://developer.apple.com/documentation/quartzcore"), title: "Core Animation",
             in: .folder(refs))
    s.addTab(url: url("https://example.com/ci"), title: "CI Dashboard", in: .today(dev))
    s.addTab(url: url("https://example.com/pr"), title: "Open Pull Request", in: .today(dev))
    s.addTab(url: url("https://example.com/logs"), title: "Crash Logs", in: .today(dev))
    s.addTab(url: url("https://example.com/perf"), title: "Frame Timings", in: .today(dev))
    return s
  }
}
