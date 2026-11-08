import Foundation

/// A read-only, per-launch view of the injected store. The first value is frozen before windows can write.
@MainActor
public final class WindowSessionObservation {
  public enum RawValue: Codable, Equatable {
    case absent
    case nonData
    case data(Data)

    public init(object: Any?) {
      guard let object else { self = .absent; return }
      guard let data = object as? Data else { self = .nonData; return }
      self = .data(data)
    }
  }

  public struct Report: Codable, Equatable {
    public let launchID: String
    public let initial: RawValue
    public let current: RawValue
    public let launchComplete: Bool

    public func json() throws -> String {
      let data = try JSONEncoder().encode(self)
      guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.coderInvalidValue) }
      return text
    }

    public static func decode(_ text: String) throws -> Report {
      try JSONDecoder().decode(Report.self, from: Data(text.utf8))
    }
  }

  private let read: @MainActor () -> Any?
  private let initial: RawValue
  private let launchID: String
  private var launchComplete = false

  public init(read: @escaping @MainActor () -> Any?, launchID: String = UUID().uuidString) {
    self.read = read
    self.initial = RawValue(object: read())
    self.launchID = launchID
  }

  public var snapshot: Report {
    Report(launchID: launchID, initial: initial, current: RawValue(object: read()), launchComplete: launchComplete)
  }

  public func finishLaunch() { launchComplete = true }
}
