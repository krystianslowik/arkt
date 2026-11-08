import Foundation

/// The settled, value-only part of link routing. Competing destinations require a policy decision.
public struct LinkRouting: Codable, Hashable, Sendable {
  public enum Condition: Codable, Hashable, Sendable {
    case contains(String)
    case matches(String)

    /// Compares the URL's absolute string without normalization or case folding.
    public func applies(to url: URL) -> Bool {
      switch self {
      case .contains(let text): url.absoluteString.contains(text)
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
    guard matches.allSatisfy({ $0.destination == first.destination }) else { return .ambiguous(matches) }
    return .destination(first.destination)
  }

  /// Returns nil for competing destinations, never the default for an ambiguous match.
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
