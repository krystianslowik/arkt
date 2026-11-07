import EngineAPI
import EngineAPITestSupport
import Foundation
import Testing
@testable import ShellUI

/// `ToastPresenter` state only; time is injected so no test waits on a real clock.
@MainActor
struct ToastPresenterTests {
  /// A sleeper that never returns on its own within a test.
  private static let forever: ToastSleep = { _ in try await Task.sleep(for: .seconds(3600)) }

  /// A sleeper each call of which returns when the gate yields once.
  private static func gated(_ gate: AsyncStream<Void>) -> ToastSleep {
    { _ in for await _ in gate { return } }
  }

  @Test func newToastReplacesCurrent() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "One"))
    presenter.show(Toast(text: "Two"))
    #expect(presenter.current?.text == "Two")
  }

  @Test func transientToastDismissesAfterDuration() async {
    let gate = AsyncStream<Void>.makeStream()
    let presenter = ToastPresenter(sleep: Self.gated(gate.stream))
    presenter.show(Toast(text: "Bye"))
    gate.continuation.yield()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current == nil)
  }

  @Test func replacedToastTimerDoesNotDismissTheNewToast() async {
    let sleeper = WakeQueueSleeper()
    let presenter = ToastPresenter(sleep: { _ in await sleeper.sleep() })
    presenter.show(Toast(text: "One"))
    await sleeper.waitForSleepers(1)
    presenter.show(Toast(text: "Two"))
    await sleeper.waitForSleepers(2)
    await sleeper.wakeOldest()      // the first timer ends its sleep after "Two" replaced "One"
    while presenter.runningTimerCountForTesting > 1 { await Task.yield() }
    #expect(presenter.current?.text == "Two")
    await sleeper.wakeOldest()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current == nil)
  }

  @Test func persistentToastStaysUntilDismissed() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "Recovered", kind: .persistent))
    #expect(presenter.current?.text == "Recovered")
    #expect(!presenter.isTimerArmedForTesting)
    presenter.dismiss()
    #expect(presenter.current == nil)
  }

  @Test func transientOverPersistentRestoresThePersistentToast() async {
    let gate = AsyncStream<Void>.makeStream()
    let presenter = ToastPresenter(sleep: Self.gated(gate.stream))
    presenter.show(Toast(text: "Recovered", kind: .persistent))
    presenter.show(Toast(text: "Couldn't add the tab."))
    #expect(presenter.current?.text == "Couldn't add the tab.")
    gate.continuation.yield()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current?.text == "Recovered")
  }

  @Test func persistentToastReplacesAnotherPersistentToast() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "First", kind: .persistent))
    presenter.show(Toast(text: "Second", kind: .persistent))
    #expect(presenter.current?.text == "Second")
    presenter.dismiss()
    #expect(presenter.current == nil)
  }

  @Test func actionRunsAndDismisses() {
    let presenter = ToastPresenter(sleep: Self.forever)
    var calls = 0
    presenter.show(Toast(text: "Restored", kind: .persistent, actionTitle: "Show Files")) { calls += 1 }
    presenter.performActionForTesting()
    #expect(calls == 1)
    #expect(presenter.current == nil)
    presenter.performActionForTesting()
    #expect(calls == 1)
  }

  /// The Peek's toast (#346): "Peek closed" with "Reopen" and its key, announced politely with the key spelled out.
  @Test func aToastCarriesItsShortcutAndAnnouncement() {
    let toast = Toast(text: "Peek closed", actionTitle: "Reopen", shortcut: "\u{2318}Z",
                      announcement: "Peek closed. Press Command-Z to reopen.", isPolite: true)
    #expect(toast.shortcut == "\u{2318}Z")
    #expect(toast.spokenText == "Peek closed. Press Command-Z to reopen.")
    #expect(toast.isPolite)
    let plain = Toast(text: "Archived 3 tabs")
    #expect(plain.shortcut == nil && plain.spokenText == "Archived 3 tabs" && !plain.isPolite)
  }

  /// A reopen by key takes the reopen toast down, and only that one.
  @Test func dismissingASpecificToastLeavesAnyOtherUp() {
    let presenter = ToastPresenter(sleep: Self.forever)
    let closed = Toast(text: "Peek closed", actionTitle: "Reopen")
    presenter.show(closed)
    presenter.dismiss(closed)
    #expect(presenter.current == nil)
    presenter.show(Toast(text: "Other"))
    presenter.dismiss(closed)
    #expect(presenter.current?.text == "Other")
  }

  @Test func actionMayShowANewToast() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "One", actionTitle: "Next")) { [unowned presenter] in
      presenter.show(Toast(text: "Two"))
    }
    presenter.performActionForTesting()
    #expect(presenter.current?.text == "Two")
  }
}

/// Kinds, lifetimes and pausing (alerts design 4.1).
@MainActor
struct ToastKindTests {
  private static let forever: ToastSleep = { _ in try await Task.sleep(for: .seconds(3600)) }

  @Test func kindsCarryTheirGlyphAndLifetime() {
    #expect(Toast(text: "Archived 3 tabs", kind: .undo).glyph == "archivebox")
    #expect(Toast(text: "Archived 3 tabs", kind: .undo).duration == .seconds(6))
    #expect(Toast(text: "Couldn't add the tab.", kind: .error).glyph == "exclamationmark.circle")
    #expect(Toast(text: "Couldn't add the tab.", kind: .error).duration == .seconds(4))
    #expect(Toast(text: "Recovered", kind: .persistent).glyph == "exclamationmark.shield")
    #expect(Toast(text: "Recovered", kind: .persistent).duration == nil)
    #expect(Toast(text: "Recovered", kind: .persistent).isPersistent)
    #expect(Toast(text: "New Tab Created").glyph == nil)
    #expect(Toast(text: "New Tab Created").duration == .seconds(4))
    #expect(Toast(text: "Tab restored to Work", glyph: "arrow.counterclockwise").glyph == "arrow.counterclockwise")
    #expect(!Toast(text: "Archived 3 tabs", kind: .undo).isPersistent)
  }

  @Test func theTimerSleepsForTheToastsOwnLifetime() async {
    let recorder = DurationRecorder()
    let presenter = ToastPresenter(sleep: { duration in
      await recorder.record(duration)
      try await Task.sleep(for: .seconds(3600))
    })
    presenter.show(Toast(text: "Archived 3 tabs", kind: .undo))
    await recorder.waitForCount(1)
    presenter.show(Toast(text: "Pinned to Work"))
    await recorder.waitForCount(2)
    #expect(await recorder.durations == [.seconds(6), .seconds(4)])
  }

  @Test func aPausedToastStaysAndResumesAtFullLength() async {
    let recorder = DurationRecorder()
    let gate = AsyncStream<Void>.makeStream()
    let presenter = ToastPresenter(sleep: { duration in
      await recorder.record(duration)
      for await _ in gate.stream { return }
    })
    presenter.show(Toast(text: "Archived 3 tabs", kind: .undo))
    await recorder.waitForCount(1)
    presenter.setPaused(true, for: .hover)
    #expect(!presenter.isTimerArmedForTesting)
    presenter.setPaused(true, for: .windowInactive)
    presenter.setPaused(false, for: .hover)
    #expect(!presenter.isTimerArmedForTesting, "still paused while the window is not key")
    gate.continuation.yield()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current?.text == "Archived 3 tabs", "a cancelled timer never dismisses")
    presenter.setPaused(false, for: .windowInactive)
    #expect(presenter.isTimerArmedForTesting)
    await recorder.waitForCount(2)
    #expect(await recorder.durations == [.seconds(6), .seconds(6)])
    gate.continuation.yield()
    await presenter.waitForIdleForTesting()
    #expect(presenter.current == nil)
  }

  @Test func aToastShownWhilePausedWaitsForTheResume() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.setPaused(true, for: .windowInactive)
    presenter.show(Toast(text: "Archived 3 tabs", kind: .undo))
    #expect(!presenter.isTimerArmedForTesting)
    presenter.setPaused(false, for: .windowInactive)
    #expect(presenter.isTimerArmedForTesting)
  }

  @Test func dismissWhereTakesDownOnlyAMatchingToast() {
    let presenter = ToastPresenter(sleep: Self.forever)
    presenter.show(Toast(text: "Archived 3 tabs", kind: .undo))
    presenter.dismiss { $0.kind == .error }
    #expect(presenter.current?.kind == .undo)
    presenter.dismiss { $0.kind == .undo }
    #expect(presenter.current == nil)
  }

  @Test func theDismissButtonTakesAPersistentToastDown() {
    let presenter = ToastPresenter(sleep: Self.forever)
    var calls = 0
    presenter.show(Toast(text: "Recovered", kind: .persistent, actionTitle: "Show Files")) { calls += 1 }
    presenter.dismissFromButton()
    #expect(presenter.current == nil)
    #expect(calls == 0, "dismiss never runs the action")
  }
}

/// The post-install toast (#594, `design/extensions` `toast-pin`): "<name> added" with Pin, since new extensions are not
/// pinned (#590). Driven by InMemoryEngine's install events.
@MainActor
struct ExtensionInstallToastTests {
  private static let forever: ToastSleep = { _ in try await Task.sleep(for: .seconds(3600)) }
  private static let reader = InstalledExtension(id: "reader", name: "Quiet Reader")
  private static let readerAction = ExtensionAction(id: "reader", name: "Quiet Reader")

  private func make() -> (InMemoryEngine, ToastPresenter, ExtensionInstallToasts) {
    let engine = InMemoryEngine()
    let presenter = ToastPresenter(sleep: Self.forever)
    let toasts = ExtensionInstallToasts(extensions: engine) { presenter }
    return (engine, presenter, toasts)
  }

  @Test func anInstallShowsOneToastWithPin() {
    let (engine, presenter, toasts) = make()
    engine.installExtension(Self.reader, action: Self.readerAction)
    #expect(presenter.current?.text == "\u{201C}Quiet Reader\u{201D} added")
    #expect(presenter.current?.actionTitle == "Pin")
    #expect(presenter.current?.kind == .notice)
    #expect(presenter.current?.spokenText == "Quiet Reader added")
    withExtendedLifetime(toasts) {}
  }

  @Test func pinPinsTheExtensionAndDismisses() {
    let (engine, presenter, toasts) = make()
    engine.installExtension(Self.reader, action: Self.readerAction)
    presenter.performActionForTesting()
    #expect(engine.pinnedExtensionIDs == ["reader"])
    #expect(presenter.current == nil)
    withExtendedLifetime(toasts) {}
  }

  /// `.installed` may arrive after the `.extensionActionsChanged` that lists the action and its pin: an extension the
  /// engine already pinned gets the toast without a Pin action.
  @Test func anAlreadyPinnedExtensionGetsNoPinAction() {
    let (engine, presenter, toasts) = make()
    engine.installExtension(Self.reader, action: Self.readerAction, pinned: true)
    #expect(presenter.current?.text == "\u{201C}Quiet Reader\u{201D} added")
    #expect(presenter.current?.actionTitle == nil)
    withExtendedLifetime(toasts) {}
  }

  /// An extension without an action yet (its action may be announced later) still pins from the toast.
  @Test func pinWorksWhenTheActionIsNotListedYet() {
    let (engine, presenter, toasts) = make()
    engine.installExtension(Self.reader)
    #expect(presenter.current?.actionTitle == "Pin")
    presenter.performActionForTesting()
    #expect(engine.pinnedExtensionIDs == ["reader"])
    withExtendedLifetime(toasts) {}
  }

  @Test func eachInstallShowsItsOwnToast() {
    let (engine, presenter, toasts) = make()
    var shown: [String] = []
    engine.installExtension(Self.reader)
    shown.append(presenter.current?.text ?? "")
    engine.installExtension(InstalledExtension(id: "clips", name: "Clips"))
    shown.append(presenter.current?.text ?? "")
    #expect(shown == ["\u{201C}Quiet Reader\u{201D} added", "\u{201C}Clips\u{201D} added"])
    presenter.performActionForTesting()
    #expect(engine.pinnedExtensionIDs == ["clips"], "Pin acts on the toast's own extension")
    withExtendedLifetime(toasts) {}
  }

  /// A long name truncates inside the quotes, so "added" always shows; VoiceOver hears the whole name.
  @Test func aLongNameTruncatesAndIsSpokenWhole() {
    let name = String(repeating: "Reader Pro ", count: 8) + "Ultimate"
    let toast = ExtensionInstallToasts.toast(for: InstalledExtension(id: "x", name: name), isPinned: false)
    #expect(toast.text.hasSuffix("\u{2026}\u{201D} added"))
    #expect(toast.text.count <= ExtensionInstallToasts.nameLimit + "\u{201C}\u{201D} added".count)
    #expect(toast.spokenText == "\(name) added")
  }

  @Test func surroundingWhitespaceIsTrimmedAndAnEmptyNameIsGeneric() {
    #expect(ExtensionInstallToasts.toast(for: InstalledExtension(id: "x", name: "  Clips \n"), isPinned: false).text
            == "\u{201C}Clips\u{201D} added")
    let unnamed = ExtensionInstallToasts.toast(for: InstalledExtension(id: "x", name: " "), isPinned: false)
    #expect(unnamed.text == "Extension added")
    #expect(unnamed.spokenText == "Extension added")
  }

  @Test func noChromiumOrWindowMenuWording() {
    let toast = ExtensionInstallToasts.toast(for: Self.reader, isPinned: false)
    for word in ["Chromium", "Window menu", "Chrome"] {
      #expect(!toast.text.contains(word) && !toast.spokenText.contains(word))
    }
  }

  @Test func noPresenterNoToastAndNoCrash() {
    let engine = InMemoryEngine()
    let toasts = ExtensionInstallToasts(extensions: engine) { nil }
    engine.installExtension(Self.reader)
    #expect(engine.pinnedExtensionIDs.isEmpty)
    withExtendedLifetime(toasts) {}
  }

  /// Extensions a browser import installs show no toast each (the import has its own summary), and an import leaves a
  /// toast already up, such as that summary, in place.
  @Test func anImportInstallShowsNoToastAndLeavesTheSummaryUp() async {
    let (engine, presenter, toasts) = make()
    presenter.show(Toast(text: "Imported 2 extensions"))
    let ids = [String(repeating: "a", count: 32), String(repeating: "b", count: 32)]
    let results = await engine.installExtensionResults(ids: ids)
    #expect(results?.map(\.outcome) == [.installed, .installed])
    #expect(presenter.current?.text == "Imported 2 extensions")
    engine.installExtension(InstalledExtension(id: "c", name: "Clips", source: .browserImport))
    #expect(presenter.current?.text == "Imported 2 extensions")
    withExtendedLifetime(toasts) {}
  }

  @Test func anInstallDefaultsToTheUser() {
    #expect(InstalledExtension(id: "x", name: "X").source == .user)
  }

  @Test func otherExtensionEventsShowNothing() {
    let (engine, presenter, toasts) = make()
    engine.setExtensionCommands([])
    #expect(presenter.current == nil)
    withExtendedLifetime(toasts) {}
  }
}

/// Records each sleep's duration.
private actor DurationRecorder {
  private(set) var durations: [Duration] = []

  func record(_ duration: Duration) { durations.append(duration) }

  func waitForCount(_ count: Int) async {
    while durations.count < count { await Task.yield() }
  }
}

/// A sleeper whose sleeps end only when the test wakes them, oldest first. It ignores cancellation on purpose, so
/// the presenter's own guard against a replaced toast's timer is what the tests exercise.
private actor WakeQueueSleeper {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var registered = 0

  func sleep() async {
    await withCheckedContinuation { waiters.append($0); registered += 1 }
  }

  /// Returns once `count` sleeps in total have started.
  func waitForSleepers(_ count: Int) async {
    while registered < count { await Task.yield() }
  }

  func wakeOldest() {
    guard !waiters.isEmpty else { return }
    waiters.removeFirst().resume()
  }
}
