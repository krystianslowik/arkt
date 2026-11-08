import Foundation

/// Value-only link routing. The first matching route in list order supplies the destination.
public struct LinkRouting: Codable, Hashable, Sendable {
  public enum Condition: Codable, Hashable, Sendable {
    case contains(String)
    case matches(String)

    /// Contains ignores case; matches compares the exact absolute string without URL normalization.
    public func applies(to url: URL) -> Bool {
      switch self {
      case .contains(let text): text.isEmpty || url.absoluteString.range(of: text, options: .caseInsensitive) != nil
      case .matches(let text): url.absoluteString == text
      }
    }
  }

  public enum Destination: Codable, Hashable, Sendable {
    case space(SpaceID)
    case littleArkt
    case mostRecentSpace
  }

  public struct Route: Codable, Hashable, Sendable {
    public var condition: Condition
    public var destination: Destination

    public init(condition: Condition, destination: Destination) {
      self.condition = condition
      self.destination = destination
    }

    public func applies(to url: URL) -> Bool { condition.applies(to: url) }
  }

  public enum Resolution: Hashable, Sendable {
    case destination(Destination)
    case ambiguous([Route])
  }

  public var routes: [Route]
  public var defaultDestination: Destination

  public init(routes: [Route], defaultDestination: Destination = .littleArkt) {
    self.routes = routes
    self.defaultDestination = defaultDestination
  }

  public func matchingRoutes(for url: URL) -> [Route] { routes.filter { $0.applies(to: url) } }

  public func resolution(for url: URL) -> Resolution {
    let matches = matchingRoutes(for: url)
    guard let first = matches.first else { return .destination(defaultDestination) }
    return .destination(first.destination)
  }

  /// Returns the first matching route's destination, or the configured default when no routes match.
  public func destination(for url: URL) -> Destination? {
    guard case .destination(let destination) = resolution(for: url) else { return nil }
    return destination
  }
}

/// Value-only boundary for loading and atomically changing routing settings.
public protocol LinkRoutingSettingsStoring: Sendable {
  func loadLinkRouting() async throws -> LinkRouting
  func updateLinkRouting(
    at date: Date, _ change: @escaping @Sendable (inout LinkRouting) -> Void
  ) async throws -> LinkRouting
}
