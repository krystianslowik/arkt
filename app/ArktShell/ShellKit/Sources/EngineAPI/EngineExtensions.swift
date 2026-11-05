import AppKit

/// One extension toolbar action of a window, as plain values (Decision 10).
public struct ExtensionAction: Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  /// The 16 pt icon at 2x, PNG.
  public var iconPNG: Data?
  public var isEnabled: Bool
  /// The extension the action belongs to; pin state, order and commands are per extension (#591).
  public var extensionID: String
  /// Pinned in the profile (`EngineExtensions.pinnedExtensionIDs`).
  public var isPinned: Bool
  /// The extension has an options page (the context menu's Options... item).
  public var hasOptionsPage: Bool
  public var siteAccess: ExtensionSiteAccess

  /// `extensionID` defaults to `id`: Chromium's action ids are extension ids.
  public init(id: String, name: String, iconPNG: Data? = nil, isEnabled: Bool = true, extensionID: String? = nil,
              isPinned: Bool = false, hasOptionsPage: Bool = false, siteAccess: ExtensionSiteAccess = .noSiteAccess) {
    self.id = id; self.name = name; self.iconPNG = iconPNG; self.isEnabled = isEnabled
    self.extensionID = extensionID ?? id; self.isPinned = isPinned; self.hasOptionsPage = hasOptionsPage
    self.siteAccess = siteAccess
  }
}

/// Extension actions, for engines that run extensions. A separate protocol: FakeEngine does not adopt it, and the
/// shell shows its Extensions control only when `engine is EngineExtensions`. Changes are announced with
/// `EngineWindowEvent.extensionActionsChanged`.
@MainActor
public protocol EngineExtensions: AnyObject {
  /// The window's actions in toolbar order, with icon and enabled state for its active tab. Pinned actions come
  /// first, in `pinnedExtensionIDs` order, then the rest.
  func extensionActions(in window: EngineWindowID) -> [ExtensionAction]
  /// Runs the action as a toolbar click; its popup is anchored to `anchor` (engine-drawn this week).
  func runExtensionAction(_ id: String, in window: EngineWindowID, anchor: NSView)

  // MARK: Pin state, order, context menu, commands, install events (#591)

  /// The profile's pinned extensions in order (left to right; Cmd-E cycles in this order, KB-047). Profile-wide: every
  /// window of the profile shows the same pins, and they outlive the windows. Default: none.
  var pinnedExtensionIDs: [String] { get }
  /// Pins (appended at the end of the order) or unpins the extension. `.extensionActionsChanged` for each window that
  /// lists it; nothing when it already has that state. Default: a no-op.
  func setExtensionPinned(_ extensionID: String, pinned: Bool)
  /// Moves a pinned extension to `index` in `pinnedExtensionIDs`, clamped to the ends. A no-op for an unpinned or
  /// unknown extension or its own place; otherwise `.extensionActionsChanged` for each window that lists it. Default:
  /// a no-op.
  func movePinnedExtension(_ extensionID: String, to index: Int)
  /// The context menu of an action in `window` (right-click or Ctrl-click), with `ExtensionContextCommand` commands;
  /// empty for an unknown action. Default: empty.
  func extensionContextMenu(forAction id: String, in window: EngineWindowID) -> [EngineMenuItem]
  /// Runs a context menu item the user chose. A no-op for an unknown action or command. Default: a no-op.
  func performExtensionContextCommand(_ command: EngineMenuCommand, forAction id: String, in window: EngineWindowID)
  /// Every extension command of the profile, grouped by extension. Default: none.
  var extensionCommands: [ExtensionCommand] { get }
  /// Sets (nil clears) a command's shortcut and its scope. The engine checks only the other extension commands, in
  /// either scope: with `replacingConflict` false a taken shortcut returns `.conflict` and changes nothing; with true
  /// the other command loses it. Conflicts with Arkt's own shortcuts are the shell's to check first. One
  /// `.commandsChanged` when something changed. Default: `.unknownCommand`.
  func setExtensionCommandShortcut(_ id: ExtensionCommandID, to shortcut: ExtensionShortcut?,
                                   scope: ExtensionCommandScope, replacingConflict: Bool) -> ExtensionShortcutResult
  /// Profile-wide extension events, through the same FIFO as `observe`. Default: none are delivered.
  func observeExtensions(_ handler: @escaping @MainActor (EngineExtensionEvent) -> Void) -> EngineObservation
}

extension EngineExtensions {
  public var pinnedExtensionIDs: [String] { [] }
  public func setExtensionPinned(_ extensionID: String, pinned: Bool) {}
  public func movePinnedExtension(_ extensionID: String, to index: Int) {}
  public func extensionContextMenu(forAction id: String, in window: EngineWindowID) -> [EngineMenuItem] { [] }
  public func performExtensionContextCommand(_ command: EngineMenuCommand, forAction id: String,
                                             in window: EngineWindowID) {}
  public var extensionCommands: [ExtensionCommand] { [] }
  public func setExtensionCommandShortcut(_ id: ExtensionCommandID, to shortcut: ExtensionShortcut?,
                                          scope: ExtensionCommandScope,
                                          replacingConflict: Bool) -> ExtensionShortcutResult { .unknownCommand }
  public func observeExtensions(_ handler: @escaping @MainActor (EngineExtensionEvent) -> Void) -> EngineObservation {
    EngineObservation {}
  }
}

// MARK: - Site access and the context menu (#591)

/// What an extension may read and change on sites (Chromium's site access; the context menu's "This Can Read and
/// Change Site Data" submenu, `design/extensions`).
public enum ExtensionSiteAccess: Equatable, Sendable {
  /// It asks for no host permissions: the submenu is not shown.
  case noSiteAccess
  /// Only when the user clicks its action.
  case onClick
  /// On the active tab's site.
  case onThisSite
  /// On all sites.
  case onAllSites
}

/// The menu commands of an extension action's context menu items (`EngineMenuItem.command`, #596): ids meaningful
/// only to this menu, which the Chromium engine maps to `ExtensionContextMenuModel` entries. A chosen item goes back
/// through `performExtensionContextCommand`. The shell runs `manage` (Settings, Extensions) and `remove` (the remove
/// sheet) itself; the engine runs the rest.
public enum ExtensionContextCommand {
  /// The extension's name, the menu's disabled header; running it does nothing.
  public static let header = EngineMenuCommand(rawValue: 0)
  /// Options...: opens the extension's options page in a tab.
  public static let options = EngineMenuCommand(rawValue: 1)
  /// Pin to Sidebar or Unpin from Sidebar, by the current state.
  public static let togglePin = EngineMenuCommand(rawValue: 2)
  /// Move Left: one place earlier in the pinned order.
  public static let moveLeft = EngineMenuCommand(rawValue: 3)
  /// Move Right: one place later in the pinned order.
  public static let moveRight = EngineMenuCommand(rawValue: 4)
  public static let siteAccessOnClick = EngineMenuCommand(rawValue: 5)
  public static let siteAccessOnThisSite = EngineMenuCommand(rawValue: 6)
  public static let siteAccessOnAllSites = EngineMenuCommand(rawValue: 7)
  /// Manage Extension...: the shell's Settings, Extensions entry.
  public static let manage = EngineMenuCommand(rawValue: 8)
  /// Remove from Arkt...: the shell's remove sheet.
  public static let remove = EngineMenuCommand(rawValue: 9)
}

// MARK: - Keyboard commands (#591)

/// One `chrome.commands` command: the extension id and the command's manifest name (`_execute_action` for the
/// action itself).
public struct ExtensionCommandID: Hashable, Sendable {
  public var extensionID: String
  public var name: String
  public init(extensionID: String, name: String) { self.extensionID = extensionID; self.name = name }
}

/// Where a command's shortcut works. The Chrome model (#590, question 1): in Arkt by default, and system-wide only
/// when the user opts in for that shortcut.
public enum ExtensionCommandScope: Equatable, Sendable {
  /// Only while Arkt is active ("In Arkt").
  case inApp
  /// In every application ("All Apps").
  case global
}

/// A keyboard shortcut: one key and its modifiers. The key is stored lowercased, so Cmd-Shift-E and Cmd-Shift-e are
/// the same shortcut.
public struct ExtensionShortcut: Hashable, Sendable {
  public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
  }

  /// The key as `NSEvent.charactersIgnoringModifiers` gives it, lowercased.
  public let key: String
  public let modifiers: Modifiers

  public init(key: String, modifiers: Modifiers) {
    self.key = key.lowercased(); self.modifiers = modifiers
  }
}

/// One keyboard command an extension declares (`chrome.commands`), with the shortcut and scope the profile has for it.
public struct ExtensionCommand: Equatable, Sendable, Identifiable {
  public var id: ExtensionCommandID
  public var extensionName: String
  /// The manifest's description, or the engine's title for `_execute_action`.
  public var description: String
  /// Nil when no shortcut is set (Settings shows Set Shortcut).
  public var shortcut: ExtensionShortcut?
  public var scope: ExtensionCommandScope

  public init(id: ExtensionCommandID, extensionName: String, description: String,
              shortcut: ExtensionShortcut? = nil, scope: ExtensionCommandScope = .inApp) {
    self.id = id; self.extensionName = extensionName; self.description = description
    self.shortcut = shortcut; self.scope = scope
  }
}

/// The answer to `EngineExtensions.setExtensionCommandShortcut`.
public enum ExtensionShortcutResult: Equatable, Sendable {
  /// The command has the shortcut and scope now.
  case applied
  /// Another extension command has the shortcut; nothing changed. The shell asks (Use or Keep Existing) and calls
  /// again with `replacingConflict: true` for Use.
  case conflict(with: ExtensionCommandID)
  /// No such command (the extension went away).
  case unknownCommand
}

// MARK: - Install events (#591)

/// An extension the profile just installed (#592, #594 post-install toast).
public struct InstalledExtension: Equatable, Sendable {
  public var id: String
  public var name: String
  /// The extension's icon, PNG.
  public var iconPNG: Data?
  public init(id: String, name: String, iconPNG: Data? = nil) { self.id = id; self.name = name; self.iconPNG = iconPNG }
}

/// Profile-wide extension events (`EngineExtensions.observeExtensions`), in the same FIFO as tab and window events.
/// Action list changes stay on the window stream (`EngineWindowEvent.extensionActionsChanged`).
public enum EngineExtensionEvent: Equatable, Sendable {
  /// An extension was installed, in place of Chromium's post-install text. Its actions, and its pin when it is pinned
  /// on install, follow as `.extensionActionsChanged`.
  case installed(InstalledExtension)
  /// `extensionCommands` changed: a shortcut or scope set, an extension with commands added or removed.
  case commandsChanged
}
