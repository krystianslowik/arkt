import CoreGraphics

/// Horizontal geometry of the Space dock's dots (#193). When the dots fit they are centered; when they do not,
/// they sit on a strip with half a gap before the first dot and after the last one, and the strip scrolls
/// (Arc's dock is a scroll area, see `docs/plans/2026-10-23-arc-measurements.md`). `offset` is how far the strip
/// is scrolled, 0 at the first dot. All x values are in the dock's coordinates.
struct SpaceDockLayout: Equatable {
  var count: Int
  var width: CGFloat
  var scale: CGFloat = 2

  private var pixelScale: CGFloat { scale > 0 ? scale : 1 }

  /// Rounds `value` to the nearest device pixel at `scale`.
  func align(_ value: CGFloat) -> CGFloat { (value * pixelScale).rounded() / pixelScale }

  var pitch: CGFloat { SidebarMetrics.spaceDotSize + SidebarMetrics.spaceDotSpacing }

  /// Leading inset before the first dot in overflow mode, pixel-aligned at `scale`.
  var inset: CGFloat { align(SidebarMetrics.spaceDotSpacing / 2) }

  /// First dot's left edge to the last dot's right edge.
  var contentWidth: CGFloat { count == 0 ? 0 : CGFloat(count) * pitch - SidebarMetrics.spaceDotSpacing }

  var overflows: Bool { contentWidth > width }

  /// Width of the scrolling strip: one hit box per dot when overflowing, the dock itself otherwise.
  var stripWidth: CGFloat { overflows ? CGFloat(count) * pitch : width }

  var maxOffset: CGFloat { max(0, stripWidth - width) }

  /// Width of the edge fades, half a gap, so a dot scrolled into view is never faded.
  var fadeWidth: CGFloat { SidebarMetrics.spaceDotSpacing / 2 }

  func clamp(_ offset: CGFloat) -> CGFloat { min(max(offset, 0), maxOffset) }

  /// Pixel-aligned origin of the scrolling strip for `offset`.
  func stripMinX(offset: CGFloat) -> CGFloat {
    guard overflows else { return 0 }
    return -align(clamp(offset))
  }

  /// Left edge of dot `index` on the strip (offset 0), pixel-aligned at `scale`.
  func stripDotMinX(_ index: Int) -> CGFloat {
    if overflows { return align(inset + CGFloat(index) * pitch) }
    return align(((width - contentWidth) / 2).rounded() + CGFloat(index) * pitch)
  }

  /// Left edge of dot `index` in the dock when the strip is scrolled by `offset`.
  func dotMinX(_ index: Int, offset: CGFloat) -> CGFloat {
    stripDotMinX(index) + stripMinX(offset: offset)
  }

  /// Left edge of dot `index`'s hit box (the full pitch, centered on the dot).
  func hitMinX(_ index: Int, offset: CGFloat) -> CGFloat {
    if overflows { return CGFloat(index) * pitch + stripMinX(offset: offset) }
    return dotMinX(index, offset: offset) - SidebarMetrics.spaceDotSpacing / 2
  }

  /// The smallest pixel-aligned scroll from `offset` that shows dot `index`'s whole hit box (an out-of-range
  /// index is clamped).
  func offsetRevealing(_ index: Int, from offset: CGFloat) -> CGFloat {
    guard overflows, count > 0 else { return 0 }
    let start = CGFloat(min(max(index, 0), count - 1)) * pitch
    let current = align(clamp(offset))
    if start < current { return clamp(align(start)) }
    if start + pitch > current + width { return clamp(align(start + pitch - width)) }
    return current
  }

  /// Which edges fade: an edge fades while dots are hidden past it.
  func fades(offset: CGFloat) -> (leading: Bool, trailing: Bool) {
    let offset = clamp(offset)
    return (leading: offset > 0.5, trailing: offset < maxOffset - 0.5)
  }
}
