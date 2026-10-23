import CoreGraphics
import Foundation

/// What the URL bars show for a page URL.
public enum AddressText {
  /// The sidebar URL bar's compact form: the lowercased host without a leading `www.`; the file name for a
  /// file URL; the whole string for a URL without a host (`about:blank`); empty without a URL.
  public static func host(_ url: URL?) -> String {
    guard let url else { return "" }
    if url.isFileURL { return url.lastPathComponent }
    guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return url.absoluteString }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  /// The Toolbar's form: the full URL (Arc's "Show full URL when Toolbar is enabled"; Arkt has no setting for the
  /// host-only variant yet).
  public static func full(_ url: URL?) -> String { url?.absoluteString ?? "" }
}

/// Splits the content card's clip area between the Toolbar and the page. The card is not flipped, so the
/// Toolbar's strip is at the highest y.
public struct CardToolbarLayout: Equatable, Sendable {
  public var toolbarFrame: CGRect
  public var contentFrame: CGRect

  public static func compute(bounds: CGRect, toolbarVisible: Bool, toolbarHeight: CGFloat) -> CardToolbarLayout {
    guard toolbarVisible else { return CardToolbarLayout(toolbarFrame: .zero, contentFrame: bounds) }
    let height = min(toolbarHeight, bounds.height)
    return CardToolbarLayout(
      toolbarFrame: CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height),
      contentFrame: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height - height))
  }
}

/// Whether the content card shows the Toolbar (Toggle Toolbar, Cmd-Shift-D; KB-018, BH-032).
///
/// Persistence: an app-level setting, stored in the app's standard user defaults (domain `dev.arkt.ArktShell`)
/// under Arc's key name `topBarURLEnabled`, so every window shares it and it survives relaunch. It is not part
/// of the sidebar database. `ephemeral()` keeps the value in memory only (tests, the scripted smoke).
@MainActor
public final class ToolbarSetting {
  public static let defaultsKey = "topBarURLEnabled"

  private let defaults: UserDefaults?

  public var isVisible: Bool {
    didSet { if isVisible != oldValue { defaults?.set(isVisible, forKey: Self.defaultsKey) } }
  }

  /// Reads the stored value (hidden when never set) and writes every change back to `defaults`.
  public convenience init(defaults: UserDefaults) { self.init(store: defaults) }

  private init(store: UserDefaults?) {
    self.defaults = store
    self.isVisible = store?.bool(forKey: Self.defaultsKey) ?? false
  }

  /// Starts hidden and never touches user defaults.
  public static func ephemeral() -> ToolbarSetting { ToolbarSetting(store: nil) }

  /// The View menu item and the URL bars' context menu (KB-018 "Show / hide Toolbar", BH-031).
  public static func menuTitle(isVisible: Bool) -> String { isVisible ? "Hide Toolbar" : "Show Toolbar" }
}
