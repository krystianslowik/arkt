import Foundation

/// The prefilled GitHub issue "Send Crash Report" opens in the browser (#129). Nothing is sent: the user reviews the
/// issue and submits it. The link carries the stripped report only, and the stack is cut, with a note, when the whole
/// report would not fit the URL length limit.
public struct GitHubIssueLink: Equatable, Sendable {
  public static let repository = "krystianslowik/arkt"
  /// GitHub refuses very long URLs (around 8 KB); browsers and proxies are stricter still.
  public static let defaultMaxLength = 7_000

  public let url: URL
  public let shownFrames: Int
  public let totalFrames: Int

  public var truncated: Bool { shownFrames < totalFrames }

  /// The longest stack, top frame first, whose URL is at most `maxLength` characters. With no frame the URL can still
  /// be longer than `maxLength` only for a limit below about 700.
  public static func make(for report: CrashReport, maxLength: Int = defaultMaxLength) -> GitHubIssueLink {
    let total = report.frames.count
    var shown = total
    while true {
      let url = url(for: report, shownFrames: shown)
      if url.absoluteString.count <= maxLength || shown == 0 {
        return GitHubIssueLink(url: url, shownFrames: shown, totalFrames: total)
      }
      shown -= 1
    }
  }

  // MARK: Building

  private static func url(for report: CrashReport, shownFrames: Int) -> URL {
    let title = "Crash report \(report.id.prefix(8)): \(report.exceptionType)"
    let query = "title=\(encode(title))&body=\(encode(body(for: report, shownFrames: shownFrames)))"
    return URL(string: "https://github.com/\(repository)/issues/new?\(query)") ?? URL(filePath: "/")
  }

  static func body(for report: CrashReport, shownFrames: Int) -> String {
    var lines = [
      "Arkt quit unexpectedly. This report has no web addresses, page titles, file paths or names. "
        + "Review it before you submit.",
      "",
      "Crash ID: \(report.id)",
      "Exception type: \(report.exceptionType)",
      "Arkt: \(report.appVersion) (\(report.appBuild))",
      "Engine: \(report.engineVersion)",
      "macOS: \(report.osVersion)",
      "Architecture: \(report.architecture)",
      "",
      "Stack, top frame first:",
      "```",
    ]
    for (index, frame) in report.frames.prefix(shownFrames).enumerated() {
      var line = "\(index)  \(frame.image)"
      if let offset = frame.offset { line += "  +\(offset)" }
      if let symbol = frame.symbol, !symbol.isEmpty { line += "  \(symbol)" }
      lines.append(line)
    }
    lines.append("```")
    var seen: Set<String> = []
    let images = report.frames.prefix(shownFrames).compactMap { frame -> String? in
      guard let uuid = frame.uuid, seen.insert(frame.image).inserted else { return nil }
      return "\(frame.image) \(uuid)"
    }
    if !images.isEmpty { lines += ["Images:", "```"] + images + ["```"] }
    if shownFrames < report.frames.count {
      lines.append("Stack truncated: showing \(shownFrames) of \(report.frames.count) frames, "
        + "so this link fits the URL length limit.")
    }
    return lines.joined(separator: "\n")
  }

  private static let unreserved = CharacterSet(charactersIn:
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  private static func encode(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
  }
}
