import Foundation
import QuartzCore

/// One main run loop pass, from wake-up to going back to sleep (after Core Animation's commit).
public struct BusySpan: Sendable, Equatable {
  /// `CACurrentMediaTime()` at wake-up and at the end of the pass.
  public var start: CFTimeInterval
  public var end: CFTimeInterval
  /// Main-thread CPU time spent in the pass.
  public var cpu: CFTimeInterval

  public var wall: CFTimeInterval { end - start }
  /// Wall time the main thread was not running in the pass: preempted by other work on the machine, or blocked (for
  /// example on a window server reply).
  public var offCPU: CFTimeInterval { max(wall - cpu, 0) }
}

/// What the main thread did across one late frame: the run loop passes that overlap the interval between the two
/// vsyncs, and which of them held the thread longest. CPU near wall time means app work; a large `offCPU` means the
/// thread was not running (preempted by load outside the app, or blocked).
public struct HitchDetail: Sendable, Equatable {
  public var label: String
  /// Index of the late interval among the session's gated intervals.
  public var frame: Int
  public var interval: CFTimeInterval
  public var late: CFTimeInterval
  public var previousLate: CFTimeInterval
  /// The longest pass overlapping the interval (nil if none ended inside it, e.g. the probe was not running).
  public var longest: BusySpan?
  /// Number of passes and their total CPU time inside the interval.
  public var passes: Int
  public var cpu: CFTimeInterval
}

/// Records main run loop passes with wall and thread CPU time while a hot-path interaction runs, so a late frame can
/// be attributed without Instruments: app work (CPU about equal to wall) versus a thread that was preempted or
/// blocked (wall well above CPU). Two run loop observers; about a microsecond per pass, only while started.
@MainActor
final class MainThreadBusyProbe {
  private var observer: CFRunLoopObserver?
  private var openStart: CFTimeInterval?
  private var openCPU: UInt64 = 0
  /// The most recent passes, oldest first (bounded; a hitch only looks a few frames back).
  private(set) var spans: [BusySpan] = []
  private let capacity: Int

  init(capacity: Int = 32) { self.capacity = capacity }

  var isRunning: Bool { observer != nil }

  func start() {
    guard observer == nil else { return }
    spans.removeAll(keepingCapacity: true)
    openStart = nil
    let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
    // Ordered last, so a before-waiting pass ends after Core Animation's commit observer (order 2000000).
    let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, CFIndex.max) { [weak self] _, activity in
      MainActor.assumeIsolated { self?.observe(activity) }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    self.observer = observer
    // The pass this is called from is already running; count it from here.
    open()
  }

  func stop() {
    guard let observer else { return }
    CFRunLoopObserverInvalidate(observer)
    self.observer = nil
    openStart = nil
  }

  /// The pass running now (from its wake-up until this call); nil when stopped.
  func currentSpan(now: CFTimeInterval = CACurrentMediaTime()) -> BusySpan? {
    guard let openStart else { return nil }
    return span(start: openStart, end: now)
  }

  /// Passes that overlap `from...to`, including the running one.
  func spans(overlapping from: CFTimeInterval, _ to: CFTimeInterval) -> [BusySpan] {
    var result = spans.filter { $0.end > from && $0.start < to }
    if let current = currentSpan(), current.start < to { result.append(current) }
    return result
  }

  private func observe(_ activity: CFRunLoopActivity) {
    if activity.contains(.afterWaiting) {
      open()
    } else if activity.contains(.beforeWaiting), let start = openStart {
      spans.append(span(start: start, end: CACurrentMediaTime()))
      if spans.count > capacity { spans.removeFirst(spans.count - capacity) }
      openStart = nil
    }
  }

  private func open() {
    openStart = CACurrentMediaTime()
    openCPU = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
  }

  private func span(start: CFTimeInterval, end: CFTimeInterval) -> BusySpan {
    BusySpan(start: start, end: end, cpu: Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) &- openCPU) / 1e9)
  }
}
