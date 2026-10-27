import AppKit
import EngineAPI

/// One row of the Library's rail: the section's glyph, its name and, for Downloads, how many there are. The current one
/// takes the `tabCurrent` fill. A real button, so the keyboard and VoiceOver reach it.
@MainActor
final class LibraryRailItem: NSButton {
  let section: LibrarySection
  private let countField = NSTextField(labelWithString: "")
  var isCurrent = false { didSet { if isCurrent != oldValue { restyle() } } }
  var count: Int? { didSet { restyle() } }

  init(section: LibrarySection) {
    self.section = section
    super.init(frame: .zero)
    title = ""
    isBordered = false
    bezelStyle = .regularSquare
    setButtonType(.momentaryChange)
    focusRingType = .default
    wantsLayer = true
    layer?.cornerRadius = DownloadsMetrics.rowCorner
    layer?.cornerCurve = .continuous
    countField.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
    countField.alignment = .right
    countField.setAccessibilityElement(false)
    addSubview(countField)
    setAccessibilityIdentifierWithCell(AXID.Downloads.railItem(section.rawValue))
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }
  override var wantsUpdateLayer: Bool { true }
  override func updateLayer() { restyle() }

  private func restyle() {
    let flavor = archiveFlavor
    countField.stringValue = count.map(String.init) ?? ""
    countField.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    countField.isHidden = (count ?? 0) == 0
    ArchiveMotion.set {
      layer?.backgroundColor = isCurrent ? ShellTokens.tabCurrent.resolve(flavor).cgColor : nil
      layer?.shadowOpacity = 0
    }
    let label = count.map { $0 > 0 ? "\(section.title), \($0)" : section.title } ?? section.title
    setArchiveAccessibilityLabel(label)
    setArchiveAccessibilityValue(isCurrent ? "selected" : nil)
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    countField.sizeToFit()
    countField.frame = NSRect(x: bounds.width - 10 - max(24, countField.frame.width),
                              y: ((bounds.height - countField.frame.height) / 2).rounded(),
                              width: max(24, countField.frame.width), height: countField.frame.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    let flavor = archiveFlavor
    let color = (isCurrent ? ShellTokens.primaryText : ShellTokens.sidebarForeground).resolve(flavor)
    let glyph = SymbolImageCache.shared.symbol(section.symbolName, box: 16, color: color, scale: shellBackingScale)
    glyph.draw(in: NSRect(x: 9, y: ((bounds.height - 16) / 2).rounded(), width: 16, height: 16))
    let text = NSAttributedString(string: section.title, attributes: [
      .font: NSFont.systemFont(ofSize: 13), .foregroundColor: ShellTokens.primaryText.resolve(flavor).nsColor(),
    ])
    text.draw(at: NSPoint(x: 9 + 16 + 9, y: ((bounds.height - text.size().height) / 2).rounded()))
  }
}

/// The Library window (design/downloads, direction A; Cmd-Shift-L, Cmd-Shift-J on Downloads, Cmd-Y on History; KB-065):
/// a section rail (Downloads and History) and the list of the section, with a search field in the title bar and, for
/// Downloads, the place files go and Clear List in the footer. One window per app. It reopens on the section used last
/// (BH-181). AppKit and Core Animation only: frames are set in `layoutContent()`.
@MainActor
public final class LibraryWindowController: NSWindowController, NSSearchFieldDelegate {
  let model: DownloadsModel
  private let settings: AppSettings
  private(set) var section: LibrarySection
  private let content = LibraryContentView(frame: .zero)
  private let dragView = ArchiveDragView(frame: .zero)
  private let titleLabel = NSTextField(labelWithString: "Library")
  let searchField = ArchiveSearchField(frame: .zero)
  private let railItems = LibrarySection.allCases.map { LibraryRailItem(section: $0) }
  let listView = LibraryListView(frame: .zero)
  private let scrollView = NSScrollView(frame: .zero)
  private let savingLabel = NSTextField(labelWithString: "")
  let changeLink = ArchiveLinkButton(style: .secondary, title: "Change...", fontSize: 12)
  let clearLink = ArchiveLinkButton(style: .destructive, title: "Clear List", fontSize: 12)
  private let emptyTitle = NSTextField(labelWithString: "")
  private let emptyDetail = NSTextField(wrappingLabelWithString: "")
  private let emptyTile = CALayer()
  private let emptyGlyph = NSImageView()
  let openFolderPill = ArchivePillButton(style: .primary, title: "Open Downloads Folder")
  private var observation: DownloadsObservation?
  private var filterText = ""
  /// Settings > General, from the footer's Change link; the link is inert while nil.
  public var onChangeLocation: (@MainActor () -> Void)?
  /// A held file's Review: the center presents the dangerous-file sheet.
  var onReview: (@MainActor (DownloadID) -> Void)?
  /// Opens the downloads folder (the empty state's pill); default: Finder.
  var openFolder: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
  var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { listView.reduceMotion = reduceMotion }
  }

  public init(model: DownloadsModel, settings: AppSettings) {
    self.model = model
    self.settings = settings
    section = settings.libraryLastSection
    let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    let frame = NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: DownloadsMetrics.libraryContent), styleMask: style)
    let window = ArchiveWindow(contentRect: NSRect(origin: .zero, size: frame.size),
                               styleMask: style.union(.fullSizeContentView), backing: .buffered, defer: true)
    window.title = "Library"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.minSize = NSWindow.frameRect(forContentRect: NSRect(origin: .zero, size: DownloadsMetrics.libraryMinimum),
                                        styleMask: style).size
    window.setAccessibilityIdentifier(AXID.Downloads.libraryWindow)
    super.init(window: window)
    window.onFind = { [weak self] in self?.focusSearch() }
    buildContent(in: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: Showing

  /// Shows the window on `section` (the last one used when nil), and clears the unseen dot.
  public func show(section requested: LibrarySection? = nil) {
    if let requested { select(requested) }
    model.markSeen()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    window?.makeFirstResponder(section == .downloads ? listView : searchField)
    startObserving()
    reload()
  }

  /// Escape: clears a search, else closes the window.
  public override func cancelOperation(_ sender: Any?) {
    if !searchField.stringValue.isEmpty {
      searchField.stringValue = ""
      setSearchText("")
    } else {
      window?.performClose(sender)
    }
  }

  func focusSearch() { window?.makeFirstResponder(searchField) }

  /// Shows `next` and remembers it for the next opening.
  func select(_ next: LibrarySection) {
    section = next
    settings.libraryLastSection = next
    searchField.stringValue = ""
    filterText = ""
    reload()
  }

  private func startObserving() {
    guard observation == nil else { return }
    observation = model.addObserver { [weak self] change in
      guard self?.window?.isVisible == true else { return }
      switch change {
      case .seen: break
      default: self?.reload(animated: true)
      }
    }
  }

  // MARK: Search

  public func controlTextDidChange(_ obj: Notification) {
    guard (obj.object as? NSSearchField) === searchField else { return }
    setSearchText(searchField.stringValue)
  }

  /// Filters the list by name or host, as typing does.
  func setSearchText(_ text: String) {
    if searchField.stringValue != text { searchField.stringValue = text }
    filterText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    reload()
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard control === searchField else { return false }
    switch selector {
    case #selector(NSResponder.cancelOperation(_:)):
      cancelOperation(nil)
      return true
    case #selector(NSResponder.moveDown(_:)):
      window?.makeFirstResponder(listView)
      if listView.selectedID == nil { listView.moveSelection(by: 1) }
      return true
    case #selector(NSResponder.insertNewline(_:)):
      return true
    default:
      return false
    }
  }

  // MARK: Content

  /// The downloads the list shows now: the model's, filtered by the search.
  var visibleItems: [DownloadItem] {
    guard !filterText.isEmpty else { return model.items }
    return model.items.filter {
      $0.filename.localizedCaseInsensitiveContains(filterText)
        || DownloadsFormat.host(of: $0.url).localizedCaseInsensitiveContains(filterText)
    }
  }

  /// Whether the empty state shows, and which words.
  enum Empty: Equatable { case none, noDownloads, noMatches, history }

  var empty: Empty {
    switch section {
    case .history: .history
    case .downloads: model.items.isEmpty ? .noDownloads : (visibleItems.isEmpty ? .noMatches : .none)
    }
  }

  func reload(animated: Bool = false) {
    let isDownloads = section == .downloads
    for item in railItems {
      item.isCurrent = item.section == section
      item.count = item.section == .downloads ? model.items.count : nil
    }
    searchField.isEnabled = isDownloads
    searchField.placeholder = isDownloads ? "Search downloads" : "Search history"
    searchField.setArchiveAccessibilityLabel(searchField.placeholder)
    listView.reload(isDownloads ? visibleItems : [], animated: animated)
    let place = settings.downloadLocation.placeName(defaultFolder: model.engine.downloadDefaultFolder)
    savingLabel.stringValue = settings.downloadLocation.asksWhereToSave ? "Asking where to save" : "Saving to \(place)"
    savingLabel.setAccessibilityLabel(savingLabel.stringValue)
    clearLink.isEnabled = model.items.contains { $0.state.isFinished && !$0.dangerType.needsSheet }
    applyEmpty()
    footerVisibility(isDownloads)
    content.needsLayout = true
    window?.setAccessibilityLabel(section.title)
  }

  private func footerVisibility(_ shown: Bool) {
    for view in [savingLabel, changeLink, clearLink] as [NSView] { view.isHidden = !shown }
  }

  private func applyEmpty() {
    let state = empty
    let flavor = content.archiveFlavor
    let showsEmpty = state != .none
    for view in [emptyTitle, emptyDetail, emptyGlyph, openFolderPill] as [NSView] { view.isHidden = !showsEmpty }
    emptyTile.isHidden = !showsEmpty
    scrollView.isHidden = showsEmpty
    openFolderPill.isHidden = state != .noDownloads
    switch state {
    case .none: break
    case .noDownloads:
      emptyTitle.stringValue = "No downloads yet"
      emptyDetail.stringValue = "Files you download appear here."
      setEmptyGlyph("arrow.down.to.line", flavor)
    case .noMatches:
      emptyTitle.stringValue = "No matches"
      emptyDetail.stringValue = "Nothing in Downloads matches \u{201C}\(filterText)\u{201D}."
      setEmptyGlyph("magnifyingglass", flavor)
    case .history:
      emptyTitle.stringValue = "History"
      emptyDetail.stringValue = "Pages you visit will be listed here."
      setEmptyGlyph("clock.arrow.circlepath", flavor)
    }
  }

  private func setEmptyGlyph(_ name: String, _ flavor: ThemeFlavor) {
    emptyGlyph.image = SymbolImageCache.shared.symbol(name, box: 20, color: ShellTokens.primaryText.resolve(flavor),
                                                      scale: content.shellBackingScale)
  }

  private func perform(_ action: DownloadRowAction, _ id: DownloadID) {
    guard let item = model.item(id) else { return }
    switch action {
    case .cancel: model.cancel(id)
    case .open:
      if item.dangerType.needsSheet { onReview?(id) } else { model.open(id) }
    case .showInFinder: model.showInFinder(id)
    case .retry: model.retry(id)
    case .remove: model.remove(id)
    case .review: onReview?(id)
    case .keep: model.keep(id)
    case .discard: model.discard(id)
    }
  }

  // MARK: Building

  private func buildContent(in window: NSWindow) {
    content.autoresizingMask = [.width, .height]
    content.frame = NSRect(origin: .zero, size: window.frame.size)
    content.onLayout = { [weak self] in self?.layoutContent() }
    content.onAppearanceChange = { [weak self] in self?.appearanceDidChange() }
    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.setAccessibilityElement(false)
    searchField.delegate = self
    searchField.setAccessibilityIdentifier(AXID.Downloads.librarySearch)
    searchField.cell?.setAccessibilityIdentifier(AXID.Downloads.librarySearch)
    for item in railItems {
      item.target = self
      item.action = #selector(railPressed(_:))
      content.addSubview(item)
    }
    listView.onAction = { [weak self] action, id in self?.perform(action, id) }
    listView.onDelete = { [weak self] id in self?.model.remove(id) }
    listView.onEscape = { [weak self] in self?.cancelOperation(nil) }
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.documentView = listView
    savingLabel.font = .systemFont(ofSize: 12)
    savingLabel.lineBreakMode = .byTruncatingMiddle
    savingLabel.setAccessibilityIdentifier(AXID.Downloads.libraryFooter)
    changeLink.target = self
    changeLink.action = #selector(changePressed(_:))
    changeLink.setAccessibilityIdentifierWithCell(AXID.Downloads.libraryChange)
    clearLink.target = self
    clearLink.action = #selector(clearPressed(_:))
    clearLink.setAccessibilityIdentifierWithCell(AXID.Downloads.libraryClear)
    emptyTitle.font = .systemFont(ofSize: 15, weight: .semibold)
    emptyTitle.alignment = .center
    emptyDetail.font = .systemFont(ofSize: 12)
    emptyDetail.alignment = .center
    emptyDetail.isSelectable = false
    emptyTile.cornerRadius = 12
    emptyTile.cornerCurve = .continuous
    emptyGlyph.imageScaling = .scaleNone
    openFolderPill.target = self
    openFolderPill.action = #selector(openFolderPressed(_:))
    openFolderPill.setAccessibilityIdentifierWithCell(AXID.Downloads.libraryOpenFolder)
    content.layer?.addSublayer(emptyTile)
    for view in [dragView, titleLabel, searchField, scrollView, savingLabel, changeLink, clearLink, emptyTitle, emptyDetail,
                 emptyGlyph, openFolderPill] as [NSView] {
      content.addSubview(view)
    }
    for view in railItems { content.addSubview(view) }
    window.contentView = content
    window.autorecalculatesKeyViewLoop = false
    window.initialFirstResponder = listView
    var loop: [NSView] = [searchField] + railItems + [listView, changeLink, clearLink]
    loop.append(openFolderPill)
    for (index, view) in loop.enumerated() { view.nextKeyView = loop[(index + 1) % loop.count] }
    appearanceDidChange()
    reload()
    window.center()
  }

  @objc private func railPressed(_ sender: LibraryRailItem) { select(sender.section) }
  @objc private func changePressed(_ sender: Any?) { onChangeLocation?() }
  @objc private func clearPressed(_ sender: Any?) { model.clearList() }
  @objc private func openFolderPressed(_ sender: Any?) { openFolder(model.engine.downloadDefaultFolder) }

  private func appearanceDidChange() {
    let flavor = content.archiveFlavor
    titleLabel.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    savingLabel.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    emptyTitle.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    emptyDetail.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
    ArchiveMotion.set { emptyTile.backgroundColor = DownloadsTokens.rowFill.resolve(flavor).cgColor }
    searchField.restyle()
    applyEmpty()
  }

  private func layoutContent() {
    guard let window, let contentView = window.contentView else { return }
    let bounds = contentView.bounds
    let bar = DownloadsMetrics.barHeightWindow
    dragView.frame = bounds
    (window as? ArchiveWindow)?.layoutTrafficLights()
    titleLabel.sizeToFit()
    titleLabel.frame.origin = NSPoint(x: ArchiveMetrics.titleLeading, y: ((bar - titleLabel.frame.height) / 2).rounded())
    let fieldWidth: CGFloat = min(240, max(120, bounds.width - titleLabel.frame.maxX - 40))
    searchField.frame = NSRect(x: bounds.width - 16 - fieldWidth, y: ((bar - ArchiveMetrics.fieldHeight) / 2).rounded(),
                               width: fieldWidth, height: ArchiveMetrics.fieldHeight)
    var y = bar + 6
    for item in railItems {
      item.frame = NSRect(x: 10, y: y, width: DownloadsMetrics.railWidth - 20, height: DownloadsMetrics.railRow)
      y += DownloadsMetrics.railRow + 2
    }
    let mainX = DownloadsMetrics.railWidth
    let footer = section == .downloads ? DownloadsMetrics.footerHeight : 0
    let mainFrame = NSRect(x: mainX, y: bar, width: bounds.width - mainX, height: max(0, bounds.height - bar - footer))
    scrollView.frame = NSRect(x: mainX, y: bar, width: mainFrame.width - 10, height: mainFrame.height)
    listView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: max(scrollView.contentSize.height, listView.contentHeight))
    let footerTop = bounds.height - DownloadsMetrics.footerHeight
    savingLabel.sizeToFit()
    changeLink.sizeToFit()
    clearLink.sizeToFit()
    let footerY = footerTop + ((DownloadsMetrics.footerHeight - 16) / 2).rounded()
    clearLink.frame.origin = NSPoint(x: bounds.width - 16 - clearLink.frame.width, y: footerY - 1)
    let savingX = mainX + 16
    let room = max(0, clearLink.frame.minX - savingX - changeLink.frame.width - 24)
    savingLabel.frame = NSRect(x: savingX, y: footerY, width: min(savingLabel.frame.width, room), height: 16)
    changeLink.frame.origin = NSPoint(x: savingLabel.frame.maxX + 8, y: footerY - 1)
    // The empty state, centered in the main area.
    let center = NSPoint(x: mainFrame.midX, y: mainFrame.midY)
    let pillHeight = openFolderPill.isHidden ? 0 : ArchiveMetrics.pillHeight + 14
    let blockHeight: CGFloat = 44 + 12 + 20 + 4 + 34 + pillHeight
    var top = center.y - blockHeight / 2
    emptyTile.frame = CGRect(x: center.x - 22, y: top, width: 44, height: 44)
    emptyGlyph.frame = NSRect(x: center.x - 10, y: top + 12, width: 20, height: 20)
    top += 44 + 12
    emptyTitle.sizeToFit()
    emptyTitle.frame = NSRect(x: center.x - 160, y: top, width: 320, height: 20)
    top += 24
    emptyDetail.frame = NSRect(x: center.x - 160, y: top, width: 320, height: 34)
    top += 34 + 14
    let pillWidth = openFolderPill.intrinsicContentSize.width
    openFolderPill.frame = NSRect(x: center.x - pillWidth / 2, y: top, width: pillWidth, height: ArchiveMetrics.pillHeight)
  }
}

/// The window's content: lays itself out through the controller and reports appearance changes.
@MainActor
final class LibraryContentView: NSView {
  var onLayout: (@MainActor () -> Void)?
  var onAppearanceChange: (@MainActor () -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = AlertTokens.dialogSurface.resolve(archiveFlavor).cgColor
  }

  override func layout() {
    super.layout()
    onLayout?()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    onAppearanceChange?()
  }
}
