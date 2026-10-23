/// Accessibility identifiers of the shell, the only handles the UI test suite (`ArktShellUITests`) uses to find and
/// drive views. This file has no imports so the UI test target can compile the same file by path, and the
/// identifiers in the app and in the tests can never drift apart. Values that tests compare against
/// (`accessibilityValue`) live next to their identifiers.
///
/// Each area is its own nested enum; later groups add enums instead of editing these.
public enum AXID {
  /// The shell window (`ShellWindow`).
  public enum Shell {
    public static let window = "shell.window"
  }

  /// The inset card that hosts the page (`ContentCardView`).
  public enum Content {
    public static let card = "content.card"
  }

  /// First run: the panel in the content card while the profile has no Space (`EmptyStateView`).
  public enum EmptyState {
    public static let root = "emptyState"
    /// "Import from Arc"; absent from the accessibility tree while hidden (no Arc data).
    public static let importFromArc = "emptyState.import"
    public static let newSpace = "emptyState.newSpace"
  }

  /// The Toolbar at the top of the content card (`ContentToolbarView`); absent while the Toolbar is hidden.
  public enum Toolbar {
    public static let root = "toolbar"
    /// Enabled only while the shown tab can go back.
    public static let back = "toolbar.back"
    /// Enabled only while the shown tab can go forward.
    public static let forward = "toolbar.forward"
    public static let reload = "toolbar.reload"
    /// Value: the full address of the shown tab.
    public static let urlBar = "toolbar.urlBar"
  }

  /// The toast over the bottom of the content card (`ToastView`); absent while no toast shows.
  public enum Toast {
    /// Label: the toast text. Value: `persistent` or `timed`.
    public static let root = "toast"
    /// The action button; present only while the toast has an action.
    public static let action = "toast.action"
    /// Value of `root` for a toast that stays until dismissed (recovery notices).
    public static let persistent = "persistent"
    /// Value of `root` for a toast that hides after its duration.
    public static let timed = "timed"
  }
}
