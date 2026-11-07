import AppKit

/// The surface of the sheet and the host of its content: porcelain (graphite in dark) like every dialog, and it
/// restyles the content when the appearance or an accessibility setting changes.
@MainActor
final class ImportSheetRootView: NSView {
  var onStyleChange: (@MainActor () -> Void)?

  override var isFlipped: Bool { true }
  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = AlertTokens.dialogSurface.resolve(archiveFlavor).cgColor
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
    onStyleChange?()
  }
}

/// The browser data import as a window sheet (File > Import Browser Data..., #514): consent with a count per type,
/// then progress, then the result. Escape is Cancel (Done on the result), Return presses the primary, Tab walks the
/// rows and then the buttons. The sheet follows its source: when the source dismisses, the sheet closes.
@MainActor
public final class BrowserDataImportSheet: NSWindowController {
  public static let width: CGFloat = 500

  let source: any BrowserDataImportSource
  let content: ImportContentView
  private let root = ImportSheetRootView()
  private var displayObserver: (any NSObjectProtocol)?
  private var keepAlive: BrowserDataImportSheet?
  private var lastPhase: BrowserDataImportPhase
  private weak var parent: NSWindow?
  /// Test seam: what VoiceOver was told.
  private(set) var announcements: [String] = []

  public init(source: any BrowserDataImportSource, reduceMotion: Bool? = nil) {
    self.source = source
    let style = ImportViewStyle.sheet(for: root, reduceMotion: reduceMotion)
    let primary = ArchivePillButton(style: .primary, title: "Import", metrics: .dialog)
    let secondary = ArchivePillButton(style: .neutral, title: "Cancel", metrics: .dialog)
    content = ImportContentView(source: source, style: style, primary: primary, secondary: secondary)
    lastPhase = source.state.phase
    let height = content.layoutContent(width: Self.width)
    let window = DialogWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: true)
    super.init(window: window)
    root.wantsLayer = true
    root.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
    content.frame = root.bounds
    content.autoresizingMask = [.width, .height]
    root.addSubview(content)
    window.contentView = root
    for button in [primary, secondary] {
      button.target = content
      button.action = #selector(ImportContentView.buttonPressed(_:))
    }
    primary.keyEquivalent = "\r"
    primary.setAccessibilityIdentifierWithCell(AXID.BrowserDataImport.primary)
    secondary.setAccessibilityIdentifierWithCell(AXID.BrowserDataImport.secondary)
    content.setAccessibilityIdentifier(AXID.BrowserDataImport.root)
    window.onEscape = { [weak self] in self?.escape() ?? false }
    window.setAccessibilityLabel(source.state.title)
    content.onAnnouncement = { [weak self] text in self?.announce(text) }
    content.onHeightChange = { [weak self] in self?.resize() }
    root.onStyleChange = { [weak self] in self?.restyle() }
    source.onChange = { [weak self] in self?.sourceChanged() }
    displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.restyle() } }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  isolated deinit {
    if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
  }

  /// Shows the sheet on `parent` and starts the count. The sheet keeps itself alive until it closes.
  public func begin(on parent: NSWindow) {
    guard let window, parent.attachedSheet == nil else { return }
    keepAlive = self
    self.parent = parent
    parent.beginSheet(window) { _ in }
    focusFirstControl()
    source.start()
  }

  /// Escape is Cancel while the sheet counts, asks or imports, and Done on the result. Always handled.
  private func escape() -> Bool {
    switch source.state.phase {
    case .result: source.finish()
    default: source.cancel()
    }
    return true
  }

  private func sourceChanged() {
    let state = source.state
    window?.setAccessibilityLabel(state.title)
    content.apply(state)
    if state.phase == .dismissed {
      closeSheet()
      return
    }
    resize()
    if state.phase != lastPhase { focusFirstControl() }
    lastPhase = state.phase
  }

  private func restyle() {
    content.restyle(ImportViewStyle.sheet(for: root))
    resize()
  }

  private func resize() {
    guard let window else { return }
    let height = content.layoutContent(width: Self.width)
    guard abs(window.contentRect(forFrameRect: window.frame).height - height) > 0.5 else { return }
    window.setContentSize(NSSize(width: Self.width, height: height))
  }

  /// The first checkbox while asking, Cancel while importing, the primary on the result.
  private func focusFirstControl() {
    guard let window else { return }
    let views = content.keyViews
    let phase = source.state.phase
    let target: NSView? = switch phase {
    case .consent: views.first
    case .result: content.primaryButton.isHidden ? content.secondaryButton : content.primaryButton
    default: content.secondaryButton.isHidden ? nil : content.secondaryButton
    }
    window.initialFirstResponder = target
    if let target { window.makeFirstResponder(target) }
  }

  private func announce(_ text: String) {
    announcements.append(text)
    guard let window else { return }
    NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
      .announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
  }

  private func closeSheet() {
    guard let window else { return }
    source.onChange = nil
    (parent ?? window.sheetParent)?.endSheet(window)
    window.orderOut(nil)
    keepAlive = nil
  }
}
