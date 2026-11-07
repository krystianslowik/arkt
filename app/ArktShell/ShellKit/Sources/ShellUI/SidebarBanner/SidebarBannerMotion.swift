import Motion
import QuartzCore

/// The banner's motion (design/sidebar-banner, Motion), as data. Appear: the row rises 8 pt and fades in, 0.24 s on
/// `firm`, while the rows above make room on the same curve. Dismiss: a 0.15 s fade while the rows settle. The popover
/// grows from 0.97 with its fade, 0.22 s on `firmFast`. Reduce Motion: opacity only, the rows jump. Nothing loops.
/// Only opacity, the row's transform and the row list's mask are animated; no frame changes per frame.
enum SidebarBannerMotion {
  /// The design system's `firm` and `firm-fast` curves (as `DownloadsMotion`).
  static let firm = MotionCurve(0.25, 1, 0.5, 1)
  static let firmFast = MotionCurve(0.2, 1, 0.4, 1)
  static let easeOut = MotionCurve.strongEaseOut

  struct Step: Equatable {
    /// Points below the resting place where the row starts (appear) or 0.
    var offset: CGFloat
    var scale: CGFloat
    var duration: CFTimeInterval
    var curve: MotionCurve
    /// The rows above move with the banner on `curve`; false: they jump to their new place.
    var movesRows: Bool
  }

  static func appear(reduceMotion: Bool) -> Step {
    reduceMotion ? Step(offset: 0, scale: 1, duration: 0.15, curve: easeOut, movesRows: false)
      : Step(offset: 8, scale: 1, duration: 0.24, curve: firm, movesRows: true)
  }

  static func dismiss(reduceMotion: Bool) -> Step {
    Step(offset: 0, scale: 1, duration: 0.15, curve: reduceMotion ? easeOut : firm, movesRows: !reduceMotion)
  }

  static func popover(reduceMotion: Bool) -> Step {
    reduceMotion ? Step(offset: 0, scale: 1, duration: 0.15, curve: easeOut, movesRows: false)
      : Step(offset: 0, scale: 0.97, duration: 0.22, curve: firmFast, movesRows: false)
  }
}

/// The banner's numbers (design/sidebar-banner, The row and the popover).
public enum SidebarBannerMetrics {
  public static let rowHeight: CGFloat = 34
  public static let cornerRadius: CGFloat = SidebarMetrics.rowCornerRadius
  /// Row bottom to the bottom bar's top.
  public static let bottomGap: CGFloat = 6
  public static let leadingPadding: CGFloat = 9
  public static let trailingPadding: CGFloat = 5
  public static let gap: CGFloat = 8
  public static let glyphSize: CGFloat = 16
  public static let labelFontSize: CGFloat = 13
  public static let pillHeight: CGFloat = 22
  public static let chevronWidth: CGFloat = 7
  public static let chevronHeight: CGFloat = 12
  /// The chevron's own inset from the trailing padding (design: margin-right 5 with a 4 pt padding).
  public static let chevronTrailing: CGFloat = 5
  /// The hover close button at the row's top leading corner, overhanging it by `closeOverhang`.
  public static let closeSize: CGFloat = 18
  public static let closeOverhang: CGFloat = 6
  /// The row list fades over its last 28 pt while a banner shows.
  public static let rowFade: CGFloat = 28
  /// Height the banner takes from the row list: the row and its gap to the bottom bar.
  public static var reservedHeight: CGFloat { rowHeight + bottomGap }

  public static let popoverWidth: CGFloat = 280
  public static let popoverPadding: CGFloat = 14
  public static let popoverCorner: CGFloat = 12
  public static let popoverTitleSize: CGFloat = 14
  public static let popoverBodySize: CGFloat = 12.5
  /// Row to popover, beside the sidebar.
  public static let popoverGap: CGFloat = 10
}

/// Frames inside the banner row (origin top leading, y down). An update row fits the glyph, "Update" and the Restart
/// pill; when they do not fit (the smallest window), the label hides and the pill takes the rest of the row. An
/// announcement row's title truncates before the trailing chevron.
struct SidebarBannerLayout: Equatable {
  var glyph: CGRect
  var label: CGRect
  var pill: CGRect
  var chevron: CGRect?
  var isCompact: Bool

  init(rowWidth: CGFloat, isUpdate: Bool, labelWidth: CGFloat, pillWidth: CGFloat) {
    typealias M = SidebarBannerMetrics
    let height = M.rowHeight
    let width = max(0, rowWidth)
    glyph = CGRect(x: M.leadingPadding, y: (height - M.glyphSize) / 2, width: M.glyphSize, height: M.glyphSize)
    let textX = glyph.maxX + M.gap
    let trailing = max(textX, width - M.trailingPadding)
    let pillY = (height - M.pillHeight) / 2
    if isUpdate {
      let needed = textX + ceil(labelWidth) + M.gap + pillWidth
      isCompact = needed > trailing
      if isCompact {
        label = CGRect(x: textX, y: 0, width: 0, height: height)
        pill = CGRect(x: textX, y: pillY, width: max(0, trailing - textX), height: M.pillHeight)
      } else {
        pill = CGRect(x: trailing - pillWidth, y: pillY, width: pillWidth, height: M.pillHeight)
        label = CGRect(x: textX, y: 0, width: max(0, pill.minX - M.gap - textX), height: height)
      }
      chevron = nil
    } else {
      isCompact = false
      pill = .zero
      let chevronMaxX = max(textX, trailing - M.chevronTrailing)
      let chevron = CGRect(x: max(textX, chevronMaxX - M.chevronWidth), y: (height - M.chevronHeight) / 2,
                           width: min(M.chevronWidth, chevronMaxX - textX), height: M.chevronHeight)
      self.chevron = chevron
      label = CGRect(x: textX, y: 0, width: max(0, chevron.minX - M.gap - textX), height: height)
    }
  }
}
