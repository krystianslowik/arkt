import Foundation

/// Reads the Chrome Web Store extensions installed in an Arc profile from `extensions.settings` (#510).
///
/// The reader works on the scratch copy made by `ArcProfileSnapshot`, never on Arc's own files. It reads the
/// `Preferences` and `Secure Preferences` copies, merges them per extension id and keeps only Web Store installs.
/// It does not touch the extension files, the network or the Keychain.
public enum ExtensionListReader {
  /// Where an extension came from, as Chromium's `ManifestLocation` (`extensions/common/mojom/manifest.mojom`).
  /// Only the two Web Store locations are kept, so only they are represented.
  public enum Location: Int, Sendable, Equatable {
    /// `kInternal = 1`: a crx from the profile's own Extensions directory, including user-installed Web Store items.
    case `internal` = 1
    /// `kExternalComponent = 10`: an internal detail of the browser installed from an update URL.
    case externalComponent = 10
  }

  public struct Entry: Sendable, Equatable {
    public let id: String
    /// The manifest name, or nil when the preferences hold no manifest or only a `__MSG_` placeholder.
    public let name: String?
    public let isEnabled: Bool
    public let location: Location

    public init(id: String, name: String?, isEnabled: Bool, location: Location) {
      self.id = id
      self.name = name
      self.isEnabled = isEnabled
      self.location = location
    }
  }

  public enum ReadError: Error, Sendable, Equatable {
    /// The named file is not a JSON object.
    case malformedJSON(file: String)
  }

  private static let preferencesName = "Preferences"
  private static let secureName = "Secure Preferences"

  // MARK: - Reading

  /// Reads the copies of `Preferences` and `Secure Preferences` in a snapshot profile. A file that was not copied
  /// counts as absent. Throws `ReadError.malformedJSON` for a copied file that is not a JSON object.
  public static func read(profile: ArcProfileSnapshot.Profile) throws -> [Entry] {
    func contents(_ name: String) -> Data? {
      guard profile.copied.contains(name) else { return nil }
      return try? Data(contentsOf: profile.directory.appendingPathComponent(name))
    }
    return try read(preferences: contents(preferencesName), securePreferences: contents(secureName))
  }

  /// Merges the two files (Secure Preferences wins on a conflicting key) and returns the Web Store extensions sorted
  /// by id. Absent data and absent or mistyped keys give an empty result.
  public static func read(preferences: Data?, securePreferences: Data?) throws -> [Entry] {
    var merged: [String: JSONValue] = [:]
    for (name, data) in [(preferencesName, preferences), (secureName, securePreferences)] {
      guard let data else { continue }
      for (id, value) in try settings(in: data, file: name) {
        merged[id] = merge(merged[id], value)
      }
    }
    return merged.keys.sorted().compactMap { id in merged[id].flatMap { entry(id: id, value: $0) } }
  }

  // MARK: - Parsing

  private static func settings(in data: Data, file: String) throws -> [String: JSONValue] {
    guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let top) = root else {
      throw ReadError.malformedJSON(file: file)
    }
    guard case .object(let section)? = top["extensions"], case .object(let settings)? = section["settings"] else {
      return [:]
    }
    return settings
  }

  /// Deep merge of two JSON objects; `overlay` wins on conflicts and on non-object values.
  private static func merge(_ base: JSONValue?, _ overlay: JSONValue) -> JSONValue {
    guard case .object(let lhs)? = base, case .object(let rhs) = overlay else { return overlay }
    return .object(lhs.merging(rhs) { merge($0, $1) })
  }

  private static func entry(id: String, value: JSONValue) -> Entry? {
    guard case .object(let fields) = value, let location = location(fields["location"]) else { return nil }
    var manifest: [String: JSONValue] = [:]
    if case .object(let object)? = fields["manifest"] { manifest = object }
    var updateURL: String?
    if case .string(let text)? = manifest["update_url"] { updateURL = text }

    switch (location, updateURL) {
    case (.internal, nil): break
    case (_, let url?) where isWebStoreUpdateURL(url): break
    default: return nil
    }
    return Entry(id: id, name: name(manifest["name"]), isEnabled: isEnabled(fields), location: location)
  }

  private static func location(_ value: JSONValue?) -> Location? {
    switch value {
    case .int(let raw)?: Int(exactly: raw).flatMap(Location.init(rawValue:))
    case .number(let raw)?: Int(exactly: raw).flatMap(Location.init(rawValue:))
    default: nil
    }
  }

  private static func name(_ value: JSONValue?) -> String? {
    guard case .string(let text)? = value, !text.isEmpty, !text.hasPrefix("__MSG_") else { return nil }
    return text
  }

  /// Chromium stores `state` 1 for enabled; a nonzero `disable_reasons` marks it disabled as well.
  private static func isEnabled(_ fields: [String: JSONValue]) -> Bool {
    guard case .int(1)? = fields["state"] else { return false }
    switch fields["disable_reasons"] {
    case .int(let reasons)?: return reasons == 0
    case .array(let reasons)?: return reasons.isEmpty
    default: return true
    }
  }

  /// The Chrome Web Store update endpoints: `clients2.google.com/service/update2/crx` and the older
  /// `chrome.google.com/webstore/...`. The host must match exactly.
  private static func isWebStoreUpdateURL(_ text: String) -> Bool {
    guard let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
      return false
    }
    switch host {
    case "clients2.google.com": return url.path.hasPrefix("/service/update2/crx")
    case "chrome.google.com": return url.path.hasPrefix("/webstore/")
    default: return false
    }
  }
}
