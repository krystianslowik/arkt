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

  /// The window closed: no observation, no sheets, nothing expanded next time.
  func stopObservingInstalledExtensions() {
    installedExtensionsObservation?.cancel()
    installedExtensionsObservation = nil
    closeExtensionSheets()
    expandedExtensionID = nil
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

  /// Rebuilds the pane, when it is built and what it shows changed, keeping the keyboard focus on the same control.
  /// The remove sheet closes when its extension went away; details close with their extension.
  func refreshExtensionsPane() {
    let state = currentExtensionsPaneState()
    if expandedExtensionID != state.expanded { expandedExtensionID = state.expanded }
    if let sheet = extensionRemoveSheet, !state.list.contains(where: { $0.id == sheet.extensionID }) {
      extensionRemoveSheet = nil
      sheet.dismiss()
    }
    guard let pane = builtPane(.extensions), state != shownExtensionsState else { return }
    let focused = (window?.firstResponder as? NSView)?.accessibilityIdentifier()
    pane.setBlocks(extensionsBlocks())
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

  // MARK: Blocks

  func extensionsBlocks() -> [SettingsBlockView] {
    let state = currentExtensionsPaneState()
    shownExtensionsState = state
    shownExtensionIDs = state.list.map(\.id)
    extensionTargets = []
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
      rows.append(extensionRow(info, pinned: state.pinned.contains(info.id), expanded: state.expanded == info.id))
      if state.expanded == info.id { rows.append(extensionDetails(info, hasCommands: state.withCommands.contains(info.id))) }
    }
    return [
      SettingsSectionView(title: "Installed", body: SettingsGroupView(rows), note: Self.extensionsNote),
      SettingsSectionView(title: nil, body: SettingsGroupView(more)),
    ]
  }

  /// "Version 8.11. <description>", "Version 0.9. Turned off." or, for a policy extension, "Version 3.2. Installed by
  /// your organization."; one line, cut at the end.
  static func extensionCaption(_ info: InstalledExtensionInfo) -> String {
    let version = info.version.isEmpty ? "" : "Version \(info.version)."
    let detail: String
    if !info.isEnabled {
      detail = "Turned off."
    } else if info.origin == .policy {
      detail = "Installed by your organization."
    } else {
      detail = info.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return [version, detail].filter { !$0.isEmpty }.joined(separator: " ")
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

  private func extensionRow(_ info: InstalledExtensionInfo, pinned: Bool, expanded: Bool) -> SettingsRowView {
    let id = info.id
    let pin = ExtensionsPinToggle()
    pin.isOn = pinned
    pin.setArchiveAccessibilityLabel("Pin \(info.name)")
    pin.toolTip = pinned ? "Unpin" : "Pin"
    let pinTarget = target { [weak self] in self?.setExtensionPinned(id, pinned: !pinned) }
    pin.target = pinTarget
    pin.action = #selector(SettingsActionTarget.fire(_:))
    identify(pin, .extensions, "pin.\(id)")
    let enabled = toggle(.extensions, "enabled.\(id)", on: info.isEnabled) { [weak self] on in
      self?.setExtension(id, enabled: on)
    }
    let row = SettingsRowView(label: info.name, caption: Self.extensionCaption(info),
                              leading: SettingsExtensionIcon(png: info.iconPNG), trailing: [pin, enabled],
                              singleLine: true)
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
      showExtensionAlert(Self.needsPermissionContent(name))
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
      askToTurnOffDeveloperMode(unpacked: unpacked.count)
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

  static func developerModeOffContent(unpacked count: Int) -> DialogContent {
    let which = count == 1 ? "The unpacked extension" : "The \(count) unpacked extensions"
    return DialogContent(title: "Turn off developer mode?",
                         paragraphs: [.init("\(which) you loaded from a folder will be turned off.")],
                         primaryTitle: "Turn Off", cancelTitle: "Cancel", defaultButton: .cancel,
                         primaryHelp: "Turns off developer mode and the unpacked extensions",
                         width: resetSettingsWidth)
  }

  /// The confirmation for developer mode off; the switch stays on until Turn Off.
  private func askToTurnOffDeveloperMode(unpacked count: Int) {
    extensionsDeveloperSwitch?.setOn(true, animated: true)
    guard extensionAlert == nil, let window, window.attachedSheet == nil else { return }
    let sheet = DialogSheet(content: Self.developerModeOffContent(unpacked: count))
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
      self.pendingUnpackedLoad = Task { [weak self] in
        let result = await engine.loadUnpackedExtension(at: folder)
        self?.finishUnpackedLoad(result)
      }
    }
  }

  private func finishUnpackedLoad(_ result: UnpackedExtensionResult) {
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

  /// Why a switch did not turn an extension on: its update asks for more permissions.
  static func needsPermissionContent(_ name: String) -> DialogContent {
    let title = name.isEmpty ? "This extension needs new permissions" : "\u{201C}\(name)\u{201D} needs new permissions"
    return DialogContent(title: title,
                         paragraphs: [.init("Its latest update asks for more access, so it stays off until you "
                           + "review the new permissions on the extensions page (chrome://extensions).")],
                         primaryTitle: "OK", width: resetSettingsWidth, titleMaxLines: 2)
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
