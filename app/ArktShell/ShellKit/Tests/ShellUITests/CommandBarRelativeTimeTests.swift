import Foundation
import Testing
@testable import ShellUI

/// "12 min", "1 h", "Yesterday": the time on a recent tab's row.
struct CommandBarRelativeTimeTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }
  /// 2026-10-27 15:30:00 UTC.
  private let now = Date(timeIntervalSince1970: 1_793_115_000)

  private func text(_ secondsAgo: TimeInterval) -> String {
    CommandBarRelativeTime.text(from: now.addingTimeInterval(-secondsAgo), to: now, calendar: calendar)
  }

  @Test func `under a minute says now`() {
    #expect(text(0) == "Now")
    #expect(text(59) == "Now")
  }

  @Test func `minutes`() {
    #expect(text(60) == "1 min")
    #expect(text(12 * 60) == "12 min")
    #expect(text(59 * 60) == "59 min")
  }

  @Test func `hours`() {
    #expect(text(3600) == "1 h")
    #expect(text(3 * 3600) == "3 h")
    #expect(text(15 * 3600) == "15 h")
  }

  @Test func `the previous calendar day says Yesterday`() {
    #expect(text(16 * 3600) == "Yesterday", "yesterday 23:30")
    #expect(text(30 * 3600) == "Yesterday")
  }

  @Test func `older days count days`() {
    #expect(text(3 * 86_400) == "3 d")
    #expect(text(40 * 86_400) == "40 d")
  }

  @Test func `a time in the future reads as now`() {
    #expect(text(-300) == "Now")
  }
}
