import Foundation

/// The time on a recent tab's row: "Now", "12 min", "3 h", "Yesterday", "3 d".
public enum CommandBarRelativeTime {
  public static func text(from date: Date, to now: Date, calendar: Calendar = .current) -> String {
    let seconds = now.timeIntervalSince(date)
    guard seconds >= 60 else { return "Now" }
    if seconds < 3600 { return "\(Int(seconds / 60)) min" }
    let startOfToday = calendar.startOfDay(for: now)
    if date >= startOfToday { return "\(Int(seconds / 3600)) h" }
    if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) { return "Yesterday" }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 0
    return "\(max(days, 2)) d"
  }
}
