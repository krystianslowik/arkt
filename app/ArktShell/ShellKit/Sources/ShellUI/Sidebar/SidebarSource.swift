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

/// A Space's dock icon (BH-034, decision D1 on #279): an SF Symbol name such as "star", or one emoji. Nil draws the
/// dot. Mirrors `SidebarModel.SpaceIcon` case for case.
public enum SpaceIconInfo: Hashable, Sendable {
  case symbol(String)
  /// Exactly one emoji, as `validatedEmoji(_:)` accepts it.
  case emoji(String)

  /// `.emoji(text)` when `text`, trimmed of whitespace, is exactly one extended grapheme cluster shown as an emoji;
  /// nil otherwise. Accepted: a cluster whose first scalar has emoji presentation by default (U+1F680, a flag, a ZWJ
  /// sequence starting with one), or an emoji-capable scalar followed by the emoji variation selector U+FE0F (U+2764
  /// U+FE0F, a keycap such as "1" U+FE0F U+20E3). Rejected: plain digits, "#", "*" and other text-default scalars
  /// without U+FE0F (they are `isEmoji` only because keycaps exist), letters, and anything longer than one cluster.
  public static func validatedEmoji(_ text: String) -> SpaceIconInfo? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 1, let character = trimmed.first else { return nil }
    let scalars = Array(character.unicodeScalars)
    guard let first = scalars.first else { return nil }
    let presentsAsEmoji = first.properties.isEmojiPresentation
      || (first.properties.isEmoji && scalars.count > 1 && scalars[1] == "\u{FE0F}")
    return presentsAsEmoji ? .emoji(String(character)) : nil
  }
}

public struct SidebarSpaceInfo: Equatable, Sendable {
  public var id: SpaceID
  public var title: String
  public var profile: String
  /// The theme the window draws: the Space's own, or the source's default when it has none.
  public var theme: SpaceThemeInfo
  /// The Space has no theme of its own and `theme` is the source's default (the header menu's "Default", D2 on #279).
  public var usesDefaultTheme: Bool
  public var icon: SpaceIconInfo?

  public init(id: SpaceID, title: String, profile: String, theme: SpaceThemeInfo, usesDefaultTheme: Bool = false,
              icon: SpaceIconInfo? = nil) {
    self.id = id; self.title = title; self.profile = profile; self.theme = theme
    self.usesDefaultTheme = usesDefaultTheme; self.icon = icon
  }
}

/// Mirrors `SidebarModel.Orientation`, value for value. `.horizontal`: the panes sit side by side; `.vertical`: top
/// to bottom (split view plan, decision 1). Turning it into an axis is the split layout's job.
/// PARITY(NEEDS-RUNTIME-CHECK RT-31)
public enum SplitOrientation: String, Hashable, Sendable {
  case horizontal
  case vertical
}

/// How a split lays out its panes (mirrors `SidebarModel.SplitItem`).
public struct SplitLayoutInfo: Equatable, Sendable {
  /// The most panes a split holds (CF-06; mirrors `Sidebar.maximumSplitPanes`).
  public static let maximumPanes = 4

  public var orientation: SplitOrientation
  /// Pane i's share of the split's main axis, as stored. Not repaired here: an imported or restored split may carry
  /// a count that does not match its panes, and the split layout normalizes before drawing (decision 2).
  public var widthFactors: [Double]

  public init(orientation: SplitOrientation, widthFactors: [Double]) {
    self.orientation = orientation
    self.widthFactors = widthFactors
  }
}

/// Track B's `NodeKind` flattened to what the sidebar draws (TabItem / FolderItem / SplitItem).
public enum SidebarNodeInfo: Equatable, Sendable {
  case tab(id: NodeID, url: URL, title: String)
  case folder(id: NodeID, title: String)
  case split(id: NodeID, layout: SplitLayoutInfo)

  public var id: NodeID {
    switch self {
    case .tab(let id, _, _), .folder(let id, _), .split(let id, _): id
    }
  }

  /// The location holding this node's children, nil for leaves.
  public var childLocation: SidebarLocation? {
    switch self {
    case .tab: nil
    case .folder(let id, _): .folder(id)
    case .split(let id, _): .split(id)
    }
  }
}

/// Why a split write was refused. The shell cannot see the model's `SidebarError`; sources map to this.
public enum SplitEditError: Error, Equatable, Sendable {
  /// The split already holds `SplitLayoutInfo.maximumPanes` panes (BH-116: "Cannot Add New Pane").
  case splitFull
  /// The ids do not describe a valid split edit: not a split, not a pane, not a tab, a repeated id, bad factors.
  case invalid
}

/// The tab that becomes a new pane in `SidebarSource.addToSplit`.
public enum SplitPaneSource: Equatable, Sendable {
  /// A tab already in the sidebar; it leaves its place (a pane of another split shrinks that split).
  case existing(NodeID)
  /// A new tab, created with the pane.
  case new(url: URL, title: String)
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
  /// A new Space for this source's default profile, appended to `spaceOrder`. Emits `.spaceAdded`.
  @discardableResult func addSpace(title: String) throws -> SpaceID
  /// New Space (BH-037): a Space for the default profile inserted directly after `space`; nil or an unknown Space
  /// appends. Emits `.spaceAdded` only (the other Spaces keep their relative order).
  @discardableResult func addSpace(title: String, after space: SpaceID?) throws -> SpaceID
  /// Sets a Space's title (BH-038). Emits `.spaceChanged` when it changed; an unknown id is ignored.
  func renameSpace(_ id: SpaceID, to title: String)
  /// Moves a Space so that it lands at `index`, measured before it is removed, clamped (BH-039). Emits `.spaceMoved`
  /// when the order changed; an unknown id is ignored.
  func moveSpace(_ id: SpaceID, to index: Int)
  /// Sets a Space's icon (BH-034). Nil clears it. Emits `.spaceChanged` when it changed; an unknown id or the same
  /// icon is ignored.
  func setIcon(_ id: SpaceID, to icon: SpaceIconInfo?)
  /// Sets a Space's theme (BH-034). Nil clears it, so the Space draws the source's default theme (D2 on #279). Emits
  /// `.spaceChanged` when it changed; an unknown id or the same theme is ignored.
  func setTheme(_ id: SpaceID, to theme: SpaceThemeInfo?)
  func updateTab(_ id: NodeID, url: URL?, title: String?)

  // Split writes (BH-115, BH-116, BH-120). Each applies as one step: observers get its changes once, and a throw
  // leaves the source untouched. A full split throws `SplitEditError.splitFull`; ids that do not fit the edit throw `.invalid`.

  /// Adds `pane` to a split. When `target` is a tab outside a split, a new split takes the target's place, holding the
  /// target and the pane with `orientation` and equal shares; `index` 0 puts the pane first, anything else after the
  /// target. When `target` is a split or one of its panes, the pane is inserted into that split at `index` (clamped)
  /// and all shares become equal [I] (RT-35); `orientation` is ignored. Returns the split and the pane.
  @discardableResult
  func addToSplit(_ pane: SplitPaneSource, target: NodeID, at index: Int, orientation: SplitOrientation) throws
    -> (split: NodeID, pane: NodeID)
  /// Ctrl-Shift-- (BH-122): the pane leaves its split without closing and lands right after it; a split left with
  /// one pane is replaced by that pane.
  func separatePane(_ pane: NodeID) throws
  /// Separate All Tabs (BH-121): the panes take the split's place, in order. Returns them.
  @discardableResult func separateSplit(_ split: NodeID) throws -> [NodeID]
  /// Expand Current Split (BH-124): `pane` takes the split's place and the other panes follow it.
  func expandPane(_ pane: NodeID) throws
  /// Reorders a pane inside its split; `index` is measured before the pane is removed. Factors follow their panes.
  func movePane(_ pane: NodeID, to index: Int) throws
  /// Divider commit: one finite, positive factor per pane, stored normalized to sum 1.
  func setSplitWidthFactors(_ split: NodeID, _ factors: [Double]) throws
  /// Convert to Horizontal / Vertical Split View (BH-120).
  func setSplitOrientation(_ split: NodeID, _ orientation: SplitOrientation) throws
  /// Duplicate split (BH-126): a copy with new ids, right after the original. Returns the copy.
  @discardableResult func duplicateSplit(_ split: NodeID) throws -> NodeID

  /// Ordered, synchronous delivery of every change to every live observer.
  /// Delivery stops on `cancel()` or when the returned handle is released.
  func observe(_ handler: @escaping @MainActor (SidebarChange) -> Void) -> SidebarObservation
}

/// What changed: a location's child list (insert / remove / reorder), one node's own fields (title, url), or one
/// Space (C6 review M10). A mutation that touches Spaces reports them first: removed, added, moved, changed.
public enum SidebarChange: Hashable, Sendable {
  case structure(SidebarLocation)
  case node(NodeID)
  /// A Space joined `spaceOrder`.
  case spaceAdded(SpaceID)
  /// A Space left `spaceOrder`. Its nodes went with it and get no `.structure` change of their own.
  case spaceRemoved(SpaceID)
  /// A Space changed its place in `spaceOrder` relative to the others (not just shifted by an add or a removal).
  case spaceMoved(SpaceID)
  /// A Space's title, profile, theme or icon changed.
  case spaceChanged(SpaceID)
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
