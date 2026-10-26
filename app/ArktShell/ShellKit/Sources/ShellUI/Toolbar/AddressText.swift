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

  /// The Toolbar's full-URL form ("Show full URL when Toolbar is enabled", `toolbarShowFullURLsEnabledPreference`).
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
/// Persistence: an app-level setting, stored in the app's standard user defaults (domain `dev.arkt.Arkt`)
/// under Arc's key name `topBarURLEnabled`, so every window shares it and it survives relaunch. It is not part
/// of the sidebar database. `ephemeral()` keeps the value in memory only (tests, the scripted smoke).
///
/// Every window of the app shares one instance and registers as an observer, so a toggle in one window shows or
/// hides the Toolbar in all of them.
@MainActor
public final class ToolbarSetting {
  public static let defaultsKey = "topBarURLEnabled"
  /// Arc's "Show full URL when Toolbar is enabled" preference key (#80, BH-032).
  public static let showsFullURLDefaultsKey = "toolbarShowFullURLsEnabledPreference"

  private let defaults: UserDefaults?
  /// Held weakly: a closed window drops out on its own.
  private var observers: [WeakObserver] = []

  public var isVisible: Bool {
    didSet {
      guard isVisible != oldValue else { return }
      defaults?.set(isVisible, forKey: Self.defaultsKey)
      notifyObservers()
    }
  }

  /// Whether the Toolbar URL bar shows the full URL (`.full`) or the host only (`.host`). Defaults to `true`
  /// (PARITY(NEEDS-RUNTIME-CHECK RT-30)).
  public var showsFullURL: Bool {
    didSet {
      guard showsFullURL != oldValue else { return }
      defaults?.set(showsFullURL, forKey: Self.showsFullURLDefaultsKey)
      notifyObservers()
    }
  }

  /// Reads the stored values (hidden and full URL when never set) and writes every change back to `defaults`.
  public convenience init(defaults: UserDefaults) { self.init(store: defaults) }

  private init(store: UserDefaults?) {
    self.defaults = store
    self.isVisible = store?.bool(forKey: Self.defaultsKey) ?? false
    self.showsFullURL = store?.object(forKey: Self.showsFullURLDefaultsKey) as? Bool ?? true
  }

  private func notifyObservers() {
    observers.removeAll { $0.value == nil }
    for observer in observers { observer.value?.toolbarSettingDidChange(self) }
  }

  /// `observer` hears every change of `isVisible` until it is deallocated.
  public func addObserver(_ observer: any ToolbarSettingObserver) {
    observers.removeAll { $0.value == nil || $0.value === observer }
    observers.append(WeakObserver(value: observer))
  }

  /// Starts hidden and never touches user defaults.
  public static func ephemeral() -> ToolbarSetting { ToolbarSetting(store: nil) }

  /// The View menu item and the URL bars' context menu (KB-018 "Show / hide Toolbar", BH-031).
  public static func menuTitle(isVisible: Bool) -> String { isVisible ? "Hide Toolbar" : "Show Toolbar" }

  private struct WeakObserver {
    weak var value: (any ToolbarSettingObserver)?
  }
}

/// Told when a shared `ToolbarSetting` changes (see `ToolbarSetting.addObserver`).
@MainActor
public protocol ToolbarSettingObserver: AnyObject {
  func toolbarSettingDidChange(_ setting: ToolbarSetting)
}
