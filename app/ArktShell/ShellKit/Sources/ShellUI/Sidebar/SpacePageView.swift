import AppKit
import Motion

/// Space header geometry (#106). TODO(measure): Arc's header edit icon and field were not measured.
extension SidebarMetrics {
  /// Title end to the hover edit button's hit box.
  static let spaceEditButtonGap: CGFloat = 2
  static let spaceEditGlyphSize: CGFloat = 11
  /// The rename field's fill reaches this far past the text on each side.
  static let spaceRenameFillInsetX: CGFloat = 6
  static let spaceRenameFillInsetY: CGFloat = 3
  static let spaceRenameFillCornerRadius: CGFloat = 6
}

/// One Space page: the Space header (title, 12 pt secondary at x 16) above the scrolling pinned + Today outline.
///
/// The title renames in place (BH-038): a click on it that stays under `spaceHeaderDragThreshold`, the hover edit
/// button, or `beginRename()` (Spaces > Rename Space, New Space) opens it with the whole name selected. A longer drag
/// in the header reorders Spaces (BH-039, "Drag to Reorder Space"): the title follows the pointer 1:1, rubber-banded
/// where no Space is left to pass, and one slot is one header width (a drag commits a move at half of it, like a swipe
/// between Space pages). On release `moveSpace` applies the move and the title springs home from where it was with the
/// release velocity; a press during the spring catches it there. Reduce Motion snaps. Hovering the header also shows a
/// "..." menu for the icon and the theme. Return or leaving the field saves the trimmed name through the source;
/// Escape, or an empty name [I], keeps the old one. Opening and closing the field is instant: it is a direct response
/// to a click or a key.
@MainActor
public final class SpacePageView: NSView, NSTextFieldDelegate, SpacePagerPage {
  public let spaceID: SpaceID
  public let titleLabel = NSTextField(labelWithString: "")
  /// BH-038: shown while the header is hovered; fades with the rows' hover close timing (Reduce Motion: at once).
  public let editButton = HoverCloseButton(frame: .zero)
  /// BH-038: the header "..." menu (icon, theme, disabled Profile). Shown with the edit button.
  public let optionsButton = HoverCloseButton(frame: .zero)
  public let scrollView: SidebarScrollView
  public let outlineController: SidebarOutlineController
  /// The title field is open for editing.
  public private(set) var isRenaming = false
  private let source: any SidebarSource
  /// Behind the open field, so it reads as editable.
  private let renameFill = NSView(frame: .zero)
  private var titleBeforeRename = ""
  private var renameCancelled = false
  private var headerHoverArea: NSTrackingArea?
  private var headerToolTip: NSView.ToolTipTag?
  /// The rect `headerToolTip` covers; nil while the title is open, which shows no reorder tip.
  private var headerToolTipRect: NSRect?
  /// Header tool tips installed so far (for tests: a layout that changes nothing installs none).
  private(set) var headerToolTipInstallsForTesting = 0
  static let reorderToolTip = "Drag to Reorder Space"
  /// The press in the header, from mouse down to mouse up.
  private var headerPress: HeaderPress?
  /// How far the title is drawn from its resting place while it follows a header drag or springs back.
  private(set) var headerDragOffset: CGFloat = 0
  /// Springs the title home after a header drag. Tests swap it for one with a fixed clock or Reduce Motion.
  var headerSettle = SpringDriver()
  private var headerDragVelocity = VelocityTracker()
  /// TODO(parity): Arc's header drag was not measured; a critically damped return, no bounce.
  static let headerSettlePreset = SpringParameters(dampingRatio: 1, response: 0.3)

  private struct HeaderPress {
    var origin: NSPoint
    var onTitle: Bool
    /// `headerDragOffset` when the press began: not 0 when it caught the title mid-spring.
    var startOffset: CGFloat
    var isDragging: Bool
    var lastX: CGFloat
  }

  public init(source: any SidebarSource, spaceID: SpaceID) {
    self.spaceID = spaceID
    self.source = source
    let scrollView = SidebarScrollView(frame: .zero)
    self.scrollView = scrollView
    self.outlineController = SidebarOutlineController(source: source, spaceID: spaceID, hostedIn: scrollView)
    super.init(frame: .zero)
    let info = source.space(spaceID)
    titleLabel.stringValue = info?.title ?? ""
    titleLabel.font = .systemFont(ofSize: SidebarMetrics.spaceTitleFontSize, weight: .medium)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.usesSingleLineMode = true
    titleLabel.cell?.isScrollable = false
    titleLabel.autoresizingMask = []
    titleLabel.delegate = self
    titleLabel.setAccessibilityIdentifierWithCell(AXID.Sidebar.spaceTitle)
    titleLabel.toolTip = Self.reorderToolTip
    renameFill.wantsLayer = true
    renameFill.layer?.cornerRadius = SidebarMetrics.spaceRenameFillCornerRadius
    renameFill.isHidden = true
    renameFill.autoresizingMask = []
    editButton.target = self
    editButton.action = #selector(editButtonPressed(_:))
    editButton.toolTip = "Rename Space"                                           // [I] wording
    editButton.setAccessibilityLabel("Rename Space")
    editButton.setAccessibilityIdentifierWithCell(AXID.Sidebar.spaceRename)
    optionsButton.target = self
    optionsButton.action = #selector(optionsButtonPressed(_:))
    optionsButton.toolTip = "Space Options"
    optionsButton.setAccessibilityLabel("Space Options")
    optionsButton.setAccessibilityIdentifierWithCell(AXID.Sidebar.spaceOptions)
    scrollView.autoresizingMask = []
    addSubview(renameFill)
    addSubview(titleLabel)
    addSubview(editButton)
    addSubview(optionsButton)
    addSubview(scrollView)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Sidebar.page)
    setAccessibilityLabel(titleLabel.stringValue)
    outlineView.axProxyRows.setParent(self)
    setFlavor(info?.theme.flavor ?? .light)
  }

  /// The header, then the proxy outline (`sidebar.outline`, #269) in place of the scroll view that holds the real
  /// outline: `NSOutlineView` does not publish its rows out of process.
  public override func accessibilityChildren() -> [Any]? {
    let children = (super.accessibilityChildren() ?? []).filter { child in
      let view = (child as? NSView) ?? (child as? NSCell)?.controlView
      return !(view?.isDescendant(of: scrollView) ?? false)
    }
    return scrollView.isHidden ? children : children + [outlineView.axProxyRows.element]
  }

  /// Applies the Space's current title and flavor after a Space change; unchanged fields cost nothing. An open title
  /// field keeps what is typed in it.
  public func refresh(from info: SidebarSpaceInfo?) {
    let title = info?.title ?? ""
    if !isRenaming, titleLabel.stringValue != title {
      titleLabel.stringValue = title
      setAccessibilityLabel(title)
      needsLayout = true
    }
    let flavor = info?.theme.flavor ?? .light
    if flavor != self.flavor { setFlavor(flavor) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  public override var isFlipped: Bool { true }

  public var outlineView: SidebarOutlineView { outlineController.outlineView }

  /// Realizes the rows around the outline's scrolled position (#297). The pager calls this with the strip slid
  /// so the page intersects the visible area: rows tiled in that state survive being parked again. The page is
  /// shown only for the layout itself and hidden again before this returns; nothing paints in between.
  public func constructVisibleRowsForDisplay() {
    isHidden = false
    layoutSubtreeIfNeeded()
    outlineView.tile()
    isHidden = true
  }

  public private(set) var flavor: ThemeFlavor = .light

  /// Pages keep their own Space's flavor (and appearance, for the scroller) while they slide past.
  public func setFlavor(_ flavor: ThemeFlavor) {
    self.flavor = flavor
    appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    applyTitleColors()
    applyHeaderGlyphs()
    outlineController.setFlavor(flavor)
  }

  private func applyTitleColors() {
    let token = isRenaming ? ShellTokens.primaryText : ShellTokens.secondaryText
    titleLabel.textColor = token.resolve(flavor).nsColor()
    renameFill.layer?.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
  }

  private func applyHeaderGlyphs() {
    let color = ShellTokens.sidebarForeground.resolve(flavor)
    let scale = shellBackingScale
    editButton.image = SymbolImageCache.shared.symbol(
      "pencil", box: SidebarMetrics.spaceEditGlyphSize, weight: .semibold, color: color, scale: scale)
    optionsButton.image = SymbolImageCache.shared.symbol(
      "ellipsis", box: SidebarMetrics.spaceEditGlyphSize, weight: .semibold, color: color, scale: scale)
  }

  /// Glyph bitmaps are per backing scale; re-render the realized rows when the window's scale changes.
  public override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    applyHeaderGlyphs()
    outlineController.refreshRealizedCells()
  }

  public override func layout() {
    super.layout()
    layoutHeader()
    let padding = SidebarMetrics.horizontalPadding
    let scrollFrame = NSRect(x: padding, y: SidebarMetrics.spaceTitleHeight,
                             width: max(0, bounds.width - 2 * padding),
                             height: max(0, bounds.height - SidebarMetrics.spaceTitleHeight))
    if scrollView.frame != scrollFrame {
      scrollView.frame = scrollFrame
      outlineView.sizeLastColumnToFit()
    }
  }

  /// The header strip above the outline, in this (flipped) view.
  private var headerRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: SidebarMetrics.spaceTitleHeight) }

  /// The title hugs its text (so only the text takes the click), leaving room for the edit and options buttons after
  /// it even while they are hidden; the open field takes the whole header width. A header drag only moves the title
  /// (`headerDragOffset`); the buttons stay at the title's resting place.
  private func layoutHeader() {
    let header = SidebarMetrics.spaceTitleHeight
    let titleX = SidebarMetrics.spaceTitleLeading
    let button = SidebarMetrics.closeButtonSize
    let available = max(0, bounds.width - titleX - SidebarMetrics.horizontalPadding)
    let textHeight = ceil(titleLabel.intrinsicContentSize.height)
    let gap = SidebarMetrics.spaceEditButtonGap
    let reserved = isRenaming ? 0 : button + gap + button + gap
    // A truncating label's intrinsic width can omit the cell's text inset. Measure the whole cell so short titles fit.
    let textWidth = isRenaming
      ? available
      : min(ceil(titleLabel.cell?.cellSize.width ?? titleLabel.intrinsicContentSize.width),
            max(0, available - reserved))
    let textY = ((header - textHeight) / 2).rounded()
    let rest = NSRect(x: titleX, y: textY, width: textWidth, height: textHeight)
    titleLabel.frame = rest.offsetBy(dx: titleOffset(headerDragOffset), dy: 0)
    let buttonY = ((header - button) / 2).rounded()
    editButton.frame = NSRect(x: rest.maxX + gap, y: buttonY, width: button, height: button)
    optionsButton.frame = NSRect(x: editButton.frame.maxX + gap, y: buttonY, width: button, height: button)
    renameFill.frame = titleLabel.frame.insetBy(dx: -SidebarMetrics.spaceRenameFillInsetX,
                                                dy: -SidebarMetrics.spaceRenameFillInsetY)
    updateHeaderToolTip()
  }

  /// The header rect, not the outline; the title has the same tip of its own, because it takes the hover. Neither
  /// shows while the title is open (typing is not a drag). Installed again only when the rect changes, not on every
  /// layout.
  private func updateHeaderToolTip() {
    let rect: NSRect? = isRenaming ? nil : headerRect
    guard rect != headerToolTipRect else { return }
    if let headerToolTip { removeToolTip(headerToolTip) }
    headerToolTip = nil
    headerToolTipRect = rect
    titleLabel.toolTip = rect == nil ? nil : Self.reorderToolTip
    guard let rect else { return }
    headerToolTip = addToolTip(rect, owner: self, userData: nil)
    headerToolTipInstallsForTesting += 1
  }

  @objc public func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
                          userData: UnsafeMutableRawPointer?) -> String {
    Self.reorderToolTip
  }

  /// The header tool tip is installed (for tests).
  var showsHeaderToolTipForTesting: Bool { headerToolTip != nil }

  // MARK: - Header hover

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let headerHoverArea { removeTrackingArea(headerHoverArea) }
    let area = NSTrackingArea(rect: headerRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
    addTrackingArea(area)
    headerHoverArea = area
  }

  public override func mouseEntered(with event: NSEvent) { setHeaderHovered(true) }
  public override func mouseExited(with event: NSEvent) { setHeaderHovered(false) }

  /// Shows the edit and options buttons while the header is hovered and the title is neither open nor dragged.
  func setHeaderHovered(_ hovered: Bool) {
    let shown = hovered && !isRenaming && headerPress?.isDragging != true
    editButton.setShown(shown, animated: true)
    optionsButton.setShown(shown, animated: true)
  }

  // MARK: - Rename

  /// A click on the title text opens it; the label itself would swallow the click.
  public override func hitTest(_ point: NSPoint) -> NSView? {
    let hit = super.hitTest(point)
    return !isRenaming && hit === titleLabel ? self : hit
  }

  public override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard !isRenaming, headerRect.contains(point) else { return super.mouseDown(with: event) }
    // A press while the title springs home catches it where it is drawn now and drags on from there.
    let caught = headerSettle.stop()
    if let caught { setHeaderDragOffset(CGFloat(caught.value)) }
    headerDragVelocity.reset()
    headerPress = HeaderPress(origin: event.locationInWindow, onTitle: titleLabel.frame.contains(point),
                              startOffset: headerDragOffset, isDragging: caught != nil,
                              lastX: event.locationInWindow.x)
  }

  /// Past `spaceHeaderDragThreshold` the title follows the pointer 1:1 from where it was grabbed. No layout, no
  /// redraw: one frame origin per event.
  public override func mouseDragged(with event: NSEvent) {
    guard var press = headerPress else { return super.mouseDragged(with: event) }
    let location = event.locationInWindow
    if !press.isDragging {
      let distance = hypot(location.x - press.origin.x, location.y - press.origin.y)
      guard distance >= SidebarMetrics.spaceHeaderDragThreshold else { return }
      press.isDragging = true
      editButton.setShown(false, animated: false)
      optionsButton.setShown(false, animated: false)
    }
    headerDragVelocity.add(delta: location.x - press.lastX, at: event.timestamp)
    press.lastX = location.x
    headerPress = press
    setHeaderDragOffset(displayedHeaderOffset(press.startOffset + location.x - press.origin.x))
  }

  /// A short press on the title renames. A drag moves the Space by the slots it crossed (one per header width,
  /// rounded), then the title springs home.
  public override func mouseUp(with event: NSEvent) {
    guard let press = headerPress else { return super.mouseUp(with: event) }
    headerPress = nil
    let dx = event.locationInWindow.x - press.origin.x
    let dy = event.locationInWindow.y - press.origin.y
    guard press.isDragging || hypot(dx, dy) >= SidebarMetrics.spaceHeaderDragThreshold else {
      if press.onTitle { beginRename() }
      return
    }
    let pitch = SpaceHeaderDrag.pitch(headerWidth: bounds.width)
    if let delta = SpaceHeaderDrag.slotDelta(translation: press.startOffset + dx, pitch: pitch),
       let index = SpaceHeaderDrag.moveIndex(
         id: spaceID, order: source.spaceOrder, visible: visibleSpaceOrder, delta: delta) {
      source.moveSpace(spaceID, to: index)
    }
    settleHeaderDrag(velocity: headerDragVelocity.velocity)
  }

  /// The title springs from where it is drawn back to its resting place, starting at the release velocity.
  private func settleHeaderDrag(velocity: CGFloat) {
    guard headerDragOffset != 0 else { return }
    headerSettle.animate(
      in: self, from: Double(headerDragOffset), to: 0, initialVelocity: Double(velocity.isFinite ? velocity : 0),
      parameters: Self.headerSettlePreset,
      onUpdate: { [weak self] value in self?.setHeaderDragOffset(CGFloat(value)) })
  }

  /// Moves only the title's frame origin; nothing else in the header is laid out again.
  private func setHeaderDragOffset(_ offset: CGFloat) {
    headerDragOffset = offset
    titleLabel.setFrameOrigin(NSPoint(x: SidebarMetrics.spaceTitleLeading + titleOffset(offset),
                                      y: titleLabel.frame.minY))
  }

  /// `offset` on the device pixel grid, so the text stays sharp while it moves.
  private func titleOffset(_ offset: CGFloat) -> CGFloat {
    let scale = shellBackingScale
    return (offset * scale).rounded() / scale
  }

  /// 1:1 while the drag stays within the slots this Space can move to, rubber-banded past them.
  private func displayedHeaderOffset(_ translation: CGFloat) -> CGFloat {
    let visible = visibleSpaceOrder
    guard let index = visible.firstIndex(of: spaceID) else { return 0 }
    return SpaceHeaderDrag.displayedOffset(
      translation, slotsBefore: index, slotsAfter: visible.count - 1 - index,
      pitch: SpaceHeaderDrag.pitch(headerWidth: bounds.width))
  }

  /// Leaving the window ends a press and the spring; the title goes home.
  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window == nil else { return }
    resetHeaderDrag()
  }

  private func resetHeaderDrag() {
    headerSettle.stop()
    headerPress = nil
    if headerDragOffset != 0 { setHeaderDragOffset(0) }
  }

  /// This profile's Spaces, in sidebar order. The drag's slots are this list; `moveSpace` indexes the full order.
  private var visibleSpaceOrder: [SpaceID] {
    let profile = source.space(spaceID)?.profile
    return source.spaceOrder.filter { source.space($0)?.profile == profile }
  }

  @objc private func editButtonPressed(_ sender: Any?) { beginRename() }

  @objc private func optionsButtonPressed(_ sender: Any?) {
    let menu = makeOptionsMenu()
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: optionsButton.isFlipped ? 0 : optionsButton.bounds.height),
               in: optionsButton)
  }

  /// Icon and theme submenus, plus Profile disabled: profiles are not in the model yet (#279).
  func makeOptionsMenu() -> NSMenu {
    let info = source.space(spaceID)
    let menu = NSMenu(title: "Space Options")
    menu.autoenablesItems = false
    menu.setAccessibilityIdentifier(AXID.Sidebar.spaceMenu)
    menu.addItem(submenuItem(title: "Icon", menu: iconMenu(current: info?.icon)))
    menu.addItem(submenuItem(title: "Theme", menu: themeMenu(current: info)))
    let profile = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
    profile.isEnabled = false
    menu.addItem(profile)
    return menu
  }

  private func submenuItem(title: String, menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  /// The symbol choices, then "Emoji..." (D1 on #279), checked while the icon is an emoji.
  private func iconMenu(current: SpaceIconInfo?) -> NSMenu {
    let menu = NSMenu(title: "Icon")
    menu.autoenablesItems = false
    for (index, choice) in SpaceIconCatalog.choices.enumerated() {
      let item = NSMenuItem(title: choice.title, action: #selector(pickIcon(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      item.state = choice.symbol.map { SpaceIconInfo.symbol($0) } == current ? .on : .off
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let emoji = NSMenuItem(title: Self.emojiItemTitle, action: #selector(chooseEmoji(_:)), keyEquivalent: "")
    emoji.target = self
    if case .emoji? = current { emoji.state = .on }
    menu.addItem(emoji)
    return menu
  }

  static let emojiItemTitle = "Emoji\u{2026}"

  /// "Default" (D2 on #279) is checked while the Space has no theme of its own; a catalog theme only when it is the
  /// Space's own.
  private func themeMenu(current: SidebarSpaceInfo?) -> NSMenu {
    let menu = NSMenu(title: "Theme")
    menu.autoenablesItems = false
    for (index, choice) in SpaceThemeCatalog.choices.enumerated() {
      let item = NSMenuItem(title: choice.title, action: #selector(pickTheme(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      item.state = SpaceThemeCatalog.isCurrent(choice, for: current) ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  @objc func pickIcon(_ sender: NSMenuItem) {
    guard SpaceIconCatalog.choices.indices.contains(sender.tag) else { return }
    let symbol = SpaceIconCatalog.choices[sender.tag].symbol
    source.setIcon(spaceID, to: symbol.map { SpaceIconInfo.symbol($0) })
  }

  /// Opens `SpaceEmojiPrompt` as a sheet; Set Icon writes through `setEmojiIcon(_:)`.
  @objc func chooseEmoji(_ sender: Any?) {
    guard let window, window.attachedSheet == nil else { return }
    var current: String?
    if case .emoji(let emoji)? = source.space(spaceID)?.icon { current = emoji }
    SpaceEmojiPrompt(current: current).begin(on: window) { [weak self] text in
      guard let self, let text else { return }
      self.setEmojiIcon(text)
    }
  }

  /// Sets the icon to `text` when it is exactly one emoji (`SpaceIconInfo.validatedEmoji(_:)`); anything else writes
  /// nothing and returns false.
  @discardableResult
  func setEmojiIcon(_ text: String) -> Bool {
    guard let icon = SpaceIconInfo.validatedEmoji(text) else { return false }
    source.setIcon(spaceID, to: icon)
    return true
  }

  @objc func pickTheme(_ sender: NSMenuItem) {
    guard SpaceThemeCatalog.choices.indices.contains(sender.tag) else { return }
    source.setTheme(spaceID, to: SpaceThemeCatalog.choices[sender.tag].theme)
  }

  /// Opens the title for editing with the whole name selected, so typing replaces it. Needs a window.
  public func beginRename() {
    guard !isRenaming, let window else { return }
    resetHeaderDrag()
    isRenaming = true
    renameCancelled = false
    titleBeforeRename = titleLabel.stringValue
    titleLabel.isEditable = true
    titleLabel.isSelectable = true
    editButton.setShown(false, animated: false)
    optionsButton.setShown(false, animated: false)
    renameFill.isHidden = false
    applyTitleColors()
    layoutHeader()
    if window.makeFirstResponder(titleLabel) {
      titleLabel.currentEditor()?.selectAll(nil)
    } else {
      finishRename()
    }
  }

  /// Return saves, Escape keeps the old title; both close the field.
  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)):
      renameCancelled = true
    case #selector(NSResponder.insertNewline(_:)):
      break
    default:
      return false
    }
    if window?.makeFirstResponder(nil) != true {
      titleLabel.abortEditing()
      finishRename()
    }
    return true
  }

  /// Every way out of the field ends here: Return, Escape, a click elsewhere, the page leaving its window.
  public func controlTextDidEndEditing(_ notification: Notification) { finishRename() }

  private func finishRename() {
    guard isRenaming else { return }
    isRenaming = false
    let typed = titleLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let keepsOld = renameCancelled || typed.isEmpty
    titleLabel.isEditable = false
    titleLabel.isSelectable = false
    renameFill.isHidden = true
    applyTitleColors()
    titleLabel.stringValue = keepsOld ? titleBeforeRename : typed
    if !keepsOld { source.renameSpace(spaceID, to: typed) }   // persisted by the source (autosave)
    refresh(from: source.space(spaceID))                        // whatever the source holds now wins
    setAccessibilityLabel(titleLabel.stringValue)
    needsLayout = true
  }
}
