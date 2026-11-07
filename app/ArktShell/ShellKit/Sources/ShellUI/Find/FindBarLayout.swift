import CoreGraphics

/// The find bar's geometry, direction A (design/find-in-page/prototype.html `.fa`): a 372 x 36 pill 12 points from the
/// top and trailing edges of the page, 13 points of padding before the glyph and 6 after the close button, 8 points
/// between the parts, and a 1 x 14 hairline with 2 points of margin before the step buttons. Y points up.
enum FindBarLayout {
  static let preferredWidth: CGFloat = 372
  static let height: CGFloat = 36
  static let cornerRadius: CGFloat = 18
  /// From the top and trailing edges of the page.
  static let edgeInset: CGFloat = 12
  static let leadingPadding: CGFloat = 13
  static let trailingPadding: CGFloat = 6
  static let gap: CGFloat = 8
  static let glyphSize: CGFloat = 14
  static let buttonSize: CGFloat = 24
  static let separatorMargin: CGFloat = 2
  static let separatorHeight: CGFloat = 14
  /// The field and the count are one text line, 20 points high.
  static let textHeight: CGFloat = 20
  static let minimumCountWidth: CGFloat = 56

  struct Parts: Equatable {
    var glyph: CGRect
    var field: CGRect
    var count: CGRect
    var separator: CGRect
    var previous: CGRect
    var next: CGRect
    var close: CGRect
  }

  /// The bar's frame in `content`, the page's area below the Toolbar: 372 wide, or the width minus 24 when that is less.
  static func frame(in content: CGRect) -> CGRect {
    let width = min(preferredWidth, max(0, content.width - 2 * edgeInset))
    return CGRect(x: content.maxX - edgeInset - width, y: content.maxY - edgeInset - height, width: width, height: height)
  }

  /// The count is at least 56 wide and as wide as its text.
  static func countWidth(textWidth: CGFloat) -> CGFloat {
    max(minimumCountWidth, textWidth.rounded(.up))
  }

  /// The parts of a bar `width` wide: laid out from the trailing edge, the field takes what is left.
  static func parts(width: CGFloat, countWidth: CGFloat) -> Parts {
    let buttonY = (height - buttonSize) / 2
    let textY = (height - textHeight) / 2
    func button(_ x: CGFloat) -> CGRect { CGRect(x: x, y: buttonY, width: buttonSize, height: buttonSize) }
    let close = button(width - trailingPadding - buttonSize)
    let next = button(close.minX - gap - buttonSize)
    let previous = button(next.minX - gap - buttonSize)
    let separator = CGRect(x: previous.minX - gap - separatorMargin - 1, y: (height - separatorHeight) / 2,
                           width: 1, height: separatorHeight)
    let count = CGRect(x: separator.minX - separatorMargin - gap - countWidth, y: textY, width: countWidth,
                       height: textHeight)
    let glyph = CGRect(x: leadingPadding, y: (height - glyphSize) / 2, width: glyphSize, height: glyphSize)
    let fieldX = glyph.maxX + gap
    let field = CGRect(x: fieldX, y: textY, width: max(0, count.minX - gap - fieldX), height: textHeight)
    return Parts(glyph: glyph, field: field, count: count, separator: separator, previous: previous, next: next,
                 close: close)
  }
}
