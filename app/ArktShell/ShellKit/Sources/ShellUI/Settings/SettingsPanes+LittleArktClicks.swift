import AppKit

/// Settings > Links: Opt-Cmd-click into Little Arkt (#356, BH-132, GS-028), on by default. The one switch covers a
/// link in a page and a tab in the sidebar.
extension SettingsWindowController {
  func littleArktClickRow() -> SettingsRowView {
    let control = SettingsSwitch(frame: .zero)
    control.state = settings.opensLittleArktOnOptionCommandClick ? .on : .off
    control.onChange = { [weak self] on in self?.settings.opensLittleArktOnOptionCommandClick = on }
    control.setAccessibilityIdentifierWithCell(AXID.Settings.control("general", "littleArktOptionCommandClick"))
    littleArktClickSwitch = control
    return SettingsRowView(label: LittleArktCopy.optionCommandClickSetting, caption: nil, trailing: [control])
  }
}
