import Foundation

/// Turns a `RawCrash` into a `CrashReport` (#129, the maintainer's stripping table).
///
/// Kept, by building the report field by field: OS version, architecture, app version and build, engine version, the
/// exception type, the stack frames and the crash ID. Dropped by never copying them: the exception's reason text and
/// every annotation, which is where a page title, a profile or Space name or a URL would arrive. Scrubbed from every
/// string that is kept: URLs, extension IDs, file paths (home becomes `~`, the rest of the path is dropped, any other
/// absolute path becomes `<path>`), the user name, and any name in `redacting`.
public struct CrashReportStripper: Sendable {
  public static let maximumFrames = 128
  public static let maximumSymbolLength = 160
  /// Names shorter than this are not redacted by substring: they would shred ordinary words.
  static let minimumRedactedLength = 3

  private let homeDirectory: String
  private let userName: String
  private let redacting: [String]

  /// - Parameters:
  ///   - homeDirectory: the user's home folder path.
  ///   - userName: the account's short name.
  ///   - redacting: further names to remove wherever they appear (profile and Space names, titles).
  public init(homeDirectory: String, userName: String, redacting: [String] = []) {
    self.homeDirectory = homeDirectory
    self.userName = userName
    self.redacting = redacting
  }

  public func report(from raw: RawCrash, id: String) -> CrashReport {
    CrashReport(
      id: id, createdAt: raw.occurredAt,
      source: raw.source == .metricKit ? .metricKit : .uncaughtException,
      osVersion: allowed(raw.osVersion, pattern: Self.versionPattern),
      architecture: allowed(raw.architecture, pattern: Self.versionPattern),
      appVersion: allowed(raw.appVersion, pattern: Self.versionPattern),
      appBuild: allowed(raw.appBuild, pattern: Self.versionPattern),
      engineVersion: allowed(raw.engineVersion, pattern: Self.versionPattern),
      exceptionType: allowed(raw.exceptionType, pattern: Self.exceptionTypePattern),
      frames: raw.frames.prefix(Self.maximumFrames).map(frame(from:)))
  }

  /// `text` with every forbidden thing removed. Exposed for the stripping tests.
  public func scrub(_ text: String) -> String {
    var result = text
    for name in redacting where name.count >= Self.minimumRedactedLength {
      result = Self.replacing(name, in: result, with: "<redacted>", wholeWord: false)
    }
    if !homeDirectory.isEmpty { result = Self.replacingTail(from: homeDirectory, in: result, with: "~") }
    result = result.replacing(#/~\/[^\n]*/#, with: "~")
    result = result.replacing(#/[A-Za-z][A-Za-z0-9+.\-]*:\/\/[^\s]*/#, with: "<url>")
    result = result.replacing(#/(?i)(?:mailto:|\bwww\.)[^\s]*/#, with: "<url>")
    result = result.replacing(#/\b[a-p]{32}\b/#, with: "<extension>")
    result = result.replacing(#/(^|[\s("'=,\[])\/[\w.~@+\-]+\/[^\n]*/#) { "\($0.output.1)<path>" }
    if !userName.isEmpty {
      result = Self.replacing(userName, in: result, with: "<user>", wholeWord: userName.count < Self.minimumRedactedLength)
    }
    return result
  }

  // MARK: Fields

  private func frame(from raw: RawFrame) -> CrashReport.Frame {
    let name = raw.image.split(separator: "/").last.map(String.init) ?? raw.image
    let image = scrub(name)
    let symbol = raw.symbol.map { String(scrub($0).prefix(Self.maximumSymbolLength)) }
    let uuid = raw.uuid.flatMap { $0.wholeMatch(of: #/[0-9A-Fa-f\-]{36}/#) == nil ? nil : $0 }
    return .init(image: image.isEmpty ? "unknown" : image, offset: raw.offset, symbol: symbol, uuid: uuid)
  }

  /// `value` when it is short and made of plain characters, else "unknown". The allow-list is the point: a string that
  /// is not what the field should hold is not kept, whatever it holds.
  private func allowed(_ value: String, pattern: Regex<Substring>) -> String {
    guard value.wholeMatch(of: pattern) != nil else { return "unknown" }
    return scrub(value)
  }

  private static var versionPattern: Regex<Substring> { #/[A-Za-z0-9._() +\-]{1,64}/# }
  private static var exceptionTypePattern: Regex<Substring> { #/[A-Za-z0-9._() +\-]{1,64}/# }

  // MARK: Replacing

  /// Every case-insensitive occurrence of `needle` replaced; with `wholeWord`, only where letters and digits do not
  /// touch it.
  private static func replacing(_ needle: String, in text: String, with replacement: String, wholeWord: Bool) -> String {
    var result = ""
    var rest = text[...]
    while let found = rest.range(of: needle, options: .caseInsensitive) {
      result += rest[..<found.lowerBound]
      let before = result.last
      let after = rest[found.upperBound...].first
      let touches = wholeWord && (before?.isLetterOrNumber == true || after?.isLetterOrNumber == true)
      result += touches ? String(rest[found]) : replacement
      rest = rest[found.upperBound...]
    }
    return result + rest
  }

  /// Each occurrence of `marker` and everything after it to the end of its line replaced.
  private static func replacingTail(from marker: String, in text: String, with replacement: String) -> String {
    var result = ""
    var rest = text[...]
    while let found = rest.range(of: marker) {
      result += rest[..<found.lowerBound] + replacement
      rest = rest[found.upperBound...]
      rest = rest.drop { !$0.isNewline }
    }
    return result + rest
  }
}

private extension Character {
  var isLetterOrNumber: Bool { isLetter || isNumber }
}
