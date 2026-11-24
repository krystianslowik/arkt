import AppKit
import Carbon.HIToolbox

/// The recorder field of the app and the extension shortcut rows (#119, #597).
@MainActor
class ShortcutRecorderButton: NSButton {
  override var acceptsFirstResponder: Bool { true }
  /// Focus left the recorder (a click on another control, the search field); the owner stops listening.
  var onResign: (@MainActor () -> Void)?

  override func resignFirstResponder() -> Bool {
    let resigned = super.resignFirstResponder()
    if resigned { onResign?() }
    return resigned
  }
}

extension SettingsWindowController {
  /// BH-199's system-shortcut warning.
  static let systemShortcutWarning = "System shortcuts may take priority over this shortcut."

  func observeShortcutEditor() {
    guard shortcutObserver == nil, let editor = services.shortcutEditor else { return }
    shortcutObserver = editor.observe { [weak self] in self?.refreshShortcutPresentation() }
    refreshShortcutControls()
  }

  func shortcutRecorder(for id: ShortcutActionID, title: String) -> NSButton {
    if let existing = shortcutRecorders[id] { return existing }
    let button = ShortcutRecorderButton(title: "", target: nil, action: nil)
    button.bezelStyle = .rounded
    button.setAccessibilityIdentifierWithCell("settings.shortcuts.record.\(id.rawValue)")
    button.setAccessibilityLabel("Record shortcut for \(title)")
    button.onResign = { [weak self] in
      guard let self, let editor = self.services.shortcutEditor, editor.recordingAction == id,
            !editor.hasConflict else { return }
      self.cancelShortcutRecording()
    }
    let target = SettingsActionTarget { [weak self, weak button] in
      guard let self, let button, let editor = self.services.shortcutEditor else { return }
      self.cancelShortcutRecording()
      self.shortcutWarningView?.removeFromSuperview()
      self.shortcutWarningView = nil
      editor.beginRecording(id)
      self.window?.makeFirstResponder(button)
      self.refreshShortcutControls()
    }
    actionTargets.append(target)
    button.target = target
    button.action = #selector(SettingsActionTarget.fire(_:))
    let menu = NSMenu()
    let resetTarget = SettingsActionTarget { [weak self] in
      guard let self, let editor = self.services.shortcutEditor else { return }
      self.cancelShortcutRecording()
      editor.reset(id)
      self.refreshShortcutPresentation()
      if editor.hasConflict { self.showShortcutConflict() }
    }
    actionTargets.append(resetTarget)
    let reset = NSMenuItem(title: "Reset Shortcut to Default", action: #selector(SettingsActionTarget.fire(_:)),
                           keyEquivalent: "")
    reset.target = resetTarget
    menu.addItem(reset)
    button.menu = menu
    shortcutRecorders[id] = button
    refreshShortcutControls()
    return button
  }

  func refreshShortcutControls() {
    guard let editor = services.shortcutEditor else { return }
    for (id, button) in shortcutRecorders {
      button.toolTip = nil
      if editor.recordingAction == id && !editor.hasConflict {
        button.title = "Type shortcut…"
      } else if let blocked = editor.blockedOverrides[id], let first = blocked.first {
        button.title = "Unavailable"
        let owners = blocked.map(\.title).joined(separator: ", ")
        let message = "Saved \(shortcutDescription(first.binding)) is unavailable because it is used by \(owners). Record another shortcut or reset it."
        button.toolTip = message
        button.setAccessibilityValue(message)
        continue
      } else if let binding = editor.binding(for: id) {
        button.title = shortcutDescription(binding)
      } else {
        button.title = "None"
      }
      button.setAccessibilityValue(button.title)
    }
    shortcutResetAll?.isEnabled = !editor.overrides.isEmpty
    syncExtensionShortcutSuspension()
  }

  private func refreshShortcutPresentation() {
    refreshShortcutControls()
    // A record operation notifies before it releases the recorder. Rebuild after that operation completes.
    if services.shortcutEditor?.recordingAction == nil { applyShortcutSearch() }
  }

  func shortcutDescription(_ binding: ShortcutBinding) -> String {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: binding.key)
    item.keyEquivalentModifierMask = binding.modifiers
    return ShortcutCatalog.entry(for: item)?.spoken ?? binding.key.uppercased()
  }

  func handleShortcutKey(_ event: NSEvent) -> Bool {
    if extensionShortcuts?.recordingCommand != nil { return handleExtensionShortcutKey(event) }
    guard selectedPane == .shortcuts, let editor = services.shortcutEditor,
          editor.recordingAction != nil else { return false }
    if editor.hasConflict {
      if [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) {
        editor.keepExisting()
        dismissShortcutConflict()
        refreshShortcutControls()
        return true
      }
      // The notice is the one thing to answer: other shortcuts go neither to the menu nor to the panes. Tab and Space
      // still move between and press its buttons.
      return !event.modifierFlags.intersection([.command, .control]).isEmpty
    }
    guard let id = editor.recordingAction, let recorder = shortcutRecorders[id],
          window?.firstResponder === recorder else {
      cancelShortcutRecording()
      return false
    }
    if Int(event.keyCode) == kVK_Tab && event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
      cancelShortcutRecording()
      if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
      else { window?.selectNextKeyView(nil) }
      return true
    }
    editor.record(event: event)
    refreshShortcutPresentation()
    showShortcutRejection(editor.rejection, for: event)
    if editor.hasConflict {
      showShortcutConflict()
    } else if editor.rejection == nil, editor.recordingAction == nil, let binding = editor.binding(for: id),
              services.isSystemShortcut(binding) {
      showShortcutWarning()
    }
    return true
  }

  /// Why the recorder refused a key (maintainer decision 2026-11-16), in the warning's place; nil removes it.
  func showShortcutRejection(_ rejection: ShortcutEditorModel.Rejection?, for event: NSEvent) {
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    guard let rejection, let root = window?.contentView, let key = event.charactersIgnoringModifiers else { return }
    let reason = switch rejection {
    case .needsCommandOrControl:
      "shortcuts need Command or Control (F1 to F20 can be used alone), so typing keeps working."
    case .textEditing: "text fields use it to move, select or delete text."
    case .confirmOrFocusKey: "Return, Tab and Escape confirm, move focus and cancel."
    case .notAnExtensionKey:
      "extension shortcuts use a letter, a digit, comma, period, Space, an arrow, Home, End, Page Up, Page Down, "
        + "Insert or Forward Delete."
    case .optionWithCommandOrControl: "extension shortcuts can\u{2019}t combine Option with Command or Control."
    }
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    let keys = [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) && flags.isEmpty
      ? "Return" : shortcutDescription(ShortcutBinding(key: key, modifiers: flags))
    let notice = settingsLabel("\(keys) can\u{2019}t be a shortcut: \(reason)", size: 12)
    notice.setAccessibilityIdentifier("settings.shortcuts.rejected")
    notice.setAccessibilityLabel(notice.stringValue)
    notice.frame = NSRect(x: 40, y: 85, width: root.bounds.width - 80, height: 34)
    root.addSubview(notice)
    shortcutWarningView = notice
  }

  func cancelShortcutRecording() {
    services.shortcutEditor?.cancelRecording()
    cancelExtensionShortcutRecording()
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    dismissShortcutConflict()
    refreshShortcutControls()
    syncExtensionShortcutSuspension()
    if extensionRowsNeedRefresh { refreshExtensionRows() }
  }

  func dismissShortcutConflict() {
    window?.defaultButtonCell = nil
    shortcutConflictView?.removeFromSuperview()
    shortcutConflictView = nil
  }

  private func showShortcutConflict() {
    guard let editor = services.shortcutEditor, let binding = editor.pendingShortcut else { return }
    let protected = editor.protectedConflicts.first
    let title = protected?.title ?? editor.conflictingActions.first.flatMap { id in
      editor.catalog.first(where: { $0.id == id })?.title
    } ?? editor.extensionConflicts.first?.title
    guard let title else { return }
    var explanation = protected == nil ? "" : " This command cannot be changed here; keep the existing shortcut and try another."
    if protected == nil, !editor.extensionConflicts.isEmpty { explanation = " Using it here removes it there." }
    // Ctrl-Space and Ctrl-1 ... 9 are both Arkt items and macOS shortcuts, so the notice carries the system warning too.
    let system = services.isSystemShortcut(binding) ? " \(Self.systemShortcutWarning)" : ""
    presentShortcutConflict(
      message: "\(shortcutDescription(binding)) is already used by \(title).\(explanation)\(system)",
      useTitle: "Use Shortcut", canUse: protected == nil,
      keep: { [weak self] in self?.cancelShortcutRecording() },
      use: { [weak self] in
        guard let self, let editor = self.services.shortcutEditor else { return }
        let id = editor.recordingAction
        editor.useRecordedShortcut()
        // Still a conflict: a protected owner, or the engine kept an extension's shortcut. The notice stays.
        if editor.hasConflict {
          self.showShortcutConflict()
          return
        }
        self.dismissShortcutConflict()
        self.refreshShortcutPresentation()
        if let id, let binding = editor.binding(for: id), self.services.isSystemShortcut(binding) {
          self.showShortcutWarning()
        }
      })
  }

  /// The conflict notice of the app and the extension recorders: the message, Keep Existing (the default, Return,
  /// #590) and Use, which is unavailable while a command Settings cannot change holds the shortcut.
  func presentShortcutConflict(message text: String, useTitle: String, canUse: Bool,
                               keep keepAction: @escaping @MainActor () -> Void,
                               use useAction: @escaping @MainActor () -> Void) {
    guard let root = window?.contentView else { return }
    dismissShortcutConflict()
    let panel = NSView(frame: NSRect(x: 40, y: 105, width: max(300, root.bounds.width - 80), height: 130))
    panel.wantsLayer = true
    // Resolved in the window's appearance, not the process's (a light Settings window on a dark system).
    root.effectiveAppearance.performAsCurrentDrawingAppearance {
      panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    panel.layer?.cornerRadius = ShellRadius.popover
    panel.autoresizingMask = [.width]
    let message = settingsLabel(text, size: 13)
    message.setAccessibilityLabel(message.stringValue)
    message.setAccessibilityIdentifier("settings.shortcuts.conflict.message")
    message.frame = NSRect(x: 12, y: 12, width: panel.bounds.width - 24, height: 64)
    message.autoresizingMask = [.width]
    panel.addSubview(message)
    let keep = NSButton(title: "Keep Existing", target: nil, action: nil)
    let use = NSButton(title: useTitle, target: nil, action: nil)
    keep.setAccessibilityIdentifierWithCell("settings.shortcuts.conflict.keep")
    use.setAccessibilityIdentifierWithCell("settings.shortcuts.conflict.use")
    use.isEnabled = canUse
    if !canUse { use.toolTip = "This shortcut belongs to a command that cannot be changed here." }
    let keepTarget = SettingsActionTarget(keepAction)
    let useTarget = SettingsActionTarget(useAction)
    actionTargets.append(contentsOf: [keepTarget, useTarget])
    keep.target = keepTarget
    keep.action = #selector(SettingsActionTarget.fire(_:))
    use.target = useTarget
    use.action = #selector(SettingsActionTarget.fire(_:))
    keep.frame = NSRect(x: 12, y: 84, width: 140, height: 30)
    use.frame = NSRect(x: 160, y: 84, width: max(140, use.intrinsicContentSize.width + 16), height: 30)
    panel.addSubview(keep)
    panel.addSubview(use)
    root.addSubview(panel)
    shortcutConflictView = panel
    window?.defaultButtonCell = keep.cell as? NSButtonCell
    window?.makeFirstResponder(keep)
  }

  func showShortcutWarning() {
    shortcutWarningView?.removeFromSuperview()
    guard let root = window?.contentView else { return }
    let warning = settingsLabel(Self.systemShortcutWarning, size: 12)
    warning.setAccessibilityIdentifier("settings.shortcuts.systemConflict")
    warning.setAccessibilityLabel(warning.stringValue)
    warning.frame = NSRect(x: 40, y: 85, width: root.bounds.width - 80, height: 28)
    root.addSubview(warning)
    shortcutWarningView = warning
  }
}
