import Foundation

/// One crash as Arkt keeps it on disk and hands it to GitHub (#129): an allow-list of fields, each already stripped
/// (`CrashReportStripper`). Never a URL, a title, a file path, a user name, a profile or Space name or an extension ID.
public struct CrashReport: Codable, Equatable, Sendable {
  public enum Source: String, Codable, Sendable {
    /// An `MXCrashDiagnostic`, delivered by MetricKit on a later launch.
    case metricKit
    /// The uncaught `NSException` handler, written as the process went down.
    case uncaughtException
  }

  public struct Frame: Codable, Equatable, Sendable {
    /// The binary's name, never its path.
    public var image: String
    /// The offset into the image's text segment, so a dSYM can symbolicate the frame later.
    public var offset: Int?
    public var symbol: String?
    /// The image's build UUID, so a dSYM can symbolicate the offsets after the fact. nil when unknown.
    public var uuid: String?

    public init(image: String, offset: Int?, symbol: String?, uuid: String? = nil) {
      self.image = image
      self.offset = offset
      self.symbol = symbol
      self.uuid = uuid
    }
  }

  /// A random id; the file name and the issue title.
  public var id: String
  /// When the crash happened (or, for MetricKit, when its payload was delivered). Retention counts from it.
  public var createdAt: Date
  public var source: Source
  public var osVersion: String
  public var architecture: String
  public var appVersion: String
  public var appBuild: String
  public var engineVersion: String
  public var exceptionType: String
  public var frames: [Frame]
  /// An uncaught-exception report that a MetricKit abort diagnostic already matched, so the abort is not stored twice.
  public var abortCovered: Bool

  public init(id: String, createdAt: Date, source: Source, osVersion: String, architecture: String,
              appVersion: String, appBuild: String, engineVersion: String, exceptionType: String,
              frames: [Frame], abortCovered: Bool = false) {
    self.id = id
    self.createdAt = createdAt
    self.source = source
    self.osVersion = osVersion
    self.architecture = architecture
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.engineVersion = engineVersion
    self.exceptionType = exceptionType
    self.frames = frames
    self.abortCovered = abortCovered
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    createdAt = try values.decode(Date.self, forKey: .createdAt)
    source = try values.decode(Source.self, forKey: .source)
    osVersion = try values.decode(String.self, forKey: .osVersion)
    architecture = try values.decode(String.self, forKey: .architecture)
    appVersion = try values.decode(String.self, forKey: .appVersion)
    appBuild = try values.decode(String.self, forKey: .appBuild)
    engineVersion = try values.decode(String.self, forKey: .engineVersion)
    exceptionType = try values.decode(String.self, forKey: .exceptionType)
    frames = try values.decode([Frame].self, forKey: .frames)
    abortCovered = try values.decodeIfPresent(Bool.self, forKey: .abortCovered) ?? false
  }
}

/// What a capture source hands over, before stripping. It may hold anything the crash exposed: the exception's reason
/// text, annotations, full image paths. Only `CrashReportStripper` turns it into a `CrashReport`.
public struct RawCrash: Sendable {
  public enum Source: Sendable { case metricKit, uncaughtException }

  public var source: Source
  public var occurredAt: Date
  public var osVersion: String
  public var architecture: String
  public var appVersion: String
  public var appBuild: String
  public var engineVersion: String
  public var exceptionType: String
  /// SIGABRT or EXC_CRASH: what an uncaught Objective-C exception ends in.
  public var isAbort: Bool
  /// Free text; never kept.
  public var exceptionReason: String?
  public var frames: [RawFrame]
  /// Free key-value data; never kept.
  public var annotations: [String: String]

  public init(source: Source, occurredAt: Date, osVersion: String, architecture: String, appVersion: String,
              appBuild: String, engineVersion: String, exceptionType: String, isAbort: Bool,
              exceptionReason: String?, frames: [RawFrame], annotations: [String: String]) {
    self.source = source
    self.occurredAt = occurredAt
    self.osVersion = osVersion
    self.architecture = architecture
    self.appVersion = appVersion
    self.appBuild = appBuild
    self.engineVersion = engineVersion
    self.exceptionType = exceptionType
    self.isAbort = isAbort
    self.exceptionReason = exceptionReason
    self.frames = frames
    self.annotations = annotations
  }
}

public struct RawFrame: Equatable, Sendable {
  /// A binary name or a full path.
  public var image: String
  public var offset: Int?
  public var symbol: String?
  public var uuid: String?

  public init(image: String, offset: Int?, symbol: String?, uuid: String? = nil) {
    self.image = image
    self.offset = offset
    self.symbol = symbol
    self.uuid = uuid
  }

  /// One line of `NSException.callStackSymbols` ("3   AppKit   0x00000001a3b4c5d0 -[NSApplication run] + 480"); nil
  /// when it does not look like one.
  public static func parse(callStackSymbol line: String) -> RawFrame? {
    guard let match = line.wholeMatch(of: #/\s*\d+\s+(.+?)\s+0x[0-9a-fA-F]+\s*(.*?)\s*/#) else { return nil }
    let symbol = String(match.output.2)
    return RawFrame(image: String(match.output.1), offset: nil, symbol: symbol.isEmpty ? nil : symbol)
  }
}
