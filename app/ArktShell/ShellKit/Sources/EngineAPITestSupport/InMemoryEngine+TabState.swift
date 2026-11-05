import EngineAPI

// Tab state (#576): crash and recovery, zoom, HTML fullscreen and the crashed session. The tab calls follow the
// `EngineClient` docs; the test drivers stand in for a page process that dies, a site's saved zoom and a page that
// calls `requestFullscreen`. Zoom is per tab here (Chromium keeps it per site).
extension InMemoryEngine {
  public func zoomIn(_ id: TabID) {
    guard let percent = snapshots[id]?.zoom.percent,
          let next = TabZoom.steps.first(where: { $0 > percent }) else { return }
    setZoom(id, percent: next, userInitiated: true)
  }

  public func zoomOut(_ id: TabID) {
    guard let percent = snapshots[id]?.zoom.percent,
          let next = TabZoom.steps.last(where: { $0 < percent }) else { return }
    setZoom(id, percent: next, userInitiated: true)
  }

  public func resetZoom(_ id: TabID) {
    setZoom(id, percent: TabZoom.default.percent, userInitiated: true)
  }

  public var sessionRecovery: (any EngineSessionRecovery)? { crashedSession }

  // MARK: Test drivers

  /// Test hook: the page's process went away. A load in progress ends and HTML fullscreen is left first; nothing is
  /// reported for a tab that is already crashed.
  public func crash(_ id: TabID, status: TabTerminationStatus) {
    guard let current = snapshots[id], current.crash == nil else { return }
    if current.isLoading {
      snapshots[id]?.isLoading = false
      hub.emit(.loadingChanged(id, isLoading: false))
    }
    setTabFullscreen(id, false)
    snapshots[id]?.crash = status
    hub.emit(.tabCrashed(id, status))
  }

  /// Test hook: the page entered or left HTML fullscreen.
  public func setTabFullscreen(_ id: TabID, _ fullscreen: Bool) {
    guard let current = snapshots[id], current.isTabFullscreen != fullscreen else { return }
    snapshots[id]?.isTabFullscreen = fullscreen
    hub.emit(.tabFullscreenChanged(id, isFullscreen: fullscreen))
  }

  /// Test hook, and the tab calls' common path: the zoom becomes `percent`. `userInitiated` false stands in for the
  /// engine's own changes (a site's saved zoom).
  public func setZoom(_ id: TabID, percent: Int, userInitiated: Bool) {
    guard let current = snapshots[id], current.zoom.percent != percent else { return }
    let zoom = TabZoom(percent: percent, isDefault: percent == TabZoom.default.percent)
    snapshots[id]?.zoom = zoom
    hub.emit(.zoomChanged(id, zoom, userInitiated: userInitiated))
  }

  /// A reload or a navigation: a crashed tab recovers first, and the new document leaves HTML fullscreen.
  func prepareForLoad(_ id: TabID) {
    if snapshots[id]?.crash != nil {
      snapshots[id]?.crash = nil
      hub.emit(.tabRecovered(id))
    }
    setTabFullscreen(id, false)
  }
}

/// InMemoryEngine's crashed session: `simulateCrashedExit()` stands in for a run that did not quit cleanly; `answers`
/// records how it was acknowledged.
@MainActor
public final class InMemorySessionRecovery: EngineSessionRecovery {
  public enum Answer: Equatable, Sendable { case restored, dismissed }

  public private(set) var lastSessionCrashed = false
  public private(set) var answers: [Answer] = []

  public init() {}

  /// Test hook: the previous run ended without a clean quit.
  public func simulateCrashedExit() { lastSessionCrashed = true }

  public func restoreLastSession() { answer(.restored) }

  public func dismissLastSession() { answer(.dismissed) }

  private func answer(_ answer: Answer) {
    guard lastSessionCrashed else { return }
    lastSessionCrashed = false
    answers.append(answer)
  }
}
