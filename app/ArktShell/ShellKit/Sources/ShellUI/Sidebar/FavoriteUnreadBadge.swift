import Foundation

/// A title-count contract for known Favorite hosts. Site title formats need runtime verification.
enum FavoriteUnreadBadge {
  static func text(url: URL, pageTitle: String, twitterBadgeEnabled: Bool, whatsAppBadgeEnabled: Bool) -> String? {
    guard let host = url.host?.lowercased() else { return nil }
    switch host {
    case "x.com", "twitter.com":
      guard twitterBadgeEnabled else { return nil }
    case "web.whatsapp.com":
      guard whatsAppBadgeEnabled else { return nil }
    case "app.slack.com", "calendar.google.com", "mail.google.com":
      break
    default:
      return nil
    }

    guard pageTitle.first == "(", let end = pageTitle.firstIndex(of: ")") else { return nil }
    let digits = pageTitle[pageTitle.index(after: pageTitle.startIndex)..<end]
    guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }),
          let count = Int(digits), count > 0 else { return nil }
    return count > 99 ? "99+" : String(count)
  }
}
