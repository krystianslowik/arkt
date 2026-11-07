import EngineAPI
import Foundation

// Extension pin state, order, context menu, commands and install events for the in-memory engine (#591). The actions
// of a window come from the `setExtensionActions` driver; pins and commands are profile-wide and outlive windows.

extension InMemoryEngine {
  // MARK: - Pin state and order

  public func setExtensionPinned(_ extensionID: String, pinned: Bool) {
    guard knownExtensionIDs.contains(extensionID), pinnedExtensionIDs.contains(extensionID) != pinned else { return }
    if pinned { pinnedExtensionIDs.append(extensionID) } else { pinnedExtensionIDs.removeAll { $0 == extensionID } }
    announceActions(of: extensionID)
  }

  public func movePinnedExtension(_ extensionID: String, to index: Int) {
    guard let from = pinnedExtensionIDs.firstIndex(of: extensionID) else { return }
    let to = min(max(index, 0), pinnedExtensionIDs.count - 1)
    guard to != from else { return }
    pinnedExtensionIDs.remove(at: from)
    pinnedExtensionIDs.insert(extensionID, at: to)
    announceActions(of: extensionID)
  }

  /// `list` with `isPinned` from the profile, pinned actions first in pin order, the rest in their own order.
  func inPinOrder(_ list: [ExtensionAction]) -> [ExtensionAction] {
    let marked = list.map { action in
      var action = action
      action.isPinned = pinnedExtensionIDs.contains(action.extensionID)
      return action
    }
    let pinned = pinnedExtensionIDs.flatMap { id in marked.filter { $0.extensionID == id } }
    return pinned + marked.filter { !$0.isPinned }
  }

  /// A driver action marked `isPinned` pins its extension the first time the engine sees that extension, as a
  /// profile's stored pins would; after that the profile's pin state wins.
  func seedPins(from list: [ExtensionAction]) {
    for action in list where !knownExtensionIDs.contains(action.extensionID) {
      knownExtensionIDs.insert(action.extensionID)
      if action.isPinned, !pinnedExtensionIDs.contains(action.extensionID) {
        pinnedExtensionIDs.append(action.extensionID)
      }
    }
  }

  /// `.extensionActionsChanged` for each window that lists an action of the extension.
  private func announceActions(of extensionID: String) {
    for window in windowIDs where actions[window]?.contains(where: { $0.extensionID == extensionID }) == true {
      hub.emit(.extensionActionsChanged(window))
    }
  }

  // MARK: - Context menu

  public func extensionContextMenu(forAction id: String, in window: EngineWindowID) -> [EngineMenuItem] {
    guard let action = extensionActions(in: window).first(where: { $0.id == id }) else { return [] }
    var menu = [
      EngineMenuItem(title: action.name, command: ExtensionContextCommand.header, isEnabled: false),
      EngineMenuItem(title: "Options...", command: ExtensionContextCommand.options, isEnabled: action.hasOptionsPage),
      EngineMenuItem(title: action.isPinned ? "Unpin from Sidebar" : "Pin to Sidebar",
                     command: ExtensionContextCommand.togglePin),
    ]
    if let place = pinnedExtensionIDs.firstIndex(of: action.extensionID) {
      menu.append(EngineMenuItem(title: "Move Left", command: ExtensionContextCommand.moveLeft, isEnabled: place > 0))
      menu.append(EngineMenuItem(title: "Move Right", command: ExtensionContextCommand.moveRight,
                                 isEnabled: place < pinnedExtensionIDs.count - 1))
    }
    if action.siteAccess != .noSiteAccess {
      let host = activeTab(in: window).flatMap { snapshots[$0]?.url?.host() } ?? "This Site"
      let choices: [(String, ExtensionSiteAccess, EngineMenuCommand)] = [
        ("When You Click the Extension", .onClick, ExtensionContextCommand.siteAccessOnClick),
        ("On \(host)", .onThisSite, ExtensionContextCommand.siteAccessOnThisSite),
        ("On All Sites", .onAllSites, ExtensionContextCommand.siteAccessOnAllSites),
      ]
      menu.append(.submenu("This Can Read and Change Site Data", choices.map {
        EngineMenuItem(title: $0.0, command: $0.2, isChecked: action.siteAccess == $0.1)
      }))
    }
    menu += [
      .separator,
      EngineMenuItem(title: "Manage Extension...", command: ExtensionContextCommand.manage),
      EngineMenuItem(title: "Remove from Arkt...", command: ExtensionContextCommand.remove),
    ]
    return menu
  }

  public func performExtensionContextCommand(_ command: EngineMenuCommand, forAction id: String,
                                             in window: EngineWindowID) {
    guard let action = extensionActions(in: window).first(where: { $0.id == id }) else { return }
    let extensionID = action.extensionID
    switch command {
    case ExtensionContextCommand.togglePin:
      setExtensionPinned(extensionID, pinned: !action.isPinned)
    case ExtensionContextCommand.moveLeft, ExtensionContextCommand.moveRight:
      guard let place = pinnedExtensionIDs.firstIndex(of: extensionID) else { return }
      movePinnedExtension(extensionID, to: place + (command == ExtensionContextCommand.moveLeft ? -1 : 1))
    case ExtensionContextCommand.siteAccessOnClick: setSiteAccess(.onClick, of: extensionID)
    case ExtensionContextCommand.siteAccessOnThisSite: setSiteAccess(.onThisSite, of: extensionID)
    case ExtensionContextCommand.siteAccessOnAllSites: setSiteAccess(.onAllSites, of: extensionID)
    case ExtensionContextCommand.options, ExtensionContextCommand.manage, ExtensionContextCommand.remove: break
    default: return
    }
    performedExtensionContextCommands.append((command, id, window))
  }

  private func setSiteAccess(_ access: ExtensionSiteAccess, of extensionID: String) {
    for window in windowIDs {
      guard var list = actions[window],
            list.contains(where: { $0.extensionID == extensionID && $0.siteAccess != access }) else { continue }
      for index in list.indices where list[index].extensionID == extensionID { list[index].siteAccess = access }
      actions[window] = list
      hub.emit(.extensionActionsChanged(window))
    }
  }

  // MARK: - Commands

  public func setExtensionCommandShortcut(_ id: ExtensionCommandID, to shortcut: ExtensionShortcut?,
                                          scope: ExtensionCommandScope,
                                          replacingConflict: Bool) -> ExtensionShortcutResult {
    guard let index = extensionCommands.firstIndex(where: { $0.id == id }) else { return .unknownCommand }
    if let shortcut, let rejection = rejection(of: shortcut, for: id, scope: scope) { return .rejected(rejection) }
    let holder = shortcut.flatMap { key in
      extensionCommands.firstIndex { $0.id != id && $0.shortcut == key }
    }
    if let holder, !replacingConflict { return .conflict(with: extensionCommands[holder].id) }
    var commands = extensionCommands
    if let holder { commands[holder].shortcut = nil }
    commands[index].shortcut = shortcut
    commands[index].scope = scope
    guard commands != extensionCommands else { return .applied }
    extensionCommands = commands
    hub.emit(EngineExtensionEvent.commandsChanged)
    return .applied
  }

  /// The commands that run an extension's action, which take no media key.
  private static let actionCommandNames: Set<String> = ["_execute_action", "_execute_browser_action",
                                                        "_execute_page_action"]

  /// Chrome's rules for a command shortcut (`ui::Command::ParseImpl` with Ctrl-Alt not allowed), and global shortcuts
  /// held elsewhere.
  private func rejection(of shortcut: ExtensionShortcut, for id: ExtensionCommandID,
                         scope: ExtensionCommandScope) -> ExtensionShortcutRejection? {
    let modifiers = shortcut.modifiers
    if shortcut.key.isMedia {
      if !modifiers.isEmpty || Self.actionCommandNames.contains(id.name) { return .notAllowed }
    } else {
      if modifiers.isDisjoint(with: [.command, .option, .control]) { return .notAllowed }
      if modifiers.contains(.option), !modifiers.isDisjoint(with: [.command, .control]) { return .notAllowed }
    }
    if scope == .global, heldGlobalShortcuts.contains(shortcut) { return .globalShortcutTaken }
    return nil
  }

  public func observeExtensions(_ handler: @escaping @MainActor (EngineExtensionEvent) -> Void) -> EngineObservation {
    hub.addExtensionObserver(handler)
  }

  // MARK: - Uninstall (#720)

  public func uninstallExtension(_ extensionID: String, reportAbuse: Bool) {
    uninstallExtension(extensionID, reportAbuse: reportAbuse, in: nil)
  }

  /// Removes the extension's action from every window, its pin and its commands, then reports
  /// `.extensionActionsChanged` for each window that listed it and `.commandsChanged` when it had commands. The engine
  /// forgets it, so a later install starts unpinned. Every call is recorded with its window; an unknown id, and one
  /// whose action says `canUninstall` false (the Chromium engine's safety net, #721), change nothing else.
  public func uninstallExtension(_ extensionID: String, reportAbuse: Bool, in window: EngineWindowID?) {
    uninstalledExtensions.append(ExtensionUninstall(extensionID: extensionID, reportAbuse: reportAbuse,
                                                    window: window))
    let listing = windowIDs.filter { actions[$0]?.contains(where: { $0.extensionID == extensionID }) == true }
    let removable = listing.allSatisfy { window in
      actions[window]?.allSatisfy { $0.extensionID != extensionID || $0.canUninstall } ?? true
    }
    guard removable else { return }
    let hadCommands = extensionCommands.contains { $0.id.extensionID == extensionID }
    knownExtensionIDs.remove(extensionID)
    pinnedExtensionIDs.removeAll { $0 == extensionID }
    for window in listing { actions[window]?.removeAll { $0.extensionID == extensionID } }
    if hadCommands { extensionCommands.removeAll { $0.id.extensionID == extensionID } }
    for window in listing { hub.emit(.extensionActionsChanged(window)) }
    if hadCommands { hub.emit(EngineExtensionEvent.commandsChanged) }
  }

  // MARK: - Test drivers

  /// Test driver: the profile's extension commands changed (an extension with commands installed, updated or
  /// removed). Reports `.commandsChanged`.
  public func setExtensionCommands(_ commands: [ExtensionCommand]) {
    extensionCommands = commands
    hub.emit(EngineExtensionEvent.commandsChanged)
  }

  /// Test driver: an extension finished installing (#592), in Chromium's order: its `action` joins every window's list
  /// (pinned at the end of the order with `pinned`), `.extensionActionsChanged` for each window that lists it, then
  /// `.installed`. Whether new extensions pin by default is the shell's product decision, not the engine's (#590,
  /// question 2). `source` overrides `info.source` when given.
  public func installExtension(_ info: InstalledExtension, action: ExtensionAction? = nil, pinned: Bool = false,
                               source: ExtensionInstallSource? = nil) {
    var info = info
    if let source { info.source = source }
    knownExtensionIDs.insert(info.id)
    if pinned, !pinnedExtensionIDs.contains(info.id) { pinnedExtensionIDs.append(info.id) }
    if let action {
      for window in windowIDs where actions[window]?.contains(where: { $0.id == action.id }) != true {
        actions[window, default: []].append(action)
      }
    }
    if action != nil || pinned { announceActions(of: info.id) }
    hub.emit(EngineExtensionEvent.installed(info))
  }
}

/// One `uninstallExtension` call InMemoryEngine recorded (#720), with the window it named (#721; nil for none).
public struct ExtensionUninstall: Equatable, Sendable {
  public var extensionID: String
  public var reportAbuse: Bool
  public var window: EngineWindowID?
  public init(extensionID: String, reportAbuse: Bool, window: EngineWindowID? = nil) {
    self.extensionID = extensionID; self.reportAbuse = reportAbuse; self.window = window
  }
}
