#if ARKT_CHROMIUM_ENGINE
import AppKit
import ChromiumEngineKit
import EngineAPI
import EngineAPITestSupport

/// The shared engine contract against the real engine, in the app (week-3 plan, Task W3-9 step 1). Runs with
/// `--arkt-engine-contract` and `--arkt-engine-test-api` (plus the tabs probe extension loaded with
/// `--load-extension`); the shell's session is not started. Every check gets a fresh `ChromiumEngine` from
/// `ChromiumEmbedding.makeEngine()`, its own windows, and pages from a loopback server. Prints one
/// `ARKT_CONTRACT` line per check and per rule, then exits: 0 when all 17 rules pass, 1 when any check fails or
/// reports not applicable, 2 when the runner cannot start.
///
/// The switch is a Chromium-style switch, not `-ArktEngineContract YES` as the plan wrote it: Chromium reads every
/// argument that is not a switch as a URL to open at startup (`YES` became a queued startup window).
@MainActor
final class EngineContractRunner {
  static var isRequested: Bool { CommandLine.arguments.contains { $0 == switchName || $0.hasPrefix(switchName + "=") } }
  static let switchName = "--arkt-engine-contract"

  /// `--arkt-engine-contract=<check>,<check>` runs only the named checks (diagnostics); the plain switch runs all.
  /// A name that is not a check, or an empty list, is an error: a typo must never run nothing and pass.
  static func selectedChecks() throws -> [ContractCheck] {
    guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix(switchName + "=") }) else {
      return ContractCheck.allCases
    }
    let names = argument.dropFirst(switchName.count + 1).split(separator: ",").map(String.init)
    let unknown = names.filter { ContractCheck(rawValue: $0) == nil }
    guard unknown.isEmpty, !names.isEmpty else {
      throw RunnerError("\(switchName)= names no check" + (unknown.isEmpty ? "" : ": unknown \(unknown.joined(separator: ", "))"))
    }
    let selected = Set(names)
    return ContractCheck.allCases.filter { selected.contains($0.rawValue) }
  }

  static let tabsProbeName = "Arkt tabs probe"

  private let server: ContractPageServer
  private let control: ChromiumEngine
  private let controlTab: TabID
  private var serial = 0
  /// Per check: the engines it made, their hosts, and the load ends seen per tab.
  private var engines: [ChromiumEngine] = []
  private var hosts: [RunnerWindowHost] = []
  private var loads: [ObjectIdentifier: LoadLog] = [:]

  private init(server: ContractPageServer, control: ChromiumEngine, controlTab: TabID) {
    self.server = server
    self.control = control
    self.controlTab = controlTab
  }

  /// Starts the runner one turn after `embedderReady`; never returns to the shell.
  static func start() {
    setvbuf(stdout, nil, _IOLBF, 0)
    Task { @MainActor in
      let status = await run()
      FileHandle.standardOutput.write(Data("ARKT_CONTRACT exit \(status)\n".utf8))
      exit(status)
    }
  }

  private static func run() async -> Int32 {
    do {
      let checks = try selectedChecks()
      let runner = try await prepare()
      return await runner.runAll(checks)
    } catch {
      print("ARKT_CONTRACT setup failed: \(error)")
      return 2
    }
  }

  /// The page server, and a control tab on the tabs probe's own page (its `chrome.tabs` drives rules 13 and 14).
  private static func prepare() async throws -> EngineContractRunner {
    guard let control = ChromiumEmbedding.makeEngine() else { throw RunnerError("no engine (before engineDidStart)") }
    guard control.testAPIEnabled else { throw RunnerError("launch with --arkt-engine-test-api") }
    let server = try await ContractPageServer.start()
    let host = RunnerWindowHost(index: 0)
    let window = control.createWindow(host: host)
    let blank = control.createTab(url: nil, in: window)
    var probeID: String?
    try await EngineContract.waitUntil(timeout: .seconds(15)) {
      probeID = control.extensionActions(in: window).first { $0.name == tabsProbeName }?.id
      return probeID != nil
    }
    guard let probeID, let page = URL(string: "chrome-extension://\(probeID)/control.html") else {
      throw RunnerError("the tabs probe is not loaded (--load-extension=<engine/test-extensions/tabs-probe>)")
    }
    let tab = control.createTab(url: page, in: window)
    control.closeTab(blank, mode: .skipUnloadHandlers)
    try await EngineContract.waitUntil(timeout: .seconds(10)) {
      control.snapshot(of: tab).map { !$0.isLoading && $0.url == page } ?? false
    }
    print("ARKT_CONTRACT setup pages=127.0.0.1:\(server.port) tabs-probe=\(probeID)")
    return EngineContractRunner(server: server, control: control, controlTab: tab)
  }

  // MARK: Checks

  private func runAll(_ checks: [ContractCheck]) async -> Int32 {
    let harness = makeHarness()
    var failedRules: Set<Int> = []
    for check in checks {
      shellLog("contract check \(check.rawValue) started")
      let started = ContinuousClock.now
      let outcome: String
      do {
        try await check.run(harness)
        outcome = "PASS"
      } catch let error as ContractNotApplicable {
        outcome = "NOT-APPLICABLE \(error)"
        failedRules.insert(check.rule)
      } catch {
        outcome = "FAIL \(error)"
        failedRules.insert(check.rule)
      }
      await cleanUp()
      let elapsed = started.duration(to: .now).components
      let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
      print("ARKT_CONTRACT rule \(check.rule) \(check.rawValue) \(outcome) (\(ms) ms)")
    }
    let rules = Set(checks.map(\.rule)).sorted()
    for rule in rules {
      print("ARKT_CONTRACT rule \(rule) \(failedRules.contains(rule) ? "FAIL" : "PASS")")
    }
    print("ARKT_CONTRACT result \(rules.count - failedRules.count)/\(rules.count)")
    control.closeTab(controlTab, mode: .skipUnloadHandlers)
    server.stop()
    return failedRules.isEmpty ? 0 : 1
  }

  /// Closes what the check left open: its windows (unload handlers skipped) and their host windows.
  private func cleanUp() async {
    for engine in engines {
      for id in engine.tabIDs { engine.closeTab(id, mode: .skipUnloadHandlers) }
      for window in engine.windowIDs { engine.closeWindow(window) }
    }
    let engines = self.engines
    do {
      try await EngineContract.waitUntil(timeout: .seconds(5)) { engines.allSatisfy(\.windowIDs.isEmpty) }
    } catch {
      let left = engines.reduce(0) { $0 + $1.windowIDs.count }
      print("ARKT_CONTRACT cleanup: \(left) window(s) still open after 5 s; the next check starts anyway")
    }
    for host in hosts { host.window.orderOut(nil) }
    self.engines = []
    hosts = []
    loads = [:]
  }

  // MARK: Harness

  private func makeHarness() -> EngineHarness {
    EngineHarness(
      makeEngine: { [unowned self] in
        guard let engine = ChromiumEmbedding.makeEngine() else { preconditionFailure("no engine") }
        engines.append(engine)
        loads[ObjectIdentifier(engine)] = LoadLog(engine: engine, mount: { [unowned self] id in mount(id, of: engine) })
        // A window-less createTab needs a window of the instance (rules 1-10).
        engine.createWindow(host: makeHost())
        return engine
      },
      pageURL: { [unowned self] title in
        serial += 1
        return server.page(title, serial: serial)
      },
      settle: { [unowned self] engine, id in try await settle(engine, id) },
      retitle: { [unowned self] engine, id, title in
        _ = try await chromium(engine).evaluateScript("document.title = \(jsString(title)); true", in: id,
                                                      userGesture: false)
      },
      pagesOnTwoHosts: { [unowned self] in
        serial += 2
        return (server.page("Alpha", host: "127.0.0.1", serial: serial - 1),
                server.page("Beta", host: "localhost", serial: serial))
      },
      makeWindowHost: { [unowned self] in makeHost() },
      engineCreateTab: { [unowned self] engine, window, opener, _ in
        try await engineCreateTab(engine, window, opener)
      },
      engineCloseTab: { [unowned self] engine, id in
        try await probeTab(engine, id, action: "await chrome.tabs.remove(t.id)")
      },
      engineActivate: { [unowned self] engine, id in
        try await probeTab(engine, id, action: "await chrome.tabs.update(t.id, { active: true })")
      },
      holdClose: { [unowned self] engine, id in
        let script = "window.onbeforeunload = (event) => { event.preventDefault(); event.returnValue = ''; "
          + "return 'hold'; }; navigator.userActivation.hasBeenActive"
        let active = try await chromium(engine).evaluateScript(script, in: id, userGesture: true)
        guard active == .bool(true) else { throw RunnerError("no sticky activation: \(String(describing: active))") }
      },
      answerDialog: { [unowned self] engine, id, accept in
        // The dialog shows a task or two after `isClosing`; retry until the engine has one to answer.
        let chromium = try chromium(engine)
        var answered = false
        try await EngineContract.waitUntil(timeout: .seconds(5)) {
          answered = chromium.answerDialog(in: id, accept: accept)
          return answered
        }
      },
      makeAudible: { [unowned self] engine, id in
        // A Web Audio tone; the user gesture lets it start under the autoplay policy (rule 17, #364).
        let state = try await chromium(engine).evaluateScript(EngineContract.toneScript, in: id, userGesture: true)
        guard state == .string("running") else {
          throw RunnerError("the tone did not start: \(String(describing: state))")
        }
      }
    )
  }

  private func makeHost() -> RunnerWindowHost {
    let host = RunnerWindowHost(index: hosts.count + 1)
    hosts.append(host)
    return host
  }

  /// Shows the active tab of its window in that window's card, as the shell does, so pages run visible.
  private func mount(_ id: TabID, of engine: ChromiumEngine) {
    guard let window = engine.snapshot(of: id)?.window,
          let host = engine.host(of: window) as? RunnerWindowHost,
          let view = engine.contentView(for: id) else { return }
    host.show(view)
  }

  /// Waits for the end of the tab's current load: a `loadingChanged(false)` on a page other than the initial
  /// `about:blank`, seen after the previous settle of that tab, with the snapshot not loading. Returns at once for a
  /// tab that closed.
  private func settle(_ engine: any EngineClient, _ id: TabID) async throws {
    let chromium = try chromium(engine)
    guard let log = loads[ObjectIdentifier(chromium)] else { throw RunnerError("no load log for the engine") }
    let baseline = log.settled[id, default: 0]
    do {
      try await EngineContract.waitUntil(timeout: .seconds(15)) {
        guard let snapshot = chromium.snapshot(of: id) else { return true }
        return log.loadEnds[id, default: 0] > baseline && !snapshot.isLoading
      }
    } catch {
      throw RunnerError("settle \(id): no load end (snapshot \(String(describing: chromium.snapshot(of: id))))")
    }
    log.settled[id] = log.loadEnds[id, default: 0]
  }

  /// `window.open` with a user gesture in the opener (or the window's first tab); the new tab once it is listed.
  private func engineCreateTab(_ engine: any EngineClient, _ window: EngineWindowID,
                               _ opener: TabID?) async throws -> TabID {
    let chromium = try chromium(engine)
    guard let source = opener ?? EngineContractRunner.firstTab(of: chromium, in: window) else {
      throw RunnerError("no tab in \(window) to open a tab from")
    }
    serial += 1
    let url = server.page("Opened", serial: serial)
    let before = Set(chromium.tabIDs)
    let opened = try await chromium.evaluateScript("!!window.open(\(jsString(url.absoluteString)))", in: source,
                                                   userGesture: true)
    guard opened == .bool(true) else { throw RunnerError("window.open answered \(String(describing: opened))") }
    var created: TabID?
    try await EngineContract.waitUntil(timeout: .seconds(10)) {
      created = Set(chromium.tabIDs).subtracting(before).first
      return created != nil
    }
    return created!
  }

  private static func firstTab(of engine: ChromiumEngine, in window: EngineWindowID) -> TabID? {
    engine.tabIDs.first { engine.snapshot(of: $0)?.window == window }
  }

  /// Runs `action` on the Chromium tab whose URL is the tab's, from the tabs probe's page (`t` is the
  /// `chrome.tabs.Tab`). The page answers asynchronously; the result is read back from `window.__arktProbe`.
  private func probeTab(_ engine: any EngineClient, _ id: TabID, action: String) async throws {
    guard let url = try chromium(engine).snapshot(of: id)?.url else { throw RunnerError("no tab \(id)") }
    let script = """
      window.__arktProbe = null;
      (async () => {
        const tabs = await chrome.tabs.query({});
        const t = tabs.find((t) => (t.url || t.pendingUrl) === \(jsString(url.absoluteString)));
        if (!t) throw new Error("no Chromium tab with the URL");
        \(action);
        return t.id;
      })().then((v) => { window.__arktProbe = "ok " + v; }, (e) => { window.__arktProbe = "error " + e.message; });
      true
      """
    _ = try await control.evaluateScript(script, in: controlTab, userGesture: false)
    var answer: String?
    let deadline = ContinuousClock.now + .seconds(10)
    while answer == nil, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
      if case .string(let value)? = try await control.evaluateScript("window.__arktProbe", in: controlTab,
                                                                     userGesture: false) {
        answer = value
      }
    }
    guard let answer, answer.hasPrefix("ok") else {
      throw RunnerError("tabs probe: \(answer ?? "no answer")")
    }
  }

  private func chromium(_ engine: any EngineClient) throws -> ChromiumEngine {
    guard let engine = engine as? ChromiumEngine else { throw RunnerError("not a ChromiumEngine: \(engine)") }
    return engine
  }

  private func jsString(_ text: String) -> String {
    let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
    return String(decoding: data, as: UTF8.self)
  }

  struct RunnerError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }
}

/// Counts each tab's load ends (not the initial `about:blank`) and mounts the active tab of each window.
@MainActor
private final class LoadLog {
  var loadEnds: [TabID: Int] = [:]
  var settled: [TabID: Int] = [:]
  private var observation: EngineObservation?

  init(engine: ChromiumEngine, mount: @escaping @MainActor (TabID) -> Void) {
    observation = engine.observe { [weak self, unowned engine] event in
      switch event {
      case .loadingChanged(let id, isLoading: false):
        if let url = engine.snapshot(of: id)?.url, url.absoluteString != "about:blank" {
          self?.loadEnds[id, default: 0] += 1
        }
      case .activeTabChanged(let id):
        mount(id)
      default:
        break
      }
    }
  }
}

/// A plain window per engine window, shown without activating the app, with the active tab mounted in its card.
@MainActor
private final class RunnerWindowHost: EngineWindowHosting {
  let window: NSWindow
  let cardView: NSView
  var forward: EngineCommandForwarding?
  var onCloseRequested: (@MainActor () -> Void)?

  init(index: Int) {
    let frame = NSRect(x: 80 + (index % 6) * 40, y: 80 + (index % 6) * 30, width: 720, height: 520)
    window = NSWindow(contentRect: frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.title = "Arkt contract runner \(index)"
    window.isReleasedWhenClosed = false
    cardView = NSView(frame: NSRect(origin: .zero, size: frame.size))
    cardView.autoresizingMask = [.width, .height]
    window.contentView = cardView
    window.orderFront(nil)
  }

  func show(_ view: NSView) {
    guard view.superview !== cardView || cardView.subviews.count != 1 else { return }
    cardView.subviews.forEach { $0.removeFromSuperview() }
    view.frame = cardView.bounds
    view.autoresizingMask = [.width, .height]
    cardView.addSubview(view)
  }

  func claim(_ command: EngineCommand) -> CommandClaim? { nil }
  func perform(_ command: EngineCommand, disposition: EngineDisposition) -> Bool { false }
}
#endif
