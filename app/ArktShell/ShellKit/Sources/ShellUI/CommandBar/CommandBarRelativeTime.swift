import Foundation

/// The time on a history row (design/command-bar/README.md, Layout): "Now", "12 min", "3 h" today, "Yesterday", the
/// weekday ("Monday") within the last week, then a short date ("Oct 20"), with the year when it is another year. Words
/// and dates follow `calendar`'s locale.
public enum CommandBarRelativeTime {
  public static func text(from date: Date, to now: Date, calendar: Calendar = .current) -> String {
    let seconds = now.timeIntervalSince(date)
    guard seconds >= 60 else { return "Now" }
    if seconds < 3600 { return "\(Int(seconds / 60)) min" }
    let startOfToday = calendar.startOfDay(for: now)
    if date >= startOfToday { return "\(Int(seconds / 3600)) h" }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 0
    if days <= 1 { return "Yesterday" }
    if days < 7 { return format(date, "EEEE", calendar) }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return format(date, sameYear ? "MMMd" : "yMMMd", calendar)
  }

  private static func format(_ date: Date, _ template: String, _ calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = calendar.locale ?? .current
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }
}
