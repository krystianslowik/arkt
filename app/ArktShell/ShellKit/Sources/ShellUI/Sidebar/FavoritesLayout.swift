import CoreGraphics

/// Favorites grid math: 3 columns of ~52x46 tiles, 9 pt gaps, stretching with the sidebar.
public enum FavoritesLayout {
  public static let columns = 3
  public static let gap: CGFloat = 9            // measured
  public static let tileHeight: CGFloat = 46    // measured
  public static let tileCornerRadius: CGFloat = 10

  public static func contentWidth(sidebarWidth: CGFloat) -> CGFloat {
    sidebarWidth - 2 * SidebarMetrics.horizontalPadding
  }

  public static func itemSize(contentWidth: CGFloat) -> CGSize {
    let width = (contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
    return CGSize(width: max(0, width), height: tileHeight)
  }

  public static func height(itemCount: Int) -> CGFloat {
    guard itemCount > 0 else { return 0 }
    let rows = (itemCount + columns - 1) / columns
    return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap
  }
}
