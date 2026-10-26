import Foundation

/// The app-level settings the Settings window edits (#307, docs/design/settings.md, section 8): one shared store,
/// typed values, user defaults (the app passes the `ARKT_DEFAULTS_SUITE` suite in Debug test runs), weak observers.
/// Every change applies at once; there is no Save.
///
/// Keys are Arc's where Arc has one, so the names stay recognizable: Count Favorites is stored inverted as
/// `excludeFavoritesInSwitchToNthTab`, Command-9 as `switchToNinthSidebarItemEnabled`. The Peek link switches keep the
/// keys `PeekLinkSettings` already writes, and the Toolbar keeps `ToolbarSetting` and its keys unchanged.
@MainActor
public final class AppSettings {
  public enum Key {
    public static let lastPane = "settingsLastPane"
    public static let windowTopLeft = "settingsWindowTopLeft"
    public static let excludeFavoritesInSwitchToNthTab = "excludeFavoritesInSwitchToNthTab"
    public static let switchToNinthSidebarItemEnabled = "switchToNinthSidebarItemEnabled"
    /// Arc's key for the system-wide Little Arkt hotkey (BH-131, KB-045).
    public static let globalLittleBrowserHotkeyEnabled = "globalLittleBrowserHotkeyEnabled"
  }

  /// Show Toolbar and Show the full URL: the instance every window observes.
  public let toolbar: ToolbarSetting
  private let defaults: UserDefaults?
  /// The values of an ephemeral store (no defaults).
  private var memory: [String: Any] = [:]
  private var observers: [WeakObserver] = []

  /// Reads and writes `defaults`. `toolbar` is the app's shared Toolbar setting; a new one over `defaults` when nil.
  public init(defaults: UserDefaults, toolbar: ToolbarSetting? = nil) {
    self.defaults = defaults
    self.toolbar = toolbar ?? ToolbarSetting(defaults: defaults)
  }

  private init(ephemeralToolbar: ToolbarSetting) {
    defaults = nil
    toolbar = ephemeralToolbar
  }

  /// Keeps every value in memory; never touches user defaults (tests, the scripted smoke).
  public static func ephemeral() -> AppSettings { AppSettings(ephemeralToolbar: .ephemeral()) }

  // MARK: Values

  /// "Count Favorites in Command-1 to Command-8" and "Command-9 opens the ninth tab" (BH-014, BH-015).
  public var tabNavigation: TabNavigationSettings {
    get {
      var value = TabNavigationSettings()
      value.countsFavorites = !bool(Key.excludeFavoritesInSwitchToNthTab, default: false)
      value.ninthOpensNinth = bool(Key.switchToNinthSidebarItemEnabled, default: false)
      return value
    }
    set {
      guard newValue != tabNavigation else { return }
      set(!newValue.countsFavorites, Key.excludeFavoritesInSwitchToNthTab)
      set(newValue.ninthOpensNinth, Key.switchToNinthSidebarItemEnabled)
      notifyObservers()
    }
  }

  /// Settings > General > Links: the two Peek switches (BH-144, BH-145).
  public var peekLinks: PeekLinkSettings {
    get {
      PeekLinkSettings(opensCrossSiteLinks: bool(PeekLinkSettings.crossSiteKey, default: true),
                       opensShiftClickedLinks: bool(PeekLinkSettings.shiftClickKey, default: true))
    }
    set {
      guard newValue != peekLinks else { return }
      set(newValue.opensCrossSiteLinks, PeekLinkSettings.crossSiteKey)
      set(newValue.opensShiftClickedLinks, PeekLinkSettings.shiftClickKey)
      notifyObservers()
    }
  }

  /// Settings > Links: "Open Little Arkt when I press ⌥⌘N" (BH-130, BH-131, KB-045), off by default (decision
  /// 2026-10-25). The app registers the system-wide hotkey from this value.
  public var opensLittleArktWithHotKey: Bool {
    get { bool(Key.globalLittleBrowserHotkeyEnabled, default: false) }
    set {
      guard newValue != opensLittleArktWithHotKey else { return }
      set(newValue, Key.globalLittleBrowserHotkeyEnabled)
      notifyObservers()
    }
  }

  /// Another app holds the combination. Runtime state of the registration, never persisted: Settings shows
  /// "⌥⌘N is used by another app." under the switch while it is on.
  public private(set) var littleArktHotKeyTaken = false

  /// The app reports each registration answer; a change reaches the Settings window through the observers.
  public func setLittleArktHotKeyTaken(_ taken: Bool) {
    guard taken != littleArktHotKeyTaken else { return }
    littleArktHotKeyTaken = taken
    notifyObservers()
  }

  /// The pane Settings shows when it opens. Window state, so observers are not told.
  public var lastPane: SettingsPane {
    get { string(Key.lastPane).flatMap(SettingsPane.init(rawValue:)) ?? .general }
    set { set(newValue.rawValue, Key.lastPane) }
  }

  /// The Settings window's top-left corner in screen coordinates, kept here (in the app's defaults suite) rather than
  /// in AppKit's frame autosave, which always writes the standard defaults. Window state: observers are not told.
  public var windowTopLeft: CGPoint? {
    get { string(Key.windowTopLeft).flatMap { $0.isEmpty ? nil : NSPointFromString($0) } }
    set { set(newValue.map { NSStringFromPoint($0) } as Any? ?? "", Key.windowTopLeft) }
  }

  // MARK: Observers

  /// `observer` hears every change of a setting the browser windows apply until it is deallocated.
  public func addObserver(_ observer: any AppSettingsObserver) {
    observers.removeAll { $0.value == nil || $0.value === observer }
    observers.append(WeakObserver(value: observer))
  }

  private func notifyObservers() {
    observers.removeAll { $0.value == nil }
    for observer in observers { observer.value?.appSettingsDidChange(self) }
  }

  // MARK: Storage

  private func bool(_ key: String, default value: Bool) -> Bool {
    if let defaults { return defaults.object(forKey: key) as? Bool ?? value }
    return memory[key] as? Bool ?? value
  }

  private func string(_ key: String) -> String? {
    if let defaults { return defaults.string(forKey: key) }
    return memory[key] as? String
  }

  private func set(_ value: Any, _ key: String) {
    if let defaults { defaults.set(value, forKey: key) } else { memory[key] = value }
  }

  private struct WeakObserver {
    weak var value: (any AppSettingsObserver)?
  }
}

/// Told when a shared `AppSettings` changes (see `AppSettings.addObserver`).
@MainActor
public protocol AppSettingsObserver: AnyObject {
  func appSettingsDidChange(_ settings: AppSettings)
}

/// The seven panes, in toolbar order: Cmd-1 to Cmd-7 (decision 1).
public enum SettingsPane: String, CaseIterable, Sendable {
  case general, spaces, appearance, shortcuts, extensions, privacy, advanced

  /// The pane item's short name.
  public var label: String {
    switch self {
    case .general: "General"
    case .spaces: "Spaces"
    case .appearance: "Appearance"
    case .shortcuts: "Shortcuts"
    case .extensions: "Extensions"
    case .privacy: "Privacy"
    case .advanced: "Advanced"
    }
  }

  /// The window title while the pane shows.
  public var title: String {
    switch self {
    case .spaces: "Spaces and Profiles"
    case .privacy: "Privacy and Security"
    default: label
    }
  }

  public var symbolName: String {
    switch self {
    case .general: "gearshape"
    case .spaces: "square.on.square"
    case .appearance: "circle.lefthalf.filled"
    case .shortcuts: "command"
    case .extensions: "puzzlepiece.extension"
    case .privacy: "checkmark.shield"
    case .advanced: "slider.horizontal.3"
    }
  }

  /// Cmd-1 is General, Cmd-7 Advanced.
  public init?(commandNumber: Int) {
    guard (1...Self.allCases.count).contains(commandNumber) else { return nil }
    self = Self.allCases[commandNumber - 1]
  }
}
