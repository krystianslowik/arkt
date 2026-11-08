import Foundation
import SidebarModel

/// An explicitly flushed snapshot editor. Load successfully before editing; edits before a successful load are ignored.
/// Flushes on this instance are serialized and retain later edits. Separate editors write whole snapshots, so the last
/// flush wins: the store's atomic transaction does not merge changes from independently loaded editors.
@MainActor
public final class LinkRoutingSettingsModel {
  public private(set) var settings = LinkRouting(routes: [])
  /// The most recent load or flush error; cleared by a successful operation.
  public private(set) var lastError: (any Error)?
  public private(set) var isLoaded = false

  private let state: any LinkRoutingSettingsStoring
  private let now: @MainActor () -> Date
  private var revision = 0
  private var savedRevision = 0
  private var pendingWrites = 0
  private var loadInProgress = false
  private var saving: Task<Bool, Never>?

  public init(state: any LinkRoutingSettingsStoring, now: @escaping @MainActor () -> Date = { Date() }) {
    self.state = state
    self.now = now
  }

  /// A reload is ignored while edits are unsaved or writes are pending, to avoid discarding them.
  public func load() async {
    guard !loadInProgress, pendingWrites == 0, revision == savedRevision else { return }
    loadInProgress = true
    defer { loadInProgress = false }
    do {
      let value = try await state.loadLinkRouting()
      settings = value
      isLoaded = true
      lastError = nil
    } catch {
      lastError = error
    }
  }

  public func appendRoute(_ route: LinkRouting.Route) {
    edit { $0.routes.append(route) }
  }

  public func replaceRoute(at index: Int, with route: LinkRouting.Route) {
    guard settings.routes.indices.contains(index) else { return }
    edit { $0.routes[index] = route }
  }

  public func removeRoute(at index: Int) {
    guard settings.routes.indices.contains(index) else { return }
    edit { $0.routes.remove(at: index) }
  }

  public func setDefaultDestination(_ destination: LinkRouting.Destination) {
    edit { $0.defaultDestination = destination }
  }

  /// Writes the snapshot at invocation and returns its result. A failed write leaves the snapshot available for retry.
  /// Cancellation does not guarantee rollback after a store write has begun.
  @discardableResult
  public func flush() async -> Bool {
    guard isLoaded, !loadInProgress else { return false }
    let (snapshot, version, state, date, previous) = (settings, revision, state, now(), saving)
    pendingWrites += 1
    let task = Task { @MainActor in
      _ = await previous?.value
      do {
        _ = try await state.updateLinkRouting(at: date) { value in value = snapshot }
        self.savedRevision = version
        self.lastError = nil
        self.pendingWrites -= 1
        return true
      } catch {
        self.lastError = error
        self.pendingWrites -= 1
        return false
      }
    }
    saving = task
    return await task.value
  }

  private func edit(_ change: (inout LinkRouting) -> Void) {
    guard isLoaded, !loadInProgress else { return }
    var updated = settings
    change(&updated)
    guard updated != settings else { return }
    settings = updated
    revision += 1
  }
}
