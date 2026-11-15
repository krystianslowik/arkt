import Foundation

/// A page outside the sidebar that the shell can offer after an unclean exit.
public struct ShellRecoveryPage: Equatable, Sendable {
  public enum Kind: Equatable, Sendable { case littleArkt, peek }
  public var title: String
  public var url: URL
  public var kind: Kind
  public var sourceNode: NodeID?

  public init(title: String, url: URL, kind: Kind, sourceNode: NodeID? = nil) {
    self.title = title
    self.url = url
    self.kind = kind
    self.sourceNode = sourceNode
  }
}

/// The App owns storage and makes writes ordered and durable off the main actor.
@MainActor
public protocol RecoveryPageSource: AnyObject {
  var pages: [ShellRecoveryPage] { get set }
}

/// Selects the records the restored sidebar can support, keeping the last Peek for each source.
@MainActor
func eligibleRecoveryPages(_ pages: [ShellRecoveryPage], sidebar: any SidebarSource) -> [ShellRecoveryPage] {
  var seen = Set<NodeID>()
  return Array(pages.reversed().filter { page in
    guard page.kind == .peek else { return true }
    guard let node = page.sourceNode, case .tab? = sidebar.node(node), sidebar.parent(of: node) != nil else {
      return false
    }
    return seen.insert(node).inserted
  }.reversed())
}
