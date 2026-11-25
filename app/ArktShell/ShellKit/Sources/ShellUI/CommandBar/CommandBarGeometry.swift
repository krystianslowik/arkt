import CoreGraphics

/// Command bar metrics (design/command-bar/README.md, Layout) and frame math. Pure, so it is unit-tested. Points.
/// Little Arkt's lookup has its own (`LittleArktGeometry`).
public enum CommandBarGeometry {
  /// `min(600, window width - 48)`.
  public static let maxWidth: CGFloat = 600
  public static let sideMargin: CGFloat = 24
  /// The top edge: `clamp(48, 14 % of the window height, 110)`, fixed, so results grow downward only.
  public static let topFraction: CGFloat = 0.14
  public static let minTop: CGFloat = 48
  public static let maxTop: CGFloat = 110
  /// The panel stops this far above the window's bottom edge; below that the list scrolls.
  public static let bottomMargin: CGFloat = 24
  public static let cornerRadius: CGFloat = 14
  public static let inputHeight: CGFloat = 54
  public static let inputLeading: CGFloat = 20
  public static let magnifierSize: CGFloat = 18
  public static let magnifierGap: CGFloat = 12
  public static let rowHeight: CGFloat = 36
  public static let rowRadius: CGFloat = 8
  public static let rowHorizontalPadding: CGFloat = 10
  /// The favicon or symbol slot, and the gap after it (also between the title, the URL and the trailing group).
  public static let slotWidth: CGFloat = 18
  public static let slotGap: CGFloat = 12
  public static let iconSize: CGFloat = 16
  public static let faviconRadius: CGFloat = 4
  public static let listSidePadding: CGFloat = 6
  public static let listTopPadding: CGFloat = 6
  public static let listBottomPadding: CGFloat = 8
  /// A group header: 26 high including 10 above; 20 high, 4 above, for the group that starts the list.
  public static let groupHeaderHeight: CGFloat = 26
  public static let firstGroupHeaderHeight: CGFloat = 20
  /// The Return key cap.
  public static let keyCapHeight: CGFloat = 20
  public static let keyCapRadius: CGFloat = 5
  /// A secondary text narrower than this is dropped rather than shown as a stub.
  public static let minimumURLWidth: CGFloat = 48
  /// The rows a Page Up or Page Down moves.
  public static let pageRows = 5

  /// The top edge's distance below the window's top, rounded to a whole point (59 in the 420 pt window).
  public static func top(windowHeight: CGFloat) -> CGFloat {
    min(max(minTop, (topFraction * windowHeight).rounded()), maxTop)
  }

  /// A row's height: 36, plus its group header when it starts a group.
  public static func rowHeight(hasHeader: Bool, isFirst: Bool) -> CGFloat {
    guard hasHeader else { return rowHeight }
    return rowHeight + (isFirst ? firstGroupHeaderHeight : groupHeaderHeight)
  }

  /// The bar's natural height: the field, and when there are rows, the hairline, the padded list and its headers.
  public static func contentHeight(rowCount: Int, headerCount: Int, firstRowHasHeader: Bool) -> CGFloat {
    guard rowCount > 0 else { return inputHeight }
    let headers = CGFloat(headerCount) * groupHeaderHeight
      - (firstRowHasHeader && headerCount > 0 ? groupHeaderHeight - firstGroupHeaderHeight : 0)
    return inputHeight + 1 + listTopPadding + CGFloat(rowCount) * rowHeight + headers + listBottomPadding
  }

  /// Screen-space frame (origin bottom-left): centred, top edge pinned, at most `window height - top - 24` tall.
  public static func frame(parentFrame p: CGRect, contentHeight: CGFloat) -> CGRect {
    let width = min(maxWidth, max(0, p.width - 2 * sideMargin))
    let top = top(windowHeight: p.height)
    let height = min(contentHeight, max(inputHeight, p.height - top - bottomMargin))
    return CGRect(x: p.midX - width / 2, y: p.maxY - top - height, width: width, height: height)
  }
}
