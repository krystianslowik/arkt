import Foundation

/// Opaque identity of one infobar (#400). The same infobar keeps its id across the lists the engine reports; a
/// replaced one is a new infobar with a new id.
public struct InfobarID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: UUID
  public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
  public var description: String { rawValue.uuidString }
}

/// What an infobar is about, for the few the shell tells apart. `other` covers the rest; its words are in the message.
public enum InfobarKind: Equatable, Sendable {
  case other
  /// An extension or DevTools session started debugging the browser.
  case debugger
  /// The browser is controlled by automated test software.
  case automation
  /// Settings changed in Page Info and the page needs a reload to apply them.
  case reload
}

/// One button of an infobar. The title is the engine's.
public struct InfobarButton: Equatable, Sendable {
  public var title: String
  public var tooltip: String?
  public var isEnabled: Bool
  public init(title: String, tooltip: String? = nil, isEnabled: Bool = true) {
    self.title = title; self.tooltip = tooltip; self.isEnabled = isEnabled
  }
}

/// A link inside an infobar's message: `range` is in UTF-16 offsets into `Infobar.message`, `index` is the number the
/// engine expects back in `InfobarAction.messageLink`.
public struct InfobarLink: Equatable, Sendable {
  public var index: Int
  public var range: Range<Int>
  public init(index: Int, range: Range<Int>) { self.index = index; self.range = range }
}

/// What the shell does on an infobar.
public enum InfobarAction: Equatable, Sendable {
  /// The OK (or only) button.
  case ok
  case cancel
  /// The link after the message.
  case link
  /// An inline link inside the message, by `InfobarLink.index`.
  case messageLink(Int)
  /// The close button.
  case close
}

/// A strip of text with buttons above a tab's page: what a page's extension, the browser or a setting wants the user to
/// know or decide (#400). Every string is the engine's, so the shell adds no copy of its own. The engine decides when
/// an infobar goes: an action runs its delegate, and the infobar leaves with the next `EngineEvent.infobarsChanged`.
public struct Infobar: Equatable, Sendable, Identifiable {
  public var id: InfobarID
  public var tab: TabID
  public var kind: InfobarKind
  public var message: String
  /// Inline links of the message, in order.
  public var messageLinks: [InfobarLink]
  /// A link after the message, or before the buttons when `linkBeforeButtons`.
  public var linkTitle: String?
  public var linkAccessibilityLabel: String?
  public var linkBeforeButtons: Bool
  /// The OK (or only) button, and the Cancel button; nil: none.
  public var ok: InfobarButton?
  public var cancel: InfobarButton?
  /// The close button's accessibility label; nil: the infobar cannot be closed.
  public var closeLabel: String?
  /// The icon as a PNG at 2x of 20 points; nil: none.
  public var iconPNG: Data?

  public var isCloseable: Bool { closeLabel != nil }

  public init(id: InfobarID, tab: TabID, kind: InfobarKind = .other, message: String, messageLinks: [InfobarLink] = [],
              linkTitle: String? = nil, linkAccessibilityLabel: String? = nil, linkBeforeButtons: Bool = false,
              ok: InfobarButton? = nil, cancel: InfobarButton? = nil, closeLabel: String? = nil, iconPNG: Data? = nil) {
    self.id = id; self.tab = tab; self.kind = kind; self.message = message; self.messageLinks = messageLinks
    self.linkTitle = linkTitle; self.linkAccessibilityLabel = linkAccessibilityLabel
    self.linkBeforeButtons = linkBeforeButtons; self.ok = ok; self.cancel = cancel; self.closeLabel = closeLabel
    self.iconPNG = iconPNG
  }
}
