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
    return id
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

  @discardableResult
  public func addSplit(in location: SidebarLocation) -> NodeID {
    let id = NodeID()
    insert(.split(id: id), id: id, in: location)
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
