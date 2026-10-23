import CoreGraphics

/// Pure geometry for the Space pager strip. Offsets are the strip's x origin: 0 shows page 0,
/// `-pageWidth` page 1, and so on.
public enum PagingMath {
  /// Seconds of release velocity added to the release translation when choosing the target page.
  public static let flickProjection: CGFloat = 0.2
  public static let rubberBandCoefficient: CGFloat = 0.55

  /// Strip offset for page `index` plus finger translation, rubber-banded past the first and last page.
  public static func offset(index: Int, translation: CGFloat, pageWidth: CGFloat, count: Int) -> CGFloat {
    let base = -CGFloat(index) * pageWidth
    let raw = base + translation
    let minOffset = -CGFloat(max(count - 1, 0)) * pageWidth
    if raw > 0 { return rubberBand(raw, dimension: pageWidth) }
    if raw < minOffset { return minOffset - rubberBand(minOffset - raw, dimension: pageWidth) }
    return raw
  }

  /// UIScrollView-style resistance: (1 - 1 / (x * c / d + 1)) * d. Always below `d`.
  public static func rubberBand(_ x: CGFloat, dimension d: CGFloat) -> CGFloat {
    guard d > 0 else { return 0 }
    return (1 - 1 / (x * rubberBandCoefficient / d + 1)) * d
  }

  /// Inverse of `rubberBand(_:dimension:)` for a rubber-banded distance `0 <= y < d`.
  public static func unrubberBand(_ y: CGFloat, dimension d: CGFloat) -> CGFloat {
    guard d > 0, y > 0 else { return 0 }
    let clamped = min(y, d * 0.999999)
    return (clamped * d) / (rubberBandCoefficient * (d - clamped))
  }

  /// Initial finger translation for `beginTracking()` at `offset` from page `index`, inverting rubber-band resistance
  /// when `offset` is already overshot past the first or last page so catching an overshooting settle keeps the exact
  /// position (#99, M3).
  public static func initialTranslation(offset: CGFloat, index: Int, pageWidth: CGFloat, count: Int) -> CGFloat {
    let base = -CGFloat(index) * pageWidth
    let minOffset = -CGFloat(max(count - 1, 0)) * pageWidth
    if offset > 0 { return unrubberBand(offset, dimension: pageWidth) - base }
    if offset < minOffset { return minOffset - unrubberBand(minOffset - offset, dimension: pageWidth) - base }
    return offset - base
  }

  /// Page to settle on after a release: at most one page away from `current`, clamped to the strip.
  public static func targetIndex(current: Int, translation: CGFloat, velocity: CGFloat,
                                 pageWidth: CGFloat, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let projected = translation + velocity * flickProjection
    var target = current
    if projected <= -pageWidth / 2 { target = current + 1 }
    if projected >= pageWidth / 2 { target = current - 1 }
    return min(max(target, 0), count - 1)
  }

  /// Continuous page position (1.25 = a quarter of the way from page 1 to page 2).
  public static func position(offset: CGFloat, pageWidth: CGFloat) -> CGFloat {
    pageWidth > 0 ? -offset / pageWidth : 0
  }
}
