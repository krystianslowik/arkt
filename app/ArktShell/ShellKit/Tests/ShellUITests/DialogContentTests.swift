import Foundation
import Motion
import QuartzCore
import Testing
@testable import ShellUI

/// The shared dialog model (alerts design 3.1, 3.4) and the dialog motion (section 7).
struct DialogContentTests {
  private static let work = SpaceThemeInfo(baseColors: [.srgb(hex: 0x3B82F6)], isDark: false)

  // MARK: Delete Space

  @Test func theCountsLineNamesOnlyWhatIsThere() {
    #expect(SpaceRemovalPrompt.countsLine(pinnedTabs: 3, todayTabs: 3) == "3 pinned tabs, 3 Today tabs")
    #expect(SpaceRemovalPrompt.countsLine(pinnedTabs: 1, todayTabs: 0) == "1 pinned tab")
    #expect(SpaceRemovalPrompt.countsLine(pinnedTabs: 0, todayTabs: 1) == "1 Today tab")
    #expect(SpaceRemovalPrompt.countsLine(pinnedTabs: 0, todayTabs: 0) == nil)
  }

  @Test func deleteSpaceIsTheSharedSheetWithTheSpacesSwatch() {
    let prompt = SpaceRemovalPrompt(space: UUID(), title: "Work", hasItems: true)
    let content = prompt.dialogContent(pinnedTabs: 3, todayTabs: 3, theme: Self.work, icon: .symbol("star"))
    #expect(content.title == "Delete the Space \u{201C}Work\u{201D}?")
    #expect(content.paragraphs == [
      .init("Its pinned tabs, folders and Today tabs move to the Archive, where you can restore them."),
      .init("3 pinned tabs, 3 Today tabs", secondary: true),
    ])
    #expect(content.icon == .spaceSwatch(colors: Self.work.baseColors, isDark: false, mark: .symbol("star")))
    #expect(content.primaryTitle == "Delete Space")
    #expect(content.isDestructive)
    #expect(content.cancelTitle == "Cancel")
    #expect(content.defaultButton == .none, "no Return key: a stray Return deletes nothing")
    #expect(content.escapeAnswersCancel)
    #expect(content.primaryHelp == "Deletes the Space")
  }

  @Test func anEmptySpaceHasNoCountsLine() {
    let prompt = SpaceRemovalPrompt(space: UUID(), title: "", hasItems: false)
    let content = prompt.dialogContent(pinnedTabs: 0, todayTabs: 0, theme: nil, icon: nil)
    #expect(content.title == "Delete this Space?")
    #expect(content.paragraphs == [.init("This cannot be undone.")])
  }

  // MARK: Crash report ask (#129)

  @Test func theCrashReportAskIsTheSharedAlertWithThreeAnswers() {
    let content = DialogContent.crashReportAsk
    #expect(content.title == "Arkt quit unexpectedly. Send a report?")
    #expect(content.primaryTitle == "Send")
    #expect(content.secondaryTitle == "Always Send")
    #expect(content.cancelTitle == "Don't Send")
    #expect(content.icon == .appIcon && content.iconPlacement == .stacked)
    #expect(content.defaultButton == .primary)
    #expect(content.escapeAnswersCancel, "Escape answers Don't Send")
    #expect(!content.isDestructive)
  }

  @Test func theCrashReportAskPromisesNothingItDoesNotDo() {
    let text = ([DialogContent.crashReportAsk.title] + DialogContent.crashReportAsk.paragraphs.map(\.text)).joined(separator: " ")
    #expect(text.contains("Nothing is sent until you review it"))
    #expect(!text.lowercased().contains("arc "), "no user-facing Arc")
    #expect(!DialogContent.crashReportAsk.paragraphs.contains { $0.text.contains("http") })
  }

  // MARK: Launch

  @Test func launchFailureOffersTryAgainAndTheDataFolder() {
    let content = DialogContent.launchFailure(errorCode: "SQLiteError 11")
    #expect(content.title == "Arkt couldn't open its data")
    #expect(!content.title.hasSuffix("."))
    #expect(content.paragraphs == [.init("Nothing was changed. Try again, or show the data folder."),
                                   .init("Error: SQLiteError 11", secondary: true)])
    #expect(content.icon == .appIcon)
    #expect(content.iconPlacement == .stacked)
    #expect(content.primaryTitle == "Try Again")
    #expect(!content.isDestructive)
    #expect(content.cancelTitle == "Quit")
    #expect(content.footerLink == "Show Data Folder")
    #expect(content.defaultButton == .primary)
  }

  @Test func newerSchemaHasQuitOnly() {
    let content = DialogContent.newerSchema
    #expect(content.title == "This data was saved by a newer version of Arkt")
    #expect(content.paragraphs == [.init("Update Arkt to open it. Nothing was changed.")])
    #expect(content.primaryTitle == "Quit")
    #expect(content.cancelTitle == nil)
    #expect(content.footerLink == nil)
    #expect(content.defaultButton == .primary)
  }

  @Test func theAccessibilityDescriptionReadsTheBodyInOrder() {
    let content = DialogContent.launchFailure(errorCode: "E 1")
    #expect(content.accessibilityDescription
      == "Nothing was changed. Try again, or show the data folder. Error: E 1")
  }

  // MARK: Motion

  @Test func motionIsTransformAndOpacityWithReduceMotionFades() {
    let alert = DialogMotion.alertIn(reduceMotion: false)
    #expect(alert.scale == 0.96 && alert.offsetY == 0 && alert.spring == SpringPreset.firmFast.parameters)
    #expect(alert.fadeDuration == 0.18)
    let panel = DialogMotion.panelIn(reduceMotion: false)
    #expect(panel.scale == 0.97 && panel.offsetY == -4 && panel.fadeDuration == 0.16)
    for step in [DialogMotion.alertIn(reduceMotion: true), DialogMotion.panelIn(reduceMotion: true)] {
      #expect(step.scale == 1 && step.offsetY == 0 && step.spring == nil && step.fadeDuration == 0.15)
    }
    #expect(DialogMotion.panelOut(keyboard: false, reduceMotion: false) == 0.10)
    #expect(DialogMotion.panelOut(keyboard: true, reduceMotion: false) == 0)
    #expect(DialogMotion.panelOut(keyboard: false, reduceMotion: true) == 0)
  }

  /// A transform that scales about `anchor` (in a flipped view: top-leading is (0, 0)).
  @Test func theStartTransformScalesAboutItsAnchor() {
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 200)
    let t = DialogMotion.transform(scale: 0.97, offsetY: 0, about: .zero, bounds: bounds, layerAnchor: .zero)
    let origin = CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(t))
    #expect(abs(origin.x) < 1e-9 && abs(origin.y) < 1e-9, "the top-leading corner stays put")
    let far = CGPoint(x: 320, y: 200).applying(CATransform3DGetAffineTransform(t))
    #expect(abs(far.x - 310.4) < 1e-6)
  }
}
