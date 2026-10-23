#if DEBUG || ARKT_SMOKE_BUILD
import AppKit
import EngineAPI
@_spi(Smoke) import ShellUI

/// Scripted smoke (launch argument `-ArktSmoke YES`, Debug and Profile builds only): command bar latency,
/// example.com through the command bar, two scripted swipes and a keyboard round trip, all through the same code
/// paths as user input. Pacing runs use the optimized Profile build. Prints one `ARKT_SMOKE {json}` line and
/// exits: 0 functional pass and pacing PASS, 1 functional pass with pacing FAIL or NOT-MEASURABLE (60 Hz screen or
/// a loaded machine), 2 functional failure, 3 the watchdog's time budget ran out (`SmokeWatchdog`).
@MainActor
final class SmokeRunner {
  struct Report: Encodable {
    var screenMaxFPS: Int
    var load1: Double
    var cores: Int
    var commandBarFirstShowMs: Double
    var commandBarWarmShowMs: [Double]
    var commandBarWarmP95Ms: Double
    var commandBarEarliestFrameBoundMs: Double
    /// Per warm show: main-thread CPU and wall time inside show(), and show() start to the first vsync.
    var commandBarWarmCPUMs: [Double]
    var commandBarWarmWallMs: [Double]
    var commandBarWarmVsyncWaitMs: [Double]
    /// Per warm show: show() start to the end of the run loop pass (and Core Animation commit) that carried it.
    var commandBarWarmCommitDelayMs: [Double]
    var pauseBetweenSeconds: Double
    var exampleLoaded: Bool
    var exampleTitle: String
    var interactions: [Interaction]
    var functional: String
    var functionalFailures: [String]
    var pacingVerdict: String
    struct Interaction: Encodable {
      var label: String; var expectedIndex: Int; var index: Int
      var frames: Int; var over8_6ms: Int; var overBudgetPct: Double; var maxMs: Double; var p99Ms: Double
      var leadInMs: Double
      /// "frame@ms" for every gated interval over 8.6 ms (frame 0 is the first after the lead-in).
      var hitches: [String]
    }
  }

  let controller: ShellWindowController
  private var failures: [String] = []

  init(controller: ShellWindowController) { self.controller = controller }

  func run() async -> Int32 {
    NSApp.activate()
    controller.window?.makeKeyAndOrderFront(nil)
    _ = await waitFor(seconds: 5) { [controller] in controller.window?.isKeyWindow ?? false }
    try? await Task.sleep(for: .seconds(1))                          // window on screen, prewarm done
    let fps = controller.window?.screen?.maximumFramesPerSecond ?? 0
    var load = [0.0]
    let cores = ProcessInfo.processInfo.activeProcessorCount
    let loaded = getloadavg(&load, 1) != 1 || load[0] >= Double(cores)
    let bar = controller.commandBar

    // 1. Command bar latency: first show after launch, then 10 warm shows.
    let first = await measureShow(bar)
    var warm: [Double] = []
    var cpu: [Double] = [], wall: [Double] = [], vsync: [Double] = [], commit: [Double] = []
    for _ in 0..<10 {
      guard let ms = await measureShow(bar) else { continue }
      warm.append(ms)
      cpu.append(bar.lastShowCPUTime * 1000)
      wall.append(bar.lastShowWallTime * 1000)
      vsync.append(bar.lastShowVsyncWait * 1000)
      commit.append(bar.lastShowCommitDelay * 1000)
    }
    if first == nil || warm.count < 10 { failures.append("command bar did not show (window not key?)") }
    let sortedWarm = warm.sorted()
    let warmP95 = sortedWarm.isEmpty ? .infinity : sortedWarm[max(sortedWarm.count * 95 / 100 - 1, 0)]
    // The adopted command bar gate (C5): the bar lands on the earliest possible frame, p95 total within
    // wall work p95 + 2 refresh intervals + 0.5 ms (an absolute 16 ms is below two 120 Hz frames).
    let sortedWall = wall.sorted()
    let wallP95 = sortedWall.isEmpty ? 0 : sortedWall[max(sortedWall.count * 95 / 100 - 1, 0)]
    let earliestFrameBound = wallP95 + 2000 / Double(max(fps, 1)) + 0.5

    // 1b. KB-003: a real key change away from the bar hides it. The panel stays ordered in since C7 fix 2,
    // so this checks the window-server path, not only the delegate call the unit tests make.
    bar.toggle(.newTab)
    let barKey = await waitFor(seconds: 1) { [controller] in !(controller.window?.isKeyWindow ?? true) }
    controller.window?.makeKey()
    let resignHid = await waitFor(seconds: 1) { [controller] in
      !bar.isVisible && (controller.window?.isKeyWindow ?? false)
    }
    if !barKey || !resignHid {
      failures.append("KB-003: resign key did not hide the command bar (bar key \(barKey), hidden \(!bar.isVisible))")
    }
    if bar.isVisible { bar.toggle(.newTab) }

    // 2. Open example.com through the command bar (KB-001 path).
    bar.toggle(.newTab)
    bar.setQueryForTesting("example.com")
    bar.commit()
    let exampleOK = await waitFor(seconds: 20) { [controller] in
      controller.currentTab.flatMap { controller.engine.snapshot(of: $0) }
        .map { !$0.isLoading && $0.title == "Example Domain" } ?? false
    }
    let title = controller.currentTab.flatMap { controller.engine.snapshot(of: $0) }?.title ?? ""
    if !exampleOK { failures.append("example.com did not load (title \"\(title)\")") }

    // 3. Scripted swipes to Space 2 and back, then the keyboard round trip.
    var interactions: [Report.Interaction] = []
    let pager = controller.pager
    // -ArktSmokePause N: seconds between interactions (diagnostics; 0 = back to back).
    let pause = SmokeArguments.double("ArktSmokePause") ?? 0
    // -ArktSmokeRepeat N: run the swipe and keyboard round trips N times (default 1).
    let rounds = SmokeArguments.rounds
    for _ in 0..<rounds {
      for (label, direction, expected) in [("swipe-next", -1.0, 1), ("swipe-back", 1.0, 0)] {
        if pause > 0 { try? await Task.sleep(for: .seconds(pause)) }
        if let stats = await scriptedSwipe(pager, direction: direction) {
          interactions.append(entry(label, expected: expected, index: pager.index, stats))
        } else {
          failures.append("\(label): no settle")
        }
      }
      for (label, expected) in [("key-next", 1), ("key-previous", 0)] {
        if pause > 0 { try? await Task.sleep(for: .seconds(pause)) }
        let stats = await keyboardSwitch(pager, next: expected == 1)
        if let stats { interactions.append(entry(label, expected: expected, index: pager.index, stats)) }
        else { failures.append("\(label): no settle") }
      }
    }
    for i in interactions where i.index != i.expectedIndex {
      failures.append("\(i.label): landed on page \(i.index), expected \(i.expectedIndex)")
    }

    let hitchFree = interactions.count == 4 * rounds && interactions.allSatisfy { $0.over8_6ms == 0 }
    let pacing: String
    if fps < 120 {
      pacing = "NOT-MEASURABLE (screen \(fps) Hz)"
    } else if loaded {
      pacing = String(format: "NOT-MEASURABLE (load %.2f on %d cores)", load[0], cores)
    } else {
      pacing = hitchFree && warmP95 <= earliestFrameBound ? "PASS" : "FAIL"
    }
    let report = Report(
      screenMaxFPS: fps, load1: load[0], cores: cores, commandBarFirstShowMs: first ?? -1,
      commandBarWarmShowMs: warm, commandBarWarmP95Ms: warmP95.isFinite ? warmP95 : -1,
      commandBarEarliestFrameBoundMs: earliestFrameBound,
      commandBarWarmCPUMs: cpu, commandBarWarmWallMs: wall, commandBarWarmVsyncWaitMs: vsync,
      commandBarWarmCommitDelayMs: commit,
      pauseBetweenSeconds: pause,
      exampleLoaded: exampleOK, exampleTitle: title, interactions: interactions,
      functional: failures.isEmpty ? "PASS" : "FAIL", functionalFailures: failures, pacingVerdict: pacing)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = (try? encoder.encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    print("ARKT_SMOKE \(json)")
    if !failures.isEmpty { return 2 }
    return pacing == "PASS" ? 0 : 1
  }

  private func entry(_ label: String, expected: Int, index: Int, _ s: FrameStats) -> Report.Interaction {
    .init(label: label, expectedIndex: expected, index: index, frames: s.frameCount, over8_6ms: s.hitchCount,
          overBudgetPct: s.overBudgetRatio * 100, maxMs: s.maxInterval * 1000, p99Ms: s.p99 * 1000,
          leadInMs: (s.leadInInterval ?? 0) * 1000,
          hitches: s.intervals.enumerated().filter { $0.element > s.hitchThreshold }
            .map { String(format: "%d@%.2f", $0.offset, $0.element * 1000) })
  }

  /// Opens the bar, waits for its first frame, closes it. Nil if it did not show within 2 s.
  private func measureShow(_ bar: CommandBarController) async -> Double? {
    var latency: Double?
    bar.onFirstFrame = { latency = $0 }
    defer { bar.onFirstFrame = nil }
    bar.toggle(.newTab)
    guard bar.isVisible else { return nil }
    _ = await waitFor(seconds: 2) { latency != nil }
    bar.toggle(.newTab)                                             // close again
    try? await Task.sleep(for: .milliseconds(30))                   // same gap as the GUI latency test
    return latency.map { $0 * 1000 }
  }

  /// 20 display frames of 9 pt finger movement (180 pt), then release: a medium trackpad swipe,
  /// stepped once per vsync like the GUI pacing test.
  private func scriptedSwipe(_ pager: SpacePagerView, direction: Double) async -> FrameStats? {
    var settled = false
    pager.onSettleForTesting = { _ in settled = true }
    defer { pager.onSettleForTesting = nil }
    pager.beginTracking()
    guard pager.isTracking else { return nil }                      // zero-width pager
    let script = SmokeFrameScript(view: pager, frames: 20,
                                  step: { t in pager.track(delta: CGFloat(direction * 9), at: t) },
                                  done: { pager.endTracking() })
    let ok = await waitFor(seconds: 5) { settled }
    script.cancel()
    return ok ? pager.lastPacing : nil
  }

  private func keyboardSwitch(_ pager: SpacePagerView, next: Bool) async -> FrameStats? {
    var settled = false
    pager.onSettleForTesting = { _ in settled = true }
    defer { pager.onSettleForTesting = nil }
    if next { controller.nextSpace(nil) } else { controller.previousSpace(nil) }
    return await waitFor(seconds: 5) { settled } ? pager.lastPacing : nil
  }

  private func waitFor(seconds: Double, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
  }
}

/// Steps a scripted interaction once per display frame.
@MainActor
private final class SmokeFrameScript: NSObject {
  private var link: CADisplayLink?
  private var remaining: Int
  private let step: @MainActor (CFTimeInterval) -> Void
  private let done: @MainActor () -> Void

  init(view: NSView, frames: Int, step: @escaping @MainActor (CFTimeInterval) -> Void,
       done: @escaping @MainActor () -> Void) {
    remaining = frames
    self.step = step
    self.done = done
    super.init()
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  func cancel() { link?.invalidate(); link = nil }

  @objc private func tick(_ link: CADisplayLink) {
    guard remaining > 0 else { cancel(); done(); return }
    remaining -= 1
    step(link.timestamp)
  }
}

/// Smoke options, read from the command line only (`-ArktSmoke YES -ArktSmokeRepeat 3`): a default persisted in
/// any other domain must never turn a normal launch into a smoke run.
enum SmokeArguments {
  /// The value after `-<key>`, or nil when the option is absent or has no value.
  static func value(_ key: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
    guard let index = arguments.firstIndex(of: "-" + key), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
  }

  /// `-ArktSmoke YES` (also `1` or `true`, any case).
  static var isEnabled: Bool {
    guard let value = value("ArktSmoke") else { return false }
    return ["yes", "1", "true"].contains(value.lowercased())
  }

  static func double(_ key: String) -> Double? { value(key).flatMap(Double.init) }

  /// `-ArktSmokeRepeat N`, at least 1.
  static var rounds: Int { max(value("ArktSmokeRepeat").flatMap(Int.init) ?? 1, 1) }
}

/// Hard budget for a smoke run: a timer off the main thread ends the process even when the main thread
/// hangs. Budget: `-ArktSmokeTimeout S`, else 60 s plus 8 s per `-ArktSmokeRepeat` round. Exit code 3.
/// Main-actor state (the timer is set once, from app launch); the handler is `@Sendable` and runs on a global
/// queue, so it captures only the budget.
@MainActor
enum SmokeWatchdog {
  private static var timer: DispatchSourceTimer?

  static func start() {
    let override = SmokeArguments.double("ArktSmokeTimeout") ?? 0
    let budget = override > 0 ? override : 60 + 8 * Double(SmokeArguments.rounds)
    let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
    source.schedule(deadline: .now() + budget)
    source.setEventHandler { @Sendable in
      let line = "ARKT_SMOKE_TIMEOUT budget=\(Int(budget))s\n"
      FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
      print("ARKT_SMOKE {\"functional\":\"TIMEOUT\",\"budgetSeconds\":\(Int(budget))}")
      fflush(stdout)
      _exit(3)
    }
    source.resume()
    timer = source
  }
}
#endif
