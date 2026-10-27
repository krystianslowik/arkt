import AppKit

/// What the hint strip shows (design/command-bar/README.md, Layout): key caps with a caption on the left, an optional
/// line on the right.
struct CommandBarHints: Equatable {
  struct Item: Equatable {
    var keyCaps: [String]
    var caption: String
  }

  /// The right-aligned part: a line of text, then key caps ("Paste and Go" and its shortcut).
  struct Trailing: Equatable {
    var text: String
    var keyCaps: [String] = []
  }

  var items: [Item]
  var trailing: Trailing?

  /// The empty state's line, right-aligned.
  static let emptyStateLine = "Type a URL, a search, or a command"

  /// Move, Open (empty state), Filter, and the Tab item when Tab scopes (`CommandBarTabAction.hint`); on the right the
  /// empty state's line, or Paste and Go with its shortcut.
  static func content(isEmptyQuery: Bool, tab: Item?, offersPasteAndGo: Bool = true) -> CommandBarHints {
    var items = [Item(keyCaps: [CommandBarKeyCaps.up, CommandBarKeyCaps.down], caption: "Move")]
    if isEmptyQuery { items.append(Item(keyCaps: [CommandBarKeyCaps.return], caption: "Open")) }
    items.append(Item(keyCaps: [CommandBarKeyCaps.command, "1\u{2013}4"], caption: "Filter"))
    if let tab { items.append(tab) }
    // Paste and Go is a new-tab surface: Cmd-L and the split pane bar leave it out.
    let trailing: Trailing? = isEmptyQuery
      ? Trailing(text: emptyStateLine)
      : offersPasteAndGo ? Trailing(text: CommandBarResults.pasteAndGoTitle,
                                    keyCaps: [CommandBarKeyCaps.command, CommandBarKeyCaps.shift, "V"]) : nil
    return CommandBarHints(items: items, trailing: trailing)
  }
}

/// The 34 pt strip under the list: a hairline above, key caps 18 pt high, 11.5 pt text.
@MainActor
final class CommandBarHintStrip: NSView {
  private let hairline = NSView()
  private var keyCaps: [CommandBarKeyCapView] = []
  private var labels: [NSTextField] = []
  private let trailingLabel = NSTextField(labelWithString: "")
  private var trailingCaps: [CommandBarKeyCapView] = []
  private(set) var hints = CommandBarHints(items: [], trailing: nil)
  private var flavor: ThemeFlavor = .dark
  private var hasUpdated = false
  /// Item key caps and captions in layout order, for tests.
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
    // A show repeats the previous state: touching nothing keeps the first frame cheap.
    if hasUpdated, hints == self.hints, flavor == self.flavor { return }
    hasUpdated = true
    self.flavor = flavor
    hairline.layer?.backgroundColor = ShellTokens.commandBarDivider.resolve(flavor).cgColor
    trailingLabel.textColor = ShellTokens.commandBarTertiaryText.resolve(flavor).nsColor()
    if hints != self.hints {
      self.hints = hints
      rebuild()
    } else {
      recolor()
    }
    trailingLabel.stringValue = hints.trailing?.text ?? ""
    trailingLabel.isHidden = hints.trailing == nil
    setAccessibilityValue(spokenText)
    needsLayout = true
  }

  /// Whether the right-aligned line shows whole (tests: the left items must leave it room).
  var trailingLineFits: Bool {
    trailingLabel.isHidden || trailingLabel.frame.width >= ceil(trailingLabel.fittingSize.width)
  }

  /// The strip read aloud: "Move, Open".
  var spokenText: String {
    hints.items.map(\.caption).joined(separator: ", ") + (hints.trailing.map { ", " + $0.text } ?? "")
  }

  private func rebuild() {
    (keyCaps as [NSView] + labels as [NSView] + trailingCaps as [NSView]).forEach { $0.removeFromSuperview() }
    keyCaps = []
    labels = []
    trailingCaps = []
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
    for cap in hints.trailing?.keyCaps ?? [] {
      let view = CommandBarKeyCapView(frame: .zero)
      view.configure(cap, flavor: flavor)
      addSubview(view)
      trailingCaps.append(view)
    }
    recolor()
  }

  private func recolor() {
    for cap in keyCaps + trailingCaps { cap.configure(cap.text, flavor: flavor) }
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
      let size = label.fittingSize
      label.frame = NSRect(x: x + 2, y: ((bounds.height - ceil(size.height)) / 2).rounded(),
                           width: ceil(size.width), height: ceil(size.height))
      x = label.frame.maxX + 14
    }
    // The right-aligned part, right to left: key caps, then the line.
    var right = bounds.width - 16
    for cap in trailingCaps.reversed() {
      cap.frame = NSRect(x: right - cap.size.width, y: (bounds.height - CommandBarKeyCapView.height) / 2,
                         width: cap.size.width, height: CommandBarKeyCapView.height)
      right = cap.frame.minX - 4
    }
    if !trailingCaps.isEmpty { right -= 2 }
    let trailingWidth = max(0, right - x)
    let th = ceil(trailingLabel.fittingSize.height)
    trailingLabel.frame = NSRect(x: right - trailingWidth, y: ((bounds.height - th) / 2).rounded(),
                                 width: trailingWidth, height: th)
  }
}
