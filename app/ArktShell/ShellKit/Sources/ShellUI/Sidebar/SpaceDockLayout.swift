import CoreGraphics

/// Horizontal geometry of the Space dock's dots (#193). When the dots fit they are centered; when they do not,
/// they sit on a strip with half a gap before the first dot and after the last one, and the strip scrolls
/// (Arc's dock is a scroll area, see `docs/plans/2026-10-23-arc-measurements.md`). `offset` is how far the strip
/// is scrolled, 0 at the first dot. All x values are in the dock's coordinates.
struct SpaceDockLayout: Equatable {
  var count: Int
  var width: CGFloat

  var pitch: CGFloat { SidebarMetrics.spaceDotSize + SidebarMetrics.spaceDotSpacing }

  /// First dot's left edge to the last dot's right edge.
  var contentWidth: CGFloat { count == 0 ? 0 : CGFloat(count) * pitch - SidebarMetrics.spaceDotSpacing }

  var overflows: Bool { contentWidth > width }

  /// Width of the scrolling strip: one hit box per dot when overflowing, the dock itself otherwise.
  var stripWidth: CGFloat { overflows ? CGFloat(count) * pitch : width }

  var maxOffset: CGFloat { max(0, stripWidth - width) }

  /// Width of the edge fades, half a gap, so a dot scrolled into view is never faded.
  var fadeWidth: CGFloat { SidebarMetrics.spaceDotSpacing / 2 }

  func clamp(_ offset: CGFloat) -> CGFloat { min(max(offset, 0), maxOffset) }

  /// Left edge of dot `index` on the strip (offset 0).
  func stripDotMinX(_ index: Int) -> CGFloat {
    if overflows { return SidebarMetrics.spaceDotSpacing / 2 + CGFloat(index) * pitch }
    return ((width - contentWidth) / 2).rounded() + CGFloat(index) * pitch
  }

  /// Left edge of dot `index` in the dock when the strip is scrolled by `offset`.
  func dotMinX(_ index: Int, offset: CGFloat) -> CGFloat { stripDotMinX(index) - clamp(offset) }

  /// Left edge of dot `index`'s hit box (the full pitch, centered on the dot).
  func hitMinX(_ index: Int, offset: CGFloat) -> CGFloat {
    dotMinX(index, offset: offset) - SidebarMetrics.spaceDotSpacing / 2
  }

  /// The smallest scroll from `offset` that shows dot `index`'s whole hit box (an out-of-range index is clamped).
  func offsetRevealing(_ index: Int, from offset: CGFloat) -> CGFloat {
    guard overflows, count > 0 else { return 0 }
    let start = CGFloat(min(max(index, 0), count - 1)) * pitch
    let current = clamp(offset)
    if start < current { return start }
    if start + pitch > current + width { return clamp(start + pitch - width) }
    return current
  }

  /// Which edges fade: an edge fades while dots are hidden past it.
  func fades(offset: CGFloat) -> (leading: Bool, trailing: Bool) {
    let offset = clamp(offset)
    return (leading: offset > 0.5, trailing: offset < maxOffset - 0.5)
  }
}
