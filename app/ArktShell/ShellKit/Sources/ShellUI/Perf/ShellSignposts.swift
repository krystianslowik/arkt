import os

/// Instruments-visible intervals (Points of Interest) and perf log lines for the shell.
public enum ShellSignposts {
  public static let subsystem = "dev.arkt.shell"
  public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
  public static let logger = Logger(subsystem: subsystem, category: "perf")
}
