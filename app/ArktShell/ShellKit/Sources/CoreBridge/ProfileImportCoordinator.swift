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
/// 3. Key: only when cookies or passwords are ticked and the profile holds some, the Safe Storage key is fetched once
///    and held (as `SecretBytes`) for the run. Rows are decrypted one batch at a time, just before that batch is
///    written, and the coordinator zeroes each batch after the write, on cancel and on a failed read, so plaintext
///    lives only for the batch in flight. A refused Keychain fails cookies and passwords (Retry) and the rest still
///    imports.
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
  /// Test seam: called with each pulled batch of cookies or logins before the cancel check and the write.
  var afterPull: (@MainActor (ImportDataType, [any Sendable]) -> Void)?

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
    // The copy is deleted off the main actor on every path out of `runSnapshot`.
    summary = await runSnapshot(snapshot, consent: consent, emit: emit)
    await ProfileImportRead.remove(snapshot)
    return summary
  }

  private func runSnapshot(
    _ snapshot: ArcProfileSnapshot, consent: @MainActor (ProfileDataCounts) async -> ImportSelection?, emit: Emit
  ) async -> ProfileImportSummary {
    var summary = ProfileImportSummary()
    let clock = now()
    guard let profile = ProfileImportRead.profile(in: snapshot) else {
      summary.abortReason = "no Arc profile found"
      return summary
    }
    var record: ArcImportRecord
    do { record = try await importRecord.loadArcImportRecord() } catch {
      summary.abortReason = "the import record could not be read"
      return summary
    }
    let salt: String
    if let stored = record.salt {
      salt = stored
    } else {
      salt = ArcImportKey.makeSalt()
      record.salt = salt
      await persist(ArcImportRecord(salt: salt))
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

    var key: ChromiumKey?
    var keyFailure: ImportTypeOutcome?
    let needsKey = (runnable.contains(.cookies) && counted.counts.cookies > 0)
      || (runnable.contains(.passwords) && counted.counts.logins > 0)
    if needsKey && !Task.isCancelled {
      switch await ProfileImportRead.openKey(provider: keyProvider) {
      case .success(let opened): key = opened
      case .failure(let failure): keyFailure = .failed(reason: failure.reason)
      }
    }
    defer { key?.wipe() }

    let context = RunContext(profile: profile, record: record, salt: salt, clock: clock, counts: counted.counts,
                             key: key, keyFailure: keyFailure)
    for type in runnable {
      if summary.cancelled || Task.isCancelled {
        summary.cancelled = true
        finish(type, .skipped(reason: "cancelled"))
        continue
      }
      let result = await importType(type, context, emit: emit)
      finish(type, result.outcome)
      if result.cancelled { summary.cancelled = true }
    }
    return summary
  }

  private struct RunContext {
    var profile: ArcProfileSnapshot.Profile
    var record: ArcImportRecord
    var salt: String
    var clock: Date
    var counts: ProfileDataCounts
    var key: ChromiumKey?
    var keyFailure: ImportTypeOutcome?
  }

  private struct TypeResult {
    var outcome: ImportTypeOutcome
    var cancelled = false
  }

  /// A pulled batch: the items to write now and how many rows were left out as already handled.
  private struct Pulled<Item> {
    var items: [Item]
    var skipped = 0
  }

  /// Hands out the batches of a read that is already complete, the first one carrying the already-handled count.
  private static func pull<Item>(_ prepared: PreparedBatches<Item>) -> () async throws -> Pulled<Item>? {
    var index = 0
    return {
      defer { index += 1 }
      if prepared.batches.isEmpty { return index == 0 && prepared.alreadyHandled > 0 ? Pulled(items: [], skipped: prepared.alreadyHandled) : nil }
      guard index < prepared.batches.count else { return nil }
      return Pulled(items: prepared.batches[index], skipped: index == 0 ? prepared.alreadyHandled : 0)
    }
  }

  private func importType(_ type: ImportDataType, _ run: RunContext, emit: Emit) async -> TypeResult {
    let profile = run.profile
    let record = run.record
    switch type {
    case .history:
      guard let file = profile.copiedFile("History") else { return TypeResult(outcome: .skipped(reason: ProfileImportRead.notInProfile)) }
      let prepared: PreparedBatches<ImportedHistoryEntry>
      do {
        prepared = try await ProfileImportRead.history(
          file: file, after: record.historyWatermark, oldest: run.clock.addingTimeInterval(-ImportRecording.historyRetention),
          visitsPerBatch: configuration.historyVisitsPerBatch)
      } catch { return TypeResult(outcome: .failed(reason: "could not read History")) }
      let watermark = record.historyWatermark
      // Batches are in time order, so each batch's newest visit is a valid watermark for the rest. Once a batch had
      // visits the engine refused, the watermark stops moving, so those visits are offered again next time.
      var frozen = false
      return await write(
        type, total: prepared.batches.reduce(0) { $0 + $1.reduce(0) { $0 + $1.visits.count } },
        next: Self.pull(prepared), size: { $0.reduce(0) { $0 + $1.visits.count } }, wipe: { _ in },
        send: { await self.engine.importHistory($0, after: watermark) },
        delta: { _, result in
          if result.failed > 0 { frozen = true }
          guard !frozen else { return nil }
          return result.latestVisit.map { ArcImportRecord(historyWatermark: $0) }
        }, emit: emit)

    case .bookmarks:
      let prepared: PreparedBatches<BookmarkRecord>
      do {
        prepared = try await ProfileImportRead.bookmarks(
          profile: profile, known: record.bookmarkKeys, salt: run.salt, batchSize: configuration.batchSize)
      } catch { return TypeResult(outcome: .failed(reason: "could not read Bookmarks")) }
      return await write(
        type, total: prepared.batches.reduce(0) { $0 + $1.count }, next: Self.pull(prepared), size: { $0.count },
        wipe: { _ in }, send: { await self.engine.importBookmarks($0) },
        delta: { batch, result in
          result.failed == 0 ? ArcImportRecord(bookmarkKeys: Set(batch.map { ArcImportKey.bookmark($0, salt: run.salt) })) : nil
        }, emit: emit)

    case .cookies:
      if let failure = run.keyFailure { return TypeResult(outcome: failure) }
      guard let key = run.key, let file = profile.copiedFile("Network/Cookies", "Cookies") else {
        return TypeResult(outcome: .done(ImportItemCounts()))
      }
      let rowsPerBatch = configuration.batchSize
      var offset = 0
      var ended = false
      return await write(
        type, total: run.counts.cookies,
        next: {
          guard !ended else { return nil }
          do {
            let window = try await ProfileImportRead.cookieWindow(
              file: file, key: key, rows: offset..<(offset + rowsPerBatch), now: run.clock, known: record.cookieKeys,
              salt: run.salt)
            offset += rowsPerBatch
            if window.scanned < rowsPerBatch { ended = true }
            return Pulled(items: window.items, skipped: window.alreadyHandled)
          } catch { throw ReadFailure(reason: "could not read Cookies") }
        },
        size: { $0.count }, wipe: { for cookie in $0 { cookie.value.wipe() } },
        send: { await self.engine.importCookies($0) },
        delta: { batch, result in
          result.failed == 0 ? ArcImportRecord(cookieKeys: Set(batch.map { ArcImportKey.cookie($0, salt: run.salt) })) : nil
        }, emit: emit)

    case .passwords:
      if let failure = run.keyFailure { return TypeResult(outcome: failure) }
      guard let key = run.key, let file = profile.copiedFile("Login Data") else {
        return TypeResult(outcome: .done(ImportItemCounts()))
      }
      let rowsPerBatch = configuration.batchSize
      var offset = 0
      var ended = false
      return await write(
        type, total: run.counts.logins,
        next: {
          guard !ended else { return nil }
          do {
            let window = try await ProfileImportRead.loginWindow(
              file: file, key: key, rows: offset..<(offset + rowsPerBatch), known: record.loginKeys, salt: run.salt)
            offset += rowsPerBatch
            if window.scanned < rowsPerBatch { ended = true }
            return Pulled(items: window.items, skipped: window.alreadyHandled)
          } catch { throw ReadFailure(reason: "could not read Login Data") }
        },
        size: { $0.count }, wipe: { for login in $0 { login.password.wipe() } },
        send: { await self.engine.importPasswords($0) },
        delta: { batch, result in
          result.failed == 0 ? ArcImportRecord(loginKeys: Set(batch.map { ArcImportKey.login($0, salt: run.salt) })) : nil
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

  private struct ReadFailure: Error { var reason: String }

  /// Pulls batch by batch. Secrets are decrypted by `next` only when asked for, and zeroed here after the write, on
  /// cancel and when a read fails, so plaintext lives for one batch at a time.
  private func write<Item: Sendable>(
    _ type: ImportDataType, total: Int, next: () async throws -> Pulled<Item>?, size: ([Item]) -> Int,
    wipe: ([Item]) -> Void, send: ([Item]) async -> ImportWriteResult,
    delta: ([Item], ImportWriteResult) -> ArcImportRecord?, emit: Emit
  ) async -> TypeResult {
    var counts = ImportItemCounts()
    var written = 0
    emit(.progress(type, .writing(done: 0, total: total)))
    while true {
      if Task.isCancelled { return TypeResult(outcome: .done(counts), cancelled: true) }
      let pulled: Pulled<Item>
      do {
        guard let next = try await next() else { break }
        pulled = next
      } catch let failure as ReadFailure {
        return TypeResult(outcome: .failed(reason: failure.reason))
      } catch { return TypeResult(outcome: .failed(reason: "could not read \(type.title)")) }
      defer { wipe(pulled.items) }
      counts.skipped += pulled.skipped
      afterPull?(type, pulled.items)
      if Task.isCancelled { return TypeResult(outcome: .done(counts), cancelled: true) }
      if !pulled.items.isEmpty {
        let result = await send(pulled.items)
        counts.add(result)
        written += size(pulled.items)
        if let delta = delta(pulled.items, result) { await persist(delta) }
      }
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
