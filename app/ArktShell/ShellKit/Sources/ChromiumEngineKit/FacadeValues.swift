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

extension FindStopAction {
  var facade: ArktFindAction {
    switch self {
    case .clear: .clear
    case .keep: .keep
    case .activate: .activate
    }
  }
}

extension TabTerminationStatus {
  /// Nil for `None`: the page is alive.
  init?(facade status: ArktTerminationStatus) {
    switch status {
    case .none: return nil
    case .crashed: self = .crashed
    case .killed: self = .killed
    case .outOfMemory: self = .outOfMemory
    case .launchFailed: self = .launchFailed
    @unknown default: self = .crashed
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
    self.init(id: action.actionId, name: action.name, iconPNG: action.iconPNG, isEnabled: action.isEnabled,
              canUninstall: action.canUninstall, canReportAbuse: action.canReportAbuse)
  }
}

extension DownloadItem {
  /// The values of one facade snapshot. A total of 0 is "not said" (Chromium); an unknown state or reason round-trips
  /// through `DownloadInterruptReason`.
  @MainActor init(facade item: any ArktDownloadItem) {
    let state: DownloadState
    switch item.state {
    case .inProgress: state = .inProgress
    case .paused: state = .paused
    case .complete: state = .complete
    case .cancelled: state = .cancelled
    case .interrupted: state = .interrupted(DownloadInterruptReason(rawValue: item.interruptReason))
    @unknown default: state = .interrupted(.crash)
    }
    self.init(id: DownloadID(item.guid), url: item.url, filename: item.filename, targetPath: item.targetPath,
              totalBytes: item.totalBytes > 0 ? item.totalBytes : nil, receivedBytes: item.receivedBytes,
              state: state, dangerType: DownloadDangerType(rawValue: item.dangerType), mimeType: item.mimeType,
              startTime: item.startTime, endTime: item.endTime, bytesPerSecond: item.bytesPerSecond,
              canResume: item.canResume)
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

// MARK: Page info (#583)

extension PageConnection {
  init(facade connection: ArktPageConnection) {
    switch connection {
    case .secure: self = .secure
    case .notSecure: self = .notSecure
    case .notFullySecure: self = .notFullySecure
    case .certificateError: self = .certificateError
    case .flagged: self = .flagged
    case .localFile: self = .localFile
    case .internalPage: self = .internalPage
    @unknown default: self = .notSecure
    }
  }
}

extension PermissionSetting {
  init(facade setting: ArktPermissionSetting) {
    switch setting {
    case .allow: self = .allow
    case .block: self = .block
    case .ask: self = .ask
    @unknown default: self = .ask
    }
  }

  var facade: ArktPermissionSetting {
    switch self {
    case .allow: .allow
    case .ask: .ask
    case .block: .block
    }
  }
}

extension SitePermissionKind {
  /// Nil for a kind added to the facade after this build.
  init?(facade kind: ArktSitePermissionKind) {
    switch kind {
    case .location: self = .location
    case .camera: self = .camera
    case .microphone: self = .microphone
    case .notifications: self = .notifications
    case .popups: self = .popups
    case .sound: self = .sound
    case .javaScript: self = .javascript
    case .images: self = .images
    case .automaticDownloads: self = .automaticDownloads
    case .clipboard: self = .clipboard
    case .midiDevices: self = .midiDevices
    case .motionSensors: self = .motionSensors
    case .usbDevices: self = .usbDevices
    case .serialPorts: self = .serialPorts
    case .hidDevices: self = .hidDevices
    case .bluetoothDevices: self = .bluetoothDevices
    case .fileEditing: self = .fileEditing
    case .windowManagement: self = .windowManagement
    case .localFonts: self = .localFonts
    case .idleDetection: self = .idleDetection
    case .backgroundSync: self = .backgroundSync
    case .insecureContent: self = .insecureContent
    @unknown default: return nil
    }
  }

  var facade: ArktSitePermissionKind {
    switch self {
    case .location: .location
    case .camera: .camera
    case .microphone: .microphone
    case .notifications: .notifications
    case .popups: .popups
    case .sound: .sound
    case .javascript: .javaScript
    case .images: .images
    case .automaticDownloads: .automaticDownloads
    case .clipboard: .clipboard
    case .midiDevices: .midiDevices
    case .motionSensors: .motionSensors
    case .usbDevices: .usbDevices
    case .serialPorts: .serialPorts
    case .hidDevices: .hidDevices
    case .bluetoothDevices: .bluetoothDevices
    case .fileEditing: .fileEditing
    case .windowManagement: .windowManagement
    case .localFonts: .localFonts
    case .idleDetection: .idleDetection
    case .backgroundSync: .backgroundSync
    case .insecureContent: .insecureContent
    }
  }
}
