import Foundation

/// Which rows the folders of one outline show (#109). Per window (BH-098): every outline keeps its own.
///
/// An open folder shows every child. A closed one shows only the rows peeking out of it: a tab moved into it
/// (BH-092), the tab chosen in Folder Preview (BH-093) or switched to from elsewhere (BH-105), with the path of
/// folders down to it. A folder whose close spring still runs (`closing`) shows everything until it settles, so the
/// rows can slide away and a reversal finds them in place. Splits always show their panes.
struct FolderDisplay: Equatable {
  /// Folders the user closed in this outline.
  var collapsed: Set<NodeID> = []
  /// Closed folders still showing their rows while their close spring runs.
  var closing: Set<NodeID> = []
  /// Rows shown under a closed folder: tabs, or a split for its panes (`peekRoot`).
  var peeks: Set<NodeID> = []

  /// The same state with every close spring settled.
  var settled: FolderDisplay {
    var copy = self
    copy.closing = []
    return copy
  }

  /// Whether `folder` shows its own rows: not closed (or still closing) itself.
  func isOpen(_ folder: NodeID) -> Bool {
    !collapsed.contains(folder) || closing.contains(folder)
  }

  /// Whether `container` shows all of its children: it is open and every folder around it is too. A split counts
  /// as open; its folders decide.
  @MainActor func isEffectivelyOpen(_ container: NodeID, in source: any SidebarSource) -> Bool {
    var current: NodeID? = container
    for _ in 0..<Self.depthGuard {
      guard let id = current else { return true }
      if case .folder? = source.node(id), !isOpen(id) { return false }
      current = source.parent(of: id)?.containerNode
    }
    return false
  }

  /// The children `container` shows, in order.
  @MainActor func children(of container: NodeID, in source: any SidebarSource) -> [NodeID] {
    guard let location = source.node(container)?.childLocation else { return [] }
    let all = source.children(of: location)
    if case .split = location { return all }
    if isEffectivelyOpen(container, in: source) { return all }
    return all.filter { holdsPeek($0, in: source, depth: 0) }
  }

  /// Every row under `container`, depth first, as the outline lists them.
  @MainActor func descendants(of container: NodeID, in source: any SidebarSource) -> [NodeID] {
    var rows: [NodeID] = []
    collect(container, into: &rows, in: source, depth: 0)
    return rows
  }

  /// Whether `node` has no row: some folder above it is closed and nothing makes it peek out.
  @MainActor func isHidden(_ node: NodeID, in source: any SidebarSource) -> Bool {
    var child = node
    for _ in 0..<Self.depthGuard {
      guard let container = source.parent(of: child)?.containerNode else { return false }
      if !children(of: container, in: source).contains(child) { return true }
      child = container
    }
    return true
  }

  /// The row that peeks for `tab`: its split when it is a pane, else the tab.
  @MainActor static func peekRoot(of tab: NodeID, in source: any SidebarSource) -> NodeID {
    if case .split(let split)? = source.parent(of: tab) { return split }
    return tab
  }

  @MainActor private func collect(_ container: NodeID, into rows: inout [NodeID], in source: any SidebarSource, depth: Int) {
    guard depth < Self.depthGuard else { return }
    for child in children(of: container, in: source) {
      rows.append(child)
      collect(child, into: &rows, in: source, depth: depth + 1)
    }
  }

  @MainActor private func holdsPeek(_ node: NodeID, in source: any SidebarSource, depth: Int) -> Bool {
    if peeks.contains(node) { return true }
    guard depth < Self.depthGuard, let location = source.node(node)?.childLocation else { return false }
    return source.children(of: location).contains { holdsPeek($0, in: source, depth: depth + 1) }
  }

  /// Bounds every walk against a malformed source (the model caps nesting at 32).
  private static let depthGuard = 64
}
