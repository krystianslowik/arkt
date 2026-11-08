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

  private func event(_ characters: String, keyCode: UInt16,
                     modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                  timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                                  charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
  }
}
