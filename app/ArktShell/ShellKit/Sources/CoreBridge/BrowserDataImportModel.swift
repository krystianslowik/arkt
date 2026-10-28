import ArcImport
import Foundation
import ShellUI

/// The profile import as the sheet needs it: `ProfileImportCoordinator` in the app, a script in tests.
@MainActor
public protocol ProfileImporting: AnyObject {
  func run(root: URL, consent: @escaping @MainActor (ProfileDataCounts) async -> ImportSelection?) throws
    -> AsyncStream<ProfileImportEvent>
  func retry(root: URL, after summary: ProfileImportSummary) throws -> AsyncStream<ProfileImportEvent>
  func cancel()
}

extension ProfileImportCoordinator: ProfileImporting {}

/// What the count pass found in the sidebar file: the Spaces and tabs row. Counts only.
public struct SpacesAndTabsCount: Equatable, Sendable {
  /// Pinned tabs and Favorites.
  public var items: Int
  public var spaces: Int

  public init(items: Int, spaces: Int) { self.items = items; self.spaces = spaces }
}

public struct SpacesAndTabsResult: Equatable, Sendable {
  /// Tabs and Favorites added.
  public var items: Int
  /// Sidebar items that could not be imported.
  public var skipped: Int
  /// Nothing was imported (the file could not be read or merged); Retry runs the step again.
  public var failed: Bool
  /// The Spaces added, in the source's order.
  public var addedSpaces: [SpaceID]

  public init(items: Int, skipped: Int, failed: Bool, addedSpaces: [SpaceID]) {
    self.items = items; self.skipped = skipped; self.failed = failed; self.addedSpaces = addedSpaces
  }
}

/// The sidebar half of the import (Spaces, tabs, Favorites): the existing `ArcImportCoordinator`, which the app owns
/// because it merges into the live sidebar and writes favicons. One row of the sheet.
public struct SpacesAndTabsStep {
  /// nil: nothing to count (no sidebar file).
  public var count: @MainActor () async -> SpacesAndTabsCount?
  public var run: @MainActor () async -> SpacesAndTabsResult

  public init(count: @escaping @MainActor () async -> SpacesAndTabsCount?,
              run: @escaping @MainActor () async -> SpacesAndTabsResult) {
    self.count = count
    self.run = run
  }
}

/// The browser data import's state machine (#514): consent with counts, progress, and the result, over the profile
/// coordinator's event stream and the sidebar step. The sheet and the first run's Hero view draw `state` and call the
/// actions; neither sees the coordinator.
///
/// - The coordinator's `consent` closure awaits the user: the model holds it until Import or Cancel.
/// - Import runs the sidebar step first, then lets the coordinator continue with the ticked types.
/// - There is no Keychain event, so "waiting for macOS" is inferred: from the moment the user answered (and the
///   sidebar step is done) until the coordinator's first progress event, which only comes after it read the key.
/// - Cancel keeps iterating the stream to its `.finished`: leaving the loop would itself cancel the run.
/// - Retry runs the coordinator's `retry(root:after:)` for the failed types, and the sidebar step again if it failed.
@MainActor
public final class BrowserDataImportModel: BrowserDataImportSource {
  public private(set) var state: BrowserDataImportState {
    didSet { if state != oldValue { onChange?() } }
  }
  public var onChange: (@MainActor () -> Void)?
  public var onFinish: (@MainActor (BrowserDataImportOutcome) -> Void)?

  private enum Decision { case run(Set<BrowserDataKind>), cancel }

  private let coordinator: any ProfileImporting
  private let root: URL
  private let spaces: SpacesAndTabsStep?
  private var runTask: Task<Void, Never>?
  private var consent: CheckedContinuation<Decision, Never>?
  private var lastSummary: ProfileImportSummary?
  private var spacesResult: SpacesAndTabsResult?
  private var cancelRequested = false
  private var didFinish = false

  public init(coordinator: any ProfileImporting, root: URL, spaces: SpacesAndTabsStep?, locale: Locale = .current) {
    self.coordinator = coordinator
    self.root = root
    self.spaces = spaces
    var state = BrowserDataImportState()
    state.locale = locale
    self.state = state
  }

  // MARK: - Actions

  public func start() {
    guard runTask == nil, state.phase == .counting else { return }
    runTask = Task { [weak self] in await self?.runFlow() }
  }

  public func setSelected(_ kind: BrowserDataKind, _ isOn: Bool) {
    guard state.phase == .consent, state.counts[kind] > 0 else { return }
    if isOn { state.selection.insert(kind) } else { state.selection.remove(kind) }
  }

  public func beginImport() {
    guard state.canImport else { return }
    resolveConsent(.run(state.effectiveSelection))
  }

  public func cancel() {
    switch state.phase {
    case .counting:
      guard !cancelRequested else { return }
      cancelRequested = true
      coordinator.cancel()
      dismiss()
    case .consent:
      cancelRequested = true
      resolveConsent(.cancel)
      dismiss()
    case .progress:
      guard !state.isStopping else { return }
      cancelRequested = true
      state.isStopping = true
      coordinator.cancel()
    case .result, .dismissed:
      break
    }
  }

  public func retry() {
    guard state.phase == .result, state.result.canRetry, let summary = lastSummary else { return }
    let redoSpaces = spacesResult?.failed == true
    let kinds = summary.retryTypes.map(Self.kind) + (redoSpaces ? [.spacesAndTabs] : [])
    guard !kinds.isEmpty else { return }
    cancelRequested = false
    let before = state.rows
    state.isRetry = true
    state.isStopping = false
    state.result = BrowserDataImportResult()
    for kind in kinds { state.rows[kind] = kind.needsPassword ? .waitingForMac : .waiting }
    state.phase = .progress
    runTask = Task { [weak self] in await self?.runRetry(after: summary, redoSpaces: redoSpaces, rowsBefore: before) }
  }

  public func finish() {
    guard state.phase == .result else { return }
    dismiss()
  }

  // MARK: - The run

  private func runFlow() async {
    let counting = Task { [spaces] in await spaces?.count() }
    let stream: AsyncStream<ProfileImportEvent>
    do {
      stream = try coordinator.run(root: root) { [weak self] counts in
        guard let self else { return nil }
        return await self.askConsent(counts, spaces: counting)
      }
    } catch {
      counting.cancel()
      state.result = BrowserDataImportResult(couldNotRead: true)
      state.phase = .result
      return
    }
    for await event in stream { handle(event) }
  }

  private func runRetry(after summary: ProfileImportSummary, redoSpaces: Bool, rowsBefore: [BrowserDataKind: BrowserDataRowStatus]) async {
    if redoSpaces { await runSpacesStep() }
    state.phase = .progress
    let stream: AsyncStream<ProfileImportEvent>
    do { stream = try coordinator.retry(root: root, after: summary) } catch {
      for (kind, status) in rowsBefore where kind != .spacesAndTabs { state.rows[kind] = status }
      state.isRetry = false
      state.result = BrowserDataImportResult(canRetry: true)
      state.phase = .result
      return
    }
    for await event in stream { handle(event) }
  }

  /// The coordinator's consent closure: shows the counts, waits for the user, runs the sidebar step, and answers with
  /// the types the coordinator should import (nil: the user declined).
  private func askConsent(_ counts: ProfileDataCounts, spaces counting: Task<SpacesAndTabsCount?, Never>) async
    -> ImportSelection? {
    let sidebar = await counting.value
    if cancelRequested { return nil }
    var found = BrowserDataCounts(items: [
      .history: counts.historyVisits, .bookmarks: counts.bookmarks, .extensions: counts.extensions,
      .cookies: counts.cookies, .passwords: counts.logins,
    ])
    if let sidebar {
      found.items[.spacesAndTabs] = sidebar.items
      found.spaces = sidebar.spaces
    }
    state.counts = found
    state.selection = Set(found.items.filter { $0.value > 0 }.map(\.key))
    state.rows = [:]
    state.phase = .consent
    let decision = await withCheckedContinuation { consent = $0 }
    guard case .run(let chosen) = decision, !cancelRequested else { return nil }

    state.selection = chosen
    for kind in BrowserDataKind.allCases { state.rows[kind] = chosen.contains(kind) ? .waiting : .skipped }
    state.phase = .progress
    if chosen.contains(.spacesAndTabs) { await runSpacesStep() }
    if cancelRequested { return nil }
    for kind in chosen where kind.needsPassword { state.rows[kind] = .waitingForMac }
    return ImportSelection(Set(chosen.compactMap(Self.dataType)))
  }

  private func resolveConsent(_ decision: Decision) {
    guard let pending = consent else { return }
    consent = nil
    pending.resume(returning: decision)
  }

  private func runSpacesStep() async {
    guard let spaces else { return }
    state.rows[.spacesAndTabs] = .working(done: 0, total: state.counts[.spacesAndTabs])
    let result = await spaces.run()
    spacesResult = result
    state.rows[.spacesAndTabs] = result.failed
      ? .notImported(.unreadable) : .imported(count: result.items, failed: result.skipped)
  }

  // MARK: - Events

  private func handle(_ event: ProfileImportEvent) {
    switch event {
    case .counted:
      break
    case .progress(_, .counting):
      break
    case .progress(let type, let progress):
      endKeychainWait()
      let kind = Self.kind(type)
      switch progress {
      case .counting: break
      case .writing(let done, let total): state.rows[kind] = .working(done: done, total: total)
      case .done(let counts): state.rows[kind] = Self.status(.done(counts))
      case .skipped(let reason): state.rows[kind] = Self.status(.skipped(reason: reason))
      case .failed(let reason): state.rows[kind] = Self.status(.failed(reason: reason))
      }
    case .finished(let summary):
      finished(summary)
    }
  }

  /// The first progress event comes after the coordinator read the key (or failed to): the prompt is gone.
  private func endKeychainWait() {
    for (kind, status) in state.rows where status == .waitingForMac { state.rows[kind] = .waiting }
  }

  private func finished(_ summary: ProfileImportSummary) {
    lastSummary = summary
    if state.phase == .dismissed { return }
    if cancelRequested, state.phase == .counting || state.phase == .consent {
      dismiss()
      return
    }
    // The summary is the last word on every type it lists; the rest never ran.
    for (type, outcome) in summary.outcomes { state.rows[Self.kind(type)] = Self.status(outcome) }
    for kind in BrowserDataKind.allCases {
      switch state.rows[kind] {
      case .waiting?, .waitingForMac?, .working?: state.rows[kind] = .stopped
      default: break
      }
    }
    let sidebarFailed = spacesResult?.failed == true
    state.result = BrowserDataImportResult(
      cancelled: summary.cancelled || cancelRequested, couldNotRead: summary.abortReason != nil,
      canRetry: summary.canRetry || sidebarFailed, recordFailed: summary.recordFailed)
    state.isStopping = false
    state.phase = .result
  }

  private func dismiss() {
    guard !didFinish else { return }
    didFinish = true
    state.phase = .dismissed
    let anything = state.rows.values.contains { if case .imported = $0 { true } else { false } }
    onFinish?(BrowserDataImportOutcome(
      importedAnything: anything, skippedSidebarItems: spacesResult?.skipped ?? 0,
      addedSpaces: spacesResult?.addedSpaces ?? []))
  }

  // MARK: - Mapping

  static func kind(_ type: ImportDataType) -> BrowserDataKind {
    switch type {
    case .history: .history
    case .bookmarks: .bookmarks
    case .cookies: .cookies
    case .passwords: .passwords
    case .extensions: .extensions
    }
  }

  static func dataType(_ kind: BrowserDataKind) -> ImportDataType? {
    switch kind {
    case .spacesAndTabs: nil
    case .history: .history
    case .bookmarks: .bookmarks
    case .cookies: .cookies
    case .passwords: .passwords
    case .extensions: .extensions
    }
  }

  static func status(_ outcome: ImportTypeOutcome) -> BrowserDataRowStatus {
    switch outcome {
    case .done(let counts): .imported(count: counts.written + counts.skipped, failed: counts.failed)
    case .skipped: .stopped
    case .failed(let reason): .notImported(Self.reason(reason))
    }
  }

  /// The coordinator's reasons are fixed phrases; a Keychain one means macOS did not hand over the key.
  static func reason(_ reason: String) -> BrowserDataNotImportedReason {
    reason.hasPrefix("Keychain") ? .keychainDenied : .unreadable
  }
}
