import ArcImport
import EngineAPI
import Foundation

/// Imports an Arc profile's history, bookmarks, cookies, passwords and extensions into the default Arkt profile (#515).
///
/// One run:
/// 1. Snapshot: copies the Arc profile files to a private scratch folder (`ArcProfileSnapshot`); the scratch folder is
///    removed in a `defer`, on every exit. Arc's own files are never opened.
/// 2. Count: key-free row counts for the consent sheet. `consent` receives them and returns the types the user ticked,
///    or nil when the user declined.
/// 3. Key: only when cookies or passwords are ticked and the profile holds some, the Safe Storage key is fetched once,
///    both databases are read with it, and it is dropped. A refused Keychain fails those two types (Retry) and the rest
///    still import.
/// 4. Write: per type, in batches, in the order history, bookmarks, cookies, passwords, extensions. After each batch
///    the keys of what it handled are added to the `ArcImportRecord` (and, for history, the watermark advances), so a
///    cancel between batches keeps everything written and a re-import adds only what is new.
///
/// Everything goes into the engine's one profile (v1: per-Space profiles come with #101). The Chrome Web Store install
/// (#513) is `EngineImporting.installExtensions(ids:)`; an engine without it makes the type "skipped, not yet
/// available". Events and the summary carry counts and fixed phrases only; nothing is logged.
@MainActor
public final class ProfileImportCoordinator {
  public private(set) var isRunning = false
  private var task: Task<Void, Never>?
  private var recordFailed = false

  private let engine: any EngineImporting
  private let importRecord: any ArcImportRecordStoring
  private let keyProvider: any SafeStorageKeyProvider
  private let configuration: ProfileImportConfiguration
  private let now: @MainActor () -> Date

  public init(
    engine: any EngineImporting, importRecord: any ArcImportRecordStoring, keyProvider: any SafeStorageKeyProvider,
    configuration: ProfileImportConfiguration = ProfileImportConfiguration(),
    now: @escaping @MainActor () -> Date = { Date() }
  ) {
    self.engine = engine
    self.importRecord = importRecord
    self.keyProvider = keyProvider
    self.configuration = configuration
    self.now = now
  }

  /// Starts a run over the Arc `User Data` folder at `root`. The stream ends with `.finished`. Throws
  /// `ProfileImportError.alreadyRunning` while another run is in progress.
  public func run(
    root: URL, consent: @escaping @MainActor (ProfileDataCounts) async -> ImportSelection?
  ) throws -> AsyncStream<ProfileImportEvent> {
    guard !isRunning else { throw ProfileImportError.alreadyRunning }
    isRunning = true
    recordFailed = false
    return AsyncStream(bufferingPolicy: .unbounded) { continuation in
      let task = Task { @MainActor in
        var summary = await execute(root: root, consent: consent) { continuation.yield($0) }
        summary.recordFailed = recordFailed
        continuation.yield(.finished(summary))
        continuation.finish()
        isRunning = false
        self.task = nil
      }
      self.task = task
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Runs only the types that failed in `summary`.
  public func retry(root: URL, after summary: ProfileImportSummary) throws -> AsyncStream<ProfileImportEvent> {
    let types = Set(summary.retryTypes)
    return try run(root: root) { _ in ImportSelection(types) }
  }

  /// Stops after the batch being written. What was written stays, and a later import adds only what is new.
  public func cancel() { task?.cancel() }

  // MARK: - Run

  private typealias Emit = (ProfileImportEvent) -> Void

  private func execute(
    root: URL, consent: @MainActor (ProfileDataCounts) async -> ImportSelection?, emit: Emit
  ) async -> ProfileImportSummary {
    var summary = ProfileImportSummary()
    let clock = now()
    let snapshot: ArcProfileSnapshot
    do {
      snapshot = try await ProfileImportRead.snapshot(root: root, scratchParent: configuration.scratchParent)
    } catch is ArcProfileSnapshot.RootNotFound {
      summary.abortReason = "Arc data not found"
      return summary
    } catch {
      summary.abortReason = "the Arc data could not be copied"
      return summary
    }
    defer { snapshot.remove() }
    guard let profile = ProfileImportRead.profile(in: snapshot) else {
      summary.abortReason = "no Arc profile found"
      return summary
    }
    let record: ArcImportRecord
    do { record = try await importRecord.loadArcImportRecord() } catch {
      summary.abortReason = "the import record could not be read"
      return summary
    }

    for type in ImportDataType.allCases { emit(.progress(type, .counting)) }
    let counted = await ProfileImportRead.count(profile: profile, now: clock)
    emit(.counted(counted.counts))
    guard let selection = await consent(counted.counts) else {
      summary.cancelled = true
      return summary
    }

    func finish(_ type: ImportDataType, _ outcome: ImportTypeOutcome) {
      summary.outcomes[type] = outcome
      switch outcome {
      case .done(let counts): emit(.progress(type, .done(counts)))
      case .skipped(let reason): emit(.progress(type, .skipped(reason: reason)))
      case .failed(let reason): emit(.progress(type, .failed(reason: reason)))
      }
    }

    let types = ImportDataType.allCases.filter(selection.types.contains)
    var runnable: [ImportDataType] = []
    for type in types {
      if let unavailable = counted.unavailable[type] { finish(type, unavailable) } else { runnable.append(type) }
    }

    let readCookies = runnable.contains(.cookies) && counted.counts.cookies > 0
    let readLogins = runnable.contains(.passwords) && counted.counts.logins > 0
    var secrets = ProfileImportRead.Secrets()
    if (readCookies || readLogins) && !Task.isCancelled {
      secrets = await ProfileImportRead.secrets(
        profile: profile, readCookies: readCookies, readLogins: readLogins, provider: keyProvider, now: clock,
        knownCookies: record.cookieKeys, knownLogins: record.loginKeys, batchSize: configuration.batchSize)
    }
    defer { secrets.wipe() }

    for type in runnable {
      if summary.cancelled || Task.isCancelled {
        summary.cancelled = true
        finish(type, .skipped(reason: "cancelled"))
        continue
      }
      let result = await importType(
        type, profile: profile, record: record, clock: clock, secrets: &secrets, emit: emit)
      finish(type, result.outcome)
      if result.cancelled { summary.cancelled = true }
    }
    return summary
  }

  private struct TypeResult {
    var outcome: ImportTypeOutcome
    var cancelled = false
  }

  private func importType(
    _ type: ImportDataType, profile: ArcProfileSnapshot.Profile, record: ArcImportRecord, clock: Date,
    secrets: inout ProfileImportRead.Secrets, emit: Emit
  ) async -> TypeResult {
    switch type {
    case .history:
      guard let file = profile.copiedFile("History") else { return TypeResult(outcome: .skipped(reason: ProfileImportRead.notInProfile)) }
      let prepared: PreparedBatches<ImportedHistoryEntry>
      do {
        prepared = try await ProfileImportRead.history(
          file: file, after: record.historyWatermark, oldest: clock.addingTimeInterval(-ImportRecording.historyRetention),
          visitsPerBatch: configuration.historyVisitsPerBatch)
      } catch { return TypeResult(outcome: .failed(reason: "could not read History")) }
      let watermark = record.historyWatermark
      return await write(
        type, prepared, size: { $0.reduce(0) { $0 + $1.visits.count } }, wipe: { _ in },
        send: { await self.engine.importHistory($0, after: watermark) },
        delta: { _, result in result.latestVisit.map { ArcImportRecord(historyWatermark: $0) } }, emit: emit)

    case .bookmarks:
      let prepared: PreparedBatches<BookmarkRecord>
      do {
        prepared = try await ProfileImportRead.bookmarks(
          profile: profile, known: record.bookmarkKeys, batchSize: configuration.batchSize)
      } catch { return TypeResult(outcome: .failed(reason: "could not read Bookmarks")) }
      return await write(
        type, prepared, size: { $0.count }, wipe: { _ in }, send: { await self.engine.importBookmarks($0) },
        delta: { batch, result in
          result.failed == 0 ? ArcImportRecord(bookmarkKeys: Set(batch.map(ArcImportKey.bookmark))) : nil
        }, emit: emit)

    case .cookies:
      if let failure = secrets.failures[.cookies] { return TypeResult(outcome: failure) }
      let prepared = secrets.cookies
      secrets.cookies = PreparedBatches()
      return await write(
        type, prepared, size: { $0.count }, wipe: { for cookie in $0 { cookie.value.wipe() } },
        send: { await self.engine.importCookies($0) },
        delta: { batch, result in
          result.failed == 0 ? ArcImportRecord(cookieKeys: Set(batch.map(ArcImportKey.cookie))) : nil
        }, emit: emit)

    case .passwords:
      if let failure = secrets.failures[.passwords] { return TypeResult(outcome: failure) }
      let prepared = secrets.logins
      secrets.logins = PreparedBatches()
      return await write(
        type, prepared, size: { $0.count }, wipe: { for login in $0 { login.password.wipe() } },
        send: { await self.engine.importPasswords($0) },
        delta: { batch, result in
          result.failed == 0 ? ArcImportRecord(loginKeys: Set(batch.map(ArcImportKey.login))) : nil
        }, emit: emit)

    case .extensions:
      let prepared: PreparedBatches<String>
      do { prepared = try await ProfileImportRead.extensionIDs(profile: profile, known: record.extensionIDs) } catch {
        return TypeResult(outcome: .failed(reason: "could not read Preferences"))
      }
      guard let ids = prepared.batches.first else {
        return TypeResult(outcome: .done(ImportItemCounts(skipped: prepared.alreadyHandled)))
      }
      guard let result = await engine.installExtensions(ids: ids) else {
        return TypeResult(outcome: .skipped(reason: "not yet available"))
      }
      var counts = ImportItemCounts(skipped: prepared.alreadyHandled)
      counts.add(result)
      if result.failed == 0 { await persist(ArcImportRecord(extensionIDs: Set(ids))) }
      return TypeResult(outcome: .done(counts))
    }
  }

  /// Writes `prepared` batch by batch. Between batches it stops when the task is cancelled; secrets of the batches it
  /// never sent are wiped by `wipe`.
  private func write<Item: Sendable>(
    _ type: ImportDataType, _ prepared: PreparedBatches<Item>, size: ([Item]) -> Int, wipe: ([Item]) -> Void,
    send: ([Item]) async -> ImportWriteResult, delta: ([Item], ImportWriteResult) -> ArcImportRecord?, emit: Emit
  ) async -> TypeResult {
    var counts = ImportItemCounts(skipped: prepared.alreadyHandled)
    let total = prepared.batches.reduce(0) { $0 + size($1) }
    var written = 0
    var index = 0
    defer { for batch in prepared.batches[index...] { wipe(batch) } }
    emit(.progress(type, .writing(done: 0, total: total)))
    while index < prepared.batches.count {
      if Task.isCancelled { return TypeResult(outcome: .done(counts), cancelled: true) }
      let batch = prepared.batches[index]
      let result = await send(batch)
      index += 1
      counts.add(result)
      written += size(batch)
      if let delta = delta(batch, result) { await persist(delta) }
      emit(.progress(type, .writing(done: written, total: total)))
    }
    return TypeResult(outcome: .done(counts))
  }

  /// Adds `delta` to the stored record. A failure is remembered for the summary, not thrown: the batch is already in
  /// the profile.
  private func persist(_ delta: ArcImportRecord) async {
    do { try await importRecord.recordArcImport(delta, at: now()) } catch { recordFailed = true }
  }
}
