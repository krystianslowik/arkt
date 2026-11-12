import Foundation

/// Opaque identity of one JavaScript dialog request (#400).
public struct DialogID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
}

/// A page's `alert()`, `confirm()` or `prompt()`, or its leave-site prompt, as plain values the shell draws (#400,
/// #584). Every value comes from the engine: the title ("example.com says", "Leave site?"), the message and the button
/// titles are Chromium's, so the shell adds no strings of its own.
public struct JavaScriptDialog: Equatable, Sendable, Identifiable {
  public enum Kind: Equatable, Sendable {
    case alert, confirm, prompt
    /// The page's `beforeunload` handler holds a close or a navigation (#584). `acceptTitle` is Leave and
    /// `cancelTitle` is Stay (or nil: the shell draws Stay). For a held close, `accepted: true` lets the close go on
    /// (`.tabClosed`, or the window's close); `accepted: false` cancels it (`.closeCancelled` for every tab the close
    /// held, so a held window close or quit stops). For a held navigation (reload, navigating away), Stay reports
    /// nothing after `.dialogEnded` and Leave lets the navigation proceed.
    ///
    /// The engine raises leave-site prompts one tab at a time and only on a shown tab: a window close or a quit that
    /// several tabs hold activates the next held tab before its prompt, and raises it only after the previous one
    /// was answered Leave. An engine that keeps its own leave-site dialog reports none of these: the close is then
    /// held with `isClosing` alone (contract rule 16).
    case beforeUnload
  }

  public var id: DialogID
  public var tab: TabID
  public var kind: Kind
  public var title: String
  public var message: String
  /// The prompt's initial text; nil for an alert or a confirm.
  public var defaultPromptText: String?
  /// The answer that continues (OK; Leave for a leave-site prompt).
  public var acceptTitle: String
  /// The answer that declines (Cancel; Stay for a leave-site prompt); nil for an alert, which only has OK. The
  /// Chromium engine sends nil for a leave-site prompt, since Chromium has no Stay string; the shell draws Stay.
  public var cancelTitle: String?

  public init(id: DialogID, tab: TabID, kind: Kind, title: String, message: String, defaultPromptText: String?,
              acceptTitle: String, cancelTitle: String?) {
    self.id = id; self.tab = tab; self.kind = kind; self.title = title; self.message = message
    self.defaultPromptText = defaultPromptText; self.acceptTitle = acceptTitle; self.cancelTitle = cancelTitle
  }
}
