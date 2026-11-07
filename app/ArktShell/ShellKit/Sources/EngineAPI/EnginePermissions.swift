import Foundation

/// Opaque identity of one permission request (#400). A tab that is hidden and shown again gets a new one.
public struct PermissionRequestID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
}

/// What a permission request asks for.
public enum PermissionKind: Equatable, Sendable {
  case geolocation, notifications, camera, microphone
  /// Anything else; its words are in `PermissionRequest.items`.
  case other
}

/// How the shell answers a permission request.
public enum PermissionChoice: Equatable, Sendable {
  case allow
  /// Allow for this visit only; engines that offer it set `PermissionRequest.allowThisTimeTitle`.
  case allowThisTime
  case block
  /// The prompt was closed without a choice (Escape, the window closing): the site's ask counts as ignored.
  case dismiss
}

/// A site's request for camera, microphone, location, notifications and the like, as plain values the shell draws
/// (#400). Every string is the engine's: the title ("example.com wants to"), the phrases ("Know your location") and the
/// button titles, so the shell adds no copy of its own.
public struct PermissionRequest: Equatable, Sendable, Identifiable {
  public var id: PermissionRequestID
  public var tab: TabID
  /// The asking origin as the engine names it ("example.com").
  public var origin: String
  /// What is asked for, one per `items` entry.
  public var kinds: [PermissionKind]
  public var title: String
  public var items: [String]
  public var allowTitle: String
  /// Nil when the request has no one-visit grant (notifications): the prompt offers Allow and Block.
  public var allowThisTimeTitle: String?
  public var blockTitle: String

  public init(id: PermissionRequestID, tab: TabID, origin: String, kinds: [PermissionKind], title: String,
              items: [String], allowTitle: String, allowThisTimeTitle: String?, blockTitle: String) {
    self.id = id; self.tab = tab; self.origin = origin; self.kinds = kinds; self.title = title; self.items = items
    self.allowTitle = allowTitle; self.allowThisTimeTitle = allowThisTimeTitle; self.blockTitle = blockTitle
  }
}
