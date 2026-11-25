import Foundation
import Testing
@testable import ShellUI

/// The time on a history row (design/command-bar/README.md): "12 min", "1 h", "Yesterday", a weekday within the last
/// week, then a short date.
struct CommandBarRelativeTimeTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    calendar.locale = Locale(identifier: "en_US")
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

  /// 2026-10-27 is a Tuesday: two to six days back read as the weekday.
  @Test func `days within the last week read as the weekday`() {
    #expect(text(2 * 86_400) == "Sunday")
    #expect(text(3 * 86_400) == "Saturday")
    #expect(text(6 * 86_400) == "Wednesday")
  }

  /// A week or more back reads as a short date; another year adds the year.
  @Test func `older visits read as a short date`() {
    #expect(text(7 * 86_400) == "Oct 20")
    #expect(text(40 * 86_400) == "Sep 17")
    #expect(text(400 * 86_400) == "Sep 22, 2025")
  }

  @Test func `a time in the future reads as now`() {
    #expect(text(-300) == "Now")
  }
}
