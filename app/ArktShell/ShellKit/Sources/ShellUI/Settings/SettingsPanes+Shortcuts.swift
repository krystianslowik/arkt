import AppKit

@MainActor
private final class ShortcutRecorderButton: NSButton {
  override var acceptsFirstResponder: Bool { true }
}

extension SettingsWindowController {
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
      if (!editor.conflictingActions.isEmpty || !editor.protectedConflicts.isEmpty) { self.showShortcutConflict() }
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
      if editor.recordingAction == id && editor.conflictingActions.isEmpty && editor.protectedConflicts.isEmpty {
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
  }

  private func refreshShortcutPresentation() {
    refreshShortcutControls()
    // A record operation notifies before it releases the recorder. Rebuild after that operation completes.
    if services.shortcutEditor?.recordingAction == nil { applyShortcutSearch() }
  }

  private func shortcutDescription(_ binding: ShortcutBinding) -> String {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: binding.key)
    item.keyEquivalentModifierMask = binding.modifiers
    return ShortcutCatalog.entry(for: item)?.spoken ?? binding.key.uppercased()
  }

  func handleShortcutKey(_ event: NSEvent) -> Bool {
    guard selectedPane == .shortcuts, let editor = services.shortcutEditor,
          editor.recordingAction != nil else { return false }
    if (!editor.conflictingActions.isEmpty || !editor.protectedConflicts.isEmpty) {
      if event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 {
        editor.keepExisting()
        dismissShortcutConflict()
        refreshShortcutControls()
        return true
      }
      return false
    }
    guard let id = editor.recordingAction, let recorder = shortcutRecorders[id],
          window?.firstResponder === recorder else {
      cancelShortcutRecording()
      return false
    }
    if event.keyCode == 48 {
      cancelShortcutRecording()
      if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
      else { window?.selectNextKeyView(nil) }
      return true
    }
    editor.record(event: event)
    refreshShortcutPresentation()
    if (!editor.conflictingActions.isEmpty || !editor.protectedConflicts.isEmpty) {
      showShortcutConflict()
    } else if event.keyCode != 53, let binding = editor.binding(for: id),
              services.isSystemShortcut(binding) {
      showShortcutWarning()
    }
    return true
  }

  func cancelShortcutRecording() {
    services.shortcutEditor?.cancelRecording()
    shortcutWarningView?.removeFromSuperview()
    shortcutWarningView = nil
    dismissShortcutConflict()
    refreshShortcutControls()
  }

  private func dismissShortcutConflict() {
    window?.defaultButtonCell = nil
    shortcutConflictView?.removeFromSuperview()
    shortcutConflictView = nil
  }

  private func showShortcutConflict() {
    guard let editor = services.shortcutEditor, let binding = editor.pendingShortcut,
          let root = window?.contentView else { return }
    let protected = editor.protectedConflicts.first
    let title = protected?.title ?? editor.conflictingActions.first.flatMap { id in
      editor.catalog.first(where: { $0.id == id })?.title
    }
    guard let title else { return }
    dismissShortcutConflict()
    let panel = NSView(frame: NSRect(x: 40, y: 105, width: max(300, root.bounds.width - 80), height: 130))
    panel.wantsLayer = true
    panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    panel.layer?.cornerRadius = ShellRadius.popover
    panel.autoresizingMask = [.width]
    let explanation = protected == nil ? "" : " This command cannot be changed here; keep the existing shortcut and try another."
    let message = settingsLabel("\(shortcutDescription(binding)) is already used by \(title).\(explanation)", size: 13)
    message.setAccessibilityLabel(message.stringValue)
    message.setAccessibilityIdentifier("settings.shortcuts.conflict.message")
    message.frame = NSRect(x: 12, y: 12, width: panel.bounds.width - 24, height: 64)
    message.autoresizingMask = [.width]
    panel.addSubview(message)
    let keep = NSButton(title: "Keep Existing", target: nil, action: nil)
    let use = NSButton(title: "Use Shortcut", target: nil, action: nil)
    keep.setAccessibilityIdentifierWithCell("settings.shortcuts.conflict.keep")
    use.setAccessibilityIdentifierWithCell("settings.shortcuts.conflict.use")
    use.isEnabled = protected == nil
    if protected != nil { use.toolTip = "This shortcut belongs to a command that cannot be changed here." }
    let keepTarget = SettingsActionTarget { [weak self] in self?.cancelShortcutRecording() }
    let useTarget = SettingsActionTarget { [weak self] in
      guard let self, let editor = self.services.shortcutEditor else { return }
      let id = editor.recordingAction
      editor.useRecordedShortcut()
      if !editor.protectedConflicts.isEmpty {
        self.showShortcutConflict()
        return
      }
      self.dismissShortcutConflict()
      self.refreshShortcutPresentation()
      if let id, let binding = editor.binding(for: id), self.services.isSystemShortcut(binding) {
        self.showShortcutWarning()
      }
    }
    actionTargets.append(contentsOf: [keepTarget, useTarget])
    keep.target = keepTarget
    keep.action = #selector(SettingsActionTarget.fire(_:))
    use.target = useTarget
    use.action = #selector(SettingsActionTarget.fire(_:))
    keep.frame = NSRect(x: 12, y: 84, width: 140, height: 30)
    use.frame = NSRect(x: 160, y: 84, width: 140, height: 30)
    panel.addSubview(keep)
    panel.addSubview(use)
    root.addSubview(panel)
    shortcutConflictView = panel
    window?.defaultButtonCell = keep.cell as? NSButtonCell
    window?.makeFirstResponder(keep)
  }

  private func showShortcutWarning() {
    shortcutWarningView?.removeFromSuperview()
    guard let root = window?.contentView else { return }
    let warning = settingsLabel("System shortcuts may take priority over this shortcut.", size: 12)
    warning.setAccessibilityIdentifier("settings.shortcuts.systemConflict")
    warning.setAccessibilityLabel(warning.stringValue)
    warning.frame = NSRect(x: 40, y: 85, width: root.bounds.width - 80, height: 28)
    root.addSubview(warning)
    shortcutWarningView = warning
  }
}
