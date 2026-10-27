import AppKit

/// The four filter pills in one capsule right of the query field (design/command-bar/README.md, Filters): 22 pt pills
/// in a 26 pt capsule, 12 pt medium titles and 10.5 pt tabular counts. Display only here; the controller sets the
/// selection and counts.
@MainActor
final class CommandBarFilterPills: NSView {
  static let capsuleHeight: CGFloat = 26
  static let pillHeight: CGFloat = 22
  private static let inset: CGFloat = 2
  private static let pillPadding: CGFloat = 10
  private static let titleCountGap: CGFloat = 5
  /// The selected pill's count is the pill text at 75 %: the design's 55 % reads 3.4:1 on the pill, below the 4.5:1 the
  /// README asks of secondary text (`ShellTokensContrastTests`).
  static let selectedCountAlpha = 0.75

  static func selectedCountColor(_ flavor: ThemeFlavor) -> RGBA {
    var color = ShellTokens.commandBarPillOnText.resolve(flavor)
    color.alpha = selectedCountAlpha
    return color
  }

  private final class Pill: NSView {
    let filter: CommandBarFilter
    let title = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")
    var isOn = false
    var countText = ""
    var flavor: ThemeFlavor = .dark

    init(filter: CommandBarFilter) {
      self.filter = filter
      super.init(frame: .zero)
      wantsLayer = true
      layer?.cornerRadius = CommandBarFilterPills.pillHeight / 2
      layer?.cornerCurve = .continuous
      title.font = .systemFont(ofSize: 12, weight: .medium)
      title.stringValue = filter.title
      count.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
      for label in [title, count] {
        label.lineBreakMode = .byClipping
        label.cell?.usesSingleLineMode = true
        addSubview(label)
      }
      setAccessibilityElement(true)
      setAccessibilityRole(.radioButton)
      setAccessibilityIdentifier(AXID.CommandBar.filter(filter))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var fittingWidth: CGFloat {
      let countWidth = count.isHidden ? 0 : CommandBarFilterPills.titleCountGap + ceil(count.intrinsicContentSize.width)
      return 2 * CommandBarFilterPills.pillPadding + ceil(title.intrinsicContentSize.width) + countWidth
    }

    func applyColors() {
      layer?.backgroundColor = isOn ? ShellTokens.commandBarPillOn.resolve(flavor).cgColor : nil
      let ink = isOn ? ShellTokens.commandBarPillOnText.resolve(flavor)
                     : ShellTokens.commandBarSecondaryText.resolve(flavor)
      title.textColor = ink.nsColor()
      count.textColor = isOn ? CommandBarFilterPills.selectedCountColor(flavor).nsColor()
                             : ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor()
    }

    override func layout() {
      super.layout()
      var x = CommandBarFilterPills.pillPadding
      let th = ceil(title.intrinsicContentSize.height)
      title.frame = NSRect(x: x, y: (bounds.height - th) / 2, width: ceil(title.intrinsicContentSize.width), height: th)
      x = title.frame.maxX + CommandBarFilterPills.titleCountGap
      let ch = ceil(count.intrinsicContentSize.height)
      count.frame = NSRect(x: x, y: (bounds.height - ch) / 2, width: ceil(count.intrinsicContentSize.width), height: ch)
    }
  }

  private let pills = CommandBarFilter.allCases.map { Pill(filter: $0) }
  private(set) var selected: CommandBarFilter = .all
  private(set) var counts: [CommandBarFilter: Int] = [:]
  private(set) var showsCounts = false
  private var flavor: ThemeFlavor = .dark

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = Self.capsuleHeight / 2
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 0.5
    pills.forEach(addSubview)
    setAccessibilityElement(true)
    setAccessibilityRole(.tabGroup)
    setAccessibilityLabel("Filters")
    setAccessibilityIdentifier(AXID.CommandBar.filters)
    update(selected: .all, counts: [:], showsCounts: false, flavor: .dark)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func update(selected: CommandBarFilter, counts: [CommandBarFilter: Int], showsCounts: Bool, flavor: ThemeFlavor) {
    self.selected = selected
    self.counts = counts
    self.showsCounts = showsCounts
    self.flavor = flavor
    layer?.backgroundColor = ShellTokens.commandBarPillWell.resolve(flavor).cgColor
    layer?.borderColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    for pill in pills {
      let n = counts[pill.filter] ?? 0
      pill.isOn = pill.filter == selected
      pill.flavor = flavor
      pill.countText = showsCounts ? String(n) : ""
      pill.count.stringValue = pill.countText
      pill.count.isHidden = !showsCounts
      pill.setAccessibilityLabel(Self.accessibilityLabel(for: pill.filter, count: n, showsCount: showsCounts,
                                                         isSelected: pill.isOn))
      pill.setAccessibilityValue(pill.isOn ? 1 : 0)
      pill.setAccessibilitySelected(pill.isOn)
      pill.applyColors()
    }
    invalidateIntrinsicContentSize()
    needsLayout = true
  }

  /// "<name>, <count> results, selected"; without counts (empty query) just the name and state.
  static func accessibilityLabel(for filter: CommandBarFilter, count: Int, showsCount: Bool, isSelected: Bool) -> String {
    var parts = [filter.title]
    if showsCount { parts.append(count == 1 ? "1 result" : "\(count) results") }
    if isSelected { parts.append("selected") }
    return parts.joined(separator: ", ")
  }

  override var intrinsicContentSize: NSSize { size }

  var size: NSSize {
    NSSize(width: 2 * Self.inset + pills.reduce(0) { $0 + $1.fittingWidth } + CGFloat(pills.count - 1) * 2,
           height: Self.capsuleHeight)
  }

  /// Pill frames in the capsule's coordinates, in order (tests).
  var pillFrames: [NSRect] { pills.map(\.frame) }

  override func layout() {
    super.layout()
    var x = Self.inset
    for pill in pills {
      let w = pill.fittingWidth
      pill.frame = NSRect(x: x, y: Self.inset, width: w, height: Self.pillHeight)
      x += w + 2
    }
  }
}
