import Foundation
import Synchronization
@testable import CrashReporting

/// Synthetic values only: every forbidden field the stripping rules name, seeded with a marker no real report holds.
enum CrashFixtures {
  static let home = "/Users/seedname"
  static let userName = "seedname"
  static let url = "https://secret.example.com/path?token=abc123"
  static let title = "Quarterly Taxes Spreadsheet"
  static let profileName = "Seed Profile"
  static let spaceName = "Seed Space"
  static let extensionID = "abcdefghijklmnopabcdefghijklmnop"
  static let homePath = "\(home)/Documents/Taxes 2025/return.pdf"
  static let otherPath = "/Volumes/Private Disk/secrets/plan.txt"

  /// Everything that must not survive stripping.
  static var forbidden: [String] {
    [url, "secret.example.com", "abc123", title, profileName, spaceName, extensionID, userName,
     "Taxes", "return.pdf", "Documents", "Private Disk", "secrets", "plan.txt"]
  }

  static let stripper = CrashReportStripper(homeDirectory: home, userName: userName,
                                            redacting: [title, profileName, spaceName])

  static func raw(source: RawCrash.Source = .metricKit, frames: [RawFrame]? = nil, isAbort: Bool = false,
                  at date: Date = Date(timeIntervalSince1970: 2_000_000_000)) -> RawCrash {
    RawCrash(
      source: source, occurredAt: date, osVersion: "15.1 (24B83)", architecture: "arm64", appVersion: "0.1.0",
      appBuild: "7", engineVersion: "142.0.7444.0", exceptionType: "EXC_BAD_ACCESS (SIGSEGV)", isAbort: isAbort,
      exceptionReason: "Could not load \(url) for \(title) in \(profileName) / \(spaceName) at \(homePath)",
      frames: frames ?? [
        RawFrame(image: "\(home)/Library/Developer/Xcode/DerivedData/Arkt/Build/Products/Debug/ArktShell",
                 offset: 4096, symbol: "-[Sidebar open:] \(url)"),
        RawFrame(image: "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit", offset: 128,
                 symbol: "load \(homePath) \(otherPath) \(extensionID) chrome-extension://\(extensionID)/page.html"),
        RawFrame(image: "libsystem_kernel.dylib", offset: 8, symbol: "\(title) \(spaceName) \(profileName) \(userName)"),
      ],
      annotations: ["tabTitle": title, "profile": profileName, "space": spaceName, "url": url,
                    "extensionID": extensionID, "user": userName, "path": homePath])
  }

  /// A store in a fresh folder under the temporary directory, with an injectable clock.
  final class Clock: Sendable {
    private let current: Mutex<Date>
    init(_ date: Date) { current = Mutex(date) }
    var now: Date { current.withLock { $0 } }
    func advance(days: Double) { current.withLock { $0 = $0.addingTimeInterval(days * 86_400) } }
  }

  static func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("crashreports-\(UUID().uuidString)", isDirectory: true)
  }
}
