import ArcImport
import EngineAPI
import Foundation

/// The kinds of browser data the profile import moves, in the order the coordinator imports them: history, bookmarks,
/// cookies, passwords, extensions (#515).
public enum ImportDataType: String, CaseIterable, Sendable, Hashable {
  case history
  case bookmarks
  case cookies
  case passwords
  case extensions

  /// Whether the type is read with the Safe Storage key.
  var needsKey: Bool { self == .cookies || self == .passwords }

  /// "visit", "bookmark" and so on, for counts-only text.
  var noun: String {
    switch self {
    case .history: "visit"
    case .bookmarks: "bookmark"
    case .cookies: "cookie"
    case .passwords: "password"
    case .extensions: "extension"
    }
  }

  var title: String {
    switch self {
    case .history: "History"
    case .bookmarks: "Bookmarks"
    case .cookies: "Cookies"
    case .passwords: "Passwords"
    case .extensions: "Extensions"
    }
  }
}

/// The types the user ticked on the consent sheet. Every type is ticked by default; cookies and passwords included
/// (maintainer decision for v1).
public struct ImportSelection: Equatable, Sendable {
  public var types: Set<ImportDataType>

  public init(_ types: Set<ImportDataType> = Set(ImportDataType.allCases)) { self.types = types }

  public static let `default` = ImportSelection()
}

/// Counts of one type's import: how many items were stored, skipped on purpose and refused. Counts only.
public struct ImportItemCounts: Equatable, Sendable {
  public var written = 0
  public var skipped = 0
  public var failed = 0

  public init(written: Int = 0, skipped: Int = 0, failed: Int = 0) {
    self.written = written; self.skipped = skipped; self.failed = failed
  }

  mutating func add(_ result: ImportWriteResult) {
    written += result.written; skipped += result.skipped; failed += result.failed
  }
}

/// How one type's import ended.
public enum ImportTypeOutcome: Equatable, Sendable {
  case done(ImportItemCounts)
  /// Not attempted, with a fixed reason such as "not yet available" or "cancelled".
  case skipped(reason: String)
  /// Attempted and not completed, with a fixed reason such as "Keychain access denied". Retry covers these.
  case failed(reason: String)
}

/// A type's progress, as the progress stream reports it.
public enum ImportProgress: Equatable, Sendable {
  case counting
  /// `done` of `total` items written so far (visits for history).
  case writing(done: Int, total: Int)
  case done(ImportItemCounts)
  case skipped(reason: String)
  case failed(reason: String)
}

public enum ProfileImportEvent: Equatable, Sendable {
  case progress(ImportDataType, ImportProgress)
  /// The count pass finished; the consent sheet shows these.
  case counted(ProfileDataCounts)
  /// Always the last event of a run.
  case finished(ProfileImportSummary)
}

/// What a profile import did, as counts and fixed phrases only: no host, URL, title, username or value.
public struct ProfileImportSummary: Equatable, Sendable {
  public var outcomes: [ImportDataType: ImportTypeOutcome] = [:]
  /// The run was cancelled; what was written before is kept and a re-import adds only what is new.
  public var cancelled = false
  /// The run could not start at all (no Arc data, the snapshot failed, the record could not be read).
  public var abortReason: String?
  /// A batch was written but its keys could not be recorded, so a re-import may write it again.
  public var recordFailed = false

  public init() {}

  /// The types a Retry runs again: only the ones that failed, in import order.
  public var retryTypes: [ImportDataType] {
    ImportDataType.allCases.filter {
      if case .failed? = outcomes[$0] { return true } else { return false }
    }
  }

  public var canRetry: Bool { !retryTypes.isEmpty }

  /// One line per attempted type, for the summary sheet.
  public var lines: [String] {
    var lines: [String] = []
    if let abortReason { lines.append("Nothing imported: \(abortReason)") }
    for type in ImportDataType.allCases {
      guard let outcome = outcomes[type] else { continue }
      switch outcome {
      case .done(let counts):
        var parts = ["\(counts.written) \(type.noun)\(counts.written == 1 ? "" : "s") added"]
        if counts.skipped > 0 { parts.append("\(counts.skipped) skipped") }
        if counts.failed > 0 { parts.append("\(counts.failed) failed") }
        lines.append("\(type.title): " + parts.joined(separator: ", "))
      case .skipped(let reason): lines.append("\(type.title): skipped, \(reason)")
      case .failed(let reason): lines.append("\(type.title): not imported, \(reason)")
      }
    }
    if cancelled { lines.append("Cancelled: what was imported is kept") }
    if recordFailed { lines.append("Some items may be imported again next time") }
    return lines
  }
}

public enum ProfileImportError: Error, Equatable, Sendable {
  case alreadyRunning
}

/// Batch sizes of one run; tests shrink them to step through the batches.
public struct ProfileImportConfiguration: Equatable, Sendable {
  /// Items per engine call for bookmarks, cookies and passwords.
  public var batchSize: Int
  /// Visits per engine call for history.
  public var historyVisitsPerBatch: Int
  /// Where the snapshot's scratch folder is made.
  public var scratchParent: URL

  public init(
    batchSize: Int = 500, historyVisitsPerBatch: Int = 2_000,
    scratchParent: URL = FileManager.default.temporaryDirectory
  ) {
    self.batchSize = max(1, batchSize)
    self.historyVisitsPerBatch = max(1, historyVisitsPerBatch)
    self.scratchParent = scratchParent
  }
}
