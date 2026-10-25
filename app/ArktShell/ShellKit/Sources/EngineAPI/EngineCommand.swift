/// A browser command the shell sends or claims (Decision 9). The raw value is Chromium's `IDC_*` id from
/// `chrome/app/chrome_command_ids.h`, so the Chromium engine passes it through unchanged. Every named constant is
/// checked against the header (week-3 results, "W3-0", Step 5, repeated on every rebase).
public struct EngineCommand: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public var description: String { "EngineCommand(\(rawValue))" }

  /// `IDC_BACK`
  public static let back = EngineCommand(rawValue: 33000)
  /// `IDC_FORWARD`
  public static let forward = EngineCommand(rawValue: 33001)
  /// `IDC_RELOAD`
  public static let reload = EngineCommand(rawValue: 33002)
  /// `IDC_STOP`
  public static let stop = EngineCommand(rawValue: 33006)
  /// `IDC_RELOAD_BYPASSING_CACHE`
  public static let reloadBypassingCache = EngineCommand(rawValue: 33007)
  /// `IDC_CLOSE_WINDOW`
  public static let closeWindow = EngineCommand(rawValue: 34012)
  /// `IDC_NEW_TAB`
  public static let newTab = EngineCommand(rawValue: 34014)
  /// `IDC_CLOSE_TAB`
  public static let closeTab = EngineCommand(rawValue: 34015)
  /// `IDC_EXIT`
  public static let exit = EngineCommand(rawValue: 34031)
  /// `IDC_VIEW_SOURCE`
  public static let viewSource = EngineCommand(rawValue: 35002)
  /// `IDC_PRINT`
  public static let print = EngineCommand(rawValue: 35003)
  /// `IDC_SAVE_PAGE`
  public static let savePage = EngineCommand(rawValue: 35004)
  /// `IDC_FIND`
  public static let find = EngineCommand(rawValue: 37000)
  /// `IDC_FIND_NEXT`
  public static let findNext = EngineCommand(rawValue: 37001)
  /// `IDC_FIND_PREVIOUS`
  public static let findPrevious = EngineCommand(rawValue: 37002)
  /// `IDC_ZOOM_PLUS`
  public static let zoomIn = EngineCommand(rawValue: 38001)
  /// `IDC_ZOOM_NORMAL`
  public static let zoomReset = EngineCommand(rawValue: 38002)
  /// `IDC_ZOOM_MINUS`
  public static let zoomOut = EngineCommand(rawValue: 38003)
  /// `IDC_DEV_TOOLS` (the id the Mac main menu uses for Developer Tools, not `IDC_DEV_TOOLS_TOGGLE`)
  public static let devTools = EngineCommand(rawValue: 40004)
  /// `IDC_DEV_TOOLS_CONSOLE`
  public static let console = EngineCommand(rawValue: 40005)
  /// `IDC_SHOW_HISTORY`
  public static let history = EngineCommand(rawValue: 40010)
  /// `IDC_SHOW_DOWNLOADS`
  public static let downloads = EngineCommand(rawValue: 40012)
  /// `IDC_DEV_TOOLS_INSPECT`
  public static let inspect = EngineCommand(rawValue: 40023)

  /// Every named constant, for the id check and for hosts that claim by table.
  public static let all: [EngineCommand] = [
    .back, .forward, .reload, .stop, .reloadBypassingCache, .closeWindow, .newTab, .closeTab, .exit, .viewSource,
    .print, .savePage, .find, .findNext, .findPrevious, .zoomIn, .zoomReset, .zoomOut, .devTools, .console, .history,
    .downloads, .inspect,
  ]
}

/// Where a command opens its result. The raw value is Chromium's `WindowOpenDisposition`
/// (`ui/base/window_open_disposition.h`, declaration index); other values pass through unchanged.
public struct EngineDisposition: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public var description: String { "EngineDisposition(\(rawValue))" }

  /// `CURRENT_TAB`
  public static let currentTab = EngineDisposition(rawValue: 1)
  /// `NEW_FOREGROUND_TAB`
  public static let newForegroundTab = EngineDisposition(rawValue: 3)
  /// `NEW_BACKGROUND_TAB`
  public static let newBackgroundTab = EngineDisposition(rawValue: 4)
  /// `NEW_WINDOW`
  public static let newWindow = EngineDisposition(rawValue: 6)
}
