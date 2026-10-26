import AppKit

/// Settings > Privacy > Crash reports (#129): one switch, off by default, and Send Crash Report. Kept in its own file
/// so the Privacy pane only gains the `crashReportsSection()` call. The copy never promises more than the app does:
/// reports are stored on this Mac, stripped, and only opened in the browser for the user to review.
extension SettingsWindowController {
  func crashReportsSection() -> SettingsSectionView {
    let toggle = SettingsSwitch(frame: .zero)
    toggle.state = settings.sendsCrashReports ? .on : .off
    toggle.onChange = { [weak self] on in self?.settings.sendsCrashReports = on }
    toggle.setAccessibilityIdentifierWithCell(AXID.Settings.control("privacy", "sendCrashReports"))
    crashReportsSwitch = toggle
    let switchRow = SettingsRowView(
      label: "Send crash reports",
      caption: "Keeps a report of each crash on this Mac, with no web addresses, page titles, file paths or names.",
      trailing: [toggle])

    let services = services
    let button = ArchivePillButton(style: .neutral, title: "Send Crash Report",
                                   metrics: .init(height: 24, fontSize: 12, weight: .semibold, padding: 16,
                                                  minWidth: nil, pressScale: 0.97))
    button.setArchiveAccessibilityLabel("Send Crash Report")
    let target = SettingsActionTarget { services.sendCrashReport() }
    actionTargets.append(target)                    // targets are weak
    button.target = target
    button.action = #selector(SettingsActionTarget.fire(_:))
    button.setAccessibilityIdentifierWithCell(AXID.Settings.control("privacy", "sendCrashReport"))
    sendCrashReportButton = button
    let sendRow = SettingsRowView(label: "Send a crash report", caption: nil, trailing: [button])
    sendCrashReportRow = sendRow
    applySendCrashReportState()

    return SettingsSectionView(title: "Crash reports", body: SettingsGroupView([switchRow, sendRow]), note: nil)
  }

  /// The button is offered only while the switch is on and a report is kept; the caption says which.
  func applySendCrashReportState() {
    guard let button = sendCrashReportButton, let row = sendCrashReportRow else { return }
    let enabled = settings.sendsCrashReports
    let count = services.crashReportCount()
    button.isEnabled = enabled && count > 0
    let caption = Self.sendCrashReportCaption(enabled: enabled, count: count)
    guard row.captionText != caption else { return }
    row.setCaption(caption)
    layoutPane()
  }

  static func sendCrashReportCaption(enabled: Bool, count: Int) -> String {
    guard enabled else { return "Available when crash reports are on." }
    guard count > 0 else { return "No crash reports on this Mac." }
    let noun = count == 1 ? "1 crash report" : "\(count) crash reports"
    return "\(noun) on this Mac. Sending opens a GitHub issue for you to review."
  }
}
