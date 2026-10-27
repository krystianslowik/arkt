import CoreGraphics

/// A row arriving at the top of Today from Little Arkt's Open in flight (#352, docs/design/little-arkt.md, Motion):
/// the row is in the outline from the start, but draws nothing until the rows below make room (`room`, 0 to 1) and
/// it fades in, growing from 0.96 (`appear`, 0 to 1). Rows below draw where they were until the room opens. Pure
/// math over row indexes, like `FolderMotionLayout`; the outline applies it as layer transforms, never frames.
enum SidebarArrivalLayout {
  /// `oldSelectionRow` is the row whose selection fill fades out as the room opens (#455); -1 when no row is shown
  /// or it is a Favorite with no outline row.
  static func styles(rowHeights: [CGFloat], arrivalRow: Int, oldSelectionRow: Int = -1,
                     room: Double, appear: Double) -> [FolderMotionLayout.RowStyle] {
    var styles = Array(repeating: FolderMotionLayout.RowStyle.rest, count: rowHeights.count)
    guard rowHeights.indices.contains(arrivalRow) else { return styles }
    apply(to: &styles, arrivalHeight: rowHeights[arrivalRow], arrivalRow: arrivalRow,
          oldSelectionRow: oldSelectionRow, room: room, appear: appear)
    return styles
  }

  /// Adds the arrival to `styles` (a folder motion frame, or rest). Only the arriving row's own height matters: the
  /// rows below it move by that, so the other rows' heights are never read. The old selection's fill fades on the
  /// same `room` spring; the arriving row's own fill is not multiplied (its whole-row alpha already fades it).
  static func apply(to styles: inout [FolderMotionLayout.RowStyle], arrivalHeight: CGFloat, arrivalRow: Int,
                    oldSelectionRow: Int = -1, room: Double, appear: Double) {
    guard styles.indices.contains(arrivalRow) else { return }
    let shown = CGFloat(min(max(appear, 0), 1))
    styles[arrivalRow].alpha *= shown
    styles[arrivalRow].scale *= 1 - CGFloat(1 - LittleArktFlightMotion.rowStartScale) * (1 - shown)
    if styles.indices.contains(oldSelectionRow), oldSelectionRow != arrivalRow {
      styles[oldSelectionRow].selectionAlpha *= 1 - CGFloat(min(max(room, 0), 1))
    }
    let missing = CGFloat(room - 1) * arrivalHeight
    for row in (arrivalRow + 1)..<styles.count {
      styles[row].offsetY += missing
    }
  }
}
