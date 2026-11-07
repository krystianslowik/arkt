import Foundation

/// MetricKit's crash data as plain values, so the mapping is testable without MetricKit (the app target does the
/// `MXCrashDiagnostic` reading and calls these).
public enum MetricKitMapping {
  /// The most frames read from a call stack tree, far above what a report keeps.
  static let frameBudget = CrashReportStripper.maximumFrames * 4

  private static let machTypes: [Int: String] = [
    1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION", 5: "EXC_SOFTWARE",
    6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL", 8: "EXC_MACH_SYSCALL", 9: "EXC_RPC_ALERT", 10: "EXC_CRASH",
    11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY",
  ]
  private static let signals: [Int: String] = [
    1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE",
    9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE",
  ]

  /// "EXC_BAD_ACCESS (SIGSEGV)": the Mach exception type and the signal, the only thing the report says about why.
  public static func exceptionName(type: Int?, signal: Int?) -> String {
    let name = type.map { machTypes[$0] ?? "EXC_UNKNOWN" } ?? "EXC_UNKNOWN"
    guard let signal else { return name }
    return "\(name) (\(signals[signal] ?? "SIG\(signal)"))"
  }

  /// SIGABRT: where an uncaught Objective-C exception ends.
  public static func isAbort(signal: Int?) -> Bool { signal == 6 }

  /// The crashing thread's frames, top frame first. MetricKit nests each frame's callee in `subFrames`, root first.
  /// Bad JSON gives no frames.
  public static func frames(fromCallStackTree data: Data) -> [RawFrame] {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let stacks = object["callStacks"] as? [[String: Any]] else { return [] }
    let stack = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
    guard var node = (stack?["callStackRootFrames"] as? [[String: Any]])?.first else { return [] }
    var path: [RawFrame] = []
    while path.count < frameBudget {
      path.append(RawFrame(image: node["binaryName"] as? String ?? "unknown",
                           offset: (node["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue,
                           symbol: nil, uuid: node["binaryUUID"] as? String))
      guard let next = (node["subFrames"] as? [[String: Any]])?.first else { break }
      node = next
    }
    return path.reversed()
  }
}
