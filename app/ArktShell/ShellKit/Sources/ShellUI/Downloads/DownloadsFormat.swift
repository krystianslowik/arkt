import EngineAPI
import Foundation

/// The Library button's state (design/downloads, direction B): nothing, the ring filling, a finished set waiting to be
/// seen, or a failed or held file waiting for a decision.
public enum DownloadsRingState: Equatable, Sendable {
  case idle
  /// Downloads are running; `fraction` is the whole's progress (0 to 1), nil when no active download knows its size.
  case active(fraction: Double?)
  /// Everything finished and the Library has not been opened since.
  case done
  /// A download failed, or a file is held for the user's decision, and the Library has not been opened since.
  case attention
}

/// A tile for a file type: the extension on a fixed mid-tone fill, white text in light and dark.
public struct DownloadFileKind: Equatable, Sendable {
  public var label: String
  public var fillHex: Int
}

/// A day's worth of rows in the Library.
public struct DownloadsSection: Equatable, Sendable {
  public var title: String
  public var items: [DownloadItem]
}

/// The words and numbers of the Downloads UI, as pure functions (design/downloads, Behavior and VoiceOver). Copy never
/// says "Arc".
public enum DownloadsFormat {
  private static let dot = " \u{00B7} "

  // MARK: Sizes and time

  /// "96 KB", "1.8 MB", "42 MB", "2.4 GB": decimal units, one decimal at most, none from 100 up.
  public static func size(_ bytes: Int64, locale: Locale = .current) -> String {
    guard bytes >= 1_000 else { return "\(max(bytes, 0)) B" }
    let units = ["KB", "MB", "GB", "TB"]
    var value = Double(bytes) / 1_000
    var index = 0
    while value >= 1_000, index < units.count - 1 {
      value /= 1_000
      index += 1
    }
    let digits: ClosedRange<Int> = value >= 100 ? 0...0 : 0...1
    return value.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " " + units[index]
  }

  /// "20 s", "2 min", "1 h 05 min"; under three seconds "Almost done".
  public static func timeLeft(seconds: Int) -> String {
    if seconds < 3 { return "Almost done" }
    if seconds < 60 { return "\(seconds) s" }
    let minutes = Int((Double(seconds) / 60).rounded())
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
  }

  private static func timeLeftPhrase(_ seconds: Int) -> String {
    let text = timeLeft(seconds: seconds)
    return seconds < 3 ? text : text + " left"
  }

  // MARK: Lines under a name

  /// "42 MB of 310 MB · 2 min left" for an active download; "Paused · 42 MB of 310 MB" while paused. An unknown total
  /// shows the amount only; a stalled download shows no time.
  public static func activeLine(_ item: DownloadItem, locale: Locale = .current) -> String {
    var amount = size(item.receivedBytes, locale: locale)
    if let total = item.totalBytes { amount += " of " + size(total, locale: locale) }
    if item.state == .paused { return "Paused" + dot + amount }
    if let left = item.secondsRemaining { amount += dot + timeLeftPhrase(left) }
    return amount
  }

  /// The popover's second line: progress, "Done, 212 MB", "Failed, Connection lost", "Unsafe file".
  public static func popoverLine(_ item: DownloadItem, locale: Locale = .current) -> String {
    if item.dangerType.needsSheet { return "Unsafe file" }
    switch item.state {
    case .inProgress, .paused: return activeLine(item, locale: locale)
    case .complete: return "Done, " + size(item.receivedBytes, locale: locale)
    case .cancelled: return "Cancelled"
    case .interrupted(let reason): return "Failed, " + reason.failureWords
    }
  }

  /// The Library row's second line, with the speed while active and the host when finished.
  public static func libraryLine(_ item: DownloadItem, locale: Locale = .current) -> String {
    let host = host(of: item.url)
    var parts: [String] = []
    if item.dangerType.needsSheet {
      parts = ["Blocked", blockedReason(item.dangerType)]
    } else {
      switch item.state {
      case .inProgress, .paused:
        var line = activeLine(item, locale: locale)
        if item.state == .inProgress, item.bytesPerSecond > 0 { line += dot + size(item.bytesPerSecond, locale: locale) + "/s" }
        return line
      case .complete:
        parts = [kind(of: item.filename).label, size(item.receivedBytes, locale: locale)]
      case .cancelled:
        parts = ["Cancelled"]
      case .interrupted(let reason):
        parts = ["Failed", reason.failureWords]
      }
    }
    if !host.isEmpty { parts.append(host) }
    if item.dangerType.isUncommon, item.state == .complete { parts.append("Not commonly downloaded") }
    return parts.joined(separator: dot)
  }

  private static func blockedReason(_ type: DownloadDangerType) -> String {
    switch type {
    case .blockedTooLarge: "too large"
    case .blockedPasswordProtected: "password protected"
    case .blockedScanFailed, .deepScannedFailed: "could not be checked"
    case .sensitiveContentBlock, .sensitiveContentWarning: "sensitive content"
    default: "may be harmful"
    }
  }

  // MARK: Tiles

  /// The tile for a file name: its extension (at most four letters) on a fixed fill by family. No extension reads
  /// "FILE".
  public static func kind(of filename: String) -> DownloadFileKind {
    let ext = (filename as NSString).pathExtension.lowercased()
    guard !ext.isEmpty else { return DownloadFileKind(label: "FILE", fillHex: 0x6A6F76) }
    let fill: Int
    switch ext {
    case "zip", "gz", "tgz", "tar", "7z", "rar", "bz2", "xz": fill = 0x4A6A96
    case "pdf": fill = 0xB84A36
    case "mp4", "mov", "mkv", "avi", "m4v", "webm": fill = 0x6B4FB0
    case "dmg", "iso": fill = 0x4A5A4E
    case "csv", "xls", "xlsx", "numbers", "tsv": fill = 0x3C7A52
    case "pkg", "app": fill = 0x8A5A2E
    default: fill = 0x6A6F76
    }
    return DownloadFileKind(label: String(ext.uppercased().prefix(4)), fillHex: fill)
  }

  /// The URL's host without a leading "www."; empty for a URL with none.
  public static func host(of url: URL) -> String {
    guard let host = url.host() else { return "" }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  // MARK: VoiceOver

  /// "Downloading <name>, 13 percent"; "<name>, finished", "failed", "cancelled", "blocked".
  public static func accessibilityLabel(_ item: DownloadItem) -> String {
    if item.dangerType.needsSheet { return "\(item.filename), blocked" }
    switch item.state {
    case .inProgress:
      return item.fraction.map { "Downloading \(item.filename), \(Int($0 * 100)) percent" } ?? "Downloading \(item.filename)"
    case .paused:
      return item.fraction.map { "\(item.filename), paused, \(Int($0 * 100)) percent" } ?? "\(item.filename), paused"
    case .complete: return "\(item.filename), finished"
    case .cancelled: return "\(item.filename), cancelled"
    case .interrupted: return "\(item.filename), failed"
    }
  }

  /// "Library, downloading 13 percent" or "Library, downloads finished".
  public static func libraryButtonLabel(_ state: DownloadsRingState) -> String {
    switch state {
    case .idle: "Library"
    case .active(let fraction?): "Library, downloading \(Int(fraction * 100)) percent"
    case .active(nil): "Library, downloading"
    case .done: "Library, downloads finished"
    case .attention: "Library, a download needs attention"
    }
  }

  /// The last of 0, 25, 50 and 75 a download has reached: progress is announced when the bucket rises, never on every
  /// tick.
  public static func announcementBucket(fraction: Double?) -> Int {
    guard let fraction else { return 0 }
    return min(75, Int(fraction * 4) * 25)
  }

  // MARK: Groups

  /// The Library's days, newest first; a day with no downloads has no section.
  public static func sections(_ items: [DownloadItem], now: Date, calendar: Calendar = .current) -> [DownloadsSection] {
    let sorted = items.sorted { $0.startTime > $1.startTime }
    var today: [DownloadItem] = [], yesterday: [DownloadItem] = [], earlier: [DownloadItem] = []
    for item in sorted {
      if calendar.isDate(item.startTime, inSameDayAs: now) {
        today.append(item)
      } else if let day = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(item.startTime, inSameDayAs: day) {
        yesterday.append(item)
      } else {
        earlier.append(item)
      }
    }
    return [("Today", today), ("Yesterday", yesterday), ("Earlier", earlier)]
      .filter { !$0.1.isEmpty }
      .map { DownloadsSection(title: $0.0, items: $0.1) }
  }
}
