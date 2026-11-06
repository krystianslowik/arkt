import Foundation
import Testing
@testable import ShellUI

/// Every place that writes a host shows it as the address bar does (`HostDisplay`, #697, #732): a real
/// internationalized host in Unicode, a look-alike in its encoded `xn--` form.
@MainActor
struct CheckedHostSurfacesTests {
  /// "münchen.de": Latin with a diacritic, shown in Unicode.
  static let real = "xn--mnchen-3ya.de"
  static let realShown = "m\u{00FC}nchen.de"
  /// "аррӏе.com": every letter Cyrillic, a whole-script look-alike of "apple.com" under .com; stays encoded.
  static let lookalike = "xn--80ak6aa92e.com"

  private static func url(_ string: String) -> URL { URL(string: string)! }

  // MARK: HostDisplay

  @Test func hostOrAddressChecksTheHostAndKeepsAnAddressWithoutOne() {
    #expect(HostDisplay.hostOrAddress(Self.url("https://\(Self.real)/a")) == Self.realShown)
    #expect(HostDisplay.hostOrAddress(Self.url("https://\(Self.lookalike)/a")) == Self.lookalike)
    #expect(HostDisplay.hostOrAddress(Self.url("https://www.example.org/a")) == "www.example.org")
    #expect(HostDisplay.hostOrAddress(Self.url("about:blank")) == "about:blank")
  }

  /// The checked text is kept per host string, so a list of many rows decodes each host once; a cached answer is
  /// the same as a fresh one.
  @Test func aRepeatedHostGivesTheSameAnswer() {
    for _ in 0..<3 {
      #expect(HostDisplay.text(forHost: Self.real) == Self.realShown)
      #expect(HostDisplay.text(forHost: Self.lookalike) == Self.lookalike)
    }
  }

  // MARK: Status pill

  @Test func statusPillShowsARealHostInUnicodeAndALookalikeEncoded() {
    let real = StatusPillText(Self.url("https://\(Self.real)/login?x=1"))
    #expect(real == StatusPillText(prefix: "", host: Self.realShown, rest: "/login?x=1"))
    let fake = StatusPillText(Self.url("http://user@\(Self.lookalike):8080/login"))
    #expect(fake == StatusPillText(prefix: "http://user@", host: Self.lookalike, rest: ":8080/login"))
  }

  // MARK: Little Arkt

  @Test func littleArktTopBarShowsTheCheckedHost() {
    #expect(LittleArktCopy.host(of: Self.url("https://\(Self.real)/a")) == Self.realShown)
    #expect(LittleArktCopy.host(of: Self.url("https://\(Self.lookalike)/a")) == Self.lookalike)
    #expect(LittleArktCopy.fullAddress(of: Self.url("https://\(Self.real)/a")) == "https://\(Self.realShown)/a")
    #expect(LittleArktCopy.fullAddress(of: Self.url("https://\(Self.lookalike)/a"))
      == "https://\(Self.lookalike)/a")
    #expect(LittleArktCopy.fullAddress(of: nil) == "")
  }

  // MARK: Command bar

  private func tab(_ host: String, title: String = "Page") -> CommandBarResults.OpenTab {
    CommandBarResults.OpenTab(node: UUID(), title: title, url: Self.url("https://\(host)/a"))
  }

  @Test func commandBarTabRowAndPreviewShowTheCheckedHost() throws {
    let rows = CommandBarResults.make(query: "", openTabs: [tab(Self.real), tab(Self.lookalike)])
    #expect(rows.map(\.subtitle) == [Self.realShown, Self.lookalike])
    #expect(rows.map { $0.previewFacts?.host } == [Self.realShown, Self.lookalike])
  }

  @Test func commandBarHistoryRowAndPreviewShowTheCheckedHost() throws {
    var input = CommandBarResults.Input()
    input.history = [
      .init(title: "Stadt", url: Self.url("https://\(Self.real)/rathaus")),
      .init(title: "Stadt", url: Self.url("https://\(Self.lookalike)/rathaus")),
    ]
    let rows = CommandBarResults.make(query: "Stadt", input: input).filter {
      if case .history = $0.kind { true } else { false }
    }
    #expect(rows.map(\.subtitle) == ["\(Self.realShown)/rathaus", "\(Self.lookalike)/rathaus"])
    #expect(rows.map { $0.previewFacts?.host } == [Self.realShown, Self.lookalike])
  }

  @Test func commandBarTypedAndPastedAddressesShowTheCheckedHost() throws {
    let typed = CommandBarResults.make(query: Self.real, input: CommandBarResults.Input())
    #expect(typed.first?.subtitle == "https://\(Self.realShown)")
    let typedFake = CommandBarResults.make(query: Self.lookalike, input: CommandBarResults.Input())
    #expect(typedFake.first?.subtitle == "https://\(Self.lookalike)")

    var input = CommandBarResults.Input()
    input.clipboardURL = Self.url("https://\(Self.real)/x")
    #expect(CommandBarResults.make(query: "", input: input).first?.subtitle == "https://\(Self.realShown)/x")
    input.clipboardURL = Self.url("https://\(Self.lookalike)/x")
    #expect(CommandBarResults.make(query: "", input: input).first?.subtitle == "https://\(Self.lookalike)/x")
  }

  /// A tab or a visit is found by its host typed either way: in Unicode as the bar shows it, or encoded.
  @Test(arguments: ["m\u{00FC}nchen", "xn--mnchen", "munchen"])
  func commandBarMatchesAHostTypedEitherWay(query: String) {
    var input = CommandBarResults.Input()
    input.openTabs = [tab(Self.real, title: "Stadtportal"), tab("example.org", title: "Other")]
    input.history = [.init(title: "Rathaus", url: Self.url("https://\(Self.real)/rathaus"))]
    let rows = CommandBarResults.make(query: query, input: input)
    #expect(rows.contains { $0.title == "Stadtportal" })
    #expect(rows.contains { $0.title == "Rathaus" })
    #expect(!rows.contains { $0.title == "Other" })
  }

  // MARK: Sidebar

  @Test func sidebarLetterTileReadsTheCheckedHost() {
    // "ελληνικά.gr": Greek under .gr, shown in Unicode, so its tile reads its first letter.
    let greek = Self.url("https://www.xn--hxargifdar.gr/")
    #expect(SidebarGlyphs.letterText(title: "Page", url: greek) == "\u{0395}")
    #expect(SidebarGlyphs.letterText(title: "Page", url: Self.url("https://\(Self.lookalike)/")) == "X")
    #expect(SidebarGlyphs.letterText(title: "Page", url: Self.url("https://www.example.org/")) == "E")
    #expect(SidebarGlyphs.letterText(title: "page", url: nil) == "P")
  }

  @Test(arguments: ["m\u{00FC}nchen", "xn--mnchen", "munchen"])
  func folderPreviewMatchesAHostTypedEitherWay(query: String) throws {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = sidebar.addFolder(title: "Folder", in: .pinned(space))
    let city = sidebar.addTab(url: Self.url("https://\(Self.real)/"), title: "Stadt", in: .folder(folder))
    _ = sidebar.addTab(url: Self.url("https://\(Self.lookalike)/"), title: "Fruit", in: .folder(folder))
    var session = FolderPreviewSession(folder: folder, in: sidebar)
    #expect(session.items.map(\.shownHost) == [Self.realShown, Self.lookalike])
    session.query = query
    #expect(session.matches.map(\.node) == [city])
  }

  // MARK: Downloads

  @Test func downloadsHostIsChecked() {
    #expect(DownloadsFormat.host(of: Self.url("https://www.\(Self.real)/f.zip")) == Self.realShown)
    #expect(DownloadsFormat.host(of: Self.url("https://\(Self.lookalike)/f.zip")) == Self.lookalike)
  }
}
