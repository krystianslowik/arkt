import Foundation
import Testing
@testable import ShellUI

/// BH-196 (#404): after repeated manual link copies, Copy URL's shortcut is suggested once, and never to someone who
/// already uses it.
@MainActor
struct CopyLinkEducationTests {
  private func suite() -> UserDefaults {
    let name = "CopyLinkEducationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test func theTipComesOnTheThirdManualCopyOnly() {
    let education = CopyLinkEducation.ephemeral()
    #expect(!education.recordManualCopy())
    #expect(!education.recordManualCopy())
    #expect(education.recordManualCopy())
    #expect(!education.recordManualCopy())
    #expect(!education.recordManualCopy())
  }

  @Test func usingTheShortcutMeansTheTipNeverComes() {
    let education = CopyLinkEducation.ephemeral()
    education.recordShortcutUse()
    for _ in 0..<5 { #expect(!education.recordManualCopy()) }
  }

  @Test func theTipIsRememberedAcrossLaunches() {
    let defaults = suite()
    let first = CopyLinkEducation(defaults: defaults, now: { Date(timeIntervalSince1970: 100) })
    _ = first.recordManualCopy()
    _ = first.recordManualCopy()
    #expect(first.recordManualCopy())
    #expect(defaults.object(forKey: CopyLinkEducation.lastSeenDefaultsKey) as? Date == Date(timeIntervalSince1970: 100))

    let second = CopyLinkEducation(defaults: defaults)
    for _ in 0..<5 { #expect(!second.recordManualCopy()) }
  }

  @Test func theCountSurvivesARelaunch() {
    let defaults = suite()
    let first = CopyLinkEducation(defaults: defaults)
    _ = first.recordManualCopy()
    _ = first.recordManualCopy()
    #expect(CopyLinkEducation(defaults: defaults).recordManualCopy())
  }

  @Test func theTipNamesTheShortcutAndSpellsItOut() {
    let toast = CopyLinkEducation.toast
    #expect(toast.text == "Copy links faster by pressing \u{21E7}\u{2318}C")
    #expect(toast.spokenText == "Copy links faster by pressing Shift-Command-C")
    #expect(toast.isPolite)
  }
}
