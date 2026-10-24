import AppKit

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
/// reorders Spaces (BH-039, "Drag to Reorder Space") through `moveSpace`. Hovering the header also shows a "..." menu
/// for the icon and the theme. Return or leaving the field saves the trimmed name through the source; Escape, or an
/// empty name [I], keeps the old one. Opening and closing the field is instant: it is a direct response to a click
/// or a key.
@MainActor
public final class SpacePageView: NSView, NSTextFieldDelegate {
  public let spaceID: SpaceID
  public let titleLabel = NSTextField(labelWithString: "")
  /// BH-038: shown while the header is hovered; fades with the rows' hover close timing (Reduce Motion: at once).
  public let editButton = HoverCloseButton(frame: .zero)
  /// BH-038: the header "..." menu (icon, theme, disabled Profile). Shown with the edit button.
  public let optionsButton = HoverCloseButton(frame: .zero)
  public let scrollView = SidebarScrollView(frame: .zero)
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
  /// Set on mouse down in the header; mouse up either renames or reorders.
  private var headerDrag: (origin: NSPoint, onTitle: Bool)?

  public init(source: any SidebarSource, spaceID: SpaceID) {
    self.spaceID = spaceID
    self.source = source
    self.outlineController = SidebarOutlineController(source: source, spaceID: spaceID)
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
    titleLabel.toolTip = "Drag to Reorder Space"
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
    scrollView.documentView = outlineController.outlineView
    addSubview(renameFill)
    addSubview(titleLabel)
    addSubview(editButton)
    addSubview(optionsButton)
    addSubview(scrollView)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityIdentifier(AXID.Sidebar.page)
    setAccessibilityLabel(titleLabel.stringValue)
    setFlavor(info?.theme.flavor ?? .light)
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

  /// The title hugs its text (so only the text takes the click), leaving room for the edit and options buttons after
  /// it even while they are hidden; the open field takes the whole header width.
  private func layoutHeader() {
    let header = SidebarMetrics.spaceTitleHeight
    let titleX = SidebarMetrics.spaceTitleLeading
    let button = SidebarMetrics.closeButtonSize
    let available = max(0, bounds.width - titleX - SidebarMetrics.horizontalPadding)
    let textHeight = ceil(titleLabel.intrinsicContentSize.height)
    let gap = SidebarMetrics.spaceEditButtonGap
    let reserved = isRenaming ? 0 : button + gap + button + gap
    let textWidth = isRenaming
      ? available
      : min(ceil(titleLabel.intrinsicContentSize.width), max(0, available - reserved))
    let textY = ((header - textHeight) / 2).rounded()
    titleLabel.frame = NSRect(x: titleX, y: textY, width: textWidth, height: textHeight)
    let buttonY = ((header - button) / 2).rounded()
    editButton.frame = NSRect(x: titleLabel.frame.maxX + gap, y: buttonY, width: button, height: button)
    optionsButton.frame = NSRect(x: editButton.frame.maxX + gap, y: buttonY, width: button, height: button)
    renameFill.frame = titleLabel.frame.insetBy(dx: -SidebarMetrics.spaceRenameFillInsetX,
                                                dy: -SidebarMetrics.spaceRenameFillInsetY)
    installHeaderToolTip()
  }

  /// The header rect, not the outline. The title has the same tip of its own, because it takes the hover.
  private func installHeaderToolTip() {
    if let headerToolTip { removeToolTip(headerToolTip) }
    let rect = NSRect(x: 0, y: 0, width: bounds.width, height: SidebarMetrics.spaceTitleHeight)
    headerToolTip = addToolTip(rect, owner: self, userData: nil)
  }

  @objc public func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
                          userData: UnsafeMutableRawPointer?) -> String {
    "Drag to Reorder Space"
  }

  // MARK: - Header hover

  public override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let headerHoverArea { removeTrackingArea(headerHoverArea) }
    let rect = NSRect(x: 0, y: 0, width: bounds.width, height: SidebarMetrics.spaceTitleHeight)
    let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
    addTrackingArea(area)
    headerHoverArea = area
  }

  public override func mouseEntered(with event: NSEvent) { setHeaderHovered(true) }
  public override func mouseExited(with event: NSEvent) { setHeaderHovered(false) }

  /// Shows the edit and options buttons while the header is hovered and the title is not open.
  func setHeaderHovered(_ hovered: Bool) {
    let shown = hovered && !isRenaming
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
    let header = NSRect(x: 0, y: 0, width: bounds.width, height: SidebarMetrics.spaceTitleHeight)
    guard !isRenaming, header.contains(point) else { return super.mouseDown(with: event) }
    headerDrag = (event.locationInWindow, titleLabel.frame.contains(point))
  }

  /// A short press on the title renames. A longer horizontal drag reorders, one dock slot per pitch (BH-039).
  public override func mouseUp(with event: NSEvent) {
    guard let drag = headerDrag else { return super.mouseUp(with: event) }
    headerDrag = nil
    let dx = event.locationInWindow.x - drag.origin.x
    let dy = event.locationInWindow.y - drag.origin.y
    if hypot(dx, dy) < SidebarMetrics.spaceHeaderDragThreshold {
      if drag.onTitle { beginRename() }
      return
    }
    let pitch = SidebarMetrics.spaceDotSize + SidebarMetrics.spaceDotSpacing
    guard let delta = SpaceHeaderDrag.slotDelta(translation: dx, pitch: pitch),
          let index = SpaceHeaderDrag.moveIndex(
            id: spaceID, order: source.spaceOrder, visible: visibleSpaceOrder, delta: delta)
    else { return }
    source.moveSpace(spaceID, to: index)
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
    menu.addItem(submenuItem(title: "Icon", menu: iconMenu(current: info?.icon?.symbol)))
    menu.addItem(submenuItem(title: "Theme", menu: themeMenu(current: info?.theme)))
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

  private func iconMenu(current: String?) -> NSMenu {
    let menu = NSMenu(title: "Icon")
    menu.autoenablesItems = false
    for (index, choice) in SpaceIconCatalog.choices.enumerated() {
      let item = NSMenuItem(title: choice.title, action: #selector(pickIcon(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      item.state = choice.symbol == current ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  private func themeMenu(current: SpaceThemeInfo?) -> NSMenu {
    let menu = NSMenu(title: "Theme")
    menu.autoenablesItems = false
    for (index, choice) in SpaceThemeCatalog.choices.enumerated() {
      let item = NSMenuItem(title: choice.title, action: #selector(pickTheme(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      item.state = choice.theme == current ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  @objc func pickIcon(_ sender: NSMenuItem) {
    guard SpaceIconCatalog.choices.indices.contains(sender.tag) else { return }
    let symbol = SpaceIconCatalog.choices[sender.tag].symbol
    source.setIcon(spaceID, to: symbol.map { SpaceIconInfo(symbol: $0) })
  }

  @objc func pickTheme(_ sender: NSMenuItem) {
    guard SpaceThemeCatalog.choices.indices.contains(sender.tag) else { return }
    source.setTheme(spaceID, to: SpaceThemeCatalog.choices[sender.tag].theme)
  }

  /// Opens the title for editing with the whole name selected, so typing replaces it. Needs a window.
  public func beginRename() {
    guard !isRenaming, let window else { return }
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
