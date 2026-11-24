import AppKit
import EngineAPI

/// Settings > Extensions (#600; design/settings `extensions`, `extensions-empty`): the installed list, one row per
/// extension by name (icon, name, "Version X. ..." caption, pin, switch), the details under a clicked row (Options...,
/// Keyboard Shortcuts..., Remove... through the remove sheet), then Get more extensions and Developer mode, with Load
/// Unpacked... while it is on. No extensions: the empty state, whose Open Chrome Web Store is the pane's one primary.
///
/// Every change goes to the engine (`EngineExtensions`, engine side #964). The pane shows what the engine reports: it
/// rebuilds on `.installedExtensionsChanged`, after its own pin and developer mode calls, and when Settings becomes key
/// (a pin changed in a browser window), and only when what it shows changed. A switch the engine refused snaps back.
/// Rows go only when the engine reports them gone, so an uninstall that fails leaves the row.
extension SettingsWindowController {
  static let extensionsNote = "Click an extension for its details, options and keyboard shortcuts. Remove it from "
    + "its details."
  static let extensionsEmptyTitle = "No Extensions Yet"
  static let extensionsEmptyDetail = "Arkt runs extensions from the Chrome Web Store. The ones you add show up here "
    + "and in the sidebar\u{2019}s extensions menu."
  static let openWebStoreTitle = "Open Chrome Web Store"
  static let loadUnpackedTitle = "Load Unpacked..."
  static let loadFailedTitle = "Couldn\u{2019}t load the extension"

  /// A row's live controls, updated in place when only the extension's state changed.
  @MainActor
  final class ExtensionRowControls {
    weak var row: SettingsRowView?
    weak var enabled: SettingsSwitch?
    weak var pin: ExtensionsPinToggle?
    init(row: SettingsRowView, enabled: SettingsSwitch, pin: ExtensionsPinToggle) {
      self.row = row; self.enabled = enabled; self.pin = pin
    }
  }

  /// What the pane shows; it rebuilds only when this changes.
  struct ExtensionsPaneState: Equatable {
    var list: [InstalledExtensionInfo]
    var pinned: [String]
    var developerMode: Bool
    var expanded: String?
    /// Extensions with keyboard commands (their details offer Keyboard Shortcuts...).
    var withCommands: Set<String>
  }

  // MARK: Engine

  /// Follows the engine's installed list while the window is open.
  func observeInstalledExtensions() {
    guard let engine = services.extensions, installedExtensionsObservation == nil else { return }
    installedExtensionsObservation = engine.observeExtensions { [weak self] event in
      guard event == .installedExtensionsChanged else { return }
      self?.refreshExtensionsPane()
    }
  }

  /// The window closed: no observation, no sheets, nothing expanded next time, and a load in flight forgotten (its
  /// answer is ignored).
  func stopObservingInstalledExtensions() {
    installedExtensionsObservation?.cancel()
    installedExtensionsObservation = nil
    closeExtensionSheets()
    expandedExtensionID = nil
    pendingUnpackedLoad = nil
    unpackedLoadTokens = []
  }

  private func currentExtensionsPaneState() -> ExtensionsPaneState {
    guard let engine = services.extensions else {
      return ExtensionsPaneState(list: [], pinned: [], developerMode: false, expanded: nil, withCommands: [])
    }
    let list = engine.installedExtensions.sorted {
      let order = $0.name.localizedStandardCompare($1.name)
      return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
    }
    let expanded = expandedExtensionID.flatMap { id in list.contains { $0.id == id } ? id : nil }
    return ExtensionsPaneState(list: list, pinned: engine.pinnedExtensionIDs,
                               developerMode: engine.isExtensionDeveloperModeEnabled, expanded: expanded,
                               withCommands: Set(engine.extensionCommands.map(\.id.extensionID)))
  }

  /// Follows what the engine reports, when the pane is built and what it shows changed. A change that keeps the rows
  /// (the same ids in the same order, the same details and developer mode, no new name or icon) updates the rows in
  /// place, so a switch just flipped stays put; anything else rebuilds the pane, keeping the keyboard focus on the
  /// same control. The remove sheet closes when its extension went away; details close with their extension.
  func refreshExtensionsPane() {
    let state = currentExtensionsPaneState()
    if expandedExtensionID != state.expanded { expandedExtensionID = state.expanded }
    if let sheet = extensionRemoveSheet, !state.list.contains(where: { $0.id == sheet.extensionID }) {
      extensionRemoveSheet = nil
      sheet.dismiss()
    }
    guard let pane = builtPane(.extensions), state != shownExtensionsState else { return }
    if let shown = shownExtensionsState, Self.rowsMatch(shown, state) {
      shownExtensionsState = state
      for info in state.list { updateExtensionRow(info, pinned: state.pinned.contains(info.id), state: state) }
      return
    }
    let focused = (window?.firstResponder as? NSView)?.accessibilityIdentifier()
    pane.setBlocks(extensionsBlocks(state))
    if selectedPane == .extensions { fitWindowToPane() }
    updateKeyViewLoop()
    if let focused, !focused.isEmpty, let view = Self.view(focused, in: pane) { window?.makeFirstResponder(view) }
  }

  private static func view(_ identifier: String, in root: NSView) -> NSView? {
    if root.accessibilityIdentifier() == identifier { return root }
    for child in root.subviews {
      if let hit = view(identifier, in: child) { return hit }
    }
    return nil
  }

  // MARK: Manage Extension...

  /// Manage Extension... (#600): Extensions with `extensionID`'s details open and scrolled into view; an extension
  /// that is not installed opens the pane with nothing open.
  public func show(extensionID: String) {
    let known = services.extensions?.installedExtensions.contains { $0.id == extensionID } ?? false
    expandedExtensionID = known ? extensionID : nil
    show(pane: .extensions)
    refreshExtensionsPane()
    if known { scrollToExtension(extensionID) }
  }

  private func scrollToExtension(_ extensionID: String) {
    guard let pane = builtPane(.extensions),
          let row = Self.view(AXID.Settings.control("extensions", "row.\(extensionID)"), in: pane)?
            .enclosingSettingsRow else { return }
    var rect = row.convert(row.bounds, to: paneContainer)
    if let details = Self.view(AXID.Settings.control("extensions", "details.\(extensionID)"), in: pane) {
      rect = rect.union(details.convert(details.bounds, to: paneContainer))
    }
    paneContainer.scrollToVisible(rect.insetBy(dx: 0, dy: -SettingsMetrics.chromeHeight / 2))
  }

  /// The rows can stay: only per-row state (on or off, pin, caption) changed. The expanded extension's details show its
  /// info, so any change to it rebuilds.
  private static func rowsMatch(_ old: ExtensionsPaneState, _ new: ExtensionsPaneState) -> Bool {
    guard old.list.map(\.id) == new.list.map(\.id), old.expanded == new.expanded,
          old.developerMode == new.developerMode, old.withCommands == new.withCommands else { return false }
    return zip(old.list, new.list).allSatisfy { before, after in
      before.name == after.name && before.iconPNG == after.iconPNG && (after.id != new.expanded || before == after)
        && (extensionCaption(before, developerMode: new.developerMode) == nil)
          == (extensionCaption(after, developerMode: new.developerMode) == nil)
    }
  }

  /// One row follows its extension's state in place: the caption, the switch (animated) and the pin.
  private func updateExtensionRow(_ info: InstalledExtensionInfo, pinned: Bool, state: ExtensionsPaneState) {
    guard let controls = extensionRowControls[info.id] else { return }
    controls.row?.setCaption(Self.extensionCaption(info, developerMode: state.developerMode))
    if let enabled = controls.enabled {
      enabled.setOn(info.isEnabled, animated: true)
      enabled.isEnabled = info.canDisable
      enabled.alphaValue = info.canDisable ? 1 : SettingsTokens.disabledControlAlpha
    }
    if let pin = controls.pin {
      pin.isOn = pinned
      pin.toolTip = pinned ? "Unpin" : "Pin"
      pin.isEnabled = info.isEnabled
      pin.alphaValue = info.isEnabled ? 1 : SettingsTokens.disabledControlAlpha
    }
  }

  /// The icon's image, decoded once per extension and PNG (the bytes compared, not a hash).
  private func extensionIcon(_ info: InstalledExtensionInfo) -> NSImage? {
    guard let png = info.iconPNG else { return nil }
    if let cached = extensionIconCache[info.id], cached.png == png { return cached.image }
    guard let image = NSImage(data: png) else { return nil }
    extensionIconCache[info.id] = (png, image)
    return image
  }

  // MARK: Blocks

  func extensionsBlocks(_ given: ExtensionsPaneState? = nil) -> [SettingsBlockView] {
    let state = given ?? currentExtensionsPaneState()
    shownExtensionsState = state
    shownExtensionIDs = state.list.map(\.id)
    extensionTargets = []
    extensionRowControls = [:]
    let current = Set(state.list.map(\.id))
    extensionIconCache = extensionIconCache.filter { current.contains($0.key) }
    let engine = services.extensions
    let hasList = !state.list.isEmpty
    let store = pill(.extensions, "openWebStore", Self.openWebStoreTitle, primary: !hasList, small: hasList) {
      [weak self] in self?.services.openWebStore?()
    }
    let developer = toggle(.extensions, "developerMode", on: state.developerMode) { [weak self] on in
      self?.setExtensionDeveloperMode(on)
    }
    extensionsDeveloperSwitch = developer
    var more: [SettingsBlockView] = []
    if hasList { more.append(row("Get more extensions", nil, [store])) }
    more.append(row("Developer mode", "Load unpacked extensions from a folder.", [developer], planned: engine == nil))
    if state.developerMode, engine != nil { more.append(loadUnpackedRow()) }
    // After the rows: a row enables the controls it holds.
    store.isEnabled = services.openWebStore != nil
    guard hasList else {
      let empty = SettingsEmptyStateBlock(symbol: "puzzlepiece.extension", title: Self.extensionsEmptyTitle,
                                          detail: Self.extensionsEmptyDetail, action: store)
      empty.setAccessibilityIdentifier(AXID.Settings.control("extensions", "empty"))
      return [
        SettingsSectionView(title: nil, body: SettingsGroupView([empty])),
        SettingsSectionView(title: nil, body: SettingsGroupView(more)),
      ]
    }
    var rows: [SettingsBlockView] = []
    for info in state.list {
      rows.append(extensionRow(info, pinned: state.pinned.contains(info.id), expanded: state.expanded == info.id,
                               developerMode: state.developerMode))
      if state.expanded == info.id { rows.append(extensionDetails(info, hasCommands: state.withCommands.contains(info.id))) }
    }
    return [
      SettingsSectionView(title: "Installed", body: SettingsGroupView(rows), note: Self.extensionsNote),
      SettingsSectionView(title: nil, body: SettingsGroupView(more)),
    ]
  }

  /// The row's caption, one line cut at the end (the design's site-access line, #600 decision): "Version 8.11. Can read
  /// and change data on all sites." (on N sites, when you click it); the short description for an extension without
  /// site access; "Turned off." ("Turned off while developer mode is off." for an unpacked one then); "Installed by
  /// your organization." for policy.
  static func extensionCaption(_ info: InstalledExtensionInfo, developerMode: Bool) -> String? {
    let version = info.version.isEmpty ? "" : "Version \(info.version)."
    let detail: String
    if !info.isEnabled {
      detail = info.origin == .unpacked && !developerMode ? "Turned off while developer mode is off." : "Turned off."
    } else if info.origin == .policy {
      detail = "Installed by your organization."
    } else {
      switch info.siteAccess {
      case .allSites: detail = "Can read and change data on all sites."
      case .someSites(let count): detail = "Can read and change data on \(count) site\(count == 1 ? "" : "s")."
      case .onClick: detail = "Can read and change data when you click it."
      case .noHostAccess: detail = info.description.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    let caption = [version, detail].filter { !$0.isEmpty }.joined(separator: " ")
    return caption.isEmpty ? nil : caption
  }

  /// "Version 8.11 · From the Chrome Web Store": the details' second line.
  static func extensionOrigin(_ info: InstalledExtensionInfo) -> String {
    let origin = switch info.origin {
    case .webStore: "From the Chrome Web Store"
    case .unpacked: "Loaded from a folder"
    case .policy: "Installed by your organization"
    case .other: "Not from the Chrome Web Store"
    }
    return info.version.isEmpty ? origin : "Version \(info.version) \u{00B7} \(origin)"
  }

  private func target(_ body: @escaping @MainActor () -> Void) -> SettingsActionTarget {
    let target = SettingsActionTarget(body)
    extensionTargets.append(target)              // targets are weak
    return target
  }

  private func extensionRow(_ info: InstalledExtensionInfo, pinned: Bool, expanded: Bool,
                            developerMode: Bool) -> SettingsRowView {
    let id = info.id
    let pin = ExtensionsPinToggle()
    pin.isOn = pinned
    pin.setArchiveAccessibilityLabel("Pin \(info.name)")
    pin.toolTip = pinned ? "Unpin" : "Pin"
    let pinTarget = target { [weak self, weak pin] in
      guard let pin else { return }
      self?.setExtensionPinned(id, pinned: !pin.isOn)
    }
    pin.target = pinTarget
    pin.action = #selector(SettingsActionTarget.fire(_:))
    identify(pin, .extensions, "pin.\(id)")
    let enabled = toggle(.extensions, "enabled.\(id)", on: info.isEnabled) { [weak self] on in
      self?.setExtension(id, enabled: on)
    }
    let row = SettingsRowView(label: info.name, caption: Self.extensionCaption(info, developerMode: developerMode),
                              leading: SettingsExtensionIcon(image: extensionIcon(info)), trailing: [pin, enabled],
                              singleLine: true)
    extensionRowControls[id] = ExtensionRowControls(row: row, enabled: enabled, pin: pin)
    row.toolTip = info.name
    // After the row: a row enables the controls it holds. Chromium pins only extensions that are on.
    pin.isEnabled = info.isEnabled
    pin.alphaValue = info.isEnabled ? 1 : SettingsTokens.disabledControlAlpha
    enabled.isEnabled = info.canDisable
    enabled.alphaValue = info.canDisable ? 1 : SettingsTokens.disabledControlAlpha
    let button = SettingsRowButton(label: info.name)
    button.setAccessibilityHelp(expanded ? "Hides its details" : "Shows its details, options and Remove")
    button.setAccessibilityExpanded(expanded)
    let rowTarget = target { [weak self] in self?.toggleExtensionDetails(id) }
    button.target = rowTarget
    button.action = #selector(SettingsActionTarget.fire(_:))
    identify(button, .extensions, "row.\(id)")
    row.setRowButton(button)
    return row
  }

  private func extensionDetails(_ info: InstalledExtensionInfo, hasCommands: Bool) -> SettingsExtensionDetailsView {
    let id = info.id
    var actions: [NSView] = []
    if info.hasOptionsPage, info.isEnabled {
      actions.append(pill(.extensions, "options.\(id)", "Options...", small: true) { [weak self] in
        self?.services.extensions?.openExtensionOptionsPage(id)
      })
    }
    if hasCommands {
      let link = ArchiveLinkButton(style: .secondary, title: "Keyboard Shortcuts...", fontSize: 13)
      link.target = target { [weak self] in self?.showShortcuts(of: info.name) }
      link.action = #selector(SettingsActionTarget.fire(_:))
      identify(link, .extensions, "shortcuts.\(id)")
      actions.append(link)
    }
    if info.canUninstall {
      let link = ArchiveLinkButton(style: .destructive, title: "Remove...", fontSize: 13)
      link.setAccessibilityLabel("Remove \(info.name)")
      link.target = target { [weak self] in self?.presentExtensionRemoveSheet(info) }
      link.action = #selector(SettingsActionTarget.fire(_:))
      identify(link, .extensions, "remove.\(id)")
      actions.append(link)
    }
    let details = SettingsExtensionDetailsView(description: info.description, meta: Self.extensionOrigin(info),
                                               actions: actions)
    details.setAccessibilityElement(true)
    details.setAccessibilityRole(.group)
    details.setAccessibilityLabel("\(info.name) details")
    details.setAccessibilityIdentifier(AXID.Settings.control("extensions", "details.\(id)"))
    return details
  }

  private func loadUnpackedRow() -> SettingsAddRowView {
    let add = SettingsAddRowView(title: Self.loadUnpackedTitle, planned: false)
    add.button.target = target { [weak self] in self?.loadUnpackedExtension() }
    add.button.action = #selector(SettingsActionTarget.fire(_:))
    identify(add.button, .extensions, "loadUnpacked")
    return add
  }

  // MARK: Actions

  private func toggleExtensionDetails(_ extensionID: String) {
    expandedExtensionID = expandedExtensionID == extensionID ? nil : extensionID
    refreshExtensionsPane()
  }

  /// The switch: the engine turns it on or off; a refusal puts the switch back. An extension whose update asks for
  /// more permissions stays off, and the one-answer sheet says why.
  private func setExtension(_ extensionID: String, enabled: Bool) {
    guard let engine = services.extensions else { return }
    let result = engine.setExtensionEnabled(extensionID, enabled: enabled)
    refreshExtensionsPane()
    guard result != .applied else { return }
    if result == .needsPermissionApproval {
      let name = engine.installedExtensions.first { $0.id == extensionID }?.name ?? ""
      showNeedsPermissionSheet(extensionID: extensionID, name: name)
    }
    let control = builtPane(.extensions).flatMap {
      Self.view(AXID.Settings.control("extensions", "enabled.\(extensionID)"), in: $0)
    } as? SettingsSwitch
    let actual = engine.installedExtensions.first { $0.id == extensionID }?.isEnabled ?? !enabled
    control?.setOn(actual, animated: true)
  }

  private func setExtensionPinned(_ extensionID: String, pinned: Bool) {
    services.extensions?.setExtensionPinned(extensionID, pinned: pinned)
    refreshExtensionsPane()
  }

  /// Developer mode: the switch shows what the engine has afterwards (an engine without it stays off). Turning it off
  /// while unpacked extensions are on asks first, since Chromium turns them off; Cancel leaves it on.
  private func setExtensionDeveloperMode(_ on: Bool) {
    guard let engine = services.extensions else { return }
    let unpacked = engine.installedExtensions.filter { $0.origin == .unpacked && $0.isEnabled }
    if !on, !unpacked.isEmpty {
      askToTurnOffDeveloperMode()
      return
    }
    applyExtensionDeveloperMode(on)
  }

  private func applyExtensionDeveloperMode(_ on: Bool) {
    guard let engine = services.extensions else { return }
    engine.setExtensionDeveloperModeEnabled(on)
    refreshExtensionsPane()
    extensionsDeveloperSwitch?.setOn(engine.isExtensionDeveloperModeEnabled, animated: true)
  }

  /// Keyboard Shortcuts...: Settings > Shortcuts searched for the extension, so its shortcuts show.
  private func showShortcuts(of name: String) {
    select(.shortcuts, animated: true)
    setShortcutSearch(name)
  }

  /// No count: extensions loaded with --load-extension are listed as unpacked too but stay on, so a count would
  /// overcount.
  static var developerModeOffContent: DialogContent {
    DialogContent(title: "Turn off developer mode?",
                  paragraphs: [.init("Unpacked extensions you loaded from a folder will be turned off. They come "
                    + "back on when you turn developer mode on again.")],
                  primaryTitle: "Turn Off", cancelTitle: "Cancel", defaultButton: .cancel,
                  primaryHelp: "Turns off developer mode and the unpacked extensions", width: resetSettingsWidth)
  }

  /// The confirmation for developer mode off; the switch stays on until Turn Off.
  private func askToTurnOffDeveloperMode() {
    extensionsDeveloperSwitch?.setOn(true, animated: true)
    guard extensionAlert == nil, let window, window.attachedSheet == nil else { return }
    let sheet = DialogSheet(content: Self.developerModeOffContent)
    sheet.onAnswer = { [weak self] answer in
      self?.extensionAlert = nil
      if answer == .primary { self?.applyExtensionDeveloperMode(false) }
    }
    extensionAlert = sheet
    sheet.begin(on: window)
  }

  /// Load Unpacked...: the folder panel, then the engine loads the folder (an absolute file URL only). A load error shows on the shared dialog
  /// sheet with one answer; a loaded extension's details open.
  private func loadUnpackedExtension() {
    guard let engine = services.extensions, window?.attachedSheet == nil else { return }
    unpackedFolderPicker(window) { [weak self] folder in
      guard let self, let folder, folder.isFileURL, folder.path.hasPrefix("/") else { return }
      let token = UUID()
      self.unpackedLoadTokens.insert(token)
      self.pendingUnpackedLoad = Task { [weak self] in
        let result = await engine.loadUnpackedExtension(at: folder)
        self?.finishUnpackedLoad(result, token: token)
      }
    }
  }

  /// Each load's answer counts once; one that finishes after Settings closed is ignored (the close forgot its token).
  private func finishUnpackedLoad(_ result: UnpackedExtensionResult, token: UUID) {
    guard unpackedLoadTokens.remove(token) != nil else { return }
    if unpackedLoadTokens.isEmpty { pendingUnpackedLoad = nil }
    switch result {
    case .loaded(let id):
      expandedExtensionID = id
      refreshExtensionsPane()
      scrollToExtension(id)
    case .failed(let reason):
      showExtensionAlert(Self.loadFailedContent(reason))
    case .developerModeOff:
      refreshExtensionsPane()
      extensionsDeveloperSwitch?.setOn(false, animated: true)
    }
  }

  static func loadFailedContent(_ reason: String) -> DialogContent {
    DialogContent(title: loadFailedTitle, paragraphs: [.init(reason)], primaryTitle: "OK", width: resetSettingsWidth)
  }

  /// Why a switch did not turn an extension on: its update asks for more permissions. Review Permissions opens
  /// chrome://extensions on it in a browser window (#600 decision B).
  static func needsPermissionContent(_ name: String) -> DialogContent {
    let title = name.isEmpty ? "This extension needs new permissions" : "\u{201C}\(name)\u{201D} needs new permissions"
    return DialogContent(title: title,
                         paragraphs: [.init("Its latest update asks for more access, so it stays off until you "
                           + "review the new permissions on the browser\u{2019}s extensions page.")],
                         primaryTitle: "Review Permissions", cancelTitle: "Cancel",
                         primaryHelp: "Opens the extension on the extensions page in a browser window",
                         width: resetSettingsWidth, titleMaxLines: 2)
  }

  /// chrome://extensions on one extension.
  static func extensionsPageURL(_ extensionID: String) -> URL? {
    var components = URLComponents()
    components.scheme = "chrome"
    components.host = "extensions"
    components.path = "/"
    components.queryItems = [URLQueryItem(name: "id", value: extensionID)]
    return components.url
  }

  private func showNeedsPermissionSheet(extensionID: String, name: String) {
    guard extensionAlert == nil, let window, window.attachedSheet == nil else { return }
    let sheet = DialogSheet(content: Self.needsPermissionContent(name))
    sheet.onAnswer = { [weak self] answer in
      guard let self else { return }
      self.extensionAlert = nil
      if answer == .primary, let url = Self.extensionsPageURL(extensionID) { self.services.openInBrowser?(url) }
    }
    extensionAlert = sheet
    sheet.begin(on: window)
  }

  private func showExtensionAlert(_ content: DialogContent) {
    guard extensionAlert == nil, let window, window.attachedSheet == nil else { return }
    let sheet = DialogSheet(content: content)
    sheet.onAnswer = { [weak self] _ in self?.extensionAlert = nil }
    extensionAlert = sheet
    sheet.begin(on: window)
  }

  /// Remove...: the remove sheet (#720) on the Settings window; Remove uninstalls through the engine with the Report
  /// abuse state (offered only for a Web Store extension). Nothing while another sheet is up.
  private func presentExtensionRemoveSheet(_ info: InstalledExtensionInfo) {
    guard info.canUninstall, extensionRemoveSheet == nil, let window, window.attachedSheet == nil else { return }
    let action = ExtensionAction(id: info.id, name: info.name, iconPNG: info.iconPNG, canUninstall: true,
                                 canReportAbuse: info.origin == .webStore)
    let sheet = ExtensionRemoveSheet(action: action)
    let extensionID = info.id
    sheet.onFinish = { [weak self] reportAbuse in
      guard let self else { return }
      self.extensionRemoveSheet = nil
      guard let reportAbuse else { return }
      self.services.extensions?.uninstallExtension(extensionID, reportAbuse: reportAbuse, in: nil)
    }
    extensionRemoveSheet = sheet
    sheet.begin(on: window)
  }

  /// Closes the remove sheet and the load error without an answer.
  func closeExtensionSheets() {
    let remove = extensionRemoveSheet
    extensionRemoveSheet = nil
    remove?.dismiss()
    let alert = extensionAlert
    extensionAlert = nil
    alert?.dismiss()
  }
}
