import Foundation

public typealias SpaceID = UUID
public typealias NodeID = UUID

/// Mirrors Track B's `SidebarModel.Location` so the later adapter is mechanical.
public enum SidebarLocation: Hashable, Sendable {
  case favorites(profile: String)
  case pinned(SpaceID)
  case today(SpaceID)
  case folder(NodeID)
  case split(NodeID)

  /// The node that owns this location, if it is a container node (Track B: `Location.containerNode`).
  public var containerNode: NodeID? {
    switch self {
    case .folder(let id), .split(let id): id
    case .favorites, .pinned, .today: nil
    }
  }
}

/// Mirrors Track B's `SpaceTheme` plus Arc's `Modifiers.noiseFactor`.
public struct SpaceThemeInfo: Equatable, Sendable {
  /// Gradient stops, top-left to bottom-right (Track B: `SpaceTheme.baseColors`).
  public var baseColors: [RGBA]
  /// Arc's second gradient layer (Track B: `SpaceTheme.overlayColors`). Not rendered yet.
  public var overlayColors: [RGBA]
  /// Tiled overlay texture: "grain", "sand", "denim" or "tweed" (Track B: `SpaceTheme.texture`).
  /// The Core Animation renderer draws every texture as grain.
  public var texture: String?
  /// Texture strength 0...1 (Arc: `Modifiers.noiseFactor`).
  public var noiseFactor: Double
  public var isDark: Bool
  public var flavor: ThemeFlavor { isDark ? .dark : .light }

  public init(baseColors: [RGBA], overlayColors: [RGBA] = [], texture: String? = nil, noiseFactor: Double = 0,
              isDark: Bool) {
    self.baseColors = baseColors; self.overlayColors = overlayColors
    self.texture = texture; self.noiseFactor = noiseFactor; self.isDark = isDark
  }

  /// Opacity of the texture layer for this theme (0 without a texture).
  public var textureOpacity: Double {
    texture == nil ? 0 : min(max(noiseFactor, 0), 1) * ShellTokens.themeTextureMaxOpacity
  }
}

public struct SidebarSpaceInfo: Equatable, Sendable {
  public var id: SpaceID
  public var title: String
  public var profile: String
  public var theme: SpaceThemeInfo

  public init(id: SpaceID, title: String, profile: String, theme: SpaceThemeInfo) {
    self.id = id; self.title = title; self.profile = profile; self.theme = theme
  }
}

/// Track B's `NodeKind` flattened to what the sidebar draws (TabItem / FolderItem / SplitItem).
public enum SidebarNodeInfo: Equatable, Sendable {
  case tab(id: NodeID, url: URL, title: String)
  case folder(id: NodeID, title: String)
  case split(id: NodeID)

  public var id: NodeID {
    switch self {
    case .tab(let id, _, _), .folder(let id, _), .split(let id): id
    }
  }

  /// The location holding this node's children, nil for leaves.
  public var childLocation: SidebarLocation? {
    switch self {
    case .tab: nil
    case .folder(let id, _): .folder(id)
    case .split(let id): .split(id)
    }
  }
}

/// What the shell needs from a sidebar store. Implemented by StubSidebar now and by an adapter over
/// Track B's `Sidebar` value type later (out of scope here).
@MainActor
public protocol SidebarSource: AnyObject {
  var spaceOrder: [SpaceID] { get }
  func space(_ id: SpaceID) -> SidebarSpaceInfo?
  func children(of location: SidebarLocation) -> [NodeID]
  func node(_ id: NodeID) -> SidebarNodeInfo?
  /// The location that holds `id` (Track B: `Node.parent`).
  func parent(of id: NodeID) -> SidebarLocation?
  /// Throws when the model refuses the location (unknown Space, too deep). `StubSidebar` never throws.
  @discardableResult func addTab(url: URL, title: String, in location: SidebarLocation) throws -> NodeID
  /// A new Space for this source's default profile, appended to `spaceOrder`. Emits `.spaces`.
  @discardableResult func addSpace(title: String) throws -> SpaceID
  func updateTab(_ id: NodeID, url: URL?, title: String?)
  /// Ordered, synchronous delivery of every change to every live observer.
  /// Delivery stops on `cancel()` or when the returned handle is released.
  func observe(_ handler: @escaping @MainActor (SidebarChange) -> Void) -> SidebarObservation
}

/// What changed: a location's child list (insert / remove / reorder), one node's own fields (title, url), or the
/// Space list.
public enum SidebarChange: Hashable, Sendable {
  case structure(SidebarLocation)
  case node(NodeID)
  /// `spaceOrder` or any Space's title, profile or theme changed.
  case spaces
}

/// Handle returned by `SidebarSource.observe`; keep it alive for as long as you want changes.
@MainActor
public final class SidebarObservation {
  private var onCancel: (@MainActor () -> Void)?
  public init(onCancel: @escaping @MainActor () -> Void) { self.onCancel = onCancel }
  public func cancel() { onCancel?(); onCancel = nil }
  isolated deinit { onCancel?() }
}

/// Observer fan-out for `SidebarSource` implementations (StubSidebar now, the Track B adapter later).
@MainActor
public final class SidebarChangeHub {
  private var handlers: [UUID: @MainActor (SidebarChange) -> Void] = [:]
  private var order: [UUID] = []

  public init() {}

  public func observe(_ handler: @escaping @MainActor (SidebarChange) -> Void) -> SidebarObservation {
    let key = UUID()
    handlers[key] = handler
    order.append(key)
    return SidebarObservation { [weak self] in
      self?.handlers[key] = nil
      self?.order.removeAll { $0 == key }
    }
  }

  public func emit(_ change: SidebarChange) {
    for key in order { handlers[key]?(change) }      // a handler cancelled mid-delivery is skipped
  }
}

extension SidebarSource {
  /// The top-level section (`.favorites`, `.pinned`, `.today`) holding `id`, through folders and splits.
  public func section(containing id: NodeID) -> SidebarLocation? {
    var location = parent(of: id)
    for _ in 0..<64 {                       // depth guard against a malformed source
      guard let current = location, let container = current.containerNode else { return location }
      location = parent(of: container)
    }
    return nil
  }

  /// The Space whose pinned or Today section holds `id`, walking up through folders and splits.
  /// Nil for favorites (they belong to a profile, not a Space) and unknown nodes.
  public func spaceID(containing id: NodeID) -> SpaceID? {
    var current = id
    for _ in 0..<64 {                       // depth guard against a malformed source
      switch parent(of: current) {
      case .pinned(let space)?, .today(let space)?: return space
      case .folder(let up)?, .split(let up)?: current = up
      case .favorites?, nil: return nil
      }
    }
    return nil
  }

  /// The first tab at or under `id` (a split activates its first pane).
  public func firstTab(at id: NodeID) -> NodeID? {
    guard let info = node(id) else { return nil }
    guard let location = info.childLocation else { return id }
    for child in children(of: location) {
      if let tab = firstTab(at: child) { return tab }
    }
    return nil
  }
}
