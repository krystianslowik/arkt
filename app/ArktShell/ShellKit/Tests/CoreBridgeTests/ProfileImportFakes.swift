import ArcImport
import CoreBridge
import CoreTestSupport
import EngineAPI
import Foundation
import Synchronization

/// An `EngineImporting` that keeps what it was given and returns scripted results. It zeroes the secrets of every batch
/// before returning, like the real engine, after copying the plain values for the test to inspect. The wall clock plays
/// no part: unlike `ImportRecording` it applies no retention window.
@MainActor
final class RecordingImportEngine: EngineImporting {
  /// One entry per engine call, in call order: "history", "bookmarks", "cookies", "passwords", "extensions".
  private(set) var calls: [String] = []
  private(set) var cookieBatches: [[ImportedCookieRecord]] = []
  private(set) var loginBatches: [[ImportedLoginRecord]] = []
  private(set) var historyCalls: [(visits: Int, watermark: Date?)] = []
  private(set) var bookmarkBatches: [[BookmarkRecord]] = []
  private(set) var installCalls: [[String]] = []

  /// What `installExtensions` returns; nil is an engine without the install step.
  var installResult: ImportWriteResult?
  /// Overrides the counts of a type's next results, for example `["bookmarks": ImportWriteResult(failed: 1)]`.
  var scripted: [String: ImportWriteResult] = [:]
  /// Runs after each call has been recorded, with the call's name and the number of calls of that kind so far.
  var afterCall: ((String, Int) -> Void)?

  var cookieCount: Int { cookieBatches.reduce(0) { $0 + $1.count } }
  var loginCount: Int { loginBatches.reduce(0) { $0 + $1.count } }
  var visitCount: Int { historyCalls.reduce(0) { $0 + $1.visits } }
  var bookmarkCount: Int { bookmarkBatches.reduce(0) { $0 + $1.count } }

  private func finish(_ name: String, default result: ImportWriteResult) -> ImportWriteResult {
    calls.append(name)
    defer { afterCall?(name, calls.filter { $0 == name }.count) }
    return scripted[name] ?? result
  }

  func importCookies(_ batch: [ArcCookie]) async -> ImportWriteResult {
    cookieBatches.append(batch.map {
      ImportedCookieRecord(hostKey: $0.hostKey, name: $0.name, value: $0.value.utf8String(), path: $0.path)
    })
    for cookie in batch { cookie.value.wipe() }
    return finish("cookies", default: ImportWriteResult(written: batch.count))
  }

  func importPasswords(_ batch: [ArcLogin]) async -> ImportWriteResult {
    loginBatches.append(batch.map {
      ImportedLoginRecord(
        signonRealm: $0.signonRealm, username: $0.username, actionURL: $0.actionURL, password: $0.password.utf8String())
    })
    for login in batch { login.password.wipe() }
    return finish("passwords", default: ImportWriteResult(written: batch.count))
  }

  func importHistory(_ batch: [ImportedHistoryEntry], after watermark: Date?) async -> ImportWriteResult {
    let visits = batch.flatMap(\.visits)
    historyCalls.append((visits.count, watermark))
    return finish("history", default: ImportWriteResult(written: visits.count, latestVisit: visits.map(\.time).max()))
  }

  func importBookmarks(_ batch: [BookmarkRecord]) async -> ImportWriteResult {
    bookmarkBatches.append(batch)
    return finish("bookmarks", default: ImportWriteResult(written: batch.count))
  }

  func installExtensions(ids: [String]) async -> ImportWriteResult? {
    installCalls.append(ids)
    calls.append("extensions")
    afterCall?("extensions", installCalls.count)
    return installResult
  }
}

/// An engine that adopts none of the optional steps: `installExtensions` is the protocol's default.
@MainActor
final class BareImportEngine: EngineImporting {
  func importCookies(_ batch: [ArcCookie]) async -> ImportWriteResult { ImportWriteResult(written: batch.count) }
  func importPasswords(_ batch: [ArcLogin]) async -> ImportWriteResult { ImportWriteResult(written: batch.count) }
  func importHistory(_ batch: [ImportedHistoryEntry], after watermark: Date?) async -> ImportWriteResult {
    ImportWriteResult()
  }
  func importBookmarks(_ batch: [BookmarkRecord]) async -> ImportWriteResult { ImportWriteResult(written: batch.count) }
}

/// A fake Safe Storage provider that counts how often the key was asked for. Never touches the Keychain.
final class CountingKeyProvider: SafeStorageKeyProvider {
  private let inner: FakeSafeStorageKeyProvider
  private let asked = Mutex(0)

  init(_ inner: FakeSafeStorageKeyProvider) { self.inner = inner }

  var timesAsked: Int { asked.withLock { $0 } }

  func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R {
    asked.withLock { $0 += 1 }
    return try inner.withPassword(body)
  }
}

/// A temp `User Data` folder with one fake Chromium profile named `Default` (invented values, never real Arc data), and
/// an empty scratch folder for the snapshots. Both are removed on deinit.
final class ArcUserDataFolder {
  let root: URL
  let scratch: URL
  let manifest: FixtureManifest

  var profile: URL { root.appendingPathComponent("Default", isDirectory: true) }

  /// Snapshot folders left in the scratch parent; empty once a run ended.
  var leftoverSnapshots: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? [])
      .filter { $0.hasPrefix(ArcProfileSnapshot.directoryPrefix) }
  }

  init(options: FakeChromiumProfile.Options = .init(), withBookmarks: Bool = true) throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ArcUserDataFolder-\(UUID().uuidString)", isDirectory: true)
    root = base.appendingPathComponent("User Data", isDirectory: true)
    scratch = base.appendingPathComponent("scratch", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    manifest = try FakeChromiumProfile.make(at: root.appendingPathComponent("Default", isDirectory: true), options: options)
    if !withBookmarks { try FileManager.default.removeItem(at: profile.appendingPathComponent("Bookmarks")) }
  }

  deinit { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
}
