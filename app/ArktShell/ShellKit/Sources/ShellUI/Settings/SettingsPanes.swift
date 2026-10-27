import AppKit

/// The panes' rows (docs/design/settings.md, section 2; copy from design/settings/prototype.html). Rows whose feature
/// exists are wired to it; every other designed row is built `planned` (decision 4). There is no ad and tracker
/// blocking row (decision 3), and no user-facing "Arc".
extension SettingsWindowController {
  func blocks(for pane: SettingsPane) -> [SettingsBlockView] {
    switch pane {
    case .general: generalBlocks()
    case .spaces: spacesBlocks()
    case .appearance: appearanceBlocks()
    case .shortcuts: shortcutsBlocks()
    case .extensions: extensionsBlocks()
    case .privacy: privacyBlocks()
    case .advanced: advancedBlocks()
    }
  }

  // MARK: Helpers

  private func section(_ title: String?, _ rows: [SettingsBlockView], note: String? = nil) -> SettingsSectionView {
    SettingsSectionView(title: title, body: SettingsGroupView(rows), note: note)
  }

  func identify(_ view: NSView, _ pane: SettingsPane, _ setting: String) {
    let identifier = AXID.Settings.control(pane.rawValue, setting)
    if let control = view as? NSControl {
      control.setAccessibilityIdentifierWithCell(identifier)
    } else {
      view.setAccessibilityIdentifier(identifier)
    }
  }

  private func toggle(_ pane: SettingsPane, _ setting: String, on: Bool,
                      change: (@MainActor (Bool) -> Void)? = nil) -> SettingsSwitch {
    let control = SettingsSwitch(frame: .zero)
    control.state = on ? .on : .off
    control.onChange = change
    identify(control, pane, setting)
    return control
  }

  func popUp(_ pane: SettingsPane, _ setting: String, _ items: [String], _ selected: String)
    -> SettingsPopUpButton {
    let control = SettingsPopUpButton(items: items, selected: selected)
    identify(control, pane, setting)
    return control
  }

  func pill(_ pane: SettingsPane, _ setting: String, _ title: String, primary: Bool = false,
                    small: Bool = false, action: @escaping @MainActor () -> Void) -> ArchivePillButton {
    let button = ArchivePillButton(style: primary ? .primary : .neutral, title: title,
                                   metrics: .init(height: small ? 24 : 28, fontSize: small ? 12 : 13,
                                                  weight: .semibold, padding: 16, minWidth: nil, pressScale: 0.97))
    button.setArchiveAccessibilityLabel(title.replacingOccurrences(of: "...", with: ""))
    let target = SettingsActionTarget(action)
    actionTargets.append(target)                 // targets are weak
    button.target = target
    button.action = #selector(SettingsActionTarget.fire(_:))
    identify(button, pane, setting)
    return button
  }

  private func destructiveLink(_ pane: SettingsPane, _ setting: String, _ title: String) -> ArchiveLinkButton {
    let link = ArchiveLinkButton(style: .destructive, title: title, fontSize: 13)
    identify(link, pane, setting)
    return link
  }

  func row(_ label: String, _ caption: String? = nil, _ controls: [NSView] = [], planned: Bool = false)
    -> SettingsRowView {
    SettingsRowView(label: label, caption: caption, trailing: controls, planned: planned)
  }

  // MARK: General

  private func generalBlocks() -> [SettingsBlockView] {
    let isDefault = services.isDefaultBrowser()
    let browser = SettingsRowView(label: defaultBrowserLabel(isDefault), caption: defaultBrowserCaption(isDefault),
                                  leading: SettingsAppIcon(), leadingSize: NSSize(width: 32, height: 32),
                                  trailing: [defaultBrowserControl(isDefault)], hoverable: false)
    defaultBrowserRow = browser
    isDefaultBrowserShown = isDefault
    let peek = settings.peekLinks
    let crossSite = toggle(.general, "peekCrossSiteLinks", on: peek.opensCrossSiteLinks) { [weak self] on in
      self?.settings.peekLinks.opensCrossSiteLinks = on
    }
    let shift = toggle(.general, "peekShiftClick", on: peek.opensShiftClickedLinks) { [weak self] on in
      self?.settings.peekLinks.opensShiftClickedLinks = on
    }
    peekCrossSiteSwitch = crossSite
    peekShiftSwitch = shift
    return [
      section("Default browser", [browser]),
      section("Opening and quitting", [
        row("When Arkt opens", "Your Spaces, pinned tabs and Favorites are always kept.",
            [popUp(.general, "whenArktOpens", ["Restore last windows", "Open a new window"], "Restore last windows")],
            planned: true),
        row("Warn before quitting", "Hold Command-Q to quit while a window is open.",
            [toggle(.general, "warnBeforeQuitting", on: false)], planned: true),
      ]),
      section("Links", [
        row(PeekLinkCopy.crossSite, PeekLinkCopy.crossSiteNote, [crossSite]),
        row(PeekLinkCopy.shiftClick, nil, [shift]),
        littleArktLookupRow(),                     // #354
      ]),
      section("Downloads", downloadRows(), note: Self.downloadsNote),        // #132
      section("Updates", [
        // Decision 6: shown disabled and off until the release work (#128).
        row("Update Arkt automatically", "Arkt checks for updates once a day and installs them when you quit.",
            [toggle(.general, "updateAutomatically", on: false)], planned: true),
      ]),
    ]
  }

  private func defaultBrowserLabel(_ isDefault: Bool) -> String {
    isDefault ? "Arkt is your default browser" : "Arkt is not your default browser"
  }

  private func defaultBrowserCaption(_ isDefault: Bool) -> String {
    isDefault ? "Links you open in other apps open in Arkt." : "Links you open in other apps open in another browser."
  }

  /// Make Default (the pane's one primary) or, once Arkt is the default, the neutral Default capsule.
  private func defaultBrowserControl(_ isDefault: Bool) -> NSView {
    if isDefault {
      let seal = SettingsDefaultCapsule(frame: .zero)
      seal.setAccessibilityIdentifier(AXID.Settings.control("general", "defaultBrowserSeal"))
      return seal
    }
    return pill(.general, "makeDefault", "Make Default", primary: true) { [weak self] in self?.makeDefaultBrowser() }
  }

  private func makeDefaultBrowser() {
    let services = services
    pendingDefaultBrowserChange = Task { [weak self] in
      await services.makeDefaultBrowser()
      self?.refreshDefaultBrowserRow()
    }
  }

  /// Reads the default browser again (the app became active, the window opened): macOS asks in its own prompt.
  func refreshDefaultBrowserRow() {
    guard let row = defaultBrowserRow else { return }
    let isDefault = services.isDefaultBrowser()
    guard isDefault != isDefaultBrowserShown else { return }
    isDefaultBrowserShown = isDefault
    let replacement = SettingsRowView(label: defaultBrowserLabel(isDefault), caption: defaultBrowserCaption(isDefault),
                                      leading: SettingsAppIcon(), leadingSize: NSSize(width: 32, height: 32),
                                      trailing: [defaultBrowserControl(isDefault)], hoverable: false)
    guard let group = row.superview as? SettingsGroupView, let section = group.superview as? SettingsSectionView,
          let pane = paneViews(containing: section) else { return }
    let newSection = SettingsSectionView(title: "Default browser", body: SettingsGroupView([replacement]))
    pane.setBlocks(pane.blocks.map { $0 === section ? newSection : $0 })
    defaultBrowserRow = replacement
    if pane.superview != nil { layoutPane() }
    updateKeyViewLoop()
  }

  private func paneViews(containing section: SettingsSectionView) -> SettingsPaneView? {
    section.superview as? SettingsPaneView
  }

  /// Rows that follow something outside Settings: the default browser and the import's availability.
  func refreshLiveRows() {
    refreshDefaultBrowserRow()
    importButton?.isEnabled = services.canImportBrowserData()
  }

  // MARK: Spaces and Profiles

  private func spacesBlocks() -> [SettingsBlockView] {
    let spaces = services.spaces()
    let spaceRows: [SettingsBlockView] = spaces.map { space in
      let profile = popUp(.spaces, "profile", [space.profileName], space.profileName)
      profile.setAccessibilityLabel("Profile for \(space.title)")
      let row = SettingsRowView(label: space.title, caption: space.detail,
                                leading: SettingsSpaceSwatch(colors: space.gradient, icon: space.icon),
                                trailing: [profile])
      profile.isEnabled = false                   // a profile per Space is not built yet (decision 4)
      profile.alphaValue = SettingsTokens.disabledControlAlpha
      profile.setAccessibilityHelp("Choosing a profile per Space: \(SettingsRowView.notAvailable)")
      row.setAccessibilityElement(true)
      row.setAccessibilityRole(.group)
      row.setAccessibilityLabel("\(space.title), \(space.detail), profile \(space.profileName)")
      row.setAccessibilityIdentifier(AXID.Settings.spaceRow(space.id.uuidString))
      return row
    }
    let profiles: [SettingsBlockView] = SettingsSpaceSummary.profiles(in: spaces).map { profile in
      SettingsRowView(label: profile.name, caption: profile.detail, leading: SettingsMonogram(name: profile.name),
                      trailing: [SettingsChevron(frame: .zero)], planned: true)
    }
    let newProfile = SettingsAddRowView(title: "New Profile...", planned: true)
    identify(newProfile.button, .spaces, "newProfile")
    let addRoute = SettingsAddRowView(title: "Add Route...", planned: true)
    identify(addRoute.button, .spaces, "addRoute")
    let archiveOptions = ["1 hour", "6 hours", "12 hours", "24 hours", "7 days", "30 days", "Never"]
    var blocks: [SettingsBlockView] = []
    if !spaceRows.isEmpty {
      blocks.append(section("Spaces", spaceRows,
                            note: "Change a Space\u{2019}s name, icon and theme from its header in the sidebar. "
                              + "Choosing a profile for each Space is not available yet."))
    }
    blocks += [
      section("Archive", [
        row("Archive Today tabs after", "Tabs you haven\u{2019}t looked at for this long move to the Archive.",
            [popUp(.spaces, "archiveTodayAfter", archiveOptions, "12 hours")], planned: true),
        row("Archive Little Arkt windows after", nil,
            [popUp(.spaces, "archiveLittleArktAfter", archiveOptions, "6 hours")], planned: true),
      ]),
      section("Profiles", profiles + [newProfile],
              note: "Each profile keeps its own Favorites, history, cookies, passwords and extensions."),
      section("Link routing", [
        row("Links from other apps open in", nil,
            [popUp(.spaces, "linksFromOtherApps", ["Current Space", "Little Arkt"], "Little Arkt")], planned: true),
        addRoute,
      ]),
    ]
    return blocks
  }

  // MARK: Appearance

  private func appearanceBlocks() -> [SettingsBlockView] {
    let toolbar = settings.toolbar
    let preview = SettingsPreviewBlock(gradient: services.spaces().first?.gradient ?? [])
    preview.preview.setShowsToolbar(toolbar.isVisible, animated: false)
    self.preview = preview.preview
    let showToolbar = toggle(.appearance, "showToolbar", on: toolbar.isVisible) { [weak self] on in
      self?.settings.toolbar.isVisible = on
    }
    let fullURL = toggle(.appearance, "showFullURL", on: toolbar.showsFullURL) { [weak self] on in
      self?.settings.toolbar.showsFullURL = on
    }
    let keys = SettingsKeycapsView(keys: ["\u{21E7}", "\u{2318}", "D"], spoken: "Shift Command D", height: 18)
    let toolbarRow = SettingsRowView(label: "Show Toolbar", caption: "Also with", captionAccessory: keys,
                                     trailing: [showToolbar])
    let fullURLRow = row("Show the full URL", "When off, the Toolbar shows the site\u{2019}s name only.", [fullURL])
    toolbarSwitch = showToolbar
    fullURLSwitch = fullURL
    self.fullURLRow = fullURLRow
    let navigation = settings.tabNavigation
    let favorites = toggle(.appearance, "countFavorites", on: navigation.countsFavorites) { [weak self] on in
      self?.settings.tabNavigation.countsFavorites = on
    }
    let ninth = toggle(.appearance, "ninthTab", on: navigation.ninthOpensNinth) { [weak self] on in
      self?.settings.tabNavigation.ninthOpensNinth = on
    }
    countFavoritesSwitch = favorites
    ninthTabSwitch = ninth
    let websites = SettingsSegmentedControl(segments: ["Light", "Dark", "Automatic"], selected: 2)
    identify(websites, .appearance, "websitesUse")
    applyToolbarSetting(animated: false)
    return [
      SettingsSectionView(title: nil, body: SettingsGroupView([preview])),
      section("Websites", [
        row("Websites use", "Sites that offer a dark design switch with it.", [websites], planned: true),
      ]),
      section("Toolbar", [toolbarRow, fullURLRow]),
      section("Sidebar", [
        row("Count Favorites in Command-1 to Command-8", nil, [favorites]),
        row("Command-9 opens the ninth tab", "When off, Command-9 opens the last tab.", [ninth]),
        row("Haptic feedback when reordering tabs", nil, [toggle(.appearance, "reorderHaptics", on: true)],
            planned: true),
        row("Play sound effects", nil, [toggle(.appearance, "soundEffects", on: true)], planned: true),
      ]),
    ]
  }

  /// Show Toolbar and Show the full URL follow the shared setting (Settings, the View menu, Cmd-Shift-D); the full
  /// URL row is dimmed while the Toolbar is off.
  func applyToolbarSetting(animated: Bool) {
    let toolbar = settings.toolbar
    toolbarSwitch?.setOn(toolbar.isVisible, animated: animated)
    fullURLSwitch?.setOn(toolbar.showsFullURL, animated: animated)
    fullURLRow?.setDimmed(!toolbar.isVisible)
    if let preview, preview.showsToolbar != toolbar.isVisible {
      preview.setShowsToolbar(toolbar.isVisible, animated: animated)
    }
  }

  // MARK: Shortcuts

  private func shortcutsBlocks() -> [SettingsBlockView] {
    shortcutSections = services.shortcutsMenu().map(ShortcutCatalog.sections(from:)) ?? []
    let search = SettingsFixedBlock(shortcutsSearch, height: SettingsMetrics.searchHeight)
    return [search] + shortcutSectionBlocks(ShortcutCatalog.filter(shortcutSections, query: shortcutsSearch.stringValue))
      + [shortcutsFooter()]
  }

  private func shortcutSectionBlocks(_ sections: [ShortcutCatalog.Section]) -> [SettingsBlockView] {
    sections.map { section in
      self.section(section.title, section.entries.map { entry in
        let keys = SettingsKeycapsView(keys: entry.keys, spoken: entry.spoken)
        let row = SettingsRowView(label: entry.title, trailing: [keys])
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.staticText)
        row.setAccessibilityLabel("\(entry.displayTitle), \(entry.spoken)")
        return row
      })
    }
  }

  private func shortcutsFooter() -> SettingsBlockView {
    let note = settingsLabel("Changing a shortcut, and choosing whether Arkt or the website gets it first, is "
                               + "not available yet.", size: 12)
    note.textColor = ShellTokens.secondaryText.resolve(window?.contentView?.archiveFlavor ?? .light).nsColor()
    let reset = destructiveLink(.shortcuts, "resetAll", "Reset All Shortcuts...")
    reset.isEnabled = false
    reset.disabledOpacity = Float(SettingsTokens.disabledControlAlpha)
    reset.setAccessibilityHelp(SettingsRowView.notAvailable)
    let holder = NSView()
    holder.addSubview(note)
    holder.addSubview(reset)
    return SettingsFixedBlock(holder, height: 34) { view, rect in
      view.frame = rect
      let resetSize = reset.intrinsicContentSize
      reset.frame = NSRect(x: rect.width - 10 - resetSize.width, y: ((rect.height - resetSize.height) / 2).rounded(),
                           width: resetSize.width, height: resetSize.height)
      let width = max(40, reset.frame.minX - 16 - 10)
      let height = settingsTextHeight(note, width: width)
      note.frame = NSRect(x: 10, y: ((rect.height - height) / 2).rounded(), width: width, height: height)
    }
  }

  /// Sets the Shortcuts search, as typing does.
  public func setShortcutSearch(_ text: String) {
    if shortcutsSearch.stringValue != text { shortcutsSearch.stringValue = text }
    applyShortcutSearch()
  }

  func applyShortcutSearch() {
    guard let pane = shortcutsPaneIfBuilt, let search = pane.blocks.first, let footer = pane.blocks.last else {
      return
    }
    let found = ShortcutCatalog.filter(shortcutSections, query: shortcutsSearch.stringValue)
    pane.setBlocks([search] + shortcutSectionBlocks(found) + [footer])
    if selectedPane == .shortcuts { layoutPane() }
    updateKeyViewLoop()
  }

  /// The titles of the Shortcuts rows shown now.
  public var visibleShortcutTitles: [String] {
    ShortcutCatalog.filter(shortcutSections, query: shortcutsSearch.stringValue).flatMap(\.entries).map(\.title)
  }

  /// The Shortcuts pane, once built (the search field sits in it).
  private var shortcutsPaneIfBuilt: SettingsPaneView? { shortcutsSearch.enclosingPane }

  // MARK: Extensions

  private func extensionsBlocks() -> [SettingsBlockView] {
    let store = pill(.extensions, "openWebStore", "Open Chrome Web Store", primary: true) {}
    store.isEnabled = false
    store.setAccessibilityHelp(SettingsRowView.notAvailable)
    return [
      SettingsSectionView(title: "Installed", body: SettingsGroupView([
        SettingsEmptyStateBlock(
          symbol: "puzzlepiece.extension", title: "Extensions",
          detail: "Arkt runs extensions from the Chrome Web Store. Turning them on and off, pinning and their details "
            + "come here; until then, use the extensions menu in the sidebar. Not available yet.",
          action: store),
      ])),
      section(nil, [
        row("Developer mode", "Load unpacked extensions from a folder.",
            [toggle(.extensions, "developerMode", on: false)], planned: true),
      ]),
    ]
  }

  // MARK: Privacy and Security

  private func privacyBlocks() -> [SettingsBlockView] {
    let permission: (String, String, String) -> SettingsRowView = { label, setting, value in
      self.row(label, nil, [self.popUp(.privacy, setting, ["Ask", "Allow", "Block"], value), SettingsChevron(frame: .zero)],
               planned: true)
    }
    let clear = destructiveLink(.privacy, "clearBrowsingData", "Clear...")
    return [
      section("Tracking", [
        row("Block third-party cookies", "Some sign-ins and embedded content may stop working.",
            [toggle(.privacy, "blockThirdPartyCookies", on: true)], planned: true),
        row("Block cookie banners", "Some pages may load incorrectly.",
            [toggle(.privacy, "blockCookieBanners", on: false)], planned: true),
        row("Safe Browsing", "Warns you about dangerous sites and downloads.",
            [popUp(.privacy, "safeBrowsing", ["Enhanced protection", "Standard protection", "No protection"],
                   "Standard protection")], planned: true),
      ]),
      section("Site permissions", [
        permission("Location", "location", "Ask"),
        permission("Camera", "camera", "Ask"),
        permission("Microphone", "microphone", "Ask"),
        permission("Notifications", "notifications", "Ask"),
        permission("Pop-ups and redirects", "popups", "Block"),
      ], note: "The arrow lists the sites you allowed or blocked. Change one site from the page with the site "
        + "controls in the URL bar."),
      section("Data", [
        row("Let websites read your Space\u{2019}s theme colors", nil, [toggle(.privacy, "themeColors", on: false)],
            planned: true),
        row("Clear browsing data", "History, cookies and cached files, for a time range.", [clear], planned: true),
      ]),
      crashReportsSection(),
    ]
  }

  // MARK: Advanced

  private func advancedBlocks() -> [SettingsBlockView] {
    let services = services
    let importButton = pill(.advanced, "importBrowserData", "Import...", small: true) {
      services.importBrowserData()
    }
    self.importButton = importButton
    let reveal = pill(.advanced, "showDataFolder", "Show in Finder", small: true) { services.showDataFolder?() }
    let importRow = row("Import browser data", "Spaces, pinned tabs, folders and Favorites from another browser.",
                        [importButton])
    // After the row: a row enables the controls it holds.
    importButton.isEnabled = services.canImportBrowserData()
    let folderRow = row("Arkt\u{2019}s data folder", "The sidebar, the Archive and their backups.", [reveal])
    reveal.isEnabled = services.showDataFolder != nil
    return [
      section("Pages", [
        row("Open Picture in Picture when you leave a video tab", nil,
            [toggle(.advanced, "autoPictureInPicture", on: true)], planned: true),
        row("Drag the window from the top of web pages", "Hold Command to select text there instead.",
            [toggle(.advanced, "dragWindowFromPage", on: true)], planned: true),
      ]),
      section("Data", [importRow, folderRow]),
      section("Reset", [
        row("Reset all settings", "Your Spaces, tabs and the Archive stay as they are.",
            [destructiveLink(.advanced, "resetAll", "Reset...")], planned: true),
      ]),
    ]
  }

  // MARK: Inspection (tests)

  /// Enabled primary (mustard) actions in `pane`: at most one per surface.
  public func primaryActionCount(in pane: SettingsPane) -> Int {
    func count(_ view: NSView) -> Int {
      let own = (view as? ArchivePillButton).map { $0.style == .primary && $0.isEnabled ? 1 : 0 } ?? 0
      return own + view.subviews.map(count).reduce(0, +)
    }
    guard let view = paneContainer.subviews.first as? SettingsPaneView, view.pane == pane else { return 0 }
    return count(view)
  }

  /// Every text the shown pane and the chrome draw: labels, captions, notes, button titles, keycap names.
  public func visibleTexts() -> [String] {
    func collect(_ view: NSView) -> [String] {
      var texts: [String] = []
      switch view {
      case let field as NSSearchField: texts.append(field.placeholderAttributedString?.string ?? "")
      case let field as NSTextField: texts.append(field.stringValue)
      case let pill as ArchivePillButton: texts.append(pill.title)
      case let link as ArchiveLinkButton: texts.append(link.title)
      case let popUp as SettingsPopUpButton: texts += popUp.items
      case let row as SettingsRowView: texts.append(row.accessibilityLabel() ?? "")
      default: break
      }
      return texts.filter { !$0.isEmpty } + view.subviews.flatMap(collect)
    }
    return collect(paneContainer) + SettingsPane.allCases.map(\.label) + [titleLabel.stringValue]
  }

  /// The Appearance preview shows the Toolbar strip.
  public var appearancePreviewShowsToolbar: Bool { preview?.showsToolbar ?? false }
}

/// A closure as a target-action target.
@MainActor
final class SettingsActionTarget: NSObject {
  private let body: @MainActor () -> Void

  init(_ body: @escaping @MainActor () -> Void) { self.body = body }

  @objc func fire(_ sender: Any?) { body() }
}

extension NSView {
  /// The settings pane this view sits in.
  var enclosingPane: SettingsPaneView? {
    var view = superview
    while let current = view {
      if let pane = current as? SettingsPaneView { return pane }
      view = current.superview
    }
    return nil
  }
}
