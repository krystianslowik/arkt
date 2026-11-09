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
  /// The user may uninstall the extension (#721): not installed by policy, not part of the engine. The shell offers
  /// Remove from Arkt... only then; `uninstallExtension` refuses the others anyway.
  public var canUninstall: Bool
  /// The extension comes from the Chrome Web Store, so it has a report page there (#721). The remove sheet offers
  /// Report abuse only then; `uninstallExtension` opens no report page for the others anyway.
  public var canReportAbuse: Bool

  /// `extensionID` defaults to `id`: Chromium's action ids are extension ids.
  public init(id: String, name: String, iconPNG: Data? = nil, isEnabled: Bool = true, extensionID: String? = nil,
              isPinned: Bool = false, hasOptionsPage: Bool = false, siteAccess: ExtensionSiteAccess = .noSiteAccess,
              canUninstall: Bool = true, canReportAbuse: Bool = true) {
    self.id = id; self.name = name; self.iconPNG = iconPNG; self.isEnabled = isEnabled
    self.extensionID = extensionID ?? id; self.isPinned = isPinned; self.hasOptionsPage = hasOptionsPage
    self.siteAccess = siteAccess; self.canUninstall = canUninstall; self.canReportAbuse = canReportAbuse
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
  /// Sets (nil clears) a command's shortcut and its scope. A shortcut Chrome forbids returns `.rejected` and changes
  /// nothing. The engine checks only the other extension commands, in either scope: with `replacingConflict` false a
  /// taken shortcut returns `.conflict` and changes nothing; with true the other command loses it. Conflicts with
  /// Arkt's own shortcuts are the shell's to check first. One `.commandsChanged` when something changed. Default:
  /// `.unknownCommand`.
  func setExtensionCommandShortcut(_ id: ExtensionCommandID, to shortcut: ExtensionShortcut?,
                                   scope: ExtensionCommandScope, replacingConflict: Bool) -> ExtensionShortcutResult
  /// Uninstalls the extension as the user's own choice, with no prompt of the engine's: the shell has asked already
  /// (the remove sheet, #720). `reportAbuse`: the user checked Report abuse, so the engine also opens the Web Store's
  /// report page for it. The removal arrives as `.extensionActionsChanged` for each window that listed its action
  /// (its pin goes with it) and `.commandsChanged` when it had commands. An unknown id or an extension the user
  /// cannot remove changes nothing. Default: a no-op (the Chromium side is #721).
  func uninstallExtension(_ extensionID: String, reportAbuse: Bool)
  /// `uninstallExtension(_:reportAbuse:)` from the remove sheet of `window`: the Web Store's report page opens in that
  /// window (#721). Nil, or a window that has closed, leaves the choice to the engine (its last active window).
  /// Default: the call without a window.
  func uninstallExtension(_ extensionID: String, reportAbuse: Bool, in window: EngineWindowID?)
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
  public func uninstallExtension(_ extensionID: String, reportAbuse: Bool) {}
  public func uninstallExtension(_ extensionID: String, reportAbuse: Bool, in window: EngineWindowID?) {
    uninstallExtension(extensionID, reportAbuse: reportAbuse)
  }
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
  /// Pin or Unpin, by the current state.
  public static let togglePin = EngineMenuCommand(rawValue: 2)
  /// Move Up: one place earlier in the pinned order.
  public static let moveUp = EngineMenuCommand(rawValue: 3)
  /// Move Down: one place later in the pinned order.
  public static let moveDown = EngineMenuCommand(rawValue: 4)
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

/// A keyboard shortcut: one key and its modifiers, as Chromium stores a command's accelerator (a layout-independent
/// `ui::KeyboardCode` and modifiers). The key is the unshifted base key: Cmd-Shift-2 is `.digit(.two)` with
/// `[.command, .shift]`, never "@".
public struct ExtensionShortcut: Hashable, Sendable {
  public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)
  }

  public enum Letter: String, CaseIterable, Hashable, Sendable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
  }

  public enum Digit: Int, CaseIterable, Hashable, Sendable {
    case zero, one, two, three, four, five, six, seven, eight, nine
  }

  /// Exactly the keys a `chrome.commands` shortcut can name (Chromium's `ui::Command::ParseImpl`): A to Z, 0 to 9,
  /// Comma, Period, the arrows, Insert, Delete, Home, End, Page Up, Page Down, Space, Tab and four media keys. A
  /// recorder takes letters by character and every other key by key code, so the digit row of an AZERTY layout (which
  /// types "&" unshifted) still records digits.
  public enum Key: Hashable, Sendable {
    case letter(Letter)
    case digit(Digit)
    case comma, period
    case up, down, left, right
    case home, end, pageUp, pageDown, space, tab, insert, delete
    case mediaNextTrack, mediaPreviousTrack, mediaPlayPause, mediaStop

    /// Media keys take no modifiers, and no `_execute_*` command takes one; every other key needs a modifier.
    public var isMedia: Bool {
      switch self {
      case .mediaNextTrack, .mediaPreviousTrack, .mediaPlayPause, .mediaStop: true
      default: false
      }
    }

    /// The key from its unshifted base character as the keyboard layout gives it
    /// (`NSEvent.characters(byApplyingModifiers: [])`): a letter of either case, a digit, comma, period or space. Use
    /// it for letters, so a non-ANSI layout records the letter printed on the key. Nil for anything else.
    public init?(character: Character) {
      let text = String(character).lowercased()
      if let letter = Letter(rawValue: text) { self = .letter(letter); return }
      if let value = Int(text), let digit = Digit(rawValue: value) { self = .digit(digit); return }
      switch text {
      case ",": self = .comma
      case ".": self = .period
      case " ": self = .space
      default: return nil
      }
    }

    /// The key from a macOS virtual key code (`NSEvent.keyCode`, Carbon's `kVK_*`), which Shift and the layout do not
    /// change. Letters, digits, comma and period by their ANSI position; named keys on any layout. Nil
    /// for any other code. Media keys arrive as system-defined events, not key codes.
    public init?(keyCode: UInt16) {
      if let key = Self.byKeyCode[keyCode] { self = key } else { return nil }
    }

    private static let byKeyCode: [UInt16: Key] = {
      var map: [UInt16: Key] = [:]
      let letters: [(UInt16, Letter)] = [
        (0x00, .a), (0x01, .s), (0x02, .d), (0x03, .f), (0x04, .h), (0x05, .g), (0x06, .z), (0x07, .x), (0x08, .c),
        (0x09, .v), (0x0B, .b), (0x0C, .q), (0x0D, .w), (0x0E, .e), (0x0F, .r), (0x10, .y), (0x11, .t), (0x1F, .o),
        (0x20, .u), (0x22, .i), (0x23, .p), (0x25, .l), (0x26, .j), (0x28, .k), (0x2D, .n), (0x2E, .m),
      ]
      for (code, letter) in letters { map[code] = .letter(letter) }
      let digits: [(UInt16, Digit)] = [
        (0x12, .one), (0x13, .two), (0x14, .three), (0x15, .four), (0x17, .five), (0x16, .six), (0x1A, .seven),
        (0x1C, .eight), (0x19, .nine), (0x1D, .zero),
      ]
      for (code, digit) in digits { map[code] = .digit(digit) }
      let named: [(UInt16, Key)] = [
        (0x2B, .comma), (0x2F, .period), (0x31, .space), (0x7E, .up), (0x7D, .down), (0x7B, .left), (0x7C, .right),
        (0x73, .home), (0x77, .end), (0x74, .pageUp), (0x79, .pageDown), (0x30, .tab), (0x72, .insert),
        (0x75, .delete),
      ]
      for (code, key) in named { map[code] = key }
      return map
    }()
  }

  public let key: Key
  public let modifiers: Modifiers

  public init(key: Key, modifiers: Modifiers) {
    self.key = key; self.modifiers = modifiers
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
  /// The engine refuses the shortcut; nothing changed.
  case rejected(ExtensionShortcutRejection)
  /// No such command (the extension went away).
  case unknownCommand
}

/// Why the engine refused a shortcut (`ExtensionShortcutResult.rejected`).
public enum ExtensionShortcutRejection: Equatable, Sendable {
  /// The engine could not turn the shortcut into a `ui::KeyboardCode` accelerator: its catch-all for a key it cannot
  /// map. Every `ExtensionShortcut.Key` has a code, so InMemoryEngine never returns it.
  case noKeyCode
  /// A combination Chrome forbids (`ui::Command::ParseImpl`, Ctrl-Alt not allowed): a non-media key without Command,
  /// Option or Control; Option with Command or Control; a media key with modifiers; a media key on `_execute_action`,
  /// `_execute_browser_action` or `_execute_page_action`.
  case notAllowed
  /// A global shortcut another application or the system already holds.
  case globalShortcutTaken
}

// MARK: - Install events (#591)

/// What installed an extension: the user (the Web Store's install sheet) or a browser import's batch
/// (`EngineImporting.installExtensionResults`), which has its own summary and shows no per-extension toast (#594).
public enum ExtensionInstallSource: Equatable, Sendable {
  case user
  case browserImport
}

/// An extension the profile just installed (#592, #594 post-install toast).
public struct InstalledExtension: Equatable, Sendable {
  public var id: String
  public var name: String
  /// The extension's icon, PNG.
  public var iconPNG: Data?
  public var source: ExtensionInstallSource
  public init(id: String, name: String, iconPNG: Data? = nil, source: ExtensionInstallSource = .user) {
    self.id = id; self.name = name; self.iconPNG = iconPNG; self.source = source
  }
}

/// Profile-wide extension events (`EngineExtensions.observeExtensions`), in the same FIFO as tab and window events.
/// Action list changes stay on the window stream (`EngineWindowEvent.extensionActionsChanged`).
public enum EngineExtensionEvent: Equatable, Sendable {
  /// An extension was installed, in place of Chromium's post-install text. Its order against the
  /// `.extensionActionsChanged` that lists its action (and its pin, when it pins on install) is not guaranteed: in
  /// Chromium `OnExtensionLoaded` adds the action before `OnExtensionInstalled` fires. `OnExtensionInstalled` also
  /// fires for an update (`is_update`); the engine filters those out and reports only first installs.
  case installed(InstalledExtension)
  /// `extensionCommands` changed: a shortcut or scope set, an extension with commands added or removed.
  case commandsChanged
}
