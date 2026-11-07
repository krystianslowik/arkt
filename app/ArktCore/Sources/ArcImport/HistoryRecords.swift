import Foundation

/// Chromium (WebKit) time: microseconds since 1601-01-01 UTC.
enum WebKitTime {
  /// Seconds between 1601-01-01 and 1970-01-01.
  static let unixEpochOffsetSeconds: Int64 = 11_644_473_600

  /// The date for `microseconds`, or nil for zero and negative values, which Chromium uses for "unset".
  static func date(fromMicroseconds microseconds: Int64) -> Date? {
    guard microseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - Double(unixEpochOffsetSeconds))
  }
}

/// The core page transition of a visit, decoded from the low 8 bits of Chromium's `transition` value. The qualifier
/// flags above those bits (chain start and end, address bar, and so on) are ignored.
public enum HistoryTransition: Sendable, Equatable, CaseIterable {
  case link
  case typed
  case autoBookmark
  case autoSubframe
  case manualSubframe
  case generated
  case autoToplevel
  case formSubmit
  case reload
  case keyword
  case keywordGenerated
  /// A core value this reader does not know.
  case unknown

  /// Mask for the core type in Chromium's `ui::PageTransition`.
  static let coreMask: Int32 = 0xFF

  /// Chromium's core `ui::PageTransition` value, the inverse of `init(webKitValue:)`. A core value this reader does not
  /// know comes back as a link, the value Chromium treats as the default.
  public var coreValue: Int {
    switch self {
    case .link, .unknown: 0
    case .typed: 1
    case .autoBookmark: 2
    case .autoSubframe: 3
    case .manualSubframe: 4
    case .generated: 5
    case .autoToplevel: 6
    case .formSubmit: 7
    case .reload: 8
    case .keyword: 9
    case .keywordGenerated: 10
    }
  }

  public init(webKitValue: Int32) {
    switch webKitValue & Self.coreMask {
    case 0: self = .link
    case 1: self = .typed
    case 2: self = .autoBookmark
    case 3: self = .autoSubframe
    case 4: self = .manualSubframe
    case 5: self = .generated
    case 6: self = .autoToplevel
    case 7: self = .formSubmit
    case 8: self = .reload
    case 9: self = .keyword
    case 10: self = .keywordGenerated
    default: self = .unknown
    }
  }
}

/// One visit to a URL.
public struct HistoryVisit: Sendable, Equatable {
  public let time: Date
  public let transition: HistoryTransition

  public init(time: Date, transition: HistoryTransition) {
    self.time = time
    self.transition = transition
  }
}

/// One `urls` row with its visits, oldest visit first.
public struct HistoryEntry: Sendable, Equatable {
  public let url: String
  public let title: String
  public let visitCount: Int
  public let typedCount: Int
  public let lastVisit: Date?
  public let visits: [HistoryVisit]

  public init(url: String, title: String, visitCount: Int, typedCount: Int, lastVisit: Date?, visits: [HistoryVisit]) {
    self.url = url
    self.title = title
    self.visitCount = visitCount
    self.typedCount = typedCount
    self.lastVisit = lastVisit
    self.visits = visits
  }
}
