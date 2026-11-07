import AppKit
internal import ArktEngineABI
import EngineAPI

// MARK: - Tab state (#577, the engine side of #576)

extension ChromiumEngine {
  /// The facade zooms through `zoom::PageZoom::Zoom`; the handle has the new zoom when the call returns, so the change
  /// is reported now (contract rule 25) and the facade's later `ZoomChanged` for it finds nothing new.
  public func zoomIn(_ id: TabID) { zoom(id, .zoomIn) }
  public func zoomOut(_ id: TabID) { zoom(id, .zoomOut) }
  public func resetZoom(_ id: TabID) { zoom(id, .reset) }

  private func zoom(_ id: TabID, _ command: ArktZoomCommand) {
    guard let handle = tabs[id]?.handle else { return }
    handle.zoom(command)
    zoomChanged(id, to: Self.zoom(of: handle), userInitiated: true)
  }

  public var sessionRecovery: (any EngineSessionRecovery)? { chromiumSessionRecovery }

  static func zoom(of handle: any ArktTabHandle) -> TabZoom {
    TabZoom(percent: handle.zoomPercent, isDefault: handle.zoomIsDefault)
  }

  /// One of the four tab state kinds, for a listed tab. Tables are written before the event is emitted (#581: the
  /// shell reads `snapshot(of:)` inside its handler).
  func tabStateChanged(_ id: TabID, _ event: any ArktEngineEvent, handle: any ArktTabHandle) {
    switch event.kind {
    case .tabCrashed:
      // Reported once until the tab recovers; a status the facade never sends (None) still counts as a crash.
      guard tabs[id]?.snapshot.crash == nil else { break }
      let status = TabTerminationStatus(facade: event.terminationStatus) ?? .crashed
      tabs[id]?.snapshot.crash = status
      hub.emit(.tabCrashed(id, status))
    case .tabRecovered:
      guard tabs[id]?.snapshot.crash != nil else { break }
      tabs[id]?.snapshot.crash = nil
      hub.emit(.tabRecovered(id))
    case .zoomChanged:
      // The handle's live zoom, not the recorded one: a batch holding two changes, or a change this client already
      // reported from its own call, then reports only what is new. Batch rule: the last event wins. The one change
      // reported for the tab carries the user flag of the batch's last ZoomChanged for it, the event that set the
      // live zoom.
      let userInitiated = batchZoomInitiator[ObjectIdentifier(handle)] ?? event.zoomIsUserInitiated
      zoomChanged(id, to: Self.zoom(of: handle), userInitiated: userInitiated)
    case .tabFullscreenChanged:
      guard tabs[id]?.snapshot.isTabFullscreen != event.isTabFullscreen else { break }
      tabs[id]?.snapshot.isTabFullscreen = event.isTabFullscreen
      hub.emit(.tabFullscreenChanged(id, isFullscreen: event.isTabFullscreen))
    default:
      break
    }
  }

  private func zoomChanged(_ id: TabID, to zoom: TabZoom, userInitiated: Bool) {
    guard tabs[id] != nil, tabs[id]?.snapshot.zoom != zoom else { return }
    tabs[id]?.snapshot.zoom = zoom
    hub.emit(.zoomChanged(id, zoom, userInitiated: userInitiated))
  }
}

/// `EngineSessionRecovery` over the facade's crashed-session state (#577). The facade reads the previous run's exit
/// type once and keeps the shell's dismissal for the rest of the run; Chromium's own restore bubble never shows on an
/// engine window, so the shell is the only one that asks.
@MainActor
final class ChromiumSessionRecovery: EngineSessionRecovery {
  private let facade: any ArktEngine

  init(facade: any ArktEngine) { self.facade = facade }

  var lastSessionCrashed: Bool { facade.lastSessionCrashed }

  func dismissLastSession() {
    guard facade.lastSessionCrashed else { return }
    facade.dismissLastSession()
  }
}
