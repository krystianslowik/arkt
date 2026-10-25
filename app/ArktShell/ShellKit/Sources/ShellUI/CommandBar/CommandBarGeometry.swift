import CoreGraphics

/// Command bar metrics (measured from Arc) and frame math. Pure, so it is unit-tested.
public enum CommandBarGeometry {
  public static let preferredWidth: CGFloat = 766      // measured
  public static let sideMargin: CGFloat = 24
  public static let topFraction: CGFloat = 0.34        // measured: top at ~34% of window height
  public static let inputHeight: CGFloat = 60          // measured
  public static let rowHeight: CGFloat = 50            // measured
  public static let cornerRadius: CGFloat = 12         // measured
  public static let selectedRowRadius: CGFloat = 8     // measured
  public static let maxVisibleRows = 8                 // TODO(measure)
  public static let listPadding: CGFloat = 8
  public static let inputLeading: CGFloat = 20
  /// BH-113 notice strip under the input row. TODO(measure): Arc's notice height.
  public static let noticeHeight: CGFloat = 32

  public static func contentHeight(rowCount: Int, showsNotice: Bool = false) -> CGFloat {
    let notice = showsNotice ? noticeHeight : 0
    let rows = min(rowCount, maxVisibleRows)
    return rows == 0 ? inputHeight + notice : inputHeight + notice + 1 + CGFloat(rows) * rowHeight + 2 * listPadding
  }

  /// Screen-space frame (origin bottom-left), top edge pinned so result changes grow downward.
  public static func frame(parentFrame p: CGRect, contentHeight: CGFloat) -> CGRect {
    let width = min(preferredWidth, p.width - 2 * sideMargin)
    let top = p.maxY - topFraction * p.height
    return CGRect(x: p.midX - width / 2, y: top - contentHeight, width: width, height: contentHeight)
  }
}
