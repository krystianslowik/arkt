import AppKit
import EngineAPI

/// One extension in the Extensions panel (design/extensions, direction C): a grip (pinned rows only), the icon (or a
/// neutral puzzle tile without one), the name, the status line, the pin toggle and the "..." button. Clicking the icon
/// and labels runs the action anchored to this row. Right-click, Ctrl-click, "..." and the accessibility show-menu
/// action open the engine's context menu (#596, `ExtensionContextMenuView`). Pinned rows offer Move Left and Move Right
/// as accessibility actions, so a drag is never the only way to order them. Frames are set in `layout()`.
@MainActor
final class ExtensionsPanelRow: ExtensionContextMenuView {
  private(set) var action: ExtensionAction
  let grip = ExtensionsGripView(frame: .zero)
  let runButton = ExtensionsRowButton()
  let pinToggle = ExtensionsPinToggle()
  let moreButton: DownloadIconButton
  let nameLabel = NSTextField(labelWithString: "")
  let statusLabel = NSTextField(labelWithString: "")
  private let background = CALayer()
  private let tile = CALayer()
  private let glyph = CALayer()
  private let dot = CALayer()
  /// The pinned place (index and the number of pinned rows), nil for a row under Not pinned.
  private(set) var place: (index: Int, count: Int)?
  private(set) var isLifted = false

  var onRun: (@MainActor (ExtensionsPanelRow) -> Void)?
  var onTogglePin: (@MainActor (ExtensionsPanelRow) -> Void)?
  /// Move Left (-1) or Move Right (1); true when it moved.
  var onMove: (@MainActor (ExtensionsPanelRow, Int) -> Bool)?

  var isPinned: Bool { action.isPinned }
  /// Increase Contrast: a 1 pt edge around the row.
  var showsContrastEdge = false {
    didSet { if showsContrastEdge != oldValue { restyle() } }
  }
  var showsAttentionDot: Bool { !dot.isHidden }
  var showsIconImage: Bool { tile.contents != nil }

  init(action: ExtensionAction) {
    self.action = action
    moreButton = DownloadIconButton(symbol: "ellipsis", label: "More for \(action.name)")
    super.init(frame: NSRect(x: 0, y: 0, width: ExtensionsPanelMetrics.width, height: ExtensionsPanelMetrics.rowHeight))
    wantsLayer = true
    layer?.addSublayer(background)
    background.cornerRadius = ExtensionsPanelMetrics.rowCorner
    background.cornerCurve = .continuous
    tile.cornerRadius = ExtensionsPanelMetrics.iconCorner
    tile.cornerCurve = .continuous
    tile.masksToBounds = true
    tile.contentsGravity = .resizeAspect
    tile.addSublayer(glyph)
    dot.isHidden = true
    for label in [nameLabel, statusLabel] {
      label.lineBreakMode = .byTruncatingTail
      label.maximumNumberOfLines = 1
      label.cell?.truncatesLastVisibleLine = true
      label.setAccessibilityElement(false)
    }
    nameLabel.font = .systemFont(ofSize: 13)
    statusLabel.font = .systemFont(ofSize: 12)
    runButton.target = self
    runButton.action = #selector(runPressed(_:))
    pinToggle.target = self
    pinToggle.action = #selector(pinPressed(_:))
    moreButton.target = self
    moreButton.action = #selector(morePressed(_:))
    for view in [runButton, grip, nameLabel, statusLabel, pinToggle, moreButton] as [NSView] { addSubview(view) }
    layer?.addSublayer(tile)
    layer?.addSublayer(dot)
    runButton.setAccessibilityIdentifierWithCell(AXID.Extensions.rowRun)
    pinToggle.setAccessibilityIdentifierWithCell(AXID.Extensions.rowPin)
    moreButton.setAccessibilityIdentifierWithCell(AXID.Extensions.rowMore)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Extensions.row)
    apply(action, place: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  // MARK: Content

  /// Shows `action` at its pinned `place` (nil: not pinned).
  func apply(_ action: ExtensionAction, place: (index: Int, count: Int)?) {
    let iconChanged = action.iconPNG != self.action.iconPNG || tile.contents == nil && action.iconPNG != nil
    self.action = action
    self.place = place
    let status = ExtensionsPanelModel.status(of: action)
    nameLabel.stringValue = action.name
    statusLabel.stringValue = status.text
    dot.isHidden = !status.needsAttention
    grip.isHidden = place == nil
    pinToggle.isOn = action.isPinned
    pinToggle.setArchiveAccessibilityLabel("Pin \(action.name)")
    pinToggle.toolTip = action.isPinned ? "Unpin" : "Pin"     // [I] product wording
    moreButton.setArchiveAccessibilityLabel("More for \(action.name)")
    runButton.setArchiveAccessibilityLabel("\(action.name), \(status.text)")
    runButton.setArchiveAccessibilityValue(action.id)
    setAccessibilityLabel(action.name)
    setAccessibilityCustomActions(moveActions(place))
    if iconChanged || tile.contents == nil { applyIcon() }
    alphaValue = 1
    restyle()
    needsLayout = true
  }

  private func moveActions(_ place: (index: Int, count: Int)?) -> [NSAccessibilityCustomAction] {
    guard let place else { return [] }
    var actions: [NSAccessibilityCustomAction] = []
    if place.index > 0 {
      actions.append(NSAccessibilityCustomAction(name: "Move Left") { [weak self] in
        guard let self else { return false }
        return MainActor.assumeIsolated { self.onMove?(self, -1) ?? false }
      })
    }
    if place.index < place.count - 1 {
      actions.append(NSAccessibilityCustomAction(name: "Move Right") { [weak self] in
        guard let self else { return false }
        return MainActor.assumeIsolated { self.onMove?(self, 1) ?? false }
      })
    }
    return actions
  }

  private func applyIcon() {
    let image = action.iconPNG.flatMap(NSImage.init(data:))
    ArchiveMotion.set {
      tile.contents = image
      glyph.isHidden = image != nil
    }
    restyle()
  }

  // MARK: Actions

  @objc private func runPressed(_ sender: Any?) { onRun?(self) }
  @objc private func pinPressed(_ sender: Any?) { onTogglePin?(self) }

  @objc private func morePressed(_ sender: Any?) {
    guard let menu = menuProvider?() else { return }
    presentMenu(menu, moreButton)
  }

  /// Ctrl-click on the row: the context menu below the row.
  func showMenu() {
    guard let menu = menuProvider?() else { return }
    presentMenu(menu, self)
  }

  // MARK: Lift

  /// The row lifted by its grip: the hovered-row fill and the overlay shadow; the panel sets its transform.
  func setLifted(_ lifted: Bool) {
    guard lifted != isLifted else { return }
    isLifted = lifted
    layer?.zPosition = lifted ? 1 : 0
    restyle()
  }

  // MARK: Layout and style

  override func layout() {
    super.layout()
    let m = ExtensionsPanelMetrics.self
    let height = bounds.height
    let button = m.buttonSize
    let moreX = bounds.width - 4 - button
    let pinX = moreX - 2 - button
    let gripX: CGFloat = 4
    let iconX = gripX + m.gripWidth + 8
    let iconY = ((height - m.iconSize) / 2).rounded()
    let textX = iconX + m.iconSize + 10
    let textWidth = max(0, pinX - 8 - textX)
    grip.frame = NSRect(x: gripX, y: 0, width: m.gripWidth, height: height)
    pinToggle.frame = NSRect(x: pinX, y: ((height - button) / 2).rounded(), width: button, height: button)
    moreButton.frame = NSRect(x: moreX, y: ((height - button) / 2).rounded(), width: button, height: button)
    nameLabel.frame = NSRect(x: textX, y: 5, width: textWidth, height: 17)
    statusLabel.frame = NSRect(x: textX, y: 22, width: textWidth, height: 16)
    runButton.frame = NSRect(x: iconX - 4, y: 2, width: pinX - 4 - (iconX - 4), height: height - 4)
    ArchiveMotion.set {
      background.frame = bounds
      tile.frame = CGRect(x: iconX, y: iconY, width: m.iconSize, height: m.iconSize)
      glyph.frame = CGRect(x: (m.iconSize - 16) / 2, y: (m.iconSize - 16) / 2, width: 16, height: 16)
      dot.frame = CGRect(x: iconX + m.iconSize - 6, y: iconY - 2, width: 8, height: 8)
      dot.cornerRadius = 4
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  private func restyle() {
    let flavor = archiveFlavor
    nameLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    statusLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    nameLabel.alphaValue = action.isEnabled ? 1 : 0.55
    let shadow = ShellTokens.overlayShadow
    ArchiveMotion.set {
      tile.backgroundColor = showsIconImage ? nil : ShellTokens.letterTileFill.resolve(flavor).cgColor
      glyph.contents = SymbolImageCache.shared.symbol(
        "puzzlepiece.extension", box: 16, color: ShellTokens.sidebarForeground.resolve(flavor),
        scale: window?.backingScaleFactor ?? 2)
      dot.backgroundColor = ShellTokens.primaryText.resolve(flavor).cgColor
      dot.borderColor = AlertTokens.dialogSurface.resolve(flavor).cgColor
      dot.borderWidth = 1.5
      background.backgroundColor = isLifted ? AlertTokens.dialogSurface.resolve(flavor).cgColor : nil
      background.borderWidth = showsContrastEdge ? 1 : 0
      background.borderColor = AlertTokens.increasedContrastEdge.resolve(flavor).cgColor
      background.shadowColor = shadow.color.resolve(flavor).cgColor
      background.shadowOpacity = isLifted ? 1 : 0
      background.shadowRadius = shadow.radius / 2
      background.shadowOffset = CGSize(width: 0, height: shadow.flippedOffset.height / 2)   // this view is flipped
    }
  }
}
