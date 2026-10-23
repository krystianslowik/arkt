import CoreGraphics
import Foundation

/// Sidebar row geometry. Values measured from Arc's layout (+-2 pt).
public enum SidebarMetrics {
  public static let rowPitch: CGFloat = 41               // measured row pitch
  public static let rowBackgroundHeight: CGFloat = 34    // measured row
  public static var rowBackgroundInsetY: CGFloat { (rowPitch - rowBackgroundHeight) / 2 }
  public static let rowCornerRadius: CGFloat = 9         // TODO(measure)
  public static let horizontalPadding: CGFloat = 8
  public static let faviconSize: CGFloat = 16
  public static let faviconLeading: CGFloat = 10
  public static let titleLeading: CGFloat = 34
  public static let titleTrailing: CGFloat = 10          // TODO(measure)
  // Hover close (X) button at the row's trailing edge (GS-043).
  public static let closeButtonSize: CGFloat = 20        // TODO(measure): hit box
  public static let closeButtonGlyphSize: CGFloat = 10   // TODO(measure)
  public static let closeButtonTrailing: CGFloat = 7     // TODO(measure): cell trailing edge to hit box
  public static let closeButtonTitleGap: CGFloat = 4     // TODO(measure): title end to hit box
  public static let closeButtonFadeDuration: Double = 0.12  // TODO(measure): fade in and out with the hover
  public static let titleFontSize: CGFloat = 14          // measured, medium weight
  public static let spaceTitleFontSize: CGFloat = 12     // measured, secondary, left 16
  public static let spaceTitleLeading: CGFloat = 16      // measured
  public static let spaceTitleHeight: CGFloat = 28       // TODO(measure)
  public static let dividerHeight: CGFloat = 13          // TODO(measure)
  public static let indentationPerLevel: CGFloat = 14    // TODO(measure)
  public static let favoritesTopGap: CGFloat = 4         // TODO(measure): URL bar to favorites
  public static let favoritesBottomGap: CGFloat = 10     // TODO(measure): favorites to Space title
  public static let bottomBarHeight: CGFloat = 36        // TODO(measure)
  public static let favoriteFaviconSize: CGFloat = 20
  public static let bottomBarIconSize: CGFloat = 16       // archive and new-tab symbols
  public static let spaceDotSize: CGFloat = 6            // TODO(measure)
  public static let spaceDotSpacing: CGFloat = 8         // TODO(measure)
  // URL bar under the traffic lights (BH-031). The gap keeps it clear of the titlebar container that hosts the
  // traffic lights (ShellWindow.layoutTrafficLights), which would otherwise take its clicks.
  public static let urlBarTopGap: CGFloat = 4            // TODO(measure): traffic-light strip to URL bar
  public static let urlBarHeight: CGFloat = 30           // TODO(measure)
  public static let urlBarCornerRadius: CGFloat = 9      // TODO(measure)
  public static let urlBarTextInset: CGFloat = 10        // TODO(measure)
  public static let urlBarFontSize: CGFloat = 13         // TODO(measure)
}

public enum TabRowState: Sendable, Equatable {
  case current, contentVisible, previous, previousHovered, pressed, normal

  /// Black-or-white at Arc's token levels over the theme; nil = no fill.
  public func background(_ flavor: ThemeFlavor) -> RGBA? {
    switch self {
    case .current: ShellTokens.tabCurrent.resolve(flavor)
    case .contentVisible: ShellTokens.tabContentVisible.resolve(flavor)
    case .previous: ShellTokens.tabPrevious.resolve(flavor)
    case .previousHovered: ShellTokens.tabPreviousHovered.resolve(flavor)
    case .pressed: ShellTokens.tabPressed.resolve(flavor)
    case .normal: nil
    }
  }

  /// The state actually drawn once pointer feedback is folded in. Current and visible rows keep their fill;
  /// pressing a resting row shows the pressed level; hovering the previous row lifts it.
  public func displayed(hovered: Bool, pressed: Bool) -> TabRowState {
    switch self {
    case .current, .contentVisible: self
    case .previous where pressed, .normal where pressed: .pressed
    case .previous where hovered: .previousHovered
    default: self
    }
  }

  public struct Resolver: Sendable, Equatable {
    public var current: NodeID?
    public var visible: Set<NodeID>
    public var previous: NodeID?

    public init(current: NodeID?, visible: Set<NodeID>, previous: NodeID?) {
      self.current = current; self.visible = visible; self.previous = previous
    }

    public static let empty = Resolver(current: nil, visible: [], previous: nil)

    /// Nodes whose state differs between `old` and this resolver (the rows that need repainting).
    public func changedNodes(from old: Resolver) -> Set<NodeID> {
      var candidates = visible.union(old.visible)
      for id in [current, previous, old.current, old.previous] { if let id { candidates.insert(id) } }
      return candidates.filter { state(for: $0) != old.state(for: $0) }
    }

    public func state(for id: NodeID) -> TabRowState {
      if id == current { return .current }
      if visible.contains(id) { return .contentVisible }
      if id == previous { return .previous }
      return .normal
    }
  }
}
