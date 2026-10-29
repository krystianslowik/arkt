import AppKit
import Motion

/// The Settings window (#307; docs/design/settings.md, design/settings/): seven panes under one unified bar. Arkt >
/// Settings... (Cmd-,) opens it or brings it forward; there is one instance. Changes apply at once.
///
/// - Width 680 (decision 5); the height fits the pane up to the screen's visible height minus 120, and the content
///   scrolls past that. The last pane and the window's top-left corner are restored (`AppSettings`).
/// - Cmd-1 to Cmd-7 switch panes instantly while Settings is key; Go to Sidebar Item validates false here, so the
///   keys reach the window (decision 1). Cmd-W and Escape close it (decision 2); Escape in the Shortcuts search field
///   clears a non-empty search first.
/// - A click switch resizes the window (0.25 s, the strong ease-out) and fades and raises the new pane on `firm`;
///   Reduce Motion jumps the frame and only cross-fades (0.15 s).
/// - Rows for features that are not built are shown disabled (decision 4).
@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  public let settings: AppSettings
  let services: SettingsServices
  public private(set) var selectedPane: SettingsPane
  /// The window title (the pane's name), drawn in the chrome.
  public var titleLabel: NSTextField { chrome.titleLabel }
  /// Holds the shown pane; the pane switch animates its layer.
  public let paneContainer = SettingsPaneContainer(frame: .zero)
  /// Reduce Motion; a test seam.
  public var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
    didSet { SettingsMotion.reduceMotion = reduceMotion }
  }
  /// The Make Default request in flight; tests await it.
  public internal(set) var pendingDefaultBrowserChange: Task<Void, Never>?

  private let chrome: SettingsChromeView
  private let scrollView = NSScrollView(frame: .zero)
  private var paneViews: [SettingsPane: SettingsPaneView] = [:]
  private var outgoing: NSView?
  /// The window was placed once; from then on its moves are remembered.
  private var isPlaced = false
  /// Menu items this window retitled ("Close Window"), restored when it resigns key.
  private var retitled: [(item: NSMenuItem, title: String)] = []

  // Live controls, kept to follow the model.
  var defaultBrowserRow: SettingsRowView?
  var isDefaultBrowserShown: Bool?
  var toolbarSwitch: SettingsSwitch?
  var fullURLSwitch: SettingsSwitch?
  var fullURLRow: SettingsRowView?
  var preview: SettingsAppearancePreview?
  var peekCrossSiteSwitch: SettingsSwitch?
  var peekShiftSwitch: SettingsSwitch?
  /// Settings > General > Warn before quitting (#487, BH-177).
  var warnBeforeQuittingSwitch: SettingsSwitch?
  /// The lookup hotkey's switch and row (#354); the row's caption carries the registration answer.
  var littleArktHotKeySwitch: SettingsSwitch?
  var littleArktHotKeyRow: SettingsRowView?
  var countFavoritesSwitch: SettingsSwitch?
  var ninthTabSwitch: SettingsSwitch?
  var importButton: ArchivePillButton?
  /// Settings > Privacy > Crash reports (#129).
  var crashReportsSwitch: SettingsSwitch?
  var sendCrashReportButton: ArchivePillButton?
  var sendCrashReportRow: SettingsRowView?
  let shortcutsSearch = ArchiveSearchField(frame: .zero)
  var shortcutSections: [ShortcutCatalog.Section] = []
  /// Settings > General > Downloads (#132): the mode, the folder row and the Library row.
  var downloadModeControl: SettingsSegmentedControl?
  var downloadModeRow: SettingsRowView?
  var downloadFolderRow: SettingsRowView?
  /// Shows the folder panel and answers the chosen folder, nil when cancelled; tests replace it.
  var downloadFolderPicker: @MainActor (NSWindow?, @escaping @MainActor (URL?) -> Void) -> Void = { window, done in
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
      done(response == .OK ? panel.url : nil)
    }
    if let window { panel.beginSheetModal(for: window) { response in MainActor.assumeIsolated { finish(response) } } }
    else { finish(panel.runModal()) }
  }
  /// Closure targets of the pills (an action's target is weak).
  var actionTargets: [NSObject] = []

  public init(settings: AppSettings, services: SettingsServices) {
    self.settings = settings
    self.services = services
    selectedPane = settings.lastPane
    chrome = SettingsChromeView(items: SettingsPane.allCases.map(SettingsPaneItemView.init(pane:)))
    let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsMetrics.windowWidth, height: 400),
                                styleMask: style, backing: .buffered, defer: true)
    window.title = "Settings"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.collectionBehavior.insert(.fullScreenNone)
    window.setAccessibilityIdentifier(AXID.Settings.window)
    super.init(window: window)
    window.delegate = self
    window.onCommandNumber = { [weak self] number in self?.commandNumber(number) ?? false }
    buildContent(in: window)
    SettingsMotion.reduceMotion = reduceMotion
    settings.toolbar.addObserver(self)
    settings.addObserver(self)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(_:)),
                                           name: NSApplication.didBecomeActiveNotification, object: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func buildContent(in window: SettingsWindow) {
    let root = SettingsRootView(frame: NSRect(x: 0, y: 0, width: SettingsMetrics.windowWidth, height: 400))
    root.wantsLayer = true
    root.autoresizingMask = [.width, .height]
    scrollView.frame = root.bounds
    scrollView.autoresizingMask = [.width, .height]
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: SettingsMetrics.chromeHeight, left: 0, bottom: 0, right: 0)
    scrollView.scrollerInsets = NSEdgeInsets(top: SettingsMetrics.chromeHeight, left: 0, bottom: 0, right: 0)
    paneContainer.wantsLayer = true
    scrollView.documentView = paneContainer
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(paneDidScroll(_:)),
                                           name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    root.addSubview(scrollView)
    chrome.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: SettingsMetrics.chromeHeight)
    chrome.autoresizingMask = [.width]
    root.addSubview(chrome)
    window.contentView = root
    root.viewDidChangeEffectiveAppearance()
    for item in chrome.items {
      item.onSelect = { [weak self] pane in self?.select(pane, animated: true) }
    }
    shortcutsSearch.placeholder = "Search actions or type a shortcut, like Command-E"
    shortcutsSearch.delegate = self
    shortcutsSearch.setAccessibilityIdentifier(AXID.Settings.shortcutsSearch)
    shortcutsSearch.setArchiveAccessibilityLabel("Search shortcuts")
  }

  // MARK: Showing

  /// Shows the window on `pane` (the last pane when nil), or brings it forward when it is open. The first open is
  /// centered on the key window's screen; later opens keep the remembered origin.
  public func show(pane: SettingsPane? = nil) {
    guard let window = window as? SettingsWindow else { return }
    let wasVisible = window.isVisible
    if !wasVisible {
      // The Spaces (and the preview's theme) may have changed while the window was closed.
      paneViews[.spaces] = nil
      paneViews[.appearance] = nil
      refreshLiveRows()
      install(pane ?? settings.lastPane)
      placeOnFirstOpen(window)
    } else if let pane, pane != selectedPane {
      select(pane, animated: false)
    }
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    // No control takes focus on open (a ring around Make Default would read as a second highlight); Tab starts the
    // key view loop.
    if !wasVisible { window.makeFirstResponder(nil) }
    window.layoutTrafficLights()
  }

  /// The remembered top-left corner when it is still on a screen; otherwise centered on the key window's screen.
  private func placeOnFirstOpen(_ window: SettingsWindow) {
    let height = targetHeight(for: selectedPane, on: NSApp.keyWindow?.screen ?? NSScreen.main)
    window.setContentSize(NSSize(width: SettingsMetrics.windowWidth, height: height))
    if let topLeft = settings.windowTopLeft,
       NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(topLeft) }) {
      window.setFrameTopLeftPoint(topLeft)
    } else if let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      window.setFrameOrigin(NSPoint(x: (visible.midX - SettingsMetrics.windowWidth / 2).rounded(),
                                    y: (visible.midY - height / 2).rounded()))
    }
    setFrame(height: targetHeight(for: selectedPane, on: window.screen), animated: false)
    isPlaced = true
  }

  /// Selects `pane`. A click animates (window frame, pane fade and rise); the keyboard does not.
  public func select(_ pane: SettingsPane, animated: Bool) {
    guard pane != selectedPane || paneContainer.subviews.isEmpty else { return }
    let reduce = reduceMotion()
    // The old pane, as drawn now, fades out over the new one (a click only).
    let snapshot = animated ? paneContainer.subviews.first.flatMap(snapshot(of:)) : nil
    install(pane, itemAnimated: animated)
    let height = targetHeight(for: pane, on: window?.screen)
    setFrame(height: height, animated: animated && !reduce)
    guard animated, let layer = paneContainer.layer else {
      paneContainer.layer?.removeAllAnimations()
      return
    }
    if let snapshot { fadeOut(snapshot) }
    let fadeIn = CABasicAnimation(keyPath: "opacity")
    fadeIn.fromValue = 0
    fadeIn.toValue = 1
    if reduce {
      fadeIn.duration = SettingsMotion.crossFade
      layer.removeAnimation(forKey: "transform.translation.y")
    } else {
      let rise = SpringAnimationFactory.make(keyPath: "transform.translation.y", from: 4, to: 0,
                                             parameters: SpringPreset.firm.parameters)
      fadeIn.duration = rise.duration
      fadeIn.timingFunction = ArchiveMotion.easeOut
      layer.add(rise, forKey: "transform.translation.y")
    }
    layer.add(fadeIn, forKey: "opacity")
  }

  /// A snapshot of the old pane stays on top for 0.08 s, fading out, then goes; the pane view itself stays cached
  /// and untouched.
  private func snapshot(of view: NSView) -> NSImageView? {
    guard let root = window?.contentView, !view.visibleRect.isEmpty,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.visibleRect) else { return nil }
    view.cacheDisplay(in: view.visibleRect, to: bitmap)
    let image = NSImage(size: view.visibleRect.size)
    image.addRepresentation(bitmap)
    let snapshot = NSImageView(frame: view.convert(view.visibleRect, to: root))
    snapshot.image = image
    snapshot.imageScaling = .scaleNone
    snapshot.wantsLayer = true
    return snapshot
  }

  private func fadeOut(_ snapshot: NSImageView) {
    outgoing?.removeFromSuperview()
    window?.contentView?.addSubview(snapshot, positioned: .below, relativeTo: chrome)
    outgoing = snapshot
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self, weak snapshot] in
      MainActor.assumeIsolated {
        snapshot?.removeFromSuperview()
        if let self, self.outgoing === snapshot { self.outgoing = nil }
      }
    }
    if let layer = snapshot.layer { SettingsMotion.fade(layer, to: 0, duration: 0.08) }
    CATransaction.commit()
  }

  private func install(_ pane: SettingsPane, itemAnimated: Bool = false) {
    selectedPane = pane
    settings.lastPane = pane
    for item in chrome.items { item.setSelected(item.pane == pane, animated: itemAnimated) }
    chrome.titleLabel.stringValue = pane.title
    (window as? SettingsWindow)?.paneTitle = pane.title
    let view = paneView(pane)
    paneContainer.subviews.filter { $0 !== view }.forEach { $0.removeFromSuperview() }
    if view.superview !== paneContainer { paneContainer.addSubview(view) }
    layoutPane()
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: -SettingsMetrics.chromeHeight))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    updateKeyViewLoop()
  }

  /// The pane's height at the window's width.
  public func paneContentHeight(_ pane: SettingsPane) -> CGFloat {
    paneView(pane).fittingHeight(width: SettingsMetrics.windowWidth)
  }

  private func targetHeight(for pane: SettingsPane, on screen: NSScreen?) -> CGFloat {
    let wanted = SettingsMetrics.chromeHeight + paneContentHeight(pane)
    guard let screen = screen ?? NSScreen.main else { return wanted }
    return min(wanted, screen.visibleFrame.height - SettingsMetrics.screenMargin)
  }

  /// Keeps the top edge; `animated` runs AppKit's frame animation (0.25 s, the strong ease-out). A frame set without
  /// animation replaces one in flight.
  private func setFrame(height: CGFloat, animated: Bool) {
    guard let window else { return }
    var frame = window.frame
    frame.origin.y = frame.maxY - height
    frame.size = NSSize(width: SettingsMetrics.windowWidth, height: height)
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        context.timingFunction = ArchiveMotion.easeOut
        window.animator().setFrame(frame, display: true)
      }
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        window.animator().setFrame(frame, display: true)
      }
      window.setFrame(frame, display: true)
    }
  }

  func layoutPane() {
    let width = SettingsMetrics.windowWidth
    guard let view = paneContainer.subviews.first as? SettingsPaneView else { return }
    let height = view.fittingHeight(width: width)
    paneContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
    view.frame = paneContainer.bounds
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
  }

  private func paneView(_ pane: SettingsPane) -> SettingsPaneView {
    if let view = paneViews[pane] { return view }
    let view = SettingsPaneView(pane: pane, blocks: blocks(for: pane))
    view.wantsLayer = true
    paneViews[pane] = view
    return view
  }

  private func commandNumber(_ number: Int) -> Bool {
    guard let pane = SettingsPane(commandNumber: number) else { return false }
    select(pane, animated: false)
    return true
  }

  // MARK: Closing and keys

  /// Escape: clears a non-empty Shortcuts search, else closes the window.
  public override func cancelOperation(_ sender: Any?) {
    if selectedPane == .shortcuts, !shortcutsSearch.stringValue.isEmpty {
      setShortcutSearch("")
    } else {
      window?.performClose(sender)
    }
  }

  /// File > Archive Tab (Cmd-W) while Settings is key: closes Settings.
  @objc public func closeTab(_ sender: Any?) { window?.performClose(sender) }

  /// Tabs > Go to Sidebar Item while Settings is key: never enabled (Cmd-1 to Cmd-7 select panes here).
  @objc public func goToSidebarItem(_ sender: Any?) {}

  public func windowDidResignKey(_ notification: Notification) {
    for (item, title) in retitled { item.title = title }
    retitled = []
  }

  public func windowDidBecomeKey(_ notification: Notification) {
    refreshLiveRows()
  }

  public func windowDidResize(_ notification: Notification) {
    (window as? SettingsWindow)?.layoutTrafficLights()
  }

  public func windowDidMove(_ notification: Notification) { rememberPosition() }

  public func windowWillClose(_ notification: Notification) { rememberPosition() }

  private func rememberPosition() {
    guard isPlaced, let frame = window?.frame else { return }
    settings.windowTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
  }

  @objc private func paneDidScroll(_ note: Notification) {
    chrome.setOverContent(scrollView.contentView.bounds.minY > -SettingsMetrics.chromeHeight + 0.5)
  }

  @objc private func appDidBecomeActive(_ note: Notification) {
    refreshDefaultBrowserRow()
  }

  /// The key view loop: pane items (Full Keyboard Access), then the pane's controls top to bottom, leading to
  /// trailing.
  func updateKeyViewLoop() {
    var views: [NSView] = chrome.items
    if let pane = paneContainer.subviews.first { views += Self.keyViews(in: pane) }
    for (view, next) in zip(views, views.dropFirst() + [views[0]]) { view.nextKeyView = next }
    window?.initialFirstResponder = chrome.items.first
  }

  private static func keyViews(in view: NSView) -> [NSView] {
    var found: [NSView] = []
    for child in view.subviews {
      if child is NSControl, !(child is NSTextField) || child is NSSearchField {
        found.append(child)
      } else {
        found += keyViews(in: child)
      }
    }
    return found
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

extension SettingsWindowController: NSMenuItemValidation {
  public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(closeTab(_:)):
      if menuItem.title != "Close Window" {
        retitled.append((menuItem, menuItem.title))
        menuItem.title = "Close Window"
      }
      return true
    case #selector(goToSidebarItem(_:)):
      return false
    default:
      return true
    }
  }
}

extension SettingsWindowController: ToolbarSettingObserver {
  public func toolbarSettingDidChange(_ setting: ToolbarSetting) { applyToolbarSetting(animated: true) }
}

extension SettingsWindowController: AppSettingsObserver {
  public func appSettingsDidChange(_ settings: AppSettings) {
    peekCrossSiteSwitch?.setOn(settings.peekLinks.opensCrossSiteLinks, animated: true)
    peekShiftSwitch?.setOn(settings.peekLinks.opensShiftClickedLinks, animated: true)
    warnBeforeQuittingSwitch?.setOn(settings.warnsBeforeQuitting, animated: true)
    applyLittleArktHotKeyState()                    // #354
    countFavoritesSwitch?.setOn(settings.tabNavigation.countsFavorites, animated: true)
    ninthTabSwitch?.setOn(settings.tabNavigation.ninthOpensNinth, animated: true)
    crashReportsSwitch?.setOn(settings.sendsCrashReports, animated: true)
    applySendCrashReportState()                     // #129
    applyDownloadLocation()                         // #132
  }
}

extension SettingsWindowController: NSSearchFieldDelegate {
  public func controlTextDidChange(_ obj: Notification) {
    guard (obj.object as? NSSearchField) === shortcutsSearch else { return }
    applyShortcutSearch()
  }

  /// Escape in the search field: clears a non-empty search, else closes Settings.
  public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    guard control === shortcutsSearch, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
    cancelOperation(nil)
    return true
  }
}

/// The scroll view's document: holds the shown pane. Flipped, so the pane starts at the top.
@MainActor
public final class SettingsPaneContainer: NSView {
  override public var isFlipped: Bool { true }
}
