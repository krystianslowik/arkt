import EngineAPI

/// Chromium command ids Arkt's main menu and window host need that `EngineAPI` has no constant for yet. W3-1 froze
/// `EngineCommand`; the six page commands are #272 (they move to `EngineCommand` by a pull request both lanes
/// approve), `IDC_NEW_WINDOW` is the host's New Window claim. Values from `chrome/app/chrome_command_ids.h` (week-3
/// results, W3-8 step 3 table, and #272).
public enum PendingEngineCommands {
  /// `IDC_NEW_WINDOW`: New Window, Cmd-N (claimed by the host).
  public static let newWindow = EngineCommand(rawValue: 34000)
  /// `IDC_STOP`: Stop, Cmd-.
  public static let stop = EngineCommand(rawValue: 33006)
  /// `IDC_RELOAD_BYPASSING_CACHE`: Force Reload, Shift-Cmd-R.
  public static let reloadBypassingCache = EngineCommand(rawValue: 33007)
  /// `IDC_FIND_NEXT`: Find Next, Cmd-G.
  public static let findNext = EngineCommand(rawValue: 37001)
  /// `IDC_FIND_PREVIOUS`: Find Previous, Shift-Cmd-G.
  public static let findPrevious = EngineCommand(rawValue: 37002)
  /// `IDC_DEV_TOOLS_INSPECT`: Inspect Elements, Opt-Cmd-C.
  public static let inspect = EngineCommand(rawValue: 40023)
  /// `IDC_DEV_TOOLS_CONSOLE`: JavaScript Console, Opt-Cmd-J.
  public static let console = EngineCommand(rawValue: 40005)

  /// Every id above.
  public static let all: [EngineCommand] = [
    newWindow, stop, reloadBypassingCache, findNext, findPrevious, inspect, console,
  ]
}
