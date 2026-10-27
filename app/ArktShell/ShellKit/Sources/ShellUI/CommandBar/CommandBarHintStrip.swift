import AppKit

/// What the hint strip shows (design/command-bar/README.md, Layout): key caps with a caption on the left, an optional
/// line on the right.
struct CommandBarHints: Equatable {
  struct Item: Equatable {
    var keyCaps: [String]
    var caption: String
  }

  var items: [Item]
  var trailingText: String?

  /// The empty state's line, right-aligned.
  static let emptyStateLine = "Type a URL, a search, or a command"

  static func content(isEmptyQuery: Bool) -> CommandBarHints {
    CommandBarHints(items: [
      Item(keyCaps: [CommandBarKeyCaps.up, CommandBarKeyCaps.down], caption: "Move"),
      Item(keyCaps: [CommandBarKeyCaps.return], caption: "Open"),
    ], trailingText: isEmptyQuery ? emptyStateLine : nil)
  }
}

/// The 34 pt strip under the list: a hairline above, key caps 18 pt high, 11.5 pt text.
@MainActor
final class CommandBarHintStrip: NSView {
  private let hairline = NSView()
  private var keyCaps: [CommandBarKeyCapView] = []
  private var labels: [NSTextField] = []
  private let trailingLabel = NSTextField(labelWithString: "")
  private(set) var hints = CommandBarHints(items: [], trailingText: nil)
  private var flavor: ThemeFlavor = .dark
  /// Item key caps and captions in layout order, for tests: ("↑↓", "Move").
  private var itemRanges: [(caps: Range<Int>, label: Int)] = []

  override var isFlipped: Bool { true }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    hairline.wantsLayer = true
    addSubview(hairline)
    trailingLabel.font = .systemFont(ofSize: 11.5)
    trailingLabel.lineBreakMode = .byTruncatingHead
    trailingLabel.cell?.usesSingleLineMode = true
    trailingLabel.alignment = .right
    addSubview(trailingLabel)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("Keyboard hints")
    setAccessibilityIdentifier(AXID.CommandBar.hints)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func update(_ hints: CommandBarHints, flavor: ThemeFlavor) {
    self.flavor = flavor
    hairline.layer?.backgroundColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    trailingLabel.textColor = ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor()
    if hints != self.hints {
      self.hints = hints
      rebuild()
    } else {
      recolor()
    }
    trailingLabel.stringValue = hints.trailingText ?? ""
    trailingLabel.isHidden = hints.trailingText == nil
    setAccessibilityValue(spokenText)
    needsLayout = true
  }

  /// The strip read aloud: "Move, Open".
  var spokenText: String {
    hints.items.map(\.caption).joined(separator: ", ") + (hints.trailingText.map { ", " + $0 } ?? "")
  }

  private func rebuild() {
    (keyCaps as [NSView] + labels as [NSView]).forEach { $0.removeFromSuperview() }
    keyCaps = []
    labels = []
    itemRanges = []
    for item in hints.items {
      let start = keyCaps.count
      for cap in item.keyCaps {
        let view = CommandBarKeyCapView(frame: .zero)
        view.configure(cap, flavor: flavor)
        addSubview(view)
        keyCaps.append(view)
      }
      let label = NSTextField(labelWithString: item.caption)
      label.font = .systemFont(ofSize: 11.5)
      label.cell?.usesSingleLineMode = true
      addSubview(label)
      labels.append(label)
      itemRanges.append((start..<keyCaps.count, labels.count - 1))
    }
    recolor()
  }

  private func recolor() {
    for cap in keyCaps { cap.configure(cap.text, flavor: flavor) }
    for label in labels { label.textColor = ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor() }
  }

  override func layout() {
    super.layout()
    let scale = window?.backingScaleFactor ?? 2
    hairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1 / scale)
    var x: CGFloat = 16
    for range in itemRanges {
      for index in range.caps {
        let cap = keyCaps[index]
        cap.frame = NSRect(x: x, y: (bounds.height - CommandBarKeyCapView.height) / 2, width: cap.size.width,
                           height: CommandBarKeyCapView.height)
        x = cap.frame.maxX + 4
      }
      let label = labels[range.label]
      let size = label.intrinsicContentSize
      label.frame = NSRect(x: x + 2, y: ((bounds.height - ceil(size.height)) / 2).rounded(),
                           width: ceil(size.width), height: ceil(size.height))
      x = label.frame.maxX + 16
    }
    let trailingWidth = max(0, bounds.width - 16 - x)
    let th = ceil(trailingLabel.intrinsicContentSize.height)
    trailingLabel.frame = NSRect(x: bounds.width - 16 - trailingWidth, y: ((bounds.height - th) / 2).rounded(),
                                 width: trailingWidth, height: th)
  }
}
