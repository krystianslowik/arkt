import CoreGraphics
import Foundation

/// Sidebar row geometry. Values measured from Arc's layout (+-2 pt). "Arc 1.168" marks a value from the measurement
/// pass in `docs/plans/2026-10-23-arc-measurements.md` (one 2x window, dark, not key, Toolbar on).
public enum SidebarMetrics {
  public static let rowPitch: CGFloat = 41               // measured row pitch
  public static let rowBackgroundHeight: CGFloat = 34    // measured row
  public static var rowBackgroundInsetY: CGFloat { (rowPitch - rowBackgroundHeight) / 2 }
  public static let rowCornerRadius: CGFloat = 9         // TODO(measure)
  public static let horizontalPadding: CGFloat = 8
  public static let faviconSize: CGFloat = 16
  public static let faviconLeading: CGFloat = 10
  public static let titleLeading: CGFloat = 34
  public static let titleTrailing: CGFloat = 9           // Arc 1.168, inferred: title end to the row fill's edge
  // Hover close (X) button at the row's trailing edge (GS-043).
  public static let closeButtonSize: CGFloat = 20        // TODO(measure): hit box
  public static let closeButtonGlyphSize: CGFloat = 10   // TODO(measure)
  public static let closeButtonTrailing: CGFloat = 7     // TODO(measure): cell trailing edge to hit box
  public static let closeButtonTitleGap: CGFloat = 4     // TODO(measure): title end to hit box
  public static let closeButtonFadeDuration: Double = 0.12  // TODO(measure): fade in and out with the hover
  // Audio button of a page that plays or is muted (#364), left of the X's slot. [I] PARITY(NEEDS-RUNTIME-CHECK)
  public static let audioButtonSize: CGFloat = 20        // hit box, as the X's
  public static let audioButtonGlyphSize: CGFloat = 12
  public static let audioButtonGap: CGFloat = 2          // audio hit box to the X's hit box
  /// Fade when the sound starts or stops: ease-out, under the X's 120 ms is too quick to read as a change of state.
  public static let audioButtonFadeDuration: Double = 0.18
  public static let titleFontSize: CGFloat = 14          // measured, medium weight
  public static let spaceTitleFontSize: CGFloat = 12     // measured, secondary, left 16
  public static let spaceTitleLeading: CGFloat = 16      // measured
  public static let spaceTitleHeight: CGFloat = 36       // Arc 1.168: Space header top to the tab list
  public static let dividerHeight: CGFloat = 25          // Arc 1.168; the hairline is `ShellTokens.sidebarDivider`
  public static let indentationPerLevel: CGFloat = 16    // Arc 1.168
  /// Arc 1.168, Toolbar-on layout only: traffic-light strip to the tiles (the sidebar URL bar is hidden then). With
  /// the Toolbar off the same gap follows the URL bar; Arc was not measured in that state.
  public static let favoritesTopGap: CGFloat = 8
  public static let favoritesBottomGap: CGFloat = 8      // Arc 1.168: tile bottom to the Space header
  public static let bottomBarHeight: CGFloat = 50        // Arc 1.168: Space dock strip, 9 pt above and below buttons
  public static let bottomBarButtonSize: CGFloat = 32    // Arc 1.168: archive and new-tab hit boxes
  public static let favoriteFaviconSize: CGFloat = 20
  // Hover close (X) on a loaded Favorite tile (#82); same glyph and fade as the rows'.
  public static let favoriteCloseButtonSize: CGFloat = 16   // TODO(measure): hit box
  public static let favoriteCloseButtonInset: CGFloat = 3   // TODO(measure): tile top and trailing edge to hit box
  public static let bottomBarIconSize: CGFloat = 16       // archive and new-tab symbols
  /// Arc 1.168. Arc's idle dot is about white 8 % over the theme, measured in a non-key dark 2x window; Arkt keeps
  /// `sidebarForeground` so the dot reaches 3:1 (#72).
  public static let spaceDotSize: CGFloat = 4
  public static let spaceDotSpacing: CGFloat = 17.5      // Arc 1.168: 21.5 pt center pitch minus the dot
  /// SF Symbol drawn in the dot's slot (BH-034). The slot pitch stays `spaceDotSize + spaceDotSpacing`.
  public static let spaceIconSize: CGFloat = 16
  /// An emoji icon's font size, so its glyph fits `spaceIconSize`. TODO(measure): Arc's dock emoji.
  public static let spaceEmojiFontSize: CGFloat = 13
  /// A header press shorter than this is a click; a longer one drags the title (BH-039).
  public static let spaceHeaderDragThreshold: CGFloat = 6
  // URL bar under the traffic lights (BH-031), shown while the Toolbar is off. The titlebar container that hosts the
  // traffic lights ends at the strip (ShellWindow.layoutTrafficLights), so it never takes the bar's clicks.
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
