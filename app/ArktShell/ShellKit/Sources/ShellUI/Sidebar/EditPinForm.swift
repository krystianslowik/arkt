import Foundation

/// Which field the Edit Pin popover focuses (#363): Name from a Favorite's Rename..., Pinned URL from Edit Pinned
/// URL...
public enum EditPinFocus: Hashable, Sendable {
  case name
  case url
}

/// What the Edit Pin popover edits: a pinned tab's row or a Favorite's tile.
public enum EditPinKind: Equatable, Sendable {
  case pinnedTab
  case favorite
}

/// The Edit Pin popover's state (design/edit-pin, direction B): the Name and Pinned URL fields, the invalid address
/// line and what Save stores. A value; `EditPinController` shows it and writes the outcome to the sidebar.
struct EditPinForm {
  /// The line under Pinned URL after Save with something that is not a web address.
  static let invalidAddressMessage = "Enter a web address, like example.com"

  /// What Save does: store the changed values (nil for a field left as it was), or show the invalid address line.
  enum Outcome: Equatable {
    /// `name` "" clears the custom title, so the tab shows its page's title again.
    case save(name: String?, url: URL?)
    case invalid
  }

  let kind: EditPinKind
  private let originalName: String
  private let originalURL: URL
  /// The address the tab shows now (its pinned URL when it has no live page), for Use Current Page.
  private let currentPage: URL
  private(set) var name: String
  private(set) var urlText: String
  private(set) var showsInvalidAddress = false
  /// The address `urlText` stands for while it is a prefilled one (the stored URL or Use Current Page's), so an
  /// address the field cannot type back exactly (http, an IP address) is stored as it was.
  private var prefilled: (text: String, url: URL)

  init(kind: EditPinKind, name: String, url: URL, currentPage: URL) {
    self.kind = kind
    originalName = name
    originalURL = url
    self.currentPage = currentPage
    self.name = name
    urlText = Self.text(for: url)
    prefilled = (urlText, url)
  }

  var title: String { kind == .favorite ? "Edit Favorite" : "Edit Pinned Tab" }

  /// The field's text for `url`: an https address without its scheme, as the address bar shows it; any other
  /// address in full. Hosts read exactly as the address bar shows them: an internationalized host stays in its
  /// encoded `xn--` form, so a look-alike host cannot pass for another; typed Unicode is encoded on Save.
  static func text(for url: URL) -> String {
    let full = url.absoluteString
    let prefix = "https://"
    guard url.scheme?.lowercased() == "https", full.lowercased().hasPrefix(prefix) else { return full }
    return String(full.dropFirst(prefix.count))
  }

  mutating func edit(name: String) { self.name = name }

  /// A change to Pinned URL clears the invalid address line.
  mutating func edit(urlText: String) {
    self.urlText = urlText
    showsInvalidAddress = false
  }

  /// Use Current Page: Pinned URL becomes the tab's current address.
  mutating func useCurrentPage() {
    urlText = Self.text(for: currentPage)
    prefilled = (urlText, currentPage)
    showsInvalidAddress = false
  }

  /// Save or Return. Something that is not a web address shows the line and stores nothing.
  mutating func submit() -> Outcome {
    let url: URL
    if urlText == prefilled.text {
      url = prefilled.url
    } else if let parsed = URLInputParser.url(from: urlText) {
      url = parsed
    } else {
      showsInvalidAddress = true
      return .invalid
    }
    // An untouched name stays as it is, even when the page's title has spaces around it: only an edit becomes a
    // custom title, trimmed.
    let newName = name == originalName ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines)
    return .save(name: newName, url: url == originalURL ? nil : url)
  }
}

