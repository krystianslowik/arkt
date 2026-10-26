import CoreGraphics

/// Favorites grid math (#337): 1 to 4 columns by sidebar width, rows filled evenly, ~52x46 tiles with 9 pt gaps that
/// grow to fill the row. Pure; the grid view, its keyboard cursor and its column spring all read it.
public enum FavoritesLayout {
  public static let maxColumns = 4
  /// The measured tile at the default 190 pt sidebar (3 columns); no tile gets narrower.
  public static let minimumTileWidth: CGFloat = 52
  public static let gap: CGFloat = 9            // measured
  public static let tileHeight: CGFloat = 46    // measured
  public static let tileCornerRadius: CGFloat = 10

  /// Where a tile sits, independent of the width: its left edge and width as shares of one row (each column's share
  /// includes the gap after it), and its row. The column spring interpolates these, so a tile in motion keeps
  /// following a sidebar that is still being resized.
  public struct Slot: Equatable, Sendable {
    public var left: Double
    public var width: Double
    public var row: Double

    public init(left: Double, width: Double, row: Double) {
      self.left = left; self.width = width; self.row = row
    }
  }

  public static func contentWidth(sidebarWidth: CGFloat) -> CGFloat {
    sidebarWidth - 2 * SidebarMetrics.horizontalPadding
  }

  // MARK: Columns

  /// How many minimum-width tiles fit side by side, 1 to 4.
  public static func columnCapacity(contentWidth: CGFloat) -> Int {
    let fitting = Int(((contentWidth + gap) / (minimumTileWidth + gap)).rounded(.down))
    return min(max(fitting, 1), maxColumns)
  }

  /// The columns for `itemCount` tiles: as few rows as the width allows, filled evenly (4 Favorites that fit side by
  /// side make one row of 4, never 3 + 1; 5 in that width make 3 + 2). An empty grid answers the capacity.
  public static func columns(itemCount: Int, contentWidth: CGFloat) -> Int {
    let capacity = columnCapacity(contentWidth: contentWidth)
    guard itemCount > 0 else { return capacity }
    let rows = (itemCount + capacity - 1) / capacity
    return (itemCount + rows - 1) / rows
  }

  public static func rows(itemCount: Int, columns: Int) -> Int {
    guard itemCount > 0 else { return 0 }
    let columns = max(columns, 1)
    return (itemCount + columns - 1) / columns
  }

  // MARK: Frames

  public static func slot(ofItem index: Int, columns: Int) -> Slot {
    let columns = max(columns, 1)
    let share = 1 / Double(columns)
    return Slot(left: Double(index % columns) * share, width: share, row: Double(index / columns))
  }

  /// A slot's frame in grid coordinates (flipped: row 0 on top). Both edges round to whole points so favicons stay
  /// sharp; the row's last tile ends exactly at `contentWidth`.
  public static func frame(of slot: Slot, contentWidth: CGFloat) -> CGRect {
    let pitch = contentWidth + gap                      // one row, counting a gap after its last tile
    let minX = (CGFloat(slot.left) * pitch).rounded()
    let maxX = (CGFloat(slot.left + slot.width) * pitch - gap).rounded()
    let y = CGFloat(slot.row) * (tileHeight + gap)
    return CGRect(x: minX, y: y, width: max(0, maxX - minX), height: tileHeight)
  }

  public static func frame(ofItem index: Int, itemCount: Int, contentWidth: CGFloat) -> CGRect {
    frame(of: slot(ofItem: index, columns: columns(itemCount: itemCount, contentWidth: contentWidth)),
          contentWidth: contentWidth)
  }

  public static func itemSize(contentWidth: CGFloat, columns: Int) -> CGSize {
    let columns = max(columns, 1)
    let width = (contentWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
    return CGSize(width: max(0, width), height: tileHeight)
  }

  /// The height of `rows` rows; fractional while the column spring moves tiles between rows.
  public static func height(rows: CGFloat) -> CGFloat {
    max(0, rows * (tileHeight + gap) - gap)
  }

  public static func height(itemCount: Int, contentWidth: CGFloat) -> CGFloat {
    let columns = columns(itemCount: itemCount, contentWidth: contentWidth)
    return height(rows: CGFloat(rows(itemCount: itemCount, columns: columns)))
  }

  // MARK: Keyboard

  /// The tile an arrow moves to from `index` (#343): Left and Right step through the order, Up and Down by one row.
  /// Down over the gap of a short last row takes that row's last tile. Nil: no tile there (Down then leaves the grid
  /// for the outline).
  public static func neighbor(of index: Int, deltaColumns: Int, deltaRows: Int, itemCount: Int,
                              columns: Int) -> Int? {
    guard (0..<itemCount).contains(index) else { return nil }
    let columns = max(columns, 1)
    let proposed = index + deltaColumns + deltaRows * columns
    if (0..<itemCount).contains(proposed) { return proposed }
    let lastRow = rows(itemCount: itemCount, columns: columns) - 1
    if deltaRows > 0, deltaColumns == 0, index / columns < lastRow { return itemCount - 1 }
    return nil
  }
}
