import Foundation

// Tab state seams (#576, part of #122): a crashed page, page zoom, HTML element fullscreen and the crashed-session
// prompt. The events are `EngineEvent.tabCrashed`, `.tabRecovered`, `.zoomChanged` and `.tabFullscreenChanged`; the
// snapshot carries `crash`, `zoom` and `isTabFullscreen`. Every `EngineClient` member here has a default, so an engine
// that has none of this (ChromiumEngine until its engine partner lands) reports nothing and keeps the defaults.

/// Why a tab's page process went away (Chromium's termination status, folded to what the shell tells apart). The tab
/// stays listed with its URL and history; a reload or a new navigation brings it back (`EngineEvent.tabRecovered`).
///
/// Chromium's `base::TerminationStatus` maps as: `TERMINATION_STATUS_PROCESS_CRASHED` and
/// `TERMINATION_STATUS_ABNORMAL_TERMINATION` to `crashed`, `TERMINATION_STATUS_PROCESS_WAS_KILLED` to `killed`,
/// `TERMINATION_STATUS_OOM` to `outOfMemory`, `TERMINATION_STATUS_LAUNCH_FAILED` to `launchFailed`;
/// `TERMINATION_STATUS_NORMAL_TERMINATION` and `TERMINATION_STATUS_STILL_RUNNING` report no event.
public enum TabTerminationStatus: Equatable, Sendable {
  /// The page process crashed.
  case crashed
  /// Something outside the page killed its process (the system, Activity Monitor, the task manager).
  case killed
  /// The page ran out of memory.
  case outOfMemory
  /// The page process could not start.
  case launchFailed
}

/// A tab's page zoom: `percent` of the page's natural size, and whether it is the zoom a new page gets (`isDefault`,
/// which follows the browser's default zoom, so it is not always 100).
public struct TabZoom: Equatable, Sendable {
  public var percent: Int
  public var isDefault: Bool

  public init(percent: Int, isDefault: Bool) {
    self.percent = percent
    self.isDefault = isDefault
  }

  /// 100 %, the default.
  public static let `default` = TabZoom(percent: 100, isDefault: true)

  /// Chromium's zoom levels in percent, in the order Zoom In walks them (`zoom::kPresetZoomFactors`).
  public static let steps = [25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300, 400, 500]
}

/// The previous run of the engine ended without a clean quit (a crash, a force quit, a power loss). The shell asks once
/// whether to bring the last session back. Dismissing acknowledges the crash, so it is not asked again; a second
/// dismiss does nothing. Only non-private pages outside the sidebar are restored.
/// A page outside the sidebar that can be reopened after a crash. Private pages must never be persisted.
public struct RecoveryPage: Equatable, Sendable {
  public enum Kind: Equatable, Sendable { case littleArkt, peek }
  public let title: String
  public let url: URL
  public let kind: Kind
  public init(title: String, url: URL, kind: Kind) {
    self.title = title
    self.url = url
    self.kind = kind
  }
}

@MainActor
public protocol EngineSessionRecovery: AnyObject {
  /// The previous run ended without a clean quit and nobody has answered yet.
  var lastSessionCrashed: Bool { get }
  /// Acknowledges the crash without restoring anything.
  func dismissLastSession()
}

/// A list of eligible pages. Providers must never return private or sidebar data.
@MainActor
public protocol EnginePageRecovery: EngineSessionRecovery {
  var recoveryPages: [RecoveryPage] { get }
}

extension EngineClient {
  public func zoomIn(_ id: TabID) {}

  public func zoomOut(_ id: TabID) {}

  public func resetZoom(_ id: TabID) {}

  public var sessionRecovery: (any EngineSessionRecovery)? { nil }
}
