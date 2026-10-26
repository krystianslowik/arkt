import AppKit
internal import ArktEngineABI
import EngineAPI

// Plain conversions between the facade header's enums and EngineAPI's types. Nothing here calls the facade.

extension CloseMode {
  var facade: ArktCloseMode {
    switch self {
    case .honourUnloadHandlers: .honourUnloadHandlers
    case .skipUnloadHandlers: .skipUnloadHandlers
    }
  }
}

extension CloseReason {
  /// `ArktCloseReasonNone` never arrives on a `TabClosed` from the real facade; a close nobody claimed is the
  /// page's own (Decision 12's default).
  init(facade reason: ArktCloseReason) {
    switch reason {
    case .client: self = .client
    case .page, .none: self = .page
    case .extension: self = .extension
    case .windowClosing: self = .windowClosing
    case .appTerminating: self = .appTerminating
    @unknown default: self = .page
    }
  }
}

extension WindowCloseReason {
  /// `ArktWindowCloseReasonNone` never arrives on a `WindowClosed` from the real facade. A close it did not classify
  /// is treated as one somebody asked for, so the shell window goes with it rather than staying on a page that
  /// might come back (#401).
  init(facade reason: ArktWindowCloseReason) {
    switch reason {
    case .user, .none: self = .userClose
    case .extension: self = .extension
    case .lastTabClosed: self = .lastTabClosed
    case .appTerminating: self = .appQuit
    @unknown default: self = .userClose
    }
  }
}

extension TabOrigin {
  init(facade origin: ArktTabOrigin) {
    self = origin == .engine ? .engine : .client
  }
}

extension EngineWindowRequestKind {
  init(facade kind: ArktWindowRequestKind) {
    switch kind {
    case .extension: self = .extension
    case .page: self = .page
    case .reopen: self = .reopen
    case .startupURL: self = .startupURL
    @unknown default: self = .reopen
    }
  }
}

extension HistoryEntry {
  @MainActor init(facade entry: any ArktHistoryEntry) {
    self.init(url: entry.url, title: entry.title)
  }
}

extension ExtensionAction {
  @MainActor init(facade action: any ArktExtensionAction) {
    self.init(id: action.actionId, name: action.name, iconPNG: action.iconPNG, isEnabled: action.isEnabled)
  }
}

/// A JSON-compatible value answered by the test API's `evaluateScript` (`NSNumber`, `NSString`, `NSArray`,
/// `NSDictionary`, `NSNull` from the facade), as a `Sendable` value.
public enum ScriptValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([ScriptValue])
  case object([String: ScriptValue])

  /// Nil for a value the facade cannot answer (undefined, a function).
  init?(facade value: Any?) {
    switch value {
    case nil: return nil
    case is NSNull: self = .null
    case let number as NSNumber:
      self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
    case let string as String: self = .string(string)
    case let array as [Any]: self = .array(array.map { ScriptValue(facade: $0) ?? .null })
    case let object as [String: Any]: self = .object(object.mapValues { ScriptValue(facade: $0) ?? .null })
    default: return nil
    }
  }
}
