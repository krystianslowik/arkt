import Foundation
import Testing
@testable import ShellUI

/// The first-run flow model (onboarding spec, sections 2, 10 and 13): branching, step lists, progress, the footer,
/// the keyboard's step rules and resume.
struct OnboardingFlowTests {
  typealias Step = OnboardingStep

  static func flow(arc: OnboardingFlow.ArcAvailability = .found, isDefault: Bool = false, extensions: Bool = true,
                   mode: OnboardingMode = .firstRun) -> OnboardingFlow {
    OnboardingFlow(conditions: .init(arc: arc, isDefaultBrowser: isDefault, includesExtensions: extensions,
                                     mode: mode))
  }

  // MARK: - Step lists

  @Test func arcFoundListsImportFirst() {
    #expect(Self.flow().kinds == [.importData, .theme, .defaultBrowser, .extensions, .tour, .done])
  }

  @Test func noArcLeavesImportOut() {
    #expect(Self.flow(arc: .notFound).kinds == [.theme, .defaultBrowser, .extensions, .tour, .done])
  }

  @Test func arcStillCheckingShowsImport() {
    #expect(Self.flow(arc: .checking).kinds.first == .importData)
  }

  @Test func alreadyDefaultLeavesTheDefaultStepOut() {
    #expect(!Self.flow(isDefault: true).kinds.contains(.defaultBrowser))
  }

  @Test func extensionsOnlyWithTheChromiumEngine() {
    #expect(!Self.flow(extensions: false).kinds.contains(.extensions))
  }

  // MARK: - Progress: "{n} of {total}", the tour counts once

  @Test(arguments: [
    (OnboardingFlow.ArcAvailability.found, false, 6), (.notFound, false, 5), (.found, true, 5), (.notFound, true, 4),
  ])
  func totals(arc: OnboardingFlow.ArcAvailability, isDefault: Bool, total: Int) {
    var flow = Self.flow(arc: arc, isDefault: isDefault)
    #expect(flow.progress == nil, "Welcome shows no progress")
    flow.advance()
    #expect(flow.progress == .init(index: 1, total: total))
  }

  @Test func tourIsOneStepWithFiveTips() {
    var flow = Self.flow()
    flow.jump(to: .tour(tip: 1))
    let progress = flow.progress
    for tip in 2...5 {
      flow.advance()
      #expect(flow.step == .tour(tip: tip))
      #expect(flow.progress == progress)
    }
    flow.advance()
    #expect(flow.step == .done)
    #expect(flow.progress == .init(index: 6, total: 6))
  }

  @Test func walkThroughEveryStepWithArc() {
    var flow = Self.flow()
    var seen: [Step] = [flow.step]
    while flow.step != .done {
      flow.advance()
      seen.append(flow.step)
    }
    #expect(seen == [.welcome, .importData, .theme, .defaultBrowser, .extensions,
                     .tour(tip: 1), .tour(tip: 2), .tour(tip: 3), .tour(tip: 4), .tour(tip: 5), .done])
  }

  // MARK: - Footer

  @Test func welcomeShowsSkipSetupOnly() {
    let flow = Self.flow()
    #expect(!flow.showsBack && flow.showsSkipSetup && flow.progress == nil)
  }

  @Test func firstStepAfterWelcomeHasNoBack() {
    var flow = Self.flow(arc: .notFound)
    flow.advance()
    #expect(flow.step == .theme)
    #expect(!flow.showsBack)
    flow.advance()
    #expect(flow.showsBack)
  }

  @Test func doneShowsAnEmptyFooter() {
    var flow = Self.flow()
    flow.jump(to: .done)
    #expect(!flow.showsBack && !flow.showsSkipSetup && flow.progress != nil)
    #expect(!flow.showsProgress)
  }

  @Test func backIsHiddenWhileImporting() {
    var flow = Self.flow()
    flow.advance()
    flow.jump(to: .theme)
    flow.back()
    #expect(flow.step == .importData)
    flow.setImportPhase(.importing)
    #expect(!flow.showsBack)
  }

  // MARK: - Import states

  @Test func importStatesDriveTheActions() {
    var flow = Self.flow()
    flow.advance()
    #expect(flow.importPhase == .counting)
    #expect(flow.primaryAction == nil, "Import is disabled while counting")
    #expect(flow.secondaryAction == .startFresh)
    flow.setImportPhase(.ready)
    #expect(flow.primaryAction == .importData)
    flow.setImportPhase(.importing)
    #expect(flow.primaryAction == nil)
    #expect(flow.secondaryAction == nil, "Escape does nothing while importing")
    flow.setImportPhase(.imported(skipped: 0))
    #expect(flow.primaryAction == .continue)
    #expect(flow.secondaryAction == nil, "Imported has Continue only")
    flow.setImportPhase(.failed)
    #expect(flow.primaryAction == .tryAgain)
    #expect(flow.secondaryAction == .startFresh)
  }

  @Test func startFreshGoesToMakeItYoursFresh() {
    var flow = Self.flow()
    flow.advance()
    flow.setImportPhase(.ready)
    flow.advance()
    #expect(flow.step == .theme)
    #expect(flow.themePath == .fresh)
  }

  @Test func afterAnImportMakeItYoursIsOnTheImportPath() {
    var flow = Self.flow()
    flow.advance()
    flow.setImportPhase(.imported(skipped: 2))
    flow.advance()
    #expect(flow.themePath == .imported)
  }

  @Test func failedThenStartFreshIsFresh() {
    var flow = Self.flow()
    flow.advance()
    flow.setImportPhase(.failed)
    flow.advance()
    #expect(flow.step == .theme && flow.themePath == .fresh)
  }

  @Test func checkSayingNoArcReplacesImport() {
    var flow = Self.flow(arc: .checking)
    flow.advance()
    #expect(flow.step == .importData)
    flow.setArc(.notFound)
    #expect(flow.step == .theme)
    #expect(flow.kinds.first == .theme)
    #expect(flow.progress == .init(index: 1, total: 5))
  }

  @Test func checkSayingArcFoundKeepsImport() {
    var flow = Self.flow(arc: .checking)
    flow.advance()
    flow.setArc(.found)
    #expect(flow.step == .importData)
  }

  // MARK: - Secondary and primary actions (Escape and Return)

  @Test func everyStepHasItsActions() {
    var flow = Self.flow()
    #expect(flow.primaryAction == .getStarted && flow.secondaryAction == .askSkipSetup)
    flow.jump(to: .theme)
    #expect(flow.primaryAction == .continue && flow.secondaryAction == .skipTheme)
    flow.jump(to: .defaultBrowser)
    #expect(flow.primaryAction == .makeDefault && flow.secondaryAction == .notNow)
    flow.jump(to: .extensions)
    #expect(flow.primaryAction == .continue && flow.secondaryAction == .skipExtensions)
    flow.jump(to: .tour(tip: 3))
    #expect(flow.primaryAction == .nextTip && flow.secondaryAction == .skipTour)
    flow.jump(to: .tour(tip: 5))
    #expect(flow.primaryAction == .finishTour)
    flow.jump(to: .done)
    #expect(flow.primaryAction == .startBrowsing && flow.secondaryAction == nil)
  }

  @Test func skipTourGoesToDone() {
    var flow = Self.flow()
    flow.jump(to: .tour(tip: 2))
    flow.skipTour()
    #expect(flow.step == .done)
  }

  // MARK: - Arrows: Left is Back, Right only returns

  @Test func backStepsThroughTipsBeforeLeavingTheTour() {
    var flow = Self.flow()
    flow.jump(to: .tour(tip: 3))
    flow.back()
    #expect(flow.step == .tour(tip: 2))
    flow.back()
    flow.back()
    #expect(flow.step == .extensions)
    flow.advance()
    #expect(flow.step == .tour(tip: 1))
  }

  @Test func backFromDoneLandsOnTheLastTip() {
    var flow = Self.flow()
    flow.jump(to: .done)
    // Back is hidden on Done; the model still answers the Left arrow the same way it answers Back elsewhere.
    flow.back()
    #expect(flow.step == .tour(tip: 5))
  }

  @Test func rightOnlyReturnsToAStepVisitedBeforeABack() {
    var flow = Self.flow()
    flow.jump(to: .extensions)
    #expect(!flow.canGoForward)
    var moved = flow.goForward()
    #expect(!moved)
    flow.back()
    flow.back()
    #expect(flow.step == .theme)
    moved = flow.goForward()
    #expect(moved)
    #expect(flow.step == .defaultBrowser)
    moved = flow.goForward()
    #expect(moved)
    #expect(flow.step == .extensions)
    moved = flow.goForward()
    #expect(!moved)
  }

  @Test func movingOnClearsTheForwardHistory() {
    var flow = Self.flow()
    flow.jump(to: .extensions)
    flow.back()
    #expect(flow.canGoForward)
    flow.advance()
    #expect(!flow.canGoForward)
  }

  @Test func backAtTheFirstStepDoesNothing() {
    var flow = Self.flow()
    flow.advance()
    flow.back()
    #expect(flow.step == .importData)
  }

  // MARK: - Resume (section 13)

  @Test func snapshotRoundTripsThroughJSON() throws {
    var flow = Self.flow()
    flow.advance()
    flow.setImportPhase(.imported(skipped: 3))
    flow.advance()
    flow.advance()
    let data = try JSONEncoder().encode(flow.snapshot)
    let snapshot = try JSONDecoder().decode(OnboardingFlow.Snapshot.self, from: data)
    let resumed = OnboardingFlow(resuming: snapshot, conditions: flow.conditions)
    #expect(resumed.step == .defaultBrowser)
    #expect(resumed.importPhase == .imported(skipped: 3))
    #expect(resumed.themePath == .imported)
  }

  @Test func aFinishedImportStaysImported() {
    var flow = Self.flow()
    flow.advance()
    flow.setImportPhase(.imported(skipped: 0))
    let resumed = OnboardingFlow(resuming: flow.snapshot, conditions: flow.conditions)
    #expect(resumed.step == .importData)
    #expect(resumed.importPhase == .imported(skipped: 0))
  }

  @Test func anUnfinishedImportCountsAgain() {
    var flow = Self.flow()
    flow.advance()
    flow.setImportPhase(.importing)
    let resumed = OnboardingFlow(resuming: flow.snapshot, conditions: flow.conditions)
    #expect(resumed.importPhase == .counting)
  }

  @Test func resumingAtAStepLeftOutMovesToTheNextOne() {
    var flow = Self.flow()
    flow.jump(to: .defaultBrowser)
    let conditions = OnboardingFlow.Conditions(arc: .found, isDefaultBrowser: true, includesExtensions: true,
                                               mode: .firstRun)
    let resumed = OnboardingFlow(resuming: flow.snapshot, conditions: conditions)
    #expect(resumed.step == .extensions)
  }

  @Test func resumeNeverReturnsToWelcomeAfterLeavingIt() {
    var flow = Self.flow()
    flow.advance()
    #expect(flow.snapshot.step == "import")
    #expect(OnboardingFlow(resuming: flow.snapshot, conditions: flow.conditions).step == .importData)
  }

  @Test func unknownSnapshotStepStartsAtWelcome() {
    let snapshot = OnboardingFlow.Snapshot(step: "nonsense", imported: false, importSkipped: 0)
    #expect(OnboardingFlow(resuming: snapshot, conditions: Self.flow().conditions).step == .welcome)
  }

  // MARK: - Step identifiers

  @Test func stepIdentifiersRoundTrip() {
    let all: [Step] = [.welcome, .importData, .theme, .defaultBrowser, .extensions, .tour(tip: 1), .tour(tip: 5), .done]
    for step in all {
      #expect(Step(identifier: step.identifier) == step)
    }
    #expect(Step(identifier: "tour-6") == nil)
    #expect(Step(identifier: "tour-0") == nil)
  }
}
