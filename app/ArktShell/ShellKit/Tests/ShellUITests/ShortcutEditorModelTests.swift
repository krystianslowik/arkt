import AppKit
import Foundation
import Testing
@testable import ShellUI

/// The editor stores only deviations from its catalog, including an explicitly cleared shortcut.
@MainActor
struct ShortcutEditorModelTests {
  private final class Suite {
    let name = "dev.arkt.tests.shortcuts.\(UUID().uuidString)"
    let defaults: UserDefaults
    init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
    deinit { UserDefaults().removePersistentDomain(forName: name) }
  }

  private let newTab = ShortcutActionID("newTab")
  private let sidebar = ShortcutActionID("showSidebar")
  private let commandT = ShortcutBinding(key: "t", modifiers: .command)
  private let commandS = ShortcutBinding(key: "s", modifiers: .command)
  private let commandE = ShortcutBinding(key: "e", modifiers: .command)

  private func catalog() -> [ShortcutDefinition] {
    [ShortcutDefinition(id: newTab, title: "New Tab", defaultBinding: commandT),
     ShortcutDefinition(id: sidebar, title: "Show Sidebar", defaultBinding: commandS)]
  }

  @Test func overridesAndClearsSurviveReloadAndResetOne() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(store.binding(for: newTab) == commandT)
    #expect(store.overrides.isEmpty)
    store.setBinding(commandE, for: newTab)
    store.setBinding(nil, for: sidebar)

    let reloaded = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(reloaded.binding(for: newTab) == commandE)
    #expect(reloaded.binding(for: sidebar) == nil)
    #expect(reloaded.overrides.count == 2)
    reloaded.reset(newTab)
    #expect(reloaded.binding(for: newTab) == commandT)
    #expect(reloaded.binding(for: sidebar) == nil)
    #expect(reloaded.overrides.count == 1)
    let again = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(again.binding(for: newTab) == commandT)
    #expect(again.binding(for: sidebar) == nil)
  }

  @Test func resetAllRestoresDefaultsAndRemovesOverrides() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    store.setBinding(commandE, for: newTab)
    store.setBinding(nil, for: sidebar)
    store.resetAll()
    let reloaded = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(reloaded.binding(for: newTab) == commandT)
    #expect(reloaded.binding(for: sidebar) == commandS)
    #expect(reloaded.overrides.isEmpty)
  }

  @Test func recordingCancelClearAndConflictChoices() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    store.beginRecording(newTab)
    store.record(event: try event("e", keyCode: 14, modifiers: .command))
    #expect(store.binding(for: newTab) == commandE)
    store.beginRecording(newTab)
    store.record(event: try event("\u{1b}", keyCode: 53))
    #expect(store.binding(for: newTab) == commandE)
    store.beginRecording(newTab)
    store.record(event: try event("\u{7f}", keyCode: 51))
    #expect(store.binding(for: newTab) == nil)
    store.beginRecording(newTab)
    store.record(event: try event("s", keyCode: 1, modifiers: .command))
    #expect(store.conflictingActions == [sidebar])
    store.keepExisting()
    #expect(store.binding(for: newTab) == nil)
    #expect(store.binding(for: sidebar) == commandS)
    store.beginRecording(newTab)
    store.record(event: try event("s", keyCode: 1, modifiers: .command))
    store.useRecordedShortcut()
    #expect(store.binding(for: newTab) == commandS)
    #expect(store.binding(for: sidebar) == nil)
    let reloaded = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(reloaded.binding(for: newTab) == commandS)
    #expect(reloaded.binding(for: sidebar) == nil)
  }

  @Test func multipleConflictsAreExplicitlyClearedAndPersisted() throws {
    let suite = try Suite()
    let third = ShortcutActionID("third")
    let definitions = catalog() + [ShortcutDefinition(id: third, title: "Third", defaultBinding: commandS)]
    let store = ShortcutEditorModel(catalog: definitions, defaults: suite.defaults)
    store.beginRecording(newTab)
    store.record(event: try event("s", keyCode: 1, modifiers: .command))
    #expect(store.conflictingActions == [sidebar, third])
    store.useRecordedShortcut()
    #expect(store.overrides[sidebar] == .cleared)
    #expect(store.overrides[third] == .cleared)
    let reloaded = ShortcutEditorModel(catalog: definitions, defaults: suite.defaults)
    #expect(reloaded.binding(for: newTab) == commandS)
    #expect(reloaded.binding(for: sidebar) == nil)
    #expect(reloaded.binding(for: third) == nil)
  }

  @Test func cancellationAndUnknownActionsCannotApplyPendingBinding() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    store.useRecordedShortcut()
    store.beginRecording(newTab)
    store.record(event: try event("s", keyCode: 1, modifiers: .command))
    store.cancelRecording()
    store.useRecordedShortcut()
    #expect(store.conflictingActions.isEmpty)
    #expect(store.binding(for: newTab) == commandT)
    let unknown = ShortcutActionID("unknown")
    store.setBinding(commandS, for: unknown)
    store.beginRecording(unknown)
    store.record(event: try event("e", keyCode: 14, modifiers: .command))
    #expect(store.binding(for: unknown) == nil)
    #expect(store.overrides.isEmpty)
  }

  @Test func malformedStorageAndEventFlagsAreHandled() throws {
    let suite = try Suite()
    suite.defaults.set(Data("not json".utf8), forKey: "shortcutOverrides")
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(store.binding(for: sidebar) == commandS)
    store.beginRecording(newTab)
    store.record(event: try event("E", keyCode: 14, modifiers: [.command, .shift, .capsLock, .numericPad]))
    #expect(store.binding(for: newTab) == ShortcutBinding(key: "e", modifiers: [.command, .shift]))
    let reloaded = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(reloaded.binding(for: newTab) == store.binding(for: newTab))
  }

  @Test func resettingAReassignedDefaultUsesTheConflictChoices() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    store.beginRecording(sidebar)
    store.record(event: try event("t", keyCode: 17, modifiers: .command))
    store.useRecordedShortcut()
    #expect(store.binding(for: newTab) == nil)
    #expect(store.binding(for: sidebar) == commandT)

    store.reset(newTab)
    #expect(store.conflictingActions == [sidebar])
    #expect(store.binding(for: newTab) == nil)
    #expect(store.binding(for: sidebar) == commandT)
    let unanswered = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(unanswered.binding(for: newTab) == nil)
    store.keepExisting()
    #expect(store.binding(for: newTab) == nil)

    store.reset(newTab)
    store.useRecordedShortcut()
    let reloaded = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(reloaded.binding(for: newTab) == commandT)
    #expect(reloaded.binding(for: sidebar) == nil)
    #expect(reloaded.overrides[newTab] == nil)
    #expect(reloaded.overrides[sidebar] == .cleared)
  }

  @Test func malformedEntriesDoNotDiscardValidOverrides() throws {
    let suite = try Suite()
    let saved = Data(#"""
      {"newTab":{"key":"e","modifiers":1048576},
       "showSidebar":{"key":42,"modifiers":1048576},
       "unknown":{"key":false,"modifiers":"invalid"}}
      """#.utf8)
    suite.defaults.set(saved, forKey: "shortcutOverrides")
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(store.binding(for: newTab) == commandE)
    #expect(store.binding(for: sidebar) == commandS)
    store.setBinding(nil, for: sidebar)
    let reloaded = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(reloaded.binding(for: newTab) == commandE)
    #expect(reloaded.binding(for: sidebar) == nil)
  }

  // MARK: Key rules (#828 review, maintainer decision 2026-11-16)

  /// A binding needs Command or Control, bare F1 ... F20 aside: a bare key, Shift or Option alone would take typing
  /// (Return, letters, accented Option letters) from every text field and page once the menu routes it first.
  @Test func keysWithoutCommandOrControlAreRejectedAndRecordingContinues() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    let cases: [(String, UInt16, NSEvent.ModifierFlags, ShortcutEditorModel.Rejection)] = [
      ("\r", 36, [], .confirmOrFocusKey), ("k", 40, [], .needsCommandOrControl),
      ("K", 40, .shift, .needsCommandOrControl), ("\u{105}", 0, .option, .needsCommandOrControl),
    ]
    for (characters, code, flags, reason) in cases {
      store.beginRecording(newTab)
      store.record(event: try event(characters, keyCode: code, modifiers: flags))
      #expect(store.rejection == reason, "\(code)")
      #expect(store.recordingAction == newTab, "recording goes on after a rejected key")
      #expect(store.binding(for: newTab) == commandT)
      #expect(store.overrides.isEmpty)
    }
    store.record(event: try event("e", keyCode: 14, modifiers: .command))
    #expect(store.rejection == nil)
    #expect(store.binding(for: newTab) == commandE)
  }

  /// Text fields own these: Cmd and Opt with an arrow or Delete move and delete by line and word, Ctrl-A / E / K and
  /// the other Emacs keys edit, and Return, Tab and Escape confirm, move focus and cancel, with any modifier.
  @Test func textEditingAndConfirmKeysAreRejected() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!), up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    let forwardDelete = String(UnicodeScalar(NSDeleteFunctionKey)!)
    let editing: [(String, UInt16, NSEvent.ModifierFlags)] = [
      (left, 123, .command), (left, 123, [.command, .shift]), (up, 126, .option), ("\u{7f}", 51, .command),
      ("\u{7f}", 51, .option), (forwardDelete, 117, .option), ("a", 0, .control), ("e", 14, .control),
      ("k", 40, .control), ("h", 4, [.control, .shift]),
    ]
    for (characters, code, flags) in editing {
      store.beginRecording(newTab)
      store.record(event: try event(characters, keyCode: code, modifiers: flags))
      #expect(store.rejection == .textEditing, "\(code) \(flags.rawValue)")
      #expect(store.binding(for: newTab) == commandT)
    }
    for (characters, code, flags) in [("\r", UInt16(36), NSEvent.ModifierFlags.command), ("\t", 48, .control),
                                      ("\u{1b}", 53, .command)] {
      store.beginRecording(newTab)
      store.record(event: try event(characters, keyCode: code, modifiers: flags))
      #expect(store.rejection == .confirmOrFocusKey, "\(code)")
    }
    #expect(store.overrides.isEmpty)
  }

  /// Allowed: bare F1 ... F20, Cmd-Opt with an arrow (Next Space's own keys), Ctrl with a letter outside the Emacs set.
  @Test func functionKeysAndCommandOrControlCombinationsAreAccepted() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    let f5 = String(UnicodeScalar(NSF5FunctionKey)!), f20 = String(UnicodeScalar(NSF20FunctionKey)!)
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    for (characters, code, flags) in [(f5, UInt16(96), NSEvent.ModifierFlags()), (f20, 90, []),
                                      (right, 124, [.command, .option]), ("j", 38, .control),
                                      ("k", 40, [.control, .option])] {
      store.beginRecording(newTab)
      store.record(event: try event(characters, keyCode: code, modifiers: flags))
      #expect(store.rejection == nil, "\(code)")
      #expect(store.binding(for: newTab) == ShortcutBinding(key: characters, modifiers: flags), "\(code)")
    }
  }

  /// Delete clears only when pressed alone; Escape alone cancels.
  @Test func bareDeleteClearsAndBareEscapeCancels() throws {
    let suite = try Suite()
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    store.beginRecording(newTab)
    store.record(event: try event("\u{1b}", keyCode: 53))
    #expect(store.recordingAction == nil && store.rejection == nil)
    store.beginRecording(newTab)
    store.record(event: try event(String(UnicodeScalar(NSDeleteFunctionKey)!), keyCode: 117))
    #expect(store.binding(for: newTab) == nil && store.overrides[newTab] == .cleared)
  }

  // MARK: Storage

  /// Entries for actions this build does not list (a newer build's #946 catalog) survive this build's saves.
  @Test func overridesForUnknownActionsSurviveASave() throws {
    let suite = try Suite()
    let future = #"{"futureAction":{"key":"j","modifiers":1048576},"newTab":{"key":"e","modifiers":1048576}}"#
    suite.defaults.set(Data(future.utf8), forKey: "shortcutOverrides")
    let store = ShortcutEditorModel(catalog: catalog(), defaults: suite.defaults)
    #expect(store.binding(for: newTab) == commandE)
    store.setBinding(commandS, for: newTab)
    store.reset(newTab)
    let data = try #require(suite.defaults.data(forKey: "shortcutOverrides"))
    let saved = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
    #expect(saved.keys.sorted() == ["futureAction"])
    #expect(saved["futureAction"]?["key"] as? String == "j")
    store.resetAll()
    #expect(suite.defaults.data(forKey: "shortcutOverrides") == nil, "Reset All clears every saved shortcut")
  }

  /// Use Shortcut clears a conflicting action through the same path as Delete: an action whose default is no
  /// shortcut stores nothing, so Reset All does not light up for a non-deviation.
  @Test func usingAShortcutTakenFromAnUnboundDefaultStoresNoOverride() throws {
    let suite = try Suite()
    let spare = ShortcutActionID("spare")
    let definitions = catalog() + [ShortcutDefinition(id: spare, title: "Spare", defaultBinding: nil)]
    let store = ShortcutEditorModel(catalog: definitions, defaults: suite.defaults)
    store.setBinding(commandE, for: spare)
    store.beginRecording(newTab)
    store.record(event: try event("e", keyCode: 14, modifiers: .command))
    store.useRecordedShortcut()
    #expect(store.binding(for: newTab) == commandE)
    #expect(store.binding(for: spare) == nil)
    #expect(store.overrides[spare] == nil)
  }

  private func event(_ characters: String, keyCode: UInt16,
                     modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                  timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
  }
}
