import AppKit
import Motion

// MARK: - GS-012: rest at the sidebar's edge to reach another Space

/// A sidebar drag that rests at the page's left or right edge pages to the previous or next Space, so the drop lands
/// on that Space's page (GS-012, BH-042). Pure: time is passed in. PARITY(NEEDS-RUNTIME-CHECK [I]): Arc's edge width
/// and dwell time are unmeasured.
public struct SpaceEdgeDwell: Sendable {
  /// How close to the page's edge the pointer has to be, in points.
  public static let edgeWidth: CGFloat = 14
  /// How long it rests there before the page turns; it keeps turning once per dwell while it stays.
  public static let dwell: Double = 0.5

  private var edge: Int?
  private var since: Double = 0

  public init() {}

  /// The pointer is at `x` of a page `width` wide at time `t`. Returns -1 or 1 when the page should turn back or
  /// forward now, nil otherwise.
  public mutating func update(x: CGFloat, width: CGFloat, at t: Double) -> Int? {
    let current: Int? = x <= Self.edgeWidth ? -1 : (x >= width - Self.edgeWidth ? 1 : nil)
    guard let current else {
      edge = nil
      return nil
    }
    if edge != current {
      edge = current
      since = t
      return nil
    }
    guard t - since >= Self.dwell else { return nil }
    since = t
    return current
  }

  public mutating func reset() { edge = nil }
}

// MARK: - GS-013: drag a tab out to a new window

/// A tab dragged out of the sidebar and released over no window opens in a new window there (GS-013, BH-029). The
/// window that held its page hands it over without a reload (Tab Handoff, #300).
public enum SidebarDragOut {
  /// True when nothing took the drop (`operation` empty), it was not cancelled with Escape, the pointer is outside
  /// every window of the app, and the drag carries one tab.
  public static func opensWindow(operation: NSDragOperation, endedByEscape: Bool, endPoint: CGPoint,
                                 windowFrames: [CGRect], payload: SidebarDragPayload) -> Bool {
    operation.isEmpty && !endedByEscape && payload.isSingleTab
      && !windowFrames.contains { $0.contains(endPoint) }
  }
}

// MARK: - GS-015: drop text into the sidebar

/// Where a drop lands as a new row: a location and an index (nil appends).
public struct SidebarDropPlacement: Equatable, Sendable {
  public var location: SidebarLocation
  public var index: Int?

  public init(location: SidebarLocation, index: Int?) {
    self.location = location; self.index = index
  }
}

/// Text or a link dragged into the sidebar opens as a new tab where the indicator stands (GS-015, BH-022): a URL as
/// itself, any other text as a search.
public enum SidebarTextDrop {
  /// The page for dropped `text`; nil for blank text.
  public static func url(for text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return URLInputParser.url(from: trimmed) ?? URLInputParser.searchURL(for: trimmed)
  }

  /// Where the new tab goes for `target`: an insert's place, a folder's end, otherwise the top of Today (a split is
  /// not a place a new row can be put).
  public static func location(for target: SidebarDropTarget?, space: SpaceID) -> SidebarDropPlacement {
    switch target {
    case .insert(let location, let index, _, _)?:
      if case .split = location { return SidebarDropPlacement(location: .today(space), index: 0) }
      return SidebarDropPlacement(location: location, index: index)
    case .folder(let folder, _)?:
      return SidebarDropPlacement(location: .folder(folder), index: nil)
    case .split?, nil:
      return SidebarDropPlacement(location: .today(space), index: 0)
    }
  }
}

// MARK: - Motion

/// The springs of a sidebar drop preview (#104).
///
/// Purpose: spatial consistency. The rows below the drop point make room, so the user sees where the row will land
/// before letting go, and slide back when the drag leaves or is cancelled. Every move is a spring that starts from
/// where the row is and how fast it moves, so a pointer that changes its mind mid-flight never makes a row jump.
/// Reduce Motion: no row moves; the indicator alone shows the place, appearing and moving without travel.
public enum SidebarDropMotion {
  /// Rows opening the gap: quick, a touch of life, no visible overshoot (`springyFast`).
  public static let makeRoom = SpringPreset.springyFast.parameters
  /// Rows closing the gap when the drag leaves or is cancelled (`firm`).
  public static let snapBack = SpringPreset.firm.parameters
  /// The indicator's fade, in seconds: it is feedback, not travel.
  public static let indicatorFade: Double = 0.12

  /// The offset (points, downward) of each displayed row for a gap before `gapBeforeRow`. Empty under Reduce
  /// Motion: the rows stay where they are.
  public static func gapOffsets(rowCount: Int, gapBeforeRow: Int, gap: CGFloat, reduceMotion: Bool) -> [Int: Double] {
    guard !reduceMotion, gapBeforeRow < rowCount else { return [:] }
    var offsets: [Int: Double] = [:]
    for row in max(gapBeforeRow, 0)..<rowCount { offsets[row] = Double(gap) }
    return offsets
  }
}

/// One interruptible spring per key on a clock passed in: a key retargeted mid-flight continues from its current
/// value and velocity. Keys not named in a retarget head back to 0.
///
/// A run settles when the solution's decaying envelopes fall under `SpringRun`'s thresholds (a quarter point, two
/// points a second), checked when sampled. That makes a retarget O(1) per key: `SpringRun` scans for its settling
/// time up front, about a millisecond per run in a Debug build, and a page of rows retargets at once.
///
/// Overlap: #109 adds `Motion.SpringField`, the same primitive for folder motion; once both are on main this
/// collapses onto it.
public struct DropGapSprings<Key: Hashable & Sendable>: Sendable {
  private struct Run: Sendable {
    var solver: SpringSolver
    var to: Double
    var start: Double

    func isDone(at t: Double) -> Bool {
      let elapsed = max(t - start, 0)
      return solver.envelope(at: elapsed) < SpringRun.defaultThreshold
        && solver.velocityEnvelope(at: elapsed) < SpringRun.velocityThreshold
    }

    func value(at t: Double) -> Double {
      isDone(at: t) ? to : to + solver.displacement(at: max(t - start, 0))
    }

    func velocity(at t: Double) -> Double {
      isDone(at: t) ? 0 : solver.velocity(at: max(t - start, 0))
    }
  }

  private var runs: [Key: Run] = [:]

  public init() {}

  public var keys: Set<Key> { Set(runs.keys) }

  /// Sends every key in `targets` to its value and every other key with a run back to 0, from time `t`.
  public mutating func retarget(_ targets: [Key: Double], at t: Double, parameters: SpringParameters) {
    for key in Set(runs.keys).union(targets.keys) {
      let goal = targets[key] ?? 0
      if let run = runs[key], run.to == goal { continue }      // already heading there: keep its run
      let value = runs[key]?.value(at: t) ?? 0
      let velocity = runs[key]?.velocity(at: t) ?? 0
      runs[key] = Run(solver: SpringSolver(parameters: parameters, displacement: value - goal, velocity: velocity),
                      to: goal, start: t)
    }
  }

  /// Puts `key` at rest on `value` at time `t`, without travel.
  public mutating func place(_ key: Key, at value: Double, time t: Double) {
    runs[key] = Run(solver: SpringSolver(parameters: SidebarDropMotion.makeRoom, displacement: 0, velocity: 0),
                    to: value, start: t)
  }

  /// Sets every key to 0 at once.
  public mutating func jumpToRest() { runs = [:] }

  public func offset(of key: Key, at t: Double) -> Double { runs[key]?.value(at: t) ?? 0 }

  public func velocity(of key: Key, at t: Double) -> Double { runs[key]?.velocity(at: t) ?? 0 }

  public func isSettled(at t: Double) -> Bool { runs.values.allSatisfy { $0.isDone(at: t) } }

  /// Drops keys that rest at 0, so a long drag does not keep a run per row it ever passed.
  public mutating func prune(at t: Double) {
    runs = runs.filter { !($0.value.isDone(at: t) && $0.value.to == 0) }
  }
}
