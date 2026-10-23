import AppKit

/// The application part of the dev engine's user agent: the Safari tokens WebKit appends after
/// `... AppleWebKit/605.1.15 (KHTML, like Gecko)`. Without them sites treat WKWebView as an unknown
/// browser and serve legacy pages. The version follows the installed Safari, so the UA stays current
/// as the system updates.
enum SafariUserAgent {
  /// Used when the installed Safari cannot be read. Update it when a new Safari major ships.
  static let fallbackVersion = "27.0"

  /// Safari's build token. WebKit froze it at 605.1.15 in every Safari UA; it is not a bundle version
  /// and must not be derived from one.
  static let safariBuild = "605.1.15"

  static let safariBundleID = "com.apple.Safari"
  static let defaultSafariPath = "/Applications/Safari.app"

  /// `Version/<installed Safari version> Safari/605.1.15`.
  static func applicationName() -> String {
    applicationName(safariVersion: installedSafariVersion())
  }

  /// `Version/<version> Safari/605.1.15`, or the fallback version when `safariVersion` is missing or malformed.
  static func applicationName(safariVersion: String?) -> String {
    let version = safariVersion.flatMap { isValidVersion($0) ? $0 : nil } ?? fallbackVersion
    return "Version/\(version) Safari/\(safariBuild)"
  }

  /// The installed Safari's marketing version (`CFBundleShortVersionString`, for example `27.0`).
  static func installedSafariVersion() -> String? {
    let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: safariBundleID).flatMap(Bundle.init(url:))
      ?? Bundle(path: defaultSafariPath)
    return bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
  }

  /// Dot-separated numbers, as Safari reports its version.
  static func isValidVersion(_ version: String) -> Bool {
    version.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil
  }
}
