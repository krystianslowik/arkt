import AppKit
import Carbon.HIToolbox
import EngineAPI

/// One extension command's controls in Settings > Shortcuts (#597), kept across the pane's rebuilds: the recorder
/// (the shortcut as keycaps; "Press new shortcut" while it listens), the Set Shortcut pill of an unset command, and
/// the scope pop-up.
@MainActor
final class ExtensionShortcutControls {
  let recorder: ExtensionShortcutRecorder
  let setShortcut: ArchivePillButton
  let scope: SettingsPopUpButton
  weak var row: SettingsRowView?

  init(recorder: ExtensionShortcutRecorder, setShortcut: ArchivePillButton, scope: SettingsPopUpButton) {
    self.recorder = recorder; self.setShortcut = setShortcut; self.scope = scope
  }
}

/// An extension command's recorder: the shortcut as separate keycaps, as the design and the Cmd-E row draw them; a
/// click records, and while it records it is a field that reads "Press new shortcut".
@MainActor
final class ExtensionShortcutRecorder: ShortcutRecorderButton {
  private var keycaps: SettingsKeycapsView?

  /// Shows `keys` as keycaps, or the recording field when nil.
  func show(keys: [String]?, spoken: String) {
    keycaps?.removeFromSuperview()
    keycaps = nil
    if let keys {
      let caps = SettingsKeycapsView(keys: keys, spoken: spoken)
      caps.setAccessibilityElement(false)
      addSubview(caps)
      keycaps = caps
      title = ""
      isBordered = false
    } else {
      title = SettingsWindowController.pressNewShortcut
      isBordered = true
      bezelStyle = .rounded
    }
    invalidateIntrinsicContentSize()
    needsLayout = true
  }

  override var intrinsicContentSize: NSSize { keycaps?.intrinsicContentSize ?? super.intrinsicContentSize }

  override func layout() {
    super.layout()
    keycaps?.frame = bounds
  }

  /// A click on a keycap is a click on the recorder.
  override func hitTest(_ point: NSPoint) -> NSView? {
    super.hitTest(point) == nil ? nil : self
  }
}

/// The conflict notice of the extension recorder, as the row under the command (design/extensions
/// `shortcuts-conflict`): the alert symbol, "X is already used by "Y".", why, Keep Existing (the one mustard pill, the
/// default, #590) and a quiet Use.
@MainActor
final class ExtensionConflictRowView: SettingsBlockView {
  private let icon = NSImageView()
  private let message: NSTextField
  private let detail: NSTextField
  let keep: ArchivePillButton
  let use: ArchiveLinkButton

  init(message text: String, detail detailText: String, keep: ArchivePillButton, use: ArchiveLinkButton) {
    message = settingsLabel(text, size: 13)
    detail = settingsLabel(detailText, size: 12)
    self.keep = keep
    self.use = use
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = SettingsMetrics.rowRadius
    layer?.cornerCurve = .continuous
    icon.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
    icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
    message.setAccessibilityIdentifier("settings.shortcuts.conflict.message")
    message.setAccessibilityLabel(text)
    detail.setAccessibilityIdentifier("settings.shortcuts.conflict.detail")
    detail.setAccessibilityLabel(detailText)
    setAccessibilityIdentifier("settings.shortcuts.extension.conflict")
    [icon, message, detail, keep, use].forEach(addSubview)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  private static let top: CGFloat = 12
  private static let textX: CGFloat = SettingsMetrics.rowPaddingLeading + 26

  private func textWidth(_ width: CGFloat) -> CGFloat { max(40, width - Self.textX - SettingsMetrics.rowPaddingTrailing) }

  override func fittingHeight(width: CGFloat) -> CGFloat {
    let text = textWidth(width)
    return Self.top + settingsTextHeight(message, width: text) + 2 + settingsTextHeight(detail, width: text) + 10
      + keep.intrinsicContentSize.height + 12
  }

  override func layout() {
    super.layout()
    let width = textWidth(bounds.width)
    icon.frame = NSRect(x: SettingsMetrics.rowPaddingLeading, y: Self.top, width: 18, height: 18)
    var y = Self.top
    let messageHeight = settingsTextHeight(message, width: width)
    message.frame = NSRect(x: Self.textX, y: y, width: width, height: messageHeight)
    y += messageHeight + 2
    let detailHeight = settingsTextHeight(detail, width: width)
    detail.frame = NSRect(x: Self.textX, y: y, width: width, height: detailHeight)
    y += detailHeight + 10
    let keepSize = keep.intrinsicContentSize
    keep.frame = NSRect(x: Self.textX, y: y, width: keepSize.width, height: keepSize.height)
    let useSize = use.intrinsicContentSize
    use.frame = NSRect(x: keep.frame.maxX + 16, y: y + ((keepSize.height - useSize.height) / 2).rounded(),
                       width: useSize.width, height: useSize.height)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  private func restyle() {
    let flavor = archiveFlavor
    layer?.backgroundColor = ShellTokens.sidebarItemBackground.resolve(flavor).cgColor
    icon.contentTintColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    message.textColor = ShellTokens.primaryText.resolve(flavor).nsColor()
    detail.textColor = ShellTokens.secondaryText.resolve(flavor).nsColor()
  }
}

/// Settings > Shortcuts > Extension Shortcuts (#597; design/extensions `shortcuts`, `shortcuts-conflict`,
/// `shortcuts-record`): the Cmd-E row first, then one group per extension. Shown while the engine runs extensions.
/// The recorder is the app recorder's (#119): the same window key route and key rules. While either recorder
/// listens, the engine's extension shortcuts are suspended, so a key an extension holds reaches the recorder (#954).
extension SettingsWindowController {
  static let inArkt = "In Arkt"
  static let allApps = "All Apps"
  static let pressNewShortcut = "Press new shortcut"
  static let cycleTitle = "Cycle through pinned extensions"

  // MARK: Model and engine

  /// Creates the model on first use and follows the engine's command changes while the window is open. A pane built
  /// before the window closed shows what the engine has now.
  func observeExtensionShortcuts() {
    guard let model = ensureExtensionShortcuts(), extensionCommandsObservation == nil else { return }
    extensionCommandsObservation = model.engine.observeExtensions { [weak self] event in
      guard event == .commandsChanged else { return }
      self?.extensionCommandsDidChange()
    }
    extensionCommandsDidChange()
  }

  @discardableResult
  private func ensureExtensionShortcuts() -> ExtensionShortcutsModel? {
    if let model = extensionShortcuts { return model }
    guard let engine = services.extensions else { return nil }
    let editor = services.shortcutEditor
    let model = ExtensionShortcutsModel(engine: engine, editor: editor) { [weak self] in
      guard let self else { return [:] }
      return ShortcutCatalog.keptOwnerIndex(in: self.services.shortcutsMenu(),
                                            editable: Set(editor?.catalog.map(\.id) ?? []))
    }
    if let editor { model.connect(editor) }
    extensionShortcuts = model
    return model
  }

  /// A command set, cleared or removed elsewhere. While a recorder listens the rows wait (unless its command went
  /// away), and the change shows when it stops (`cancelShortcutRecording`, `finishExtensionShortcutRecording`).
  private func extensionCommandsDidChange() {
    guard let model = extensionShortcuts else { return }
    if let id = model.recordingCommand {
      guard model.command(id) == nil else {
        extensionRowsNeedRefresh = true
        return
      }
      cancelShortcutRecording()
    }
    refreshExtensionRows()
  }

  /// Rebuilds the rows from the engine's commands now, unless the app recorder listens (then it waits too).
  func refreshExtensionRows() {
    guard let model = extensionShortcuts else { return }
    guard services.shortcutEditor?.recordingAction == nil else {
      extensionRowsNeedRefresh = true
      return
    }
    extensionRowsNeedRefresh = false
    let present = Set(model.engine.extensionCommands.map(\.id))
    extensionShortcutControls = extensionShortcutControls.filter { present.contains($0.key) }
    applyShortcutSearch()
  }

  /// Suspends the engine's extension shortcuts exactly while a recorder listens. Derived from both recorders' state
  /// and sent only on a change.
  func syncExtensionShortcutSuspension() {
    let listening = services.shortcutEditor?.recordingAction != nil || extensionShortcuts?.recordingCommand != nil
    guard listening != isExtensionShortcutHandlingSuspended, let engine = services.extensions else { return }
    isExtensionShortcutHandlingSuspended = listening
    engine.setExtensionShortcutHandlingSuspended(listening)
  }

  // MARK: Blocks

  /// The Extension Shortcuts section, filtered by the Shortcuts search: the Cmd-E row, then one group per extension,
  /// and the conflict notice under the command it is about. The engine's commands and the owners are read once.
  func extensionShortcutBlocks() -> [SettingsBlockView] {
    guard let model = ensureExtensionShortcuts() else { return [] }
    let query = shortcutsSearch.stringValue
    let index = model.ownerIndex()
    var rows: [SettingsBlockView] = []
    let cycle = ShortcutCatalog.Entry(title: Self.cycleTitle, keys: ["\u{2318}", "E"], spoken: "Command E")
    if !ShortcutCatalog.filter([ShortcutCatalog.Section(title: "", entries: [cycle])], query: query).isEmpty {
      let keys = SettingsKeycapsView(keys: cycle.keys, spoken: cycle.spoken)
      let row = SettingsRowView(label: Self.cycleTitle,
                                caption: "Hold Command and tap E. Opens each pinned extension in turn.",
                                trailing: [keys])
      row.setAccessibilityElement(true)
      row.setAccessibilityRole(.staticText)
      row.setAccessibilityLabel("\(Self.cycleTitle), \(cycle.spoken)")
      row.setAccessibilityIdentifier("settings.shortcuts.extension.cycle")
      rows.append(row)
    }
    for group in ExtensionShortcutsModel.filter(ExtensionShortcutsModel.groups(of: index.commands), query: query) {
      let header = SettingsRowView(label: group.name, leading: ExtensionLetterTile(name: group.name),
                                   hoverable: false)
      header.setAccessibilityIdentifier("settings.shortcuts.extension.group.\(group.extensionID)")
      rows.append(header)
      for command in group.commands {
        rows.append(extensionRow(command, model: model, index: index))
        if case .conflict(let id, let shortcut, let owners) = model.phase, id == command.id {
          rows.append(extensionConflictRow(shortcut: shortcut, owners: owners, model: model))
        }
      }
    }
    guard !rows.isEmpty else { return [] }
    return [SettingsSectionView(title: "Extension Shortcuts", body: SettingsGroupView(rows))]
  }

  /// The titles of the extension command rows shown now.
  public var visibleExtensionShortcutTitles: [String] {
    guard let model = extensionShortcuts else { return [] }
    return ExtensionShortcutsModel.filter(model.groups, query: shortcutsSearch.stringValue)
      .flatMap(\.commands).map(ExtensionShortcutsModel.title(of:))
  }

  private func extensionRow(_ command: ExtensionCommand, model: ExtensionShortcutsModel,
                            index: ExtensionShortcutsModel.OwnerIndex) -> SettingsRowView {
    let controls = extensionControls(for: command)
    let row = SettingsRowView(label: ExtensionShortcutsModel.title(of: command),
                              caption: extensionCaption(command, model: model, index: index), trailing: [])
    controls.row = row
    refreshExtensionControls(command, model: model)
    return row
  }

  /// The description line ("The main action"), "Not set" for an unset command, and for a shortcut Arkt keeps what
  /// holds it (#922 review: the engine gives the key to the main menu, so the extension's shortcut does not run).
  private func extensionCaption(_ command: ExtensionCommand, model: ExtensionShortcutsModel,
                                index: ExtensionShortcutsModel.OwnerIndex) -> String? {
    var lines = [ExtensionShortcutsModel.detail(of: command)].compactMap { $0 }
    if let shortcut = command.shortcut {
      let arkt = model.owners(of: shortcut, excluding: command.id, in: index).first {
        if case .extensionCommand = $0 { false } else { true }
      }
      if let arkt { lines.append("Arkt uses this shortcut for \u{201C}\(arkt.title)\u{201D}, so it does not run.") }
    } else {
      lines.append("Not set")
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  private func extensionControls(for command: ExtensionCommand) -> ExtensionShortcutControls {
    if let existing = extensionShortcutControls[command.id] { return existing }
    let id = command.id
    let key = "\(id.extensionID).\(id.name)"
    let title = ExtensionShortcutsModel.title(of: command)
    let recorder = ExtensionShortcutRecorder(title: "", target: nil, action: nil)
    recorder.bezelStyle = .rounded
    recorder.setAccessibilityIdentifierWithCell("settings.shortcuts.extension.record.\(key)")
    recorder.setAccessibilityLabel("Shortcut for \(title)")
    let begin = SettingsActionTarget { [weak self] in self?.beginExtensionShortcutRecording(id) }
    actionTargets.append(begin)
    recorder.target = begin
    recorder.action = #selector(SettingsActionTarget.fire(_:))
    recorder.onResign = { [weak self] in
      guard let self, let model = self.extensionShortcuts, model.phase == .listening(id) else { return }
      self.cancelShortcutRecording()
    }
    let setShortcut = pill(.shortcuts, "extension.set.\(key)", "Set Shortcut") { [weak self] in
      self?.beginExtensionShortcutRecording(id)
    }
    setShortcut.setArchiveAccessibilityLabel("Set Shortcut for \(title)")
    let scope = popUp(.shortcuts, "extension.scope.\(key)", [Self.inArkt, Self.allApps], Self.inArkt)
    scope.setAccessibilityLabel("Where the shortcut for \(title) works")
    scope.toolTip = "In Arkt: only while Arkt is the active app. All Apps: also when another app is in front."
    scope.onChange = { [weak self] chosen in self?.chooseExtensionScope(chosen, for: id) }
    let controls = ExtensionShortcutControls(recorder: recorder, setShortcut: setShortcut, scope: scope)
    extensionShortcutControls[id] = controls
    return controls
  }

  /// Shows the command's state in its controls without rebuilding the pane.
  private func refreshExtensionControls(_ id: ExtensionCommandID) {
    guard let model = extensionShortcuts, let command = model.command(id) else { return }
    refreshExtensionControls(command, model: model)
  }

  private func refreshExtensionControls(_ command: ExtensionCommand, model: ExtensionShortcutsModel) {
    guard let controls = extensionShortcutControls[command.id] else { return }
    let recording = model.recordingCommand == command.id
    if recording {
      controls.recorder.show(keys: nil, spoken: "")
      controls.recorder.setAccessibilityValue("Recording, press the new shortcut")
    } else if let shortcut = command.shortcut {
      let shown = ExtensionShortcutsModel.display(shortcut)
      controls.recorder.show(keys: shown.keys, spoken: shown.spoken)
      controls.recorder.setAccessibilityValue(shown.spoken)
    }
    controls.scope.show(model.scope(of: command) == .global ? Self.allApps : Self.inArkt)
    let first: NSView = recording || command.shortcut != nil ? controls.recorder : controls.setShortcut
    if let row = controls.row, row.trailing.first !== first { row.setTrailing([first, controls.scope]) }
    controls.row?.needsLayout = true                   // the recorder's width follows its state
  }

  /// The conflict notice under the command: Keep Existing (primary pill) and a quiet Use, unavailable while a key
  /// Arkt keeps owns the shortcut.
  private func extensionConflictRow(shortcut: ExtensionShortcut, owners: [ExtensionShortcutOwner],
                                    model: ExtensionShortcutsModel) -> ExtensionConflictRowView {
    let keys = ExtensionShortcutsModel.display(shortcut).keys.joined()
    let title = owners.first?.title ?? ""
    var detail = model.canUse
      ? "Using it here removes it there."
      : "This command cannot be changed here; keep the existing shortcut and try another."
    if model.bindings(for: shortcut).contains(where: services.isSystemShortcut) {
      detail += " \(Self.systemShortcutWarning)"
    }
    let keep = pill(.shortcuts, "conflict.keep", "Keep Existing", primary: true) { [weak self] in
      guard let self, let model = self.extensionShortcuts, let id = model.recordingCommand else { return }
      model.keepExisting()
      self.finishExtensionShortcutRecording(id)
    }
    let use = ArchiveLinkButton(style: .secondary, title: "Use \(keys)", fontSize: 13)
    use.setAccessibilityIdentifierWithCell("settings.shortcuts.conflict.use")
    let useTarget = SettingsActionTarget { [weak self] in
      guard let self, let model = self.extensionShortcuts, let id = model.recordingCommand else { return }
      model.useRecorded()
      if case .conflict = model.phase {
        self.showExtensionShortcutConflict()
      } else {
        self.finishExtensionShortcutRecording(id)
      }
    }
    actionTargets.append(useTarget)
    use.target = useTarget
    use.action = #selector(SettingsActionTarget.fire(_:))
    use.isEnabled = model.canUse
    if !model.canUse { use.toolTip = "This shortcut belongs to a command that cannot be changed here." }
    let row = ExtensionConflictRowView(message: "\(keys) is already used by \u{201C}\(title)\u{201D}.",
                                       detail: detail, keep: keep, use: use)
    extensionConflictKeep = keep
    return row
  }

  // MARK: Recording

  func beginExtensionShortcutRecording(_ id: ExtensionCommandID) {
    guard let model = extensionShortcuts else { return }
    cancelShortcutRecording()
    model.begin(id)
    guard model.recordingCommand == id else { return }
    refreshExtensionControls(id)
    if let recorder = extensionShortcutControls[id]?.recorder { window?.makeFirstResponder(recorder) }
    syncExtensionShortcutSuspension()
    announce("Recording, press the new shortcut")
  }

  /// Stops the extension recorder and dismisses what it showed; part of `cancelShortcutRecording`, which also shows
  /// the command changes that waited for it.
  func cancelExtensionShortcutRecording() {
    guard let model = extensionShortcuts, let id = model.recordingCommand else { return }
    let hadNotice = model.phase != .listening(id)
    model.cancel()
    refreshExtensionControls(id)
    if hadNotice { extensionRowsNeedRefresh = true }
  }

  /// A key while the extension recorder listens or its notice is open (`SettingsWindow.onShortcutKey`).
  func handleExtensionShortcutKey(_ event: NSEvent) -> Bool {
    guard let model = extensionShortcuts, let id = model.recordingCommand else { return false }
    guard selectedPane == .shortcuts else {
      cancelShortcutRecording()
      return false
    }
    if case .conflict = model.phase {
      if [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) {
        model.keepExisting()
        finishExtensionShortcutRecording(id)
        return true
      }
      // As the app notice: other shortcuts reach neither the menu nor the panes; Tab and Space move and press.
      return !event.modifierFlags.intersection([.command, .control]).isEmpty
    }
    guard let recorder = extensionShortcutControls[id]?.recorder, window?.firstResponder === recorder else {
      cancelShortcutRecording()
      return false
    }
    if Int(event.keyCode) == kVK_Tab && event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
      cancelShortcutRecording()
      if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) } else { window?.selectNextKeyView(nil) }
      return true
    }
    model.record(event: event)
    switch model.phase {
    case .conflict:
      showExtensionShortcutConflict()
    case .listening:
      showShortcutRejection(model.rejection, for: event)
    case .idle:
      finishExtensionShortcutRecording(id)
    }
    return true
  }

  /// Shows the notice as the row under the command and moves focus to Keep Existing.
  private func showExtensionShortcutConflict() {
    guard let model = extensionShortcuts, case .conflict(_, let shortcut, let owners) = model.phase,
          let owner = owners.first else { return }
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    applyShortcutSearch()
    if let keep = extensionConflictKeep { window?.makeFirstResponder(keep) }
    let keys = ExtensionShortcutsModel.display(shortcut).keys.joined()
    announce("\(keys) is already used by \u{201C}\(owner.title)\u{201D}.")
  }

  /// The recorder stopped: the notice goes, the rows show the engine's commands, and the engine's answer (a refused
  /// shortcut, a removed extension) or the system shortcut warning shows.
  private func finishExtensionShortcutRecording(_ id: ExtensionCommandID) {
    dismissShortcutConflict()
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    extensionConflictKeep = nil
    syncExtensionShortcutSuspension()
    refreshExtensionRows()
    guard let model = extensionShortcuts else { return }
    if let notice = model.notice {
      showExtensionNotice(notice)
    } else if let shortcut = model.command(id)?.shortcut,
              model.bindings(for: shortcut).contains(where: services.isSystemShortcut) {
      showShortcutWarning()
    }
  }

  /// The row's scope pop-up. It ends a recording in progress first (the pop-up takes no focus without Full
  /// Keyboard Access, so the recorder's resign hook does not run), so the suspension lifts.
  private func chooseExtensionScope(_ title: String, for id: ExtensionCommandID) {
    guard let model = extensionShortcuts else { return }
    cancelShortcutRecording()
    model.setScope(title == Self.allApps ? .global : .inApp, for: id)
    syncExtensionShortcutSuspension()
    refreshExtensionControls(id)
    if let notice = model.notice { showExtensionNotice(notice) }
  }

  private func showExtensionNotice(_ notice: ExtensionShortcutsModel.Notice) {
    shortcutWarningView?.removeFromSuperview()
    guard let root = window?.contentView else { return }
    let text = switch notice {
    case .engine(.globalShortcutTaken): "This shortcut couldn\u{2019}t be set to work in All Apps."
    case .engine(.notAllowed), .engine(.noKeyCode):
      "This shortcut can\u{2019}t be used for this command here."
    case .commandGone: "This extension is no longer installed."
    case .taken(let owner): "\u{201C}\(owner)\u{201D} already uses this shortcut."
    }
    let label = settingsLabel(text, size: 12)
    label.setAccessibilityIdentifier("settings.shortcuts.extension.notice")
    label.setAccessibilityLabel(text)
    label.frame = NSRect(x: 40, y: 85, width: root.bounds.width - 80, height: 28)
    root.addSubview(label)
    shortcutWarningView = label
    announce(text)
  }

  private func announce(_ text: String) {
    guard let window else { return }
    NSAccessibility.post(element: window, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
  }
}

/// The small tile before an extension's name: its initial on a neutral plate (no icon comes with the commands).
@MainActor
final class ExtensionLetterTile: NSView {
  private let text = CATextLayer()

  init(name: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = SettingsMetrics.keycapRadius
    layer?.cornerCurve = .continuous
    text.string = name.first.map { String($0).uppercased() } ?? ""
    text.alignmentMode = .center
    text.font = ShellType.sectionHeader.font
    text.fontSize = ShellType.sectionHeader.size
    layer?.addSublayer(text)
    setAccessibilityElement(false)
    restyle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layout() {
    super.layout()
    text.frame = NSRect(x: 0, y: (bounds.height - 14) / 2, width: bounds.width, height: 14)
    text.contentsScale = window?.backingScaleFactor ?? 2
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyle()
  }

  private func restyle() {
    let flavor = archiveFlavor
    layer?.backgroundColor = ShellTokens.primaryText.resolve(flavor).cgColor
    text.foregroundColor = ShellTokens.commandBarSurfaceOpaque.resolve(flavor).cgColor
  }
}
