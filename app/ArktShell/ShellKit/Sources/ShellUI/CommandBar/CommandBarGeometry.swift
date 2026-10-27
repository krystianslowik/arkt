import CoreGraphics

/// Command bar metrics (design/command-bar/README.md, Layout) and frame math. Pure, so it is unit-tested. Points.
public enum CommandBarGeometry {
  public static let preferredWidth: CGFloat = 680
  public static let sideMargin: CGFloat = 24
  /// The top edge sits at a fixed share of the window height, so results grow downward: 176 pt in the design's 800 pt
  /// window.
  public static let topFraction: CGFloat = 0.22
  public static let inputHeight: CGFloat = 58
  public static let inputLeading: CGFloat = 18
  public static let cornerRadius: CGFloat = 16
  public static let rowHeight: CGFloat = 40
  public static let selectedRowRadius: CGFloat = 9
  public static let rowHorizontalPadding: CGFloat = 12
  /// The favicon or symbol slot, and the gap between it and the title.
  public static let slotWidth: CGFloat = 20
  public static let slotGap: CGFloat = 12
  public static let iconSize: CGFloat = 16
  public static let listPadding: CGFloat = 6
  public static let hintStripHeight: CGFloat = 34
  /// A group header: 11 pt text, 8 above and 4 below.
  public static let groupHeaderHeight: CGFloat = 26
  /// The selected row's tick: 3 wide, inset 10 from the top and bottom of the row.
  public static let tickWidth: CGFloat = 3
  public static let tickInset: CGFloat = 10
  /// Rows shown without scrolling in the search states; the empty state shows more.
  public static let maxVisibleRows = 5
  public static let maxEmptyStateRows = 7
  /// BH-113 notice strip under the input row.
  public static let noticeHeight: CGFloat = 32

  /// The bar's height: the field, the notice, and, when there are rows, a hairline, the padded list, a hairline and
  /// the hint strip. `headerCount` group headers sit inside the list. More than `maxRows` rows scroll.
  public static func contentHeight(rowCount: Int, headerCount: Int = 0, showsNotice: Bool = false,
                                   maxRows: Int = maxVisibleRows) -> CGFloat {
    let notice = showsNotice ? noticeHeight : 0
    guard rowCount > 0 else { return inputHeight + notice }
    let rows = CGFloat(min(rowCount, maxRows)) * rowHeight
    let headers = CGFloat(headerCount) * groupHeaderHeight
    return inputHeight + notice + 1 + listPadding + rows + headers + listPadding + 1 + hintStripHeight
  }

  /// Screen-space frame (origin bottom-left), top edge pinned so result changes grow downward.
  public static func frame(parentFrame p: CGRect, contentHeight: CGFloat) -> CGRect {
    let width = min(preferredWidth, p.width - 2 * sideMargin)
    let top = p.maxY - topFraction * p.height
    return CGRect(x: p.midX - width / 2, y: top - contentHeight, width: width, height: contentHeight)
  }
}
