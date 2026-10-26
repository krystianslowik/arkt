import AppKit

// MARK: - Link activation (#313)

/// Modifier keys held for a link activation. Only the four that change what a click does.
public struct EngineLinkModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let shift = EngineLinkModifiers(rawValue: 1 << 0)
  public static let command = EngineLinkModifiers(rawValue: 1 << 1)
  public static let option = EngineLinkModifiers(rawValue: 1 << 2)
  public static let control = EngineLinkModifiers(rawValue: 1 << 3)

  /// The link modifiers among AppKit's flags; every other flag (Caps Lock, Function, ...) is dropped.
  public init(_ flags: NSEvent.ModifierFlags) {
    var value: EngineLinkModifiers = []
    if flags.contains(.shift) { value.insert(.shift) }
    if flags.contains(.command) { value.insert(.command) }
    if flags.contains(.option) { value.insert(.option) }
    if flags.contains(.control) { value.insert(.control) }
    self = value
  }
}

/// A link the user activated in a page, reported before the engine navigates (#313, Peek). The engine reports only
/// user activations (a click or a key press on a link) of the tab's main frame; script navigations, forms, reloads and
/// history moves never ask.
public struct EngineLinkActivation: Equatable, Sendable {
  /// Where the link goes.
  public var url: URL
  /// The tab the link is in.
  public var sourceTab: TabID
  /// The source tab's committed URL when the link was activated, so a host can decide without calling the engine.
  public var sourceURL: URL?
  public var modifiers: EngineLinkModifiers
  /// Where the engine would open the link (`.currentTab` for a plain click).
  public var disposition: EngineDisposition

  public init(url: URL, sourceTab: TabID, sourceURL: URL?, modifiers: EngineLinkModifiers = [],
              disposition: EngineDisposition = .currentTab) {
    self.url = url
    self.sourceTab = sourceTab
    self.sourceURL = sourceURL
    self.modifiers = modifiers
    self.disposition = disposition
  }
}

/// A host's answer to a link activation.
public enum EngineLinkDecision: Equatable, Sendable {
  /// The engine goes on as it would have.
  case navigate
  /// The engine drops the navigation; the host opens the link itself (a Peek, a new tab), after the call returns.
  case cancel
}

// MARK: - Host defaults

extension EngineWindowHosting {
  /// Default: every link navigates as the engine would.
  public func decideLinkActivation(_ activation: EngineLinkActivation) -> EngineLinkDecision { .navigate }
  /// Default: the host takes no unhandled key.
  public func handleUnhandledKeyDown(_ event: NSEvent, in tab: TabID?) -> Bool { false }
}
