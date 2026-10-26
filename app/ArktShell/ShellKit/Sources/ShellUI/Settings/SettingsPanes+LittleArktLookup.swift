import AppKit

/// Settings > Links: the system-wide lookup hotkey (#354, BH-130, BH-131, KB-045). Off by default (decision
/// 2026-10-25); the conflict line under the switch is the registration answer, so a combination another app holds reads
/// "⌥⌘N is used by another app." while the switch stays on (the in-app menu item still works).
extension SettingsWindowController {
  /// The row's control, built here rather than with the pane helpers: this file is the only one that changes for the
  /// row, so a parallel edit to the Links section only adds the `littleArktLookupRow()` call.
  func littleArktLookupRow() -> SettingsRowView {
    let hotKey = SettingsSwitch(frame: .zero)
    hotKey.state = settings.opensLittleArktWithHotKey ? .on : .off
    hotKey.onChange = { [weak self] on in self?.settings.opensLittleArktWithHotKey = on }
    hotKey.setAccessibilityIdentifierWithCell(AXID.Settings.control("general", "littleArktHotKey"))
    littleArktHotKeySwitch = hotKey
    let row = SettingsRowView(label: LittleArktLookup.settingLabel,
                              caption: Self.littleArktHotKeyCaption(taken: settings.littleArktHotKeyTaken),
                              trailing: [hotKey])
    littleArktHotKeyRow = row
    return row
  }

  /// The caption under the switch, nil while the combination is free.
  static func littleArktHotKeyCaption(taken: Bool) -> String? {
    taken ? LittleArktLookup.conflictMessage : nil
  }

  /// Follows the store: the switch, then the conflict line. The pane's layout follows, so the row grows into place.
  func applyLittleArktHotKeyState() {
    littleArktHotKeySwitch?.setOn(settings.opensLittleArktWithHotKey, animated: true)
    guard let row = littleArktHotKeyRow,
          row.captionText != (Self.littleArktHotKeyCaption(taken: settings.littleArktHotKeyTaken) ?? "") else { return }
    row.setCaption(Self.littleArktHotKeyCaption(taken: settings.littleArktHotKeyTaken))
    layoutPane()
  }
}
