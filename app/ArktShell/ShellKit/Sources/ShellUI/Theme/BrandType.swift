import AppKit

/// The brand face for first run, About and other brand moments (onboarding spec, section 3): Avenir Next, used by
/// PostScript name from the copy macOS ships in `/System/Library/Fonts`. Never bundled or redistributed. When a face
/// is missing, the system font at the same size and weight takes its place and every layout keeps working.
///
/// Tracking is per size (`kern` = em x size), never one value for every size; display lines get a fixed line height
/// (size x leading). Browser chrome stays on the system font.
@MainActor
public enum BrandType {
  public enum Weight: Sendable, CaseIterable {
    case regular, medium, demiBold

    public var postScriptName: String {
      switch self {
      case .regular: "AvenirNext-Regular"
      case .medium: "AvenirNext-Medium"
      case .demiBold: "AvenirNext-DemiBold"
      }
    }

    /// The system font weight that stands in for the face.
    public var systemWeight: NSFont.Weight {
      switch self {
      case .regular: .regular
      case .medium: .medium
      case .demiBold: .semibold
      }
    }
  }

  /// A font lookup by PostScript name and size; `NSFont(name:size:)` in the app, injectable in tests.
  public typealias Lookup = (String, CGFloat) -> NSFont?

  /// The face at `size`, or the system font at the same size and weight when the face is missing.
  public static func font(_ weight: Weight, size: CGFloat,
                          lookup: Lookup = { NSFont(name: $0, size: $1) }) -> NSFont {
    lookup(weight.postScriptName, size) ?? .systemFont(ofSize: size, weight: weight.systemWeight)
  }

  /// Tabular figures of the face (counts and the "2 of 6" progress).
  public static func tabularFont(_ weight: Weight, size: CGFloat) -> NSFont {
    let base = font(weight, size: size)
    let descriptor = base.fontDescriptor.addingAttributes([
      .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                          NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]],
    ])
    return NSFont(descriptor: descriptor, size: size) ?? base
  }

  /// Tracking in points for a tracking of `em` at `size`.
  public nonisolated static func kern(em: CGFloat, size: CGFloat) -> CGFloat { em * size }

  // MARK: - Roles

  public struct Style: Equatable, Sendable {
    public var weight: Weight
    public var size: CGFloat
    /// Line height as a multiple of the size; nil keeps the font's own.
    public var leading: CGFloat?
    public var trackingEm: CGFloat
    public var uppercase: Bool
    /// Figures of equal width (counts, progress).
    public var tabular: Bool

    public var lineHeight: CGFloat? { leading.map { size * $0 } }
    public var kern: CGFloat { BrandType.kern(em: trackingEm, size: size) }
  }

  /// The type table of section 3, with the compact sizes of section 4 (windows below 700 pt tall).
  public enum Role: Sendable, CaseIterable {
    case welcomeTitle, stepTitle, importTitle, nameField, countLarge, countRow
    case lede, welcomeLede, note, eyebrow, countLabel, countLabelLarge
    case button, quiet, progress, option, themeName, previewName, keyCap
    /// The browser data import's Hero entry (#514): headline, row name, detail, count, status, note and progress line.
    case dataTitle, dataRow, dataDetail, dataCount, dataStatus, dataNote, dataProgress

    public nonisolated func style(compact: Bool) -> Style {
      func display(_ size: CGFloat, _ compactSize: CGFloat, leading: CGFloat = 0.92) -> Style {
        Style(weight: .demiBold, size: compact ? compactSize : size, leading: leading, trackingEm: -0.055,
              uppercase: false, tabular: false)
      }
      func text(_ weight: Weight, _ size: CGFloat, tracking: CGFloat = 0, leading: CGFloat? = nil,
                uppercase: Bool = false, tabular: Bool = false) -> Style {
        Style(weight: weight, size: size, leading: leading, trackingEm: tracking, uppercase: uppercase,
              tabular: tabular)
      }
      switch self {
      case .welcomeTitle: return display(80, 72)
      case .stepTitle: return display(64, 56)
      case .importTitle: return display(54, 54)
      case .nameField: return display(64, 56, leading: 1.02)
      case .countLarge:
        return Style(weight: .demiBold, size: compact ? 176 : 210, leading: 0.86, trackingEm: -0.04,
                     uppercase: false, tabular: true)
      case .countRow:
        return Style(weight: .demiBold, size: compact ? 56 : 64, leading: 0.86, trackingEm: -0.04,
                     uppercase: false, tabular: true)
      case .lede: return text(.regular, 18, leading: 1.5)
      case .welcomeLede: return text(.regular, 20, leading: 1.5)
      case .note: return text(.regular, 16, leading: 1.5)
      case .eyebrow: return text(.demiBold, 12, tracking: 0.16, uppercase: true)
      case .countLabel: return text(.demiBold, 11, tracking: 0.16, uppercase: true)
      case .countLabelLarge: return text(.demiBold, 13, tracking: 0.16, uppercase: true)
      case .button: return text(.demiBold, 15, tracking: 0.005)
      case .quiet: return text(.medium, 14)
      case .progress: return text(.regular, 13, tracking: 0.01, tabular: true)
      case .option: return text(.medium, 15)
      case .themeName: return text(.regular, 13)
      case .previewName: return text(.medium, 9)
      case .keyCap: return text(.demiBold, 30)
      case .dataTitle: return display(56, 46)
      case .dataRow: return text(.medium, compact ? 16 : 18)
      case .dataDetail: return text(.regular, compact ? 13 : 14)
      case .dataCount:
        return Style(weight: .demiBold, size: compact ? 22 : 26, leading: nil, trackingEm: -0.02, uppercase: false,
                     tabular: true)
      case .dataStatus: return text(.regular, compact ? 16 : 18, tabular: true)
      case .dataNote: return text(.regular, 15, leading: 1.45)
      case .dataProgress: return text(.demiBold, 15)
      }
    }
  }

  /// Where a display line's glyphs sit, the CSS way: with a fixed line height below the font's own (titles at 0.92,
  /// counts at 0.86) CSS splits the overlap evenly above and below, while AppKit lets it all spill above the line.
  /// The renderer moves the glyphs down by this much to match the website.
  public static func cssShift(font: NSFont, lineHeight: CGFloat) -> CGFloat {
    max(0, ((font.ascender - font.descender) - lineHeight) / 2)
  }

  public static func font(for style: Style) -> NSFont {
    style.tabular ? tabularFont(style.weight, size: style.size) : font(style.weight, size: style.size)
  }

  /// `text` set in `role`: font, colour, per-size kern and, for roles with a leading, a fixed line height.
  public static func attributed(_ text: String, role: Role, color: NSColor, compact: Bool = false,
                                alignment: NSTextAlignment = .center) -> NSAttributedString {
    let style = role.style(compact: compact)
    return NSAttributedString(string: style.uppercase ? text.uppercased() : text,
                              attributes: attributes(style, color: color, alignment: alignment))
  }

  public static func attributes(_ style: Style, color: NSColor,
                                alignment: NSTextAlignment = .center) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let font = font(for: style)
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: style.kern]
    if let lineHeight = style.lineHeight {
      paragraph.minimumLineHeight = lineHeight
      paragraph.maximumLineHeight = lineHeight
    }
    attributes[.paragraphStyle] = paragraph
    return attributes
  }
}
