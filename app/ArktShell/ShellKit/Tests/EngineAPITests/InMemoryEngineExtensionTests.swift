import AppKit
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// Extension pin state, order, context menu, commands and install events (#591): the `EngineExtensions` defaults and
/// the InMemoryEngine behaviour the shell's extension surfaces build against (#595, #596, #597, #599).
@MainActor
struct InMemoryEngineExtensionTests {
  private func action(_ id: String, _ name: String, siteAccess: ExtensionSiteAccess = .noSiteAccess,
                      options: Bool = false) -> ExtensionAction {
    ExtensionAction(id: id, name: name, extensionID: id, hasOptionsPage: options, siteAccess: siteAccess)
  }

  private func engineWithActions(_ ids: [String] = ["a", "b", "c"]) -> (InMemoryEngine, EngineWindowID) {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    engine.setExtensionActions(ids.map { action($0, $0.uppercased()) }, in: window)
    return (engine, window)
  }

  private func listed(_ engine: InMemoryEngine, _ window: EngineWindowID) -> [String] {
    engine.extensionActions(in: window).map(\.id)
  }

  private func pinned(_ engine: InMemoryEngine, _ window: EngineWindowID) -> [String] {
    engine.extensionActions(in: window).filter(\.isPinned).map(\.id)
  }

  // MARK: - Values and defaults

  @Test func actionValuesAreAdditive() {
    let plain = ExtensionAction(id: "x", name: "X")
    #expect(plain.extensionID == "x")
    #expect(plain.isPinned == false)
    #expect(plain.hasOptionsPage == false)
    #expect(plain.siteAccess == .noSiteAccess)
    let full = ExtensionAction(id: "act", name: "N", extensionID: "ext", isPinned: true, hasOptionsPage: true,
                               siteAccess: .onAllSites)
    #expect(full.extensionID == "ext" && full.isPinned && full.hasOptionsPage && full.siteAccess == .onAllSites)
  }

  @Test func defaultsAreInertForAnEngineWithOnlyActions() {
    let engine = ActionsOnlyEngine()
    let window = EngineWindowID()
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    engine.setExtensionPinned("a", pinned: true)
    engine.movePinnedExtension("a", to: 0)
    engine.performExtensionContextCommand(ExtensionContextCommand.togglePin, forAction: "a", in: window)
    #expect(engine.pinnedExtensionIDs.isEmpty)
    #expect(engine.extensionContextMenu(forAction: "a", in: window).isEmpty)
    #expect(engine.extensionCommands.isEmpty)
    let id = ExtensionCommandID(extensionID: "a", name: "run")
    #expect(engine.setExtensionCommandShortcut(id, to: nil, scope: .inApp, replacingConflict: false) == .unknownCommand)
    #expect(events.isEmpty)
    token.cancel()
  }

  // MARK: - Pin and order

  @Test func pinAppendsToThePinnedOrderAndListsPinnedFirst() {
    let (engine, window) = engineWithActions()
    let recorder = EventRecorder(engine)
    engine.setExtensionPinned("c", pinned: true)
    engine.setExtensionPinned("a", pinned: true)
    #expect(engine.pinnedExtensionIDs == ["c", "a"])
    #expect(listed(engine, window) == ["c", "a", "b"])
    #expect(pinned(engine, window) == ["c", "a"])
    #expect(recorder.windowEvents == [.extensionActionsChanged(window), .extensionActionsChanged(window)])
  }

  @Test func pinningAPinnedExtensionReportsNothing() {
    let (engine, window) = engineWithActions()
    engine.setExtensionPinned("a", pinned: true)
    let recorder = EventRecorder(engine)
    engine.setExtensionPinned("a", pinned: true)
    engine.setExtensionPinned("b", pinned: false)
    #expect(recorder.windowEvents.isEmpty)
    #expect(pinned(engine, window) == ["a"])
  }

  @Test func unpinRemovesFromTheOrderAndKeepsTheRest() {
    let (engine, window) = engineWithActions()
    for id in ["a", "b", "c"] { engine.setExtensionPinned(id, pinned: true) }
    engine.setExtensionPinned("b", pinned: false)
    #expect(engine.pinnedExtensionIDs == ["a", "c"])
    #expect(listed(engine, window) == ["a", "c", "b"])
    #expect(engine.extensionActions(in: window).first { $0.id == "b" }?.isPinned == false)
  }

  @Test func moveAtBothEnds() {
    let (engine, window) = engineWithActions()
    for id in ["a", "b", "c"] { engine.setExtensionPinned(id, pinned: true) }
    let recorder = EventRecorder(engine)

    engine.movePinnedExtension("c", to: 0)
    #expect(engine.pinnedExtensionIDs == ["c", "a", "b"])
    engine.movePinnedExtension("c", to: 2)
    #expect(engine.pinnedExtensionIDs == ["a", "b", "c"])
    #expect(recorder.windowEvents.count == 2)

    // Past either end clamps; already there reports nothing.
    engine.movePinnedExtension("a", to: -5)
    engine.movePinnedExtension("c", to: 99)
    #expect(engine.pinnedExtensionIDs == ["a", "b", "c"])
    #expect(recorder.windowEvents.count == 2)

    engine.movePinnedExtension("a", to: 99)
    #expect(engine.pinnedExtensionIDs == ["b", "c", "a"])
    #expect(listed(engine, window) == ["b", "c", "a"])
  }

  @Test func movingAnUnpinnedOrUnknownExtensionDoesNothing() {
    let (engine, _) = engineWithActions()
    engine.setExtensionPinned("a", pinned: true)
    let recorder = EventRecorder(engine)
    engine.movePinnedExtension("b", to: 0)
    engine.movePinnedExtension("missing", to: 0)
    #expect(engine.pinnedExtensionIDs == ["a"])
    #expect(recorder.windowEvents.isEmpty)
  }

  @Test func pinsAreProfileWideAndOutliveWindows() {
    let (engine, first) = engineWithActions()
    engine.setExtensionPinned("b", pinned: true)
    engine.setExtensionPinned("a", pinned: true)
    let second = engine.createWindow(host: StubWindowHost())
    let recorder = EventRecorder(engine)
    engine.setExtensionActions(["a", "b", "c"].map { action($0, $0) }, in: second)
    #expect(listed(engine, second) == ["b", "a", "c"])

    engine.setExtensionPinned("c", pinned: true)
    #expect(recorder.windowEvents.filter { $0 != .extensionActionsChanged(second) }
            == [.extensionActionsChanged(first)])

    engine.closeWindow(first)
    let third = engine.createWindow(host: StubWindowHost())
    engine.setExtensionActions(["c", "b", "a"].map { action($0, $0) }, in: third)
    #expect(pinned(engine, third) == ["b", "a", "c"])
  }

  @Test func driverActionsMarkedPinnedSeedTheOrderOnce() {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let list = [ExtensionAction(id: "a", name: "A"), ExtensionAction(id: "b", name: "B", isPinned: true)]
    engine.setExtensionActions(list, in: window)
    #expect(engine.pinnedExtensionIDs == ["b"])
    engine.setExtensionPinned("b", pinned: false)
    engine.setExtensionActions(list, in: window)
    #expect(engine.pinnedExtensionIDs.isEmpty)
  }

  // MARK: - Context menu

  @Test func contextMenuOfAnUnpinnedActionWithSiteAccess() throws {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    engine.createTab(url: URL(string: "https://news.example.com/a"), in: window)
    engine.setExtensionActions([action("a", "Alpha", siteAccess: .onClick, options: true)], in: window)

    let menu = engine.extensionContextMenu(forAction: "a", in: window)
    #expect(menu.map(\.title) == ["Alpha", "Options...", "Pin to Sidebar", "This Can Read and Change Site Data", "",
                                  "Manage Extension...", "Remove from Arkt..."])
    #expect(menu[0].isEnabled == false && menu[0].command == ExtensionContextCommand.header)
    #expect(menu[1].isEnabled && menu[1].command == ExtensionContextCommand.options)
    #expect(menu[2].command == ExtensionContextCommand.togglePin)
    #expect(menu[4].isSeparator)
    let access = menu[3].submenu ?? []
    #expect(access.map(\.title) == ["When You Click the Extension", "On news.example.com", "On All Sites"])
    #expect(access.map(\.isChecked) == [true, false, false])
    #expect(access.map(\.command) == [ExtensionContextCommand.siteAccessOnClick,
                                      ExtensionContextCommand.siteAccessOnThisSite,
                                      ExtensionContextCommand.siteAccessOnAllSites])
  }

  @Test func contextMenuOfPinnedActionsDisablesMovesAtTheEnds() {
    let (engine, window) = engineWithActions()
    for id in ["a", "b", "c"] { engine.setExtensionPinned(id, pinned: true) }
    func moves(_ id: String) -> [Bool] {
      engine.extensionContextMenu(forAction: id, in: window)
        .filter { $0.title == "Move Left" || $0.title == "Move Right" }.map(\.isEnabled)
    }
    #expect(moves("a") == [false, true])
    #expect(moves("b") == [true, true])
    #expect(moves("c") == [true, false])
    let menu = engine.extensionContextMenu(forAction: "a", in: window)
    #expect(menu.contains { $0.title == "Unpin from Sidebar" })
    #expect(menu.first { $0.title == "Options..." }?.isEnabled == false)
    #expect(!menu.contains { $0.title == "This Can Read and Change Site Data" })
    #expect(engine.extensionContextMenu(forAction: "missing", in: window).isEmpty)
  }

  @Test func contextCommandsPinMoveAndSetSiteAccess() {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    engine.setExtensionActions([action("a", "A", siteAccess: .onClick, options: true), action("b", "B")], in: window)
    let run = { (command: EngineMenuCommand, id: String) in
      engine.performExtensionContextCommand(command, forAction: id, in: window)
    }
    typealias C = ExtensionContextCommand
    run(C.togglePin, "a")
    run(C.togglePin, "b")
    #expect(engine.pinnedExtensionIDs == ["a", "b"])
    run(C.moveLeft, "b")
    #expect(engine.pinnedExtensionIDs == ["b", "a"])
    run(C.moveRight, "b")
    #expect(engine.pinnedExtensionIDs == ["a", "b"])
    run(C.togglePin, "a")
    #expect(engine.pinnedExtensionIDs == ["b"])

    let recorder = EventRecorder(engine)
    run(C.siteAccessOnAllSites, "a")
    #expect(engine.extensionActions(in: window).first { $0.id == "a" }?.siteAccess == .onAllSites)
    #expect(recorder.windowEvents == [.extensionActionsChanged(window)])

    run(C.options, "a")
    run(C.manage, "a")
    run(C.remove, "a")
    run(C.options, "missing")
    #expect(engine.performedExtensionContextCommands.map(\.command).suffix(3) == [C.options, C.manage, C.remove])
    #expect(engine.performedExtensionContextCommands.allSatisfy { $0.actionID != "missing" })
  }

  // MARK: - Commands

  private func commandsEngine() -> InMemoryEngine {
    let engine = InMemoryEngine()
    engine.setExtensionCommands([
      ExtensionCommand(id: ExtensionCommandID(extensionID: "a", name: "open"), extensionName: "A",
                       description: "Open A",
                       shortcut: ExtensionShortcut(key: .letter(.e), modifiers: [.command, .shift])),
      ExtensionCommand(id: ExtensionCommandID(extensionID: "b", name: "save"), extensionName: "B",
                       description: "Save page"),
    ])
    return engine
  }

  @Test func commandsDefaultToTheAppScope() {
    let engine = commandsEngine()
    #expect(engine.extensionCommands.map(\.scope) == [.inApp, .inApp])
    #expect(engine.extensionCommands.map(\.id.name) == ["open", "save"])
  }

  @Test func settingAShortcutAndScopeReportsCommandsChanged() {
    let engine = commandsEngine()
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    let save = ExtensionCommandID(extensionID: "b", name: "save")
    let shortcut = ExtensionShortcut(key: .letter(.s), modifiers: [.option, .shift])
    #expect(engine.setExtensionCommandShortcut(save, to: shortcut, scope: .global, replacingConflict: false)
            == .applied)
    let command = engine.extensionCommands.first { $0.id == save }
    #expect(command?.shortcut == shortcut && command?.scope == .global)
    #expect(events == [.commandsChanged])

    // The same values again: applied, nothing reported. Clearing keeps the scope.
    #expect(engine.setExtensionCommandShortcut(save, to: shortcut, scope: .global, replacingConflict: false)
            == .applied)
    #expect(events == [.commandsChanged])
    #expect(engine.setExtensionCommandShortcut(save, to: nil, scope: .global, replacingConflict: false) == .applied)
    #expect(engine.extensionCommands.first { $0.id == save }?.shortcut == nil)
    #expect(events == [.commandsChanged, .commandsChanged])
    token.cancel()
  }

  @Test func conflictIsReportedWithoutAChange() {
    let engine = commandsEngine()
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    let open = ExtensionCommandID(extensionID: "a", name: "open")
    let save = ExtensionCommandID(extensionID: "b", name: "save")
    let taken = ExtensionShortcut(key: .letter(.e), modifiers: [.shift, .command])
    #expect(engine.setExtensionCommandShortcut(save, to: taken, scope: .inApp, replacingConflict: false)
            == .conflict(with: open))
    #expect(engine.extensionCommands.first { $0.id == save }?.shortcut == nil)
    #expect(engine.extensionCommands.first { $0.id == open }?.shortcut == taken)
    #expect(events.isEmpty)

    // A different scope still conflicts: one key, one command.
    #expect(engine.setExtensionCommandShortcut(save, to: taken, scope: .global, replacingConflict: false)
            == .conflict(with: open))
    // Setting a command's own shortcut is not a conflict.
    #expect(engine.setExtensionCommandShortcut(open, to: taken, scope: .inApp, replacingConflict: false) == .applied)
    token.cancel()
  }

  @Test func replacingAConflictMovesTheShortcut() {
    let engine = commandsEngine()
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    let open = ExtensionCommandID(extensionID: "a", name: "open")
    let save = ExtensionCommandID(extensionID: "b", name: "save")
    let taken = ExtensionShortcut(key: .letter(.e), modifiers: [.command, .shift])
    #expect(engine.setExtensionCommandShortcut(save, to: taken, scope: .inApp, replacingConflict: true) == .applied)
    #expect(engine.extensionCommands.first { $0.id == save }?.shortcut == taken)
    #expect(engine.extensionCommands.first { $0.id == open }?.shortcut == nil)
    #expect(events == [.commandsChanged])
    token.cancel()
  }

  @Test func unknownCommandIsReported() {
    let engine = commandsEngine()
    let missing = ExtensionCommandID(extensionID: "z", name: "nope")
    #expect(engine.setExtensionCommandShortcut(missing, to: nil, scope: .inApp, replacingConflict: false)
            == .unknownCommand)
  }

  @Test func shortcutKeysAreTheUnshiftedBaseKey() throws {
    // Cmd-Shift-2: key code kVK_ANSI_2 (0x13) types "@" on a US layout; the shortcut is still 2 with Shift.
    let fromKeyCode = ExtensionShortcut(key: try #require(.init(keyCode: 0x13)), modifiers: [.command, .shift])
    let fromCharacter = ExtensionShortcut(key: try #require(.init(character: "2")), modifiers: [.command, .shift])
    #expect(fromKeyCode == fromCharacter)
    #expect(fromKeyCode.key == .digit(.two))
    #expect(ExtensionShortcut.Key(character: "@") == nil)
    #expect(ExtensionShortcut.Key(character: "E") == .letter(.e))
    #expect(ExtensionShortcut.Key(keyCode: 0x0E) == .letter(.e))
    #expect(ExtensionShortcut.Key(keyCode: 0x7E) == .up)
    #expect(ExtensionShortcut.Key(keyCode: 0x30) == .tab)
    #expect(ExtensionShortcut.Key(keyCode: 0x7A) == nil)  // F1: not a command key
    #expect(ExtensionShortcut.Key(keyCode: 0x35) == nil)  // Escape
    #expect(ExtensionShortcut(key: .letter(.e), modifiers: .command)
            != ExtensionShortcut(key: .letter(.e), modifiers: .control))
  }

  @Test func forbiddenShortcutsAreRejectedWithoutAChange() {
    let engine = commandsEngine()
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    let save = ExtensionCommandID(extensionID: "b", name: "save")
    func set(_ key: ExtensionShortcut.Key, _ modifiers: ExtensionShortcut.Modifiers,
             _ scope: ExtensionCommandScope = .inApp) -> ExtensionShortcutResult {
      engine.setExtensionCommandShortcut(save, to: ExtensionShortcut(key: key, modifiers: modifiers), scope: scope,
                                         replacingConflict: false)
    }
    #expect(set(.letter(.k), []) == .rejected(.notAllowed))
    #expect(set(.letter(.k), .shift) == .rejected(.notAllowed))
    #expect(set(.letter(.k), [.control, .option]) == .rejected(.notAllowed))
    #expect(set(.letter(.k), [.command, .option]) == .rejected(.notAllowed))
    #expect(set(.mediaPlayPause, .command) == .rejected(.notAllowed))
    engine.heldGlobalShortcuts = [ExtensionShortcut(key: .letter(.k), modifiers: [.command, .shift])]
    #expect(set(.letter(.k), [.command, .shift], .global) == .rejected(.globalShortcutTaken))
    #expect(engine.extensionCommands.first { $0.id == save }?.shortcut == nil)
    #expect(events.isEmpty)

    #expect(set(.mediaPlayPause, []) == .applied)
    #expect(set(.letter(.k), [.command, .shift]) == .applied)
    #expect(set(.letter(.k), [.option]) == .applied)
    #expect(set(.tab, [.option, .shift]) == .applied)
    token.cancel()
  }

  @Test func mediaKeysAreRejectedOnActionCommands() {
    let engine = InMemoryEngine()
    let names = ["_execute_action", "_execute_browser_action", "_execute_page_action"]
    engine.setExtensionCommands(names.map {
      ExtensionCommand(id: ExtensionCommandID(extensionID: "a", name: $0), extensionName: "A", description: $0)
    })
    for name in names {
      let id = ExtensionCommandID(extensionID: "a", name: name)
      #expect(engine.setExtensionCommandShortcut(id, to: ExtensionShortcut(key: .mediaStop, modifiers: []),
                                                 scope: .inApp, replacingConflict: false) == .rejected(.notAllowed))
    }
    let action = ExtensionCommandID(extensionID: "a", name: "_execute_action")
    #expect(engine.setExtensionCommandShortcut(action, to: ExtensionShortcut(key: .letter(.y), modifiers: .command),
                                               scope: .inApp, replacingConflict: false) == .applied)
  }

  @Test func scopeAloneChangesWithNoShortcut() {
    let engine = commandsEngine()
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    let save = ExtensionCommandID(extensionID: "b", name: "save")
    #expect(engine.setExtensionCommandShortcut(save, to: nil, scope: .global, replacingConflict: false) == .applied)
    let command = engine.extensionCommands.first { $0.id == save }
    #expect(command?.shortcut == nil && command?.scope == .global)
    #expect(events == [.commandsChanged])
    token.cancel()
  }

  @Test func replacingWithTheCommandsOwnShortcutChangesNothing() {
    let engine = commandsEngine()
    let before = engine.extensionCommands
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    let open = ExtensionCommandID(extensionID: "a", name: "open")
    let own = ExtensionShortcut(key: .letter(.e), modifiers: [.command, .shift])
    #expect(engine.setExtensionCommandShortcut(open, to: own, scope: .inApp, replacingConflict: true) == .applied)
    #expect(engine.extensionCommands == before)
    #expect(events.isEmpty)
    token.cancel()
  }

  // MARK: - Install events

  @Test func installReportsTheExtensionAndPinsWhenAsked() {
    let (engine, window) = engineWithActions(["a", "b"])
    var events: [EngineExtensionEvent] = []
    let token = engine.observeExtensions { events.append($0) }
    let recorder = EventRecorder(engine)
    let info = InstalledExtension(id: "b", name: "Beta", iconPNG: Data([7]))
    engine.installExtension(info, pinned: true)
    #expect(events == [.installed(info)])
    #expect(engine.pinnedExtensionIDs == ["b"])
    #expect(recorder.windowEvents == [.extensionActionsChanged(window)])

    let other = InstalledExtension(id: "c", name: "Gamma")
    engine.installExtension(other)
    #expect(events == [.installed(info), .installed(other)])
    #expect(engine.pinnedExtensionIDs == ["b"])
    token.cancel()
  }

  @Test func installAddsTheActionBeforeReportingInstalled() {
    let engine = InMemoryEngine()
    let first = engine.createWindow(host: StubWindowHost())
    let second = engine.createWindow(host: StubWindowHost())
    var log: [String] = []
    let windows = engine.observeWindows {
      if case .extensionActionsChanged(let window) = $0 { log.append(window == first ? "first" : "second") }
    }
    let extensions = engine.observeExtensions { if case .installed = $0 { log.append("installed") } }
    let info = InstalledExtension(id: "n", name: "New")
    engine.installExtension(info, action: action("n", "New"), pinned: true)
    #expect(log == ["first", "second", "installed"])
    #expect(pinned(engine, first) == ["n"] && pinned(engine, second) == ["n"])
    windows.cancel(); extensions.cancel()
  }

  @Test func pinningAnExtensionTheEngineNeverSawDoesNothing() {
    let (engine, _) = engineWithActions()
    let recorder = EventRecorder(engine)
    engine.setExtensionPinned("never-seen", pinned: true)
    #expect(engine.pinnedExtensionIDs.isEmpty)
    #expect(recorder.windowEvents.isEmpty)
  }

  @Test func extensionEventsShareTheEngineQueue() {
    let (engine, window) = engineWithActions(["a"])
    var log: [String] = []
    let windows = engine.observeWindows { if case .extensionActionsChanged = $0 { log.append("actions") } }
    let extensions = engine.observeExtensions { event in
      log.append("installed")
      if case .installed(let info) = event { engine.setExtensionPinned(info.id, pinned: true) }
      log.append("handler done")
    }
    engine.installExtension(InstalledExtension(id: "a", name: "A"))
    #expect(log == ["installed", "handler done", "actions"])
    #expect(pinned(engine, window) == ["a"])
    windows.cancel(); extensions.cancel()
  }
}

/// An engine that implements only the two required `EngineExtensions` members.
@MainActor
private final class ActionsOnlyEngine: EngineExtensions {
  func extensionActions(in window: EngineWindowID) -> [ExtensionAction] { [] }
  func runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView) {}
}
