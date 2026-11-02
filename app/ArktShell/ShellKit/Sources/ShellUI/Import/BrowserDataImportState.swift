import Foundation

// The browser data import (#514, direction B "Tiers" of design/browser-data-import): what the consent, progress and
// result views show, as values. ShellUI knows nothing of the coordinator that fills them in (CoreBridge's
// `BrowserDataImportModel` does, behind `BrowserDataImportSource`), so every rule about what a row says, which group
// it sits in and which buttons the state has is plain, testable data.

/// One row of the sheet. The coordinator's bookmarks are their own row (the design's five rows had no place for them).
public enum BrowserDataKind: CaseIterable, Hashable, Sendable {
  case spacesAndTabs, history, bookmarks, extensions, cookies, passwords

  public var title: String {
    switch self {
    case .spacesAndTabs: "Spaces and tabs"
    case .history: "History"
    case .bookmarks: "Bookmarks"
    case .extensions: "Extensions"
    case .cookies: "Cookies"
    case .passwords: "Passwords"
    }
  }

  /// The name in accessibility identifiers (`AXID.BrowserDataImport.row`).
  public var identifier: String {
    switch self {
    case .spacesAndTabs: "spaces"
    case .history: "history"
    case .bookmarks: "bookmarks"
    case .extensions: "extensions"
    case .cookies: "cookies"
    case .passwords: "passwords"
    }
  }

  /// Read with the browser's Safe Storage key, which macOS asks the user's password for.
  public var needsPassword: Bool { self == .cookies || self == .passwords }

  /// The kinds that need no password, in row order.
  public static let readyKinds: [BrowserDataKind] = [.spacesAndTabs, .history, .bookmarks, .extensions]
  /// The kinds behind the Keychain prompt, in row order.
  public static let passwordKinds: [BrowserDataKind] = [.cookies, .passwords]
}

/// What the count pass found. Counts only.
public struct BrowserDataCounts: Equatable, Sendable {
  public var items: [BrowserDataKind: Int]
  /// The Spaces behind the Spaces and tabs count ("in 4 Spaces").
  public var spaces: Int

  public init(items: [BrowserDataKind: Int] = [:], spaces: Int = 0) {
    self.items = items
    self.spaces = spaces
  }

  public subscript(kind: BrowserDataKind) -> Int { max(0, items[kind] ?? 0) }
}

public enum BrowserDataNotImportedReason: Equatable, Sendable {
  /// macOS refused (or the user dismissed) the Keychain prompt.
  case keychainDenied
  /// Attempted and not read or written.
  case unreadable
}

public enum BrowserDataRowStatus: Equatable, Sendable {
  /// Consent: nothing has started.
  case idle
  /// Progress: not reached yet.
  case waiting
  /// The Keychain prompt is up.
  case waitingForMac
  /// `done` of `total` items written; a total of 0 is not known yet.
  case working(done: Int, total: Int)
  /// Came over: `count` items are now in Arkt (written, or already there); `failed` were refused.
  case imported(count: Int, failed: Int)
  /// Not chosen.
  case skipped
  /// Chosen but not run (cancelled, or the engine cannot do it yet).
  case stopped
  case notImported(BrowserDataNotImportedReason)
}

public enum BrowserDataImportPhase: Equatable, Sendable {
  /// The sheet is open and the snapshot and count are running.
  case counting
  case consent
  case progress
  case result
  /// The flow is over; the host closes its view.
  case dismissed
}

public struct BrowserDataImportResult: Equatable, Sendable {
  /// The user cancelled the run; what was written stays.
  public var cancelled = false
  /// Nothing could be read at all (no data found, the copy failed).
  public var couldNotRead = false
  /// A Retry would run something.
  public var canRetry = false
  /// Some batches were written without being recorded, so a later import may write them again.
  public var recordFailed = false

  public init(cancelled: Bool = false, couldNotRead: Bool = false, canRetry: Bool = false, recordFailed: Bool = false) {
    self.cancelled = cancelled; self.couldNotRead = couldNotRead; self.canRetry = canRetry; self.recordFailed = recordFailed
  }
}

public struct BrowserDataImportState: Equatable, Sendable {
  public var phase: BrowserDataImportPhase = .counting
  public var counts = BrowserDataCounts()
  /// The kinds ticked (consent) or chosen (progress and result).
  public var selection: Set<BrowserDataKind> = []
  public var rows: [BrowserDataKind: BrowserDataRowStatus] = [:]
  /// The progress is a Retry's: the Keychain line shows again.
  public var isRetry = false
  /// Cancel was pressed while importing; the run stops after the batch it is writing.
  public var isStopping = false
  public var result = BrowserDataImportResult()
  /// How numbers are written; tests pin it.
  public var locale = Locale.current

  public init() {}

  public init(phase: BrowserDataImportPhase, counts: BrowserDataCounts = BrowserDataCounts(),
              selection: Set<BrowserDataKind> = [], rows: [BrowserDataKind: BrowserDataRowStatus] = [:],
              isRetry: Bool = false, isStopping: Bool = false, result: BrowserDataImportResult = .init(),
              locale: Locale = .current) {
    self.phase = phase; self.counts = counts; self.selection = selection; self.rows = rows
    self.isRetry = isRetry; self.isStopping = isStopping; self.result = result; self.locale = locale
  }
}

// MARK: - Number text

/// Counts as the sheet writes them: grouped digits up to 9,999,999 ("48,210"), then compact ("12.5M", "2.1B"), so a
/// count never wraps and "x of y" stays under 14 characters.
public enum BrowserDataNumberFormat {
  public static func text(_ value: Int, locale: Locale = .current) -> String {
    let value = max(0, value)
    if value <= 9_999_999 {
      let formatter = NumberFormatter()
      formatter.locale = locale
      formatter.numberStyle = .decimal
      formatter.usesGroupingSeparator = true
      return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    var scaled = Double(value) / 1_000_000
    for unit in ["M", "B", "T"] {
      if scaled < 1_000 { return compact(scaled, unit: unit, locale: locale) }
      scaled /= 1_000
    }
    return "999T+"
  }

  private static func compact(_ value: Double, unit: String, locale: Locale) -> String {
    let tenths = (value * 10).rounded(.down) / 10
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    formatter.usesGroupingSeparator = false
    return (formatter.string(from: NSNumber(value: tenths)) ?? String(tenths)) + unit
  }

  /// "30,854 of 48,210".
  public static func progress(done: Int, total: Int, locale: Locale = .current) -> String {
    "\(text(done, locale: locale)) of \(text(total, locale: locale))"
  }

  /// "1 Space", "4 Spaces".
  public static func spaces(_ count: Int, locale: Locale = .current) -> String {
    "\(text(count, locale: locale)) \(count == 1 ? "Space" : "Spaces")"
  }
}
