import EngineAPI

/// Chromium command ids Arkt's main menu and window host need that `EngineAPI` has no constant for yet. The six page
/// commands moved to `EngineCommand` with #272; what is left is `IDC_NEW_WINDOW`, the host's New Window claim. Values
/// from `chrome/app/chrome_command_ids.h` (week-3 results, W3-8 step 3 table).
public enum PendingEngineCommands {
  /// `IDC_NEW_WINDOW`: New Window, Cmd-N (claimed by the host).
  public static let newWindow = EngineCommand(rawValue: 34000)

  /// Every id above.
  public static let all: [EngineCommand] = [newWindow]
}
