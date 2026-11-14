#if ARKT_CHROMIUM_ENGINE && ARKT_TEST_SWITCHES
import AppKit
import ArcImport
import ChromiumEngineKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import Foundation
import Persistence
import ShellUI

/// The engine check for the import writes (#512, #511), against the real engine. Runs with `--arkt-import-check=import` or
/// `=verify` and `--arkt-engine-test-api`; the shell's session is not started. `ARKT_IMPORT_FIXTURE_DIR` names a profile
/// folder made by `FakeChromiumProfile` (invented values, a fake Safe Storage key): the runner reads its cookies and
/// logins with the Arc readers, writes them through `ChromiumEngine.importCookies` and `importPasswords`, loads a page on
/// 127.0.0.1 and prints what `document.cookie` shows. It also reads the fixture's History and Bookmarks, moves the visits
/// to the last days (the fixture's are from 2024, past the 90 days Chromium keeps), and writes them through
/// `importHistory` and `importBookmarks`, twice: the second history call passes the first one's newest visit as the
/// watermark and must write nothing. `verify` skips the import and only loads the page, for the run
/// after a relaunch. `=extensions` (#513) installs the Web Store ids of `ARKT_EXTENSION_IDS` (comma separated) twice
/// through `installExtensionResults`, pressing "Install" on the batch sheet from inside the process, and prints the
/// results and the ids the engine reports as extension actions. `=sheet` (#517) runs the whole import the way File > Import
/// Browser Data... does, minus the Keychain: `ProfileImportCoordinator` over `ARKT_ARC_DIR`'s `User Data` with the
/// fixture's key and the import record in `ARKT_DATA_DIR`'s database, behind `BrowserDataImportModel` and the real
/// `BrowserDataImportSheet` on a runner window; the process ticks every type and presses Import through the model. It
/// prints the coordinator's events, the consent counts and each row's result, then the cookie page, the password store
/// count and what chrome://history and chrome://bookmarks show. Prints one `ARKT_IMPORT` line per step and quits
/// through the application's own terminate.
@MainActor
final class ImportCheckRunner {
  static let switchName = "--arkt-import-check"
  static var phase: String? {
    CommandLine.arguments.first { $0.hasPrefix(switchName + "=") }.map { String($0.dropFirst(switchName.count + 1)) }
  }
  static var isRequested: Bool { phase != nil }

  /// The fixture's invented Safe Storage password.
  private struct FixtureKey: SafeStorageKeyProvider {
    func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R { try body(Array("fixture-password".utf8)) }
  }

  /// One run-loop turn after `embedderReady`, like the contract runner.
  static func start() {
    setvbuf(stdout, nil, _IOLBF, 0)
    Task { @MainActor in
      let status = await run()
      print("ARKT_IMPORT exit \(status)")
      if status == 0 { NSApp.terminate(nil) } else { exit(status) }
    }
  }

  private static func run() async -> Int32 {
    do {
      guard let engine = ChromiumEmbedding.makeEngine() else { throw RunnerError("no engine (before engineDidStart)") }
      guard engine.testAPIEnabled else { throw RunnerError("launch with --arkt-engine-test-api") }
      if phase == "extensions" {
        try await installExtensions(through: engine)
        return 0
      }
      if phase == "history-shutdown" {
        try await importHistoryThenQuit(into: engine)
        return 0
      }
      if phase == "history-retry" {
        try await importSyntheticHistoryAgain(into: engine)
        return 0
      }
      if phase == "sheet" {
        try await importThroughSheet(into: engine)
        try await showCookies(in: engine)
        print("ARKT_IMPORT passwords (empty batch) \(describe(await engine.importPasswords([])))")
        try await showImportedPages(in: engine)
        return 0
      }
      if phase == "import" { try await importFixture(into: engine) }
      if phase == "verify" {
        // An empty batch writes nothing; the engine logs how many logins its store holds.
        print("ARKT_IMPORT passwords (empty batch) \(describe(await engine.importPasswords([])))")
      }
      try await showCookies(in: engine)
      return 0
    } catch {
      print("ARKT_IMPORT failed: \(error)")
      return 1
    }
  }

  private static func importFixture(into engine: ChromiumEngine) async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_IMPORT_FIXTURE_DIR"] else {
      throw RunnerError("ARKT_IMPORT_FIXTURE_DIR is not set")
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    // The fixture's fixed cookies expire in 2024 and 2025: the reader's clock is set to its base date so it delivers
    // them, and the engine then skips them as expired (counted). The 127.0.0.1 cookie expires in 2100.
    var cookies: [ArcCookie] = []
    let clock = Date(timeIntervalSince1970: 1_704_067_200 + 60)
    let cookieSummary = try CookieReader(now: { clock }).read(
      cookiesDatabase: directory.appendingPathComponent("Network/Cookies"), keyProvider: FixtureKey()
    ) { cookies += $0 }
    print("ARKT_IMPORT read \(cookieSummary)")
    var logins: [ArcLogin] = []
    let loginSummary = try LoginReader().read(
      loginDatabase: directory.appendingPathComponent("Login Data"), keyProvider: FixtureKey()
    ) { logins += $0 }
    print("ARKT_IMPORT read \(loginSummary)")

    // A partitioned cookie the reader would never deliver, to reach the engine's own refusal: it must be skipped.
    cookies.append(ArcCookie(
      hostKey: "127.0.0.1", name: "partitioned", value: SecretBytes(taking: Array("must-not-land".utf8)), path: "/",
      expires: Date(timeIntervalSince1970: 4_102_444_800), creation: clock, lastAccess: clock, partitionKey: "https://top.example"))
    let cookieResult = await engine.importCookies(cookies)
    print("ARKT_IMPORT cookies \(describe(cookieResult))")
    let loginResult = await engine.importPasswords(logins)
    print("ARKT_IMPORT passwords \(describe(loginResult))")
    // The same logins again, with the dates they carry: none is newer than what the store holds, so all are skipped.
    var loginsAgain: [ArcLogin] = []
    _ = try LoginReader().read(
      loginDatabase: directory.appendingPathComponent("Login Data"), keyProvider: FixtureKey()
    ) { loginsAgain += $0 }
    print("ARKT_IMPORT passwords again \(describe(await engine.importPasswords(loginsAgain)))")
    // Importing the same batch again is all skipped for the cookies that were written (no newer cookie), and the
    // store updates the logins it holds.
    var again: [ArcCookie] = []
    _ = try CookieReader(now: { clock }).read(
      cookiesDatabase: directory.appendingPathComponent("Network/Cookies"), keyProvider: FixtureKey()
    ) { again += $0 }
    print("ARKT_IMPORT cookies again \(describe(await engine.importCookies(again)))")

    try await importHistoryAndBookmarks(from: directory, into: engine)
  }

  private static func importHistoryAndBookmarks(from directory: URL, into engine: ChromiumEngine) async throws {
    let read = try HistoryReader.readAll(from: directory.appendingPathComponent("History"))
    print("ARKT_IMPORT read history \(read.summary)")
    // Fixed gaps are kept; the newest visit moves to yesterday.
    let newest = read.entries.flatMap(\.visits).map(\.time).max() ?? Date()
    let shift = Date().addingTimeInterval(-86_400).timeIntervalSince(newest)
    let entries = read.entries.map { entry in
      ImportedHistoryEntry(
        url: entry.url, title: entry.title, visitCount: entry.visitCount, typedCount: entry.typedCount,
        lastVisit: entry.lastVisit?.addingTimeInterval(shift),
        visits: entry.visits.map { HistoryVisit(time: $0.time.addingTimeInterval(shift), transition: $0.transition) })
    }
    // A visit from the fixture's own date, past the retention window: skipped and counted.
    let stale = ImportedHistoryEntry(
      url: "https://stale.example/", title: "Stale", visitCount: 1, typedCount: 0, lastVisit: nil,
      visits: [HistoryVisit(time: newest, transition: .link)])
    let first = await engine.importHistory(entries + [stale], after: nil)
    print("ARKT_IMPORT history \(describe(first)) latest=\(first.latestVisit.map { String($0.timeIntervalSince1970) } ?? "none")")
    let again = await engine.importHistory(entries, after: first.latestVisit)
    print("ARKT_IMPORT history again \(describe(again)) latest=\(again.latestVisit.map { String($0.timeIntervalSince1970) } ?? "none")")

    let bookmarks = try BookmarksReader.read(from: directory.appendingPathComponent("Bookmarks"))
    print("ARKT_IMPORT read bookmarks \(bookmarks.bookmarks.count) skipped \(bookmarks.skippedNodes)")
    print("ARKT_IMPORT bookmarks \(describe(await engine.importBookmarks(bookmarks.bookmarks)))")
    print("ARKT_IMPORT bookmarks again \(describe(await engine.importBookmarks(bookmarks.bookmarks)))")
  }

  /// The synthetic batch of `=history-shutdown` and `=history-retry`: 4000 URLs with 10 visits each. The visit times
  /// count back from the start of today, so every run on the same day sends the same visits.
  private static func syntheticHistory() -> [ImportedHistoryEntry] {
    let base = Calendar.current.startOfDay(for: Date())
    return (0..<4_000).map { index in
      ImportedHistoryEntry(
        url: "https://shutdown-\(index).example/", title: "Shutdown \(index)", visitCount: 10, typedCount: 0,
        lastVisit: nil,
        visits: (0..<10).map { HistoryVisit(time: base.addingTimeInterval(-Double(index * 10 + $0 + 60)), transition: .link) })
    }
  }

  /// `=history-shutdown` (#531): queues a large synthetic history batch and quits while the history thread is still
  /// writing it, so the profile's history service is deleted before the import's barrier answers. The engine logs
  /// the visits that got no answer; the answer itself may arrive after the run loop has stopped.
  private static func importHistoryThenQuit(into engine: ChromiumEngine) async throws {
    let entries = syntheticHistory()
    Task { @MainActor in
      let result = await engine.importHistory(entries, after: nil)
      print("ARKT_IMPORT history before quit \(describe(result))")
    }
    // Long enough for the batch to reach the history service, too short for the history thread to write 40000 visits.
    try await Task.sleep(for: .milliseconds(200))
    print("ARKT_IMPORT quitting with the history batch queued")
  }

  /// `=history-retry` (#754): sends the same synthetic batch with no watermark, as the coordinator does after a batch
  /// that got no answer, and waits for the answer. Run after `=history-shutdown` (or after itself) on the same
  /// profile: a visit the profile already holds is skipped, so the history ends with each visit once.
  private static func importSyntheticHistoryAgain(into engine: ChromiumEngine) async throws {
    let result = await engine.importHistory(syntheticHistory(), after: nil)
    print("ARKT_IMPORT history retry \(describe(result)) latest=\(result.latestVisit.map { String($0.timeIntervalSince1970) } ?? "none")")
  }

  private static func installExtensions(through engine: ChromiumEngine) async throws {
    guard let list = ProcessInfo.processInfo.environment["ARKT_EXTENSION_IDS"] else {
      throw RunnerError("ARKT_EXTENSION_IDS is not set")
    }
    let ids = list.split(separator: ",").map(String.init)
    let host = RunnerWindowHost(index: 0)
    let window = engine.createWindow(host: host)
    host.window.makeKeyAndOrderFront(nil)
    for round in 1...2 {
      // The sheet is the shell's to answer in a real run; here the process presses its own "Install" button.
      let presser = Task { @MainActor in
        for _ in 0..<600 {
          if let sheet = host.window.attachedSheet, let button = installButton(in: sheet.contentView) {
            print("ARKT_IMPORT sheet shown round \(round): \(sheet.contentView.map(sheetText) ?? "")")
            button.performClick(nil)
            return
          }
          try? await Task.sleep(for: .milliseconds(100))
        }
        print("ARKT_IMPORT no sheet round \(round)")
      }
      let work = Task { @MainActor in await engine.installExtensionResults(ids: ids) }
      // ARKT_EXTENSION_CANCEL_AFTER (seconds): the first round cancels its task that long after it started.
      if round == 1, let after = ProcessInfo.processInfo.environment["ARKT_EXTENSION_CANCEL_AFTER"].flatMap(Double.init) {
        Task { @MainActor in
          try? await Task.sleep(for: .seconds(after))
          print("ARKT_IMPORT cancelling round 1")
          work.cancel()
        }
      }
      let started = Date()
      let results = await work.value
      print("ARKT_IMPORT round \(round) took \(Int(Date().timeIntervalSince(started))) s")
      presser.cancel()
      for result in results ?? [] { print("ARKT_IMPORT extension round \(round) \(result.id) \(result.outcome)") }
      let actions = engine.extensionActions(in: window)
      print("ARKT_IMPORT extension actions \(actions.count): \(actions.map(\.name).joined(separator: ", "))")
    }
    engine.closeWindow(window)
    host.window.orderOut(nil)
  }

  /// `=sheet`: the import sheet over the coordinator, on the real engine. Refuses to run without `ARKT_ARC_DIR` and
  /// `ARKT_DATA_DIR`, so it never reads the real data folders.
  private static func importThroughSheet(into engine: ChromiumEngine) async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let arc = environment["ARKT_ARC_DIR"], environment["ARKT_DATA_DIR"] != nil else {
      throw RunnerError("set ARKT_ARC_DIR to the fixture and ARKT_DATA_DIR to a throwaway folder")
    }
    let location = try await AppEnvironment.databaseLocation()
    let database = try await openDatabase(at: location.databaseURL)
    let scratch = location.directory.appending(path: "ImportScratch", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let coordinator = ProfileImportCoordinator(
      engine: engine, importRecord: SettingsStore(database: database), keyProvider: FixtureKey(),
      configuration: ProfileImportConfiguration(scratchParent: scratch))
    let model = BrowserDataImportModel(
      coordinator: PrintingImporter(coordinator),
      root: URL(fileURLWithPath: arc, isDirectory: true).appending(path: "User Data", directoryHint: .isDirectory),
      spaces: nil)

    let host = RunnerWindowHost(index: 0)
    let window = engine.createWindow(host: host)
    host.window.makeKeyAndOrderFront(nil)
    let sheet = BrowserDataImportSheet(source: model)
    sheet.begin(on: host.window)
    model.start()
    try await EngineContract.waitUntil(timeout: .seconds(30)) { model.state.phase == .consent }
    let kinds = BrowserDataKind.allCases
    print("ARKT_IMPORT consent counts " + kinds.map { "\($0.identifier)=\(model.state.counts[$0])" }.joined(separator: " "))
    print("ARKT_IMPORT consent sheet: \(sheet.window?.contentView.map(sheetText) ?? "")")
    for kind in kinds where kind != .spacesAndTabs { model.setSelected(kind, true) }
    print("ARKT_IMPORT selected " + kinds.filter(model.state.selection.contains).map(\.identifier).joined(separator: ","))
    let started = Date()
    model.beginImport()
    try await EngineContract.waitUntil(timeout: .seconds(180)) { model.state.phase == .result }
    print("ARKT_IMPORT result after \(Int(Date().timeIntervalSince(started))) s")
    for kind in kinds { print("ARKT_IMPORT row \(kind.identifier) \(model.state.rows[kind].map { "\($0)" } ?? "none")") }
    print("ARKT_IMPORT result \(model.state.result)")
    print("ARKT_IMPORT result sheet: \(sheet.window?.contentView.map(sheetText) ?? "")")
    model.finish()
    engine.closeWindow(window)
    host.window.orderOut(nil)
  }

  @concurrent
  private static func openDatabase(at url: URL) async throws -> ArktDatabase { try ArktDatabase.open(at: url) }

  /// Passes the coordinator through and prints every event (counts and fixed phrases only).
  @MainActor
  private final class PrintingImporter: ProfileImporting {
    let inner: any ProfileImporting
    init(_ inner: any ProfileImporting) { self.inner = inner }

    func run(root: URL, consent: @escaping @MainActor (ProfileDataCounts) async -> ImportSelection?) throws
      -> AsyncStream<ProfileImportEvent> {
      Self.printing(try inner.run(root: root, consent: consent))
    }

    func retry(root: URL, after summary: ProfileImportSummary) throws -> AsyncStream<ProfileImportEvent> {
      Self.printing(try inner.retry(root: root, after: summary))
    }

    func cancel() { inner.cancel() }

    private static func printing(_ stream: AsyncStream<ProfileImportEvent>) -> AsyncStream<ProfileImportEvent> {
      AsyncStream(bufferingPolicy: .unbounded) { continuation in
        let task = Task { @MainActor in
          for await event in stream {
            print("ARKT_IMPORT event \(event)")
            continuation.yield(event)
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    }
  }

  /// chrome://history and chrome://bookmarks in a runner tab: what the pages themselves list. Each script stores its
  /// answer on `window` and a later call reads it, so no call depends on a promise being awaited.
  private static func showImportedPages(in engine: ChromiumEngine) async throws {
    let host = RunnerWindowHost(index: 1)
    let window = engine.createWindow(host: host)
    host.window.makeKeyAndOrderFront(nil)
    // Closing a window's last tab closes the window, so one blank tab stays open until the end.
    let keeper = engine.createTab(url: URL(string: "about:blank")!, in: window)
    let pages: [(URL, String)] = [
      (URL(string: "chrome://history/")!, """
        (() => { const find = (root, tag) => { for (const el of root.querySelectorAll('*')) {
            if (el.tagName === tag) return el;
            if (el.shadowRoot) { const hit = find(el.shadowRoot, tag); if (hit) return hit; } } return null; };
          const list = find(document, 'HISTORY-LIST');
          const data = (list && list.historyData_) || [];
          return data.length + ': ' + data.map(e => e.title || e.url).join(' | '); })()
        """),
      (URL(string: "chrome://bookmarks/")!, """
        (() => { if (window.arktAnswer === undefined) { window.arktAnswer = '0: waiting';
          chrome.bookmarks.getTree(tree => { const titles = [];
            const walk = n => { if (n.url) titles.push(n.title); (n.children || []).forEach(walk); };
            tree.forEach(walk); window.arktAnswer = titles.length + ': ' + titles.join(' | '); }); }
          return window.arktAnswer; })()
        """),
    ]
    for (url, script) in pages {
      let tab = engine.createTab(url: url, in: window)
      do {
        try await EngineContract.waitUntil(timeout: .seconds(15)) {
          engine.snapshot(of: tab).map { !$0.isLoading } ?? false
        }
      } catch {
        print("ARKT_IMPORT \(url.absoluteString) still loading after 15 s: \(engine.snapshot(of: tab).map { "\($0)" } ?? "no tab")")
      }
      var answer = "no answer"
      for _ in 0..<50 {
        do {
          let seen = try await engine.evaluateScript(script, in: tab, userGesture: false)
          answer = seen.map { "\($0)" } ?? "undefined"
          if case .string(let text)? = seen, !text.hasPrefix("0:") { break }
        } catch {
          answer = "script error: \(error)"
        }
        try await Task.sleep(for: .milliseconds(200))
      }
      print("ARKT_IMPORT \(url.absoluteString) \(answer)")
      engine.closeTab(tab, mode: .skipUnloadHandlers)
    }
    engine.closeTab(keeper, mode: .skipUnloadHandlers)
    engine.closeWindow(window)
    host.window.orderOut(nil)
  }

  private static func installButton(in view: NSView?) -> NSButton? {
    guard let view else { return nil }
    if let button = view as? NSButton, button.title == "Install" { return button }
    for subview in view.subviews { if let found = installButton(in: subview) { return found } }
    return nil
  }

  private static func sheetText(_ view: NSView) -> String {
    var parts: [String] = []
    func walk(_ view: NSView) {
      if let field = view as? NSTextField, !field.stringValue.isEmpty { parts.append(field.stringValue) }
      view.subviews.forEach(walk)
    }
    walk(view)
    return parts.joined(separator: " | ")
  }

  private static func showCookies(in engine: ChromiumEngine) async throws {
    let server = try await ContractPageServer.start()
    defer { server.stop() }
    let host = RunnerWindowHost(index: 0)
    let window = engine.createWindow(host: host)
    let page = server.page("ImportCheck", serial: 1)
    let tab = engine.createTab(url: page, in: window)
    try await EngineContract.waitUntil(timeout: .seconds(15)) {
      engine.snapshot(of: tab).map { !$0.isLoading && $0.url == page } ?? false
    }
    let seen = try await engine.evaluateScript("document.cookie", in: tab, userGesture: false)
    print("ARKT_IMPORT document.cookie \(String(describing: seen))")
    if phase == "import" {
      _ = try await engine.evaluateScript("document.cookie = 'control=page-set; max-age=3600; path=/'; true", in: tab,
                                          userGesture: false)
      let after = try await engine.evaluateScript("document.cookie", in: tab, userGesture: false)
      print("ARKT_IMPORT document.cookie with control \(String(describing: after))")
    }
    engine.closeTab(tab, mode: .skipUnloadHandlers)
    engine.closeWindow(window)
    host.window.orderOut(nil)
  }

  private static func describe(_ result: ImportWriteResult) -> String {
    "written=\(result.written) skipped=\(result.skipped) failed=\(result.failed) "
      + "reason=\(result.failureReason?.replacingOccurrences(of: "\n", with: "; ") ?? "none")"
  }

  struct RunnerError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }
}
#endif
