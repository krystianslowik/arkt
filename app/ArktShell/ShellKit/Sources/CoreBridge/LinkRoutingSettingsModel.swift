import Foundation
import SidebarModel
import ShellUI

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
  private var writePending = false
  private var saveFailed = false
  private var submissions = 0
  private var storeCall: Task<Result<Void, any Error>, Never>?
  private let flushTimeout: Duration?
  private var pendingRemovedSpaces: Set<UUID> = []
  private var removalGeneration = 0
  private var removalHistory: [UUID: Int] = [:]
  private var loadInProgress = false
  private var loading: Task<Void, Never>?

  public init(state: any LinkRoutingSettingsStoring, flushTimeout: Duration? = .seconds(1),
              now: @escaping @MainActor () -> Date = { Date() }) {
    self.state = state
    self.flushTimeout = flushTimeout
    self.now = now
  }

  /// A reload is ignored while edits are unsaved or writes are pending, to avoid discarding them.
  public func load() async {
    if let loading { await loading.value; return }
    guard revision == savedRevision, !writePending, !saveFailed else { return }
    loadInProgress = true
    let readGeneration = removalGeneration
    let pendingAtRead = pendingRemovedSpaces
    let task = Task { @MainActor in
      defer { self.loadInProgress = false }
      do {
        var value = try await self.state.loadLinkRouting()
        // A read may return a snapshot taken before a cleanup completed.
        let removedDuringRead = pendingAtRead.union(self.removalHistory.filter { $0.value > readGeneration }.map(\.key))
        value.routes.removeAll { route in
          if case .space(let id) = route.destination { return removedDuringRead.contains(id) }
          return false
        }
        self.settings = value
        self.isLoaded = true
        self.applyPendingRemovals()
        self.lastError = nil
      } catch {
        self.isLoaded = false
        self.lastError = error
      }
    }
    loading = task
    await task.value
    loading = nil
  }

  public func removeRoutes(to id: UUID) {
    removalGeneration += 1
    pendingRemovedSpaces.insert(id)
    removalHistory[id] = removalGeneration
    if isLoaded && !loadInProgress { applyPendingRemovals() }
  }

  private func applyPendingRemovals() {
    let ids = pendingRemovedSpaces
    var updated = settings
    updated.routes.removeAll { route in
      if case .space(let id) = route.destination { return ids.contains(id) }
      return false
    }
    if updated != settings { settings = updated; revision += 1 }
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

  /// True for an unsaved edit or the latest submitted write, including a timed-out write.
  public var needsFlush: Bool { revision != savedRevision || writePending || saveFailed || !pendingRemovedSpaces.isEmpty }

  private enum FlushError: Error { case timedOut }

  /// Each detached store call waits for the preceding call without requiring the main actor.
  private func submit() -> (Task<Result<Void, any Error>, Never>, Int, Int, Set<UUID>, Int) {
    // Without a usable snapshot, prune only the current stored value in the atomic update.
    let snapshot: LinkRouting? = isLoaded && !loadInProgress ? settings : nil
    let (version, state, date, previous, removals) = (revision, state, now(), storeCall, pendingRemovedSpaces)
    let call = Task.detached { () -> Result<Void, any Error> in
      _ = await previous?.value
      do {
        _ = try await state.updateLinkRouting(at: date) { value in
          if let snapshot { value = snapshot }
          value.routes.removeAll { route in
            if case .space(let id) = route.destination { return removals.contains(id) }
            return false
          }
        }
        return .success(())
      } catch { return .failure(error) }
    }
    storeCall = call
    submissions += 1
    writePending = true
    return (call, submissions, version, removals, removalGeneration)
  }

  private func finish(_ result: Result<Void, any Error>, submission: Int, version: Int,
                      removals: Set<UUID>, generation: Int) -> Bool {
    guard submission == submissions else { return (try? result.get()) != nil }
    writePending = false
    switch result {
    case .success:
      savedRevision = version
      pendingRemovedSpaces.subtract(removals.filter { (removalHistory[$0] ?? 0) <= generation })
      saveFailed = false
      if isLoaded { lastError = nil }
      return true
    case .failure(let error):
      saveFailed = true
      lastError = error
      return false
    }
  }

  /// Writes the snapshot at invocation and keeps failed edits available for retry.
  @discardableResult
  public func flush() async -> Bool {
    guard isLoaded, !loadInProgress else { return false }
    let (call, number, version, removals, generation) = submit()
    return finish(await call.value, submission: number, version: version, removals: removals, generation: generation)
  }

  /// Normal termination must also give up on a stalled store without marking its snapshot saved.
  @discardableResult
  public func flushForTermination() async -> Bool {
    guard (isLoaded && !loadInProgress) || !pendingRemovedSpaces.isEmpty else { return !needsFlush }
    guard needsFlush else { return true }
    let (call, number, version, removals, generation) = submit()
    let attempt = Task { @MainActor in
      self.finish(await call.value, submission: number, version: version, removals: removals, generation: generation)
    }
    guard let flushTimeout else { return await attempt.value }
    let result = await FlushRace.run(timeout: flushTimeout, sleep: { try await Task.sleep(for: $0) }, attempt: attempt)
    if !result, number == submissions, writePending {
      saveFailed = true
      lastError = FlushError.timedOut
    }
    return result
  }

  /// The SIGTERM caller blocks the main thread, so neither the write nor its ordering can depend on it.
  @discardableResult
  public func flushBlocking() -> Bool {
    guard (isLoaded && !loadInProgress) || !pendingRemovedSpaces.isEmpty else { return !needsFlush }
    guard needsFlush else { return true }
    let (call, number, version, removals, generation) = submit()
    guard let result = BlockingFlush.run(timeout: flushTimeout, { await call.value }) else {
      saveFailed = true
      lastError = FlushError.timedOut
      return false
    }
    return finish(result, submission: number, version: version, removals: removals, generation: generation)
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

public extension LinkRoutingSettingsModel {
  /// Plain Settings actions over this editor. Multiple consumers share its snapshot.
  var settingsRows: SettingsLinkRoutingRows {
    SettingsLinkRoutingRows(
      load: { [weak self] in
        guard let self, !self.isLoaded else { return }
        await self.load()
      },
      destination: { [weak self] in
        guard let self, self.isLoaded, !self.loadInProgress else { return nil }
        switch self.settings.defaultDestination {
        case .littleArkt: return .littleArkt
        case .mostRecentSpace: return .mostRecentSpace
        case .space(let id): return .space(id)
        }
      },
      routes: { [weak self] in self?.settings.routes.map(SettingsLinkRoute.init) ?? [] },
      appendRoute: { [weak self] in self?.appendRoute($0.coreRoute) },
      replaceRoute: { [weak self] index, route in self?.replaceRoute(at: index, with: route.coreRoute) },
      replaceRouteIfUnchanged: { [weak self] index, expected, route in
        guard let self, self.isLoaded, !self.loadInProgress, self.settings.routes.map(SettingsLinkRoute.init) == expected,
              self.settings.routes.indices.contains(index) else { return false }
        self.replaceRoute(at: index, with: route.coreRoute)
        return true
      },
      removalGeneration: { [weak self] in self?.removalGeneration ?? 0 },
      hasLoadError: { [weak self] in self?.isLoaded == false && self?.lastError != nil },
      hasSaveError: { [weak self] in self?.isLoaded == true && self?.lastError != nil },
      setDestination: { [weak self] destination in
        switch destination {
        case .littleArkt: self?.setDefaultDestination(.littleArkt)
        case .mostRecentSpace: self?.setDefaultDestination(.mostRecentSpace)
        case .space(let id): self?.setDefaultDestination(.space(id))
        }
      },
      flush: { [weak self] in await self?.flush() ?? false })
  }
}

private extension SettingsLinkDestination {
  init(_ destination: LinkRouting.Destination) {
    switch destination {
    case .littleArkt: self = .littleArkt
    case .mostRecentSpace: self = .mostRecentSpace
    case .space(let id): self = .space(id)
    }
  }
  var coreDestination: LinkRouting.Destination {
    switch self {
    case .littleArkt: .littleArkt
    case .mostRecentSpace: .mostRecentSpace
    case .space(let id): .space(id)
    }
  }
}

private extension SettingsLinkRoute {
  init(_ route: LinkRouting.Route) {
    let condition: Condition
    switch route.condition {
    case .contains(let literal): condition = .contains(literal)
    case .matches(let literal): condition = .matches(literal)
    }
    self.init(condition: condition, destination: SettingsLinkDestination(route.destination))
  }
  var coreRoute: LinkRouting.Route {
    let coreCondition: LinkRouting.Condition
    switch condition {
    case .contains(let literal): coreCondition = .contains(literal)
    case .matches(let literal): coreCondition = .matches(literal)
    }
    return .init(condition: coreCondition, destination: destination.coreDestination)
  }
}
