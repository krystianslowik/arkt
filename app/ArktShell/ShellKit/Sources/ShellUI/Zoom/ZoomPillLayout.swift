import CoreGraphics

/// The zoom pill's geometry (design/extensions/prototype.html `.zoom`, surface `surf-zoom`): a 36 pt pill 12 points from
/// the top and trailing edges of the page, 6 points of padding at each end, 2 points between the parts, the round
/// 24 pt minus and plus buttons around a 48 pt percent, and the small Reset pill 4 points further on. While the find
/// bar shows, the pill sits 8 points below it. Y points up.
enum ZoomPillLayout {
  static let height: CGFloat = 36
  static let cornerRadius: CGFloat = 18
  /// From the top and trailing edges of the page.
  static let edgeInset: CGFloat = 12
  static let padding: CGFloat = 6
  static let gap: CGFloat = 2
  static let buttonSize: CGFloat = 24
  static let percentWidth: CGFloat = 48
  /// Extra space before Reset.
  static let resetMargin: CGFloat = 4
  /// Between the find bar and the pill when both show.
  static let stackGap: CGFloat = 8
  /// The percent is one text line, 20 points high.
  static let textHeight: CGFloat = 20

  struct Parts: Equatable {
    var zoomOut: CGRect
    var percent: CGRect
    var zoomIn: CGRect
    var reset: CGRect
  }

  /// The pill's width for a Reset pill `resetWidth` wide.
  static func width(resetWidth: CGFloat) -> CGFloat {
    padding + buttonSize + gap + percentWidth + gap + buttonSize + gap + resetMargin + resetWidth + padding
  }

  /// The pill's frame in `content`, the page's area below the Toolbar: at the top trailing corner, or below `findBar`
  /// (the find bar's frame) while it shows. Never wider than the page minus the insets.
  static func frame(in content: CGRect, resetWidth: CGFloat, below findBar: CGRect? = nil) -> CGRect {
    let width = min(self.width(resetWidth: resetWidth), max(0, content.width - 2 * edgeInset))
    let top = findBar.map { $0.minY - stackGap } ?? content.maxY - edgeInset
    return CGRect(x: content.maxX - edgeInset - width, y: top - height, width: width, height: height)
  }

  /// The parts from the leading edge.
  static func parts(resetWidth: CGFloat) -> Parts {
    let buttonY = (height - buttonSize) / 2
    let zoomOut = CGRect(x: padding, y: buttonY, width: buttonSize, height: buttonSize)
    let percent = CGRect(x: zoomOut.maxX + gap, y: (height - textHeight) / 2, width: percentWidth, height: textHeight)
    let zoomIn = CGRect(x: percent.maxX + gap, y: buttonY, width: buttonSize, height: buttonSize)
    let reset = CGRect(x: zoomIn.maxX + gap + resetMargin, y: buttonY, width: resetWidth, height: buttonSize)
    return Parts(zoomOut: zoomOut, percent: percent, zoomIn: zoomIn, reset: reset)
  }
}
