import CoreGraphics

/// BH-047 drop zones inside the sidebar: a tab dropped above the Space title becomes a Favorite. The overlay covers
/// only the band since #104; the page rule below (a Favorite pinned in the current Space) is kept for callers that
/// pass a point under the band, and the page outline places a Favorite dropped there where its indicator stands.
public enum FavoritesDrop {
  /// The band above the Space title that takes drops: the Favorites grid's frame, expanded to one tile row when
  /// the grid is empty (zero Favorites must still offer the target, BH-046).
  public static func band(favoritesFrame: CGRect) -> CGRect {
    guard !favoritesFrame.isEmpty else {
      return CGRect(x: favoritesFrame.minX, y: favoritesFrame.minY, width: favoritesFrame.width,
                    height: FavoritesLayout.tileHeight)
    }
    return favoritesFrame
  }

  /// What a drop at `point` (overlay coordinates; the overlay covers the band and the Space page below it) does
  /// with a node whose top-level section is `section`. Nil refuses the drop: a Favorite over the band, anything
  /// but a Favorite over the page, an unknown node, or a page drop with no current Space.
  public static func target(at point: CGPoint, band: CGRect, bounds: CGRect, section: SidebarLocation?,
                            profile: String, currentSpace: SpaceID?) -> SidebarLocation? {
    guard let section else { return nil }
    if band.contains(point) {
      return section == .favorites(profile: profile) ? nil : .favorites(profile: profile)
    }
    if point.y >= band.maxY, point.y <= bounds.maxY, case .favorites = section, let currentSpace {
      return .pinned(currentSpace)
    }
    return nil
  }
}
