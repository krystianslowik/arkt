import AppKit

@MainActor
private final class ShortcutRecorderButton: NSButton {
  override var acceptsFirstResponder: Bool { true }
}

extension SettingsWindowController {
  func observeShortcutEditor() {
    guard shortcutObserver == nil, let editor = services.shortcutEditor else { return }
    shortcutObserver = editor.observe { [weak self] in self?.refreshShortcutControls() }
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
      self.refreshShortcutControls()
      if !editor.conflictingActions.isEmpty { self.showShortcutConflict() }
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
      if editor.recordingAction == id && editor.conflictingActions.isEmpty {
        button.title = "Type shortcut…"
      } else if let binding = editor.binding(for: id) {
        button.title = shortcutDescription(binding)
      } else {
        button.title = "None"
      }
    }
    shortcutResetAll?.isEnabled = !editor.overrides.isEmpty
  }

  private func shortcutDescription(_ binding: ShortcutBinding) -> String {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: binding.key)
    item.keyEquivalentModifierMask = binding.modifiers
    return ShortcutCatalog.entry(for: item)?.spoken ?? binding.key.uppercased()
  }

  func handleShortcutKey(_ event: NSEvent) -> Bool {
    guard selectedPane == .shortcuts, let editor = services.shortcutEditor,
          editor.recordingAction != nil else { return false }
    if !editor.conflictingActions.isEmpty {
      if event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 {
        editor.keepExisting()
        dismissShortcutConflict()
        refreshShortcutControls()
        return true
      }
      return false
    }
    if event.keyCode == 48 {
      cancelShortcutRecording()
      if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
      else { window?.selectNextKeyView(nil) }
      return true
    }
    let id = editor.recordingAction
    editor.record(event: event)
    refreshShortcutControls()
    if !editor.conflictingActions.isEmpty {
      showShortcutConflict()
    } else if let id, event.keyCode != 53, let binding = editor.binding(for: id),
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
    guard let editor = services.shortcutEditor, let conflict = editor.conflictingActions.first,
          let definition = editor.catalog.first(where: { $0.id == conflict }),
          let binding = editor.binding(for: conflict), let root = window?.contentView else { return }
    dismissShortcutConflict()
    let panel = NSView(frame: NSRect(x: 40, y: 105, width: max(300, root.bounds.width - 80), height: 104))
    panel.wantsLayer = true
    panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    panel.layer?.cornerRadius = 8
    panel.autoresizingMask = [.width]
    let message = settingsLabel("\(shortcutDescription(binding)) is already used by \(definition.title).", size: 13)
    message.setAccessibilityIdentifier("settings.shortcuts.conflict.message")
    message.frame = NSRect(x: 12, y: 12, width: panel.bounds.width - 24, height: 38)
    message.autoresizingMask = [.width]
    panel.addSubview(message)
    let keep = NSButton(title: "Keep Existing", target: nil, action: nil)
    let use = NSButton(title: "Use Shortcut", target: nil, action: nil)
    keep.setAccessibilityIdentifierWithCell("settings.shortcuts.conflict.keep")
    use.setAccessibilityIdentifierWithCell("settings.shortcuts.conflict.use")
    let keepTarget = SettingsActionTarget { [weak self] in self?.cancelShortcutRecording() }
    let useTarget = SettingsActionTarget { [weak self] in
      guard let self else { return }
      self.services.shortcutEditor?.useRecordedShortcut()
      self.dismissShortcutConflict()
      self.refreshShortcutControls()
    }
    actionTargets.append(contentsOf: [keepTarget, useTarget])
    keep.target = keepTarget
    keep.action = #selector(SettingsActionTarget.fire(_:))
    use.target = useTarget
    use.action = #selector(SettingsActionTarget.fire(_:))
    keep.frame = NSRect(x: 12, y: 58, width: 140, height: 30)
    use.frame = NSRect(x: 160, y: 58, width: 140, height: 30)
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
