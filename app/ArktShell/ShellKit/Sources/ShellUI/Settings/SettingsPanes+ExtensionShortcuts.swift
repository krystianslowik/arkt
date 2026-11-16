import AppKit
import Carbon.HIToolbox
import EngineAPI

/// One extension command's controls in Settings > Shortcuts (#597), kept across the pane's rebuilds: the recorder
/// (the shortcut as keycaps; "Press new shortcut" while it listens), the Set Shortcut pill of an unset command, and
/// the scope pop-up.
@MainActor
final class ExtensionShortcutControls {
  let recorder: ShortcutRecorderButton
  let setShortcut: ArchivePillButton
  let scope: SettingsPopUpButton
  weak var row: SettingsRowView?

  init(recorder: ShortcutRecorderButton, setShortcut: ArchivePillButton, scope: SettingsPopUpButton) {
    self.recorder = recorder; self.setShortcut = setShortcut; self.scope = scope
  }
}

/// Settings > Shortcuts > Pinned extensions and Extension Shortcuts (#597; design/extensions `shortcuts`,
/// `shortcuts-conflict`, `shortcuts-record`). Shown while the engine runs extensions. The recorder is the app
/// recorder's (#119): the same window key route, key rules and conflict notice. While either recorder listens, the
/// engine's extension shortcuts are suspended, so a key an extension holds reaches the recorder (#954).
extension SettingsWindowController {
  static let inArkt = "In Arkt"
  static let allApps = "All Apps"
  static let pressNewShortcut = "Press new shortcut"
  static let cycleTitle = "Cycle through pinned extensions"

  // MARK: Model and engine

  /// Creates the model on first use and follows the engine's command changes while the window is open.
  func observeExtensionShortcuts() {
    guard let model = ensureExtensionShortcuts(), extensionCommandsObservation == nil else { return }
    extensionCommandsObservation = model.engine.observeExtensions { [weak self] event in
      guard event == .commandsChanged else { return }
      self?.extensionCommandsDidChange()
    }
  }

  @discardableResult
  private func ensureExtensionShortcuts() -> ExtensionShortcutsModel? {
    if let model = extensionShortcuts { return model }
    guard let engine = services.extensions else { return nil }
    let editor = services.shortcutEditor
    let model = ExtensionShortcutsModel(engine: engine, editor: editor) { [weak self] binding in
      guard let self else { return [] }
      return ShortcutCatalog.keptOwners(of: binding, in: self.services.shortcutsMenu(),
                                        editable: Set(editor?.catalog.map(\.id) ?? []))
    }
    if let editor { model.connect(editor) }
    extensionShortcuts = model
    return model
  }

  /// A command set, cleared or removed elsewhere. The rows wait while a recorder listens, unless its command went
  /// away.
  private func extensionCommandsDidChange() {
    guard let model = extensionShortcuts else { return }
    if let id = model.recordingCommand {
      guard model.command(id) == nil else { return }
      cancelShortcutRecording()
    }
    extensionShortcutControls = extensionShortcutControls.filter { model.command($0.key) != nil }
    if services.shortcutEditor?.recordingAction == nil { applyShortcutSearch() }
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

  /// The two sections, filtered by the Shortcuts search: the Cmd-E row, then one group per extension.
  func extensionShortcutBlocks() -> [SettingsBlockView] {
    guard let model = ensureExtensionShortcuts() else { return [] }
    let query = shortcutsSearch.stringValue
    var blocks: [SettingsBlockView] = []
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
      blocks.append(SettingsSectionView(title: "Pinned extensions", body: SettingsGroupView([row])))
    }
    let groups = ExtensionShortcutsModel.filter(model.groups, query: query)
    guard !groups.isEmpty else { return blocks }
    var rows: [SettingsBlockView] = []
    for group in groups {
      let header = SettingsRowView(label: group.name, leading: ExtensionLetterTile(name: group.name),
                                   hoverable: false)
      header.setAccessibilityIdentifier("settings.shortcuts.extension.group.\(group.extensionID)")
      rows.append(header)
      for command in group.commands { rows.append(extensionRow(command, model: model)) }
    }
    blocks.append(SettingsSectionView(title: "Extension Shortcuts", body: SettingsGroupView(rows)))
    return blocks
  }

  /// The titles of the extension command rows shown now.
  public var visibleExtensionShortcutTitles: [String] {
    guard let model = extensionShortcuts else { return [] }
    return ExtensionShortcutsModel.filter(model.groups, query: shortcutsSearch.stringValue)
      .flatMap(\.commands).map(ExtensionShortcutsModel.title(of:))
  }

  private func extensionRow(_ command: ExtensionCommand, model: ExtensionShortcutsModel) -> SettingsRowView {
    let controls = extensionControls(for: command)
    let row = SettingsRowView(label: ExtensionShortcutsModel.title(of: command),
                              caption: extensionCaption(command, model: model), trailing: [])
    controls.row = row
    refreshExtensionControls(command.id)
    return row
  }

  /// "Not set" for an unset command; for a shortcut Arkt keeps, what holds it (#922 review: the engine gives the key
  /// to the main menu, so the extension's shortcut does not run).
  private func extensionCaption(_ command: ExtensionCommand, model: ExtensionShortcutsModel) -> String? {
    guard let shortcut = command.shortcut else { return "Not set" }
    let arkt = model.owners(of: shortcut, excluding: command.id).first {
      if case .extensionCommand = $0 { false } else { true }
    }
    return arkt.map { "Arkt uses this shortcut for \u{201C}\($0.title)\u{201D}, so it does not run." }
  }

  private func extensionControls(for command: ExtensionCommand) -> ExtensionShortcutControls {
    if let existing = extensionShortcutControls[command.id] { return existing }
    let id = command.id
    let key = "\(id.extensionID).\(id.name)"
    let title = ExtensionShortcutsModel.title(of: command)
    let recorder = ShortcutRecorderButton(title: "", target: nil, action: nil)
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
    guard let model = extensionShortcuts, let controls = extensionShortcutControls[id],
          let command = model.command(id) else { return }
    let recording = model.recordingCommand == id
    if recording {
      controls.recorder.title = Self.pressNewShortcut
      controls.recorder.setAccessibilityValue("Recording, press the new shortcut")
    } else if let shortcut = command.shortcut {
      let shown = ExtensionShortcutsModel.display(shortcut)
      controls.recorder.title = shown.keys.joined()
      controls.recorder.setAccessibilityValue(shown.spoken)
    }
    controls.scope.show(model.scope(of: id) == .global ? Self.allApps : Self.inArkt)
    let first: NSView = recording || command.shortcut != nil ? controls.recorder : controls.setShortcut
    if let row = controls.row, row.trailing.first !== first { row.setTrailing([first, controls.scope]) }
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

  /// Stops the extension recorder and dismisses what it showed; part of `cancelShortcutRecording`.
  func cancelExtensionShortcutRecording() {
    guard let model = extensionShortcuts, let id = model.recordingCommand else { return }
    model.cancel()
    refreshExtensionControls(id)
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

  private func showExtensionShortcutConflict() {
    guard let model = extensionShortcuts, case .conflict(let id, let shortcut, let owners) = model.phase,
          let owner = owners.first else { return }
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    let keys = ExtensionShortcutsModel.display(shortcut).keys.joined()
    let explanation = model.canUse
      ? "Using it here removes it there."
      : "This command cannot be changed here; keep the existing shortcut and try another."
    let system = ExtensionShortcutsModel.bindings(for: shortcut).contains(where: services.isSystemShortcut)
      ? " \(Self.systemShortcutWarning)" : ""
    let text = "\(keys) is already used by \u{201C}\(owner.title)\u{201D}. \(explanation)\(system)"
    presentShortcutConflict(message: text, useTitle: "Use \(keys)", canUse: model.canUse,
                            keep: { [weak self] in
                              guard let self else { return }
                              model.keepExisting()
                              self.finishExtensionShortcutRecording(id)
                            },
                            use: { [weak self] in
                              guard let self else { return }
                              model.useRecorded()
                              if case .conflict = model.phase {
                                self.showExtensionShortcutConflict()
                              } else {
                                self.finishExtensionShortcutRecording(id)
                              }
                            })
    announce(text)
  }

  /// The recorder stopped: the notice goes, the rows show the engine's commands, and the engine's answer (a refused
  /// shortcut, a removed extension) or the system shortcut warning shows.
  private func finishExtensionShortcutRecording(_ id: ExtensionCommandID) {
    dismissShortcutConflict()
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    refreshExtensionControls(id)
    syncExtensionShortcutSuspension()
    applyShortcutSearch()
    if let notice = extensionShortcuts?.notice {
      showExtensionNotice(notice)
    } else if let shortcut = extensionShortcuts?.command(id)?.shortcut,
              ExtensionShortcutsModel.bindings(for: shortcut).contains(where: services.isSystemShortcut) {
      showShortcutWarning()
    }
  }

  private func chooseExtensionScope(_ title: String, for id: ExtensionCommandID) {
    guard let model = extensionShortcuts else { return }
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    model.setScope(title == Self.allApps ? .global : .inApp, for: id)
    refreshExtensionControls(id)
    if let notice = model.notice { showExtensionNotice(notice) }
  }

  private func showExtensionNotice(_ notice: ExtensionShortcutsModel.Notice) {
    shortcutWarningView?.removeFromSuperview()
    guard let root = window?.contentView else { return }
    let text = switch notice {
    case .engine(.globalShortcutTaken):
      "macOS or another app already uses this shortcut, so it can\u{2019}t work in All Apps."
    case .engine(.notAllowed), .engine(.noKeyCode):
      "This shortcut can\u{2019}t be used for this command here."
    case .commandGone: "This extension is no longer installed."
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
