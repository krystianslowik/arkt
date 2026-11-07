import AppKit

/// Settings > Advanced > Reset all settings (#617; docs/design/settings.md, section 3): the red Reset... link opens the
/// shared dialog sheet on the Settings window (alerts design 3.1 to 3.3). Focus starts on Cancel, the destructive
/// Reset Settings has no Return key, and Escape cancels. Reset Settings returns every preference to its default
/// (`AppSettings.resetToDefaults`) and the archive rows through the app; Spaces, tabs, history, the Archive, extensions
/// and profiles are not settings and are not touched. Engine-backed preferences join through the bridge (#616).
extension SettingsWindowController {
  static let resetSettingsWidth: CGFloat = 400

  /// The sheet's content: the row's caption as the reassurance, "Reset Settings" as the destructive answer.
  static var resetSettingsContent: DialogContent {
    DialogContent(title: "Reset all settings?",
                  paragraphs: [.init("Every setting returns to its default. Your Spaces, tabs and archived items "
                    + "stay as they are.")],
                  primaryTitle: "Reset Settings", cancelTitle: "Cancel", defaultButton: .none, isDestructive: true,
                  primaryHelp: "Returns every setting to its default", width: resetSettingsWidth)
  }

  /// Reset...: shows the confirmation on the Settings window; one at a time.
  func askToResetSettings() {
    guard resetSheet == nil, let window else { return }
    let sheet = DialogSheet(content: Self.resetSettingsContent)
    sheet.view.primaryButton.setAccessibilityIdentifierWithCell(AXID.Settings.resetConfirm)
    sheet.onAnswer = { [weak self] answer in
      self?.resetSheet = nil
      if answer == .primary { self?.resetSettings() }
    }
    resetSheet = sheet
    sheet.begin(on: window)
  }

  /// Every preference back to its default; the shown controls follow (the switches through the observers, the
  /// archive pop-ups here, since their values live in the app).
  func resetSettings() {
    settings.resetToDefaults()
    guard let rows = services.archiveRows else { return }
    rows.reset()
    archiveTabsPopUp?.show(rows.tabsAfter())
    archiveLittleArktPopUp?.show(rows.littleArktAfter())
  }
}
