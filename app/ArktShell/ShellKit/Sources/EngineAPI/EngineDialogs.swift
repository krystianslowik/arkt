import Foundation

/// Opaque identity of one JavaScript dialog request (#400).
public struct DialogID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
}

/// A page's `alert()`, `confirm()` or `prompt()`, as plain values the shell draws (#400). Every value comes from the
/// engine: the title ("example.com says"), the message and the button titles are Chromium's, so the shell adds no
/// strings of its own. `beforeunload` is not reported here; Chromium keeps its app-modal Leave site dialog (#265).
public struct JavaScriptDialog: Equatable, Sendable, Identifiable {
  public enum Kind: Equatable, Sendable { case alert, confirm, prompt }

  public var id: DialogID
  public var tab: TabID
  public var kind: Kind
  public var title: String
  public var message: String
  /// The prompt's initial text; nil for an alert or a confirm.
  public var defaultPromptText: String?
  /// The answer that continues (OK).
  public var acceptTitle: String
  /// The answer that declines; nil for an alert, which only has OK.
  public var cancelTitle: String?

  public init(id: DialogID, tab: TabID, kind: Kind, title: String, message: String, defaultPromptText: String?,
              acceptTitle: String, cancelTitle: String?) {
    self.id = id; self.tab = tab; self.kind = kind; self.title = title; self.message = message
    self.defaultPromptText = defaultPromptText; self.acceptTitle = acceptTitle; self.cancelTitle = cancelTitle
  }
}
