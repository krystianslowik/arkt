import Foundation

/// Reports kept on this Mac, one JSON file per report in `directory` (#129): at most 20, none older than 30 days.
/// Synchronous file work; the app calls it off the main actor, except the uncaught-exception handler, which writes
/// as the process goes down.
public struct CrashReportStore: Sendable {
  public static let maximumCount = 20
  public static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

  public enum StoreError: Error, Equatable {
    /// An id that could be a path; ids are generated, so this is a bug, not a user condition.
    case unsafeID
  }

  public let directory: URL
  private let now: @Sendable () -> Date

  /// `now` is the clock retention counts with; tests inject theirs.
  public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
    self.directory = directory
    self.now = now
  }

  /// Writes `report`, then applies the retention limits.
  public func save(_ report: CrashReport) throws {
    guard Self.isSafe(report.id) else { throw StoreError.unsafeID }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Self.encoder.encode(report).write(to: file(for: report.id), options: .atomic)
    _ = try reports()
  }

  /// Every kept report, newest first, after retention removed the expired and the surplus. A file that does not read
  /// as a report is deleted.
  public func reports() throws -> [CrashReport] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
    var kept: [CrashReport] = []
    for name in names where name.hasSuffix(".json") {
      let url = directory.appendingPathComponent(name)
      if let data = try? Data(contentsOf: url), let report = try? Self.decoder.decode(CrashReport.self, from: data),
         name == "\(report.id).json" {
        kept.append(report)
      } else {
        try? FileManager.default.removeItem(at: url)
      }
    }
    let cutoff = now().addingTimeInterval(-Self.maximumAge)
    kept.sort { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    var result: [CrashReport] = []
    for report in kept {
      if report.createdAt < cutoff || result.count >= Self.maximumCount {
        try? FileManager.default.removeItem(at: file(for: report.id))
      } else {
        result.append(report)
      }
    }
    return result
  }

  public func remove(id: String) {
    guard Self.isSafe(id) else { return }
    try? FileManager.default.removeItem(at: file(for: id))
  }

  public func removeAll() {
    try? FileManager.default.removeItem(at: directory)
  }

  /// Deletes every report except the `count` newest.
  public func keepNewest(_ count: Int) {
    guard let all = try? reports() else { return }
    for report in all.dropFirst(count) { remove(id: report.id) }
  }

  private func file(for id: String) -> URL { directory.appendingPathComponent("\(id).json") }

  private static func isSafe(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
