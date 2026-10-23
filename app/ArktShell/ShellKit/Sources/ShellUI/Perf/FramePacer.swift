import AppKit
import QuartzCore

/// Records display-link intervals while a hot-path interaction runs. A blocked main thread delays the
/// callback past a vsync, so the vsync-aligned `timestamp` jumps by two refresh intervals and shows up
/// as an interval over the threshold. Every interval over 8.6 ms is logged as a `hitch` line (the first
/// interval as a `leadin` line: it is excluded from the gate, see `FrameStats`), with how late this and the
/// previous callback ran after their vsync and the link's current frame duration (a display rate change
/// shows as frameMs other than 8.33); `end()` logs one `pacing`
/// summary line (subsystem dev.arkt.shell, category perf).
@MainActor
public final class FramePacer: NSObject {
  private var link: CADisplayLink?
  private var last: CFTimeInterval?
  /// How late the previous callback ran after its vsync (main-thread blocked vs. a skipped vsync).
  private var lastLate: CFTimeInterval = 0
  private var label = ""
  private var session = 0
  public private(set) var stats = FrameStats()

  public var isRunning: Bool { link != nil }

  /// Starts a measurement (ending any running one) and returns its session token for `end(session:)`.
  @discardableResult
  public func begin(_ label: String, in view: NSView) -> Int {
    end()
    session += 1
    self.label = label
    stats = FrameStats()
    last = nil
    lastLate = 0
    let link = view.displayLink(target: self, selector: #selector(tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    self.link = link
    return session
  }

  /// Ends the measurement started with `session` (no-op if a newer one replaced it) and logs it.
  @discardableResult
  public func end(session token: Int) -> FrameStats? {
    token == session ? end() : nil
  }

  /// Ends whatever measurement is running and logs it. Nil if none was running.
  @discardableResult
  public func end() -> FrameStats? {
    guard let link else { return nil }
    link.invalidate()
    self.link = nil
    let fps = NSScreen.main?.maximumFramesPerSecond ?? 0
    let s = stats
    ShellSignposts.logger.notice("""
      pacing label=\(self.label, privacy: .public) screenMaxFPS=\(fps) frames=\(s.frameCount) \
      over8.6=\(s.hitchCount) overBudgetPct=\(s.overBudgetRatio * 100, format: .fixed(precision: 2)) \
      maxMs=\(s.maxInterval * 1000, format: .fixed(precision: 2)) p99Ms=\(s.p99 * 1000, format: .fixed(precision: 2)) \
      leadInMs=\((s.leadInInterval ?? 0) * 1000, format: .fixed(precision: 2))
      """)
    return s
  }

  @objc private func tick(_ link: CADisplayLink) {
    let late = CACurrentMediaTime() - link.timestamp
    defer { last = link.timestamp; lastLate = late }
    guard let last else { return }     // the first tick after begin has no interval
    let interval = link.timestamp - last
    let leadIn = stats.leadInInterval == nil
    stats.record(interval: interval)
    if leadIn {
      ShellSignposts.logger.info(
        "leadin label=\(self.label, privacy: .public) ms=\(interval * 1000, format: .fixed(precision: 2))")
    } else if interval > stats.hitchThreshold {
      ShellSignposts.signposter.emitEvent("Hitch")      // findable in an Instruments trace
      ShellSignposts.logger.notice("""
        hitch label=\(self.label, privacy: .public) ms=\(interval * 1000, format: .fixed(precision: 2)) \
        lateMs=\(late * 1000, format: .fixed(precision: 2)) prevLateMs=\(self.lastLate * 1000, format: .fixed(precision: 2)) \
        frameMs=\((link.targetTimestamp - link.timestamp) * 1000, format: .fixed(precision: 2))
        """)
    }
  }
}
