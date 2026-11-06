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
  /// "pàypal-login.net": a real Latin host with a diacritic, shown in Unicode; "paypal" must not find it through the
  /// shown host.
  static let accented = "xn--pypal-login-76a.net"
  static let accentedShown = "p\u{00E0}ypal-login.net"

  private static func url(_ string: String) -> URL { URL(string: string)! }

  // MARK: HostDisplay

  @Test func hostOrAddressChecksTheHostAndKeepsAnAddressWithoutOne() {
    #expect(HostDisplay.hostOrAddress(Self.url("https://\(Self.real)/a")) == Self.realShown)
    #expect(HostDisplay.hostOrAddress(Self.url("https://\(Self.lookalike)/a")) == Self.lookalike)
    #expect(HostDisplay.hostOrAddress(Self.url("https://www.example.org/a")) == "www.example.org")
    #expect(HostDisplay.hostOrAddress(Self.url("about:blank")) == "about:blank")
  }

  /// A tab with no page title is saved under its raw host; the title is written by the rule only when shown, so a
  /// title saved before #732 (or under an older rule) reads as today's check says.
  @Test func aSavedHostTitleIsShownByTheRule() {
    let real = Self.url("https://\(Self.real)/a")
    let fake = Self.url("https://\(Self.lookalike)/a")
    #expect(HostDisplay.savedTitle(for: real) == Self.real)
    #expect(HostDisplay.savedTitle(for: fake) == Self.lookalike)
    #expect(HostDisplay.savedTitle(for: Self.url("about:blank")) == "about:blank")
    #expect(HostDisplay.title(Self.real, for: real) == Self.realShown)
    #expect(HostDisplay.title(Self.lookalike, for: fake) == Self.lookalike)
    #expect(HostDisplay.title("Rathaus \(Self.real)", for: real) == "Rathaus \(Self.real)", "a page title stays")
    #expect(HostDisplay.title(Self.real, for: fake) == Self.real, "another host's name stays")
    #expect(HostDisplay.title("www.example.org", for: Self.url("https://www.example.org/")) == "www.example.org")
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

  @Test func commandBarShowsASavedHostTitleCheckedAndTheModelKeepsItRaw() throws {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "S", theme: SpaceThemeInfo(baseColors: [], isDark: false))
    let realURL = Self.url("https://\(Self.real)/a")
    let fakeURL = Self.url("https://\(Self.lookalike)/a")
    let realNode = sidebar.addTab(url: realURL, title: HostDisplay.savedTitle(for: realURL), in: .today(space))
    let fakeNode = sidebar.addTab(url: fakeURL, title: HostDisplay.savedTitle(for: fakeURL), in: .today(space))
    let rows = CommandBarResults.make(query: "", openTabs: CommandBarResults.openTabs(in: sidebar, space: space))
    #expect(rows.map(\.title) == [Self.realShown, Self.lookalike])
    #expect(rows.map { $0.previewFacts?.title } == [Self.realShown, Self.lookalike])
    guard case .tab(_, _, let realTitle)? = sidebar.node(realNode),
          case .tab(_, _, let fakeTitle)? = sidebar.node(fakeNode) else {
      Issue.record("tabs missing")
      return
    }
    #expect(realTitle == Self.real, "the model keeps the raw host")
    #expect(fakeTitle == Self.lookalike)
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

  /// A tab or a visit is found by its host typed either way: in Unicode as the bar shows it (any case), or encoded.
  @Test(arguments: ["m\u{00FC}nchen", "M\u{00DC}NCHEN", "xn--mnchen"])
  func commandBarMatchesAHostTypedEitherWay(query: String) {
    var input = CommandBarResults.Input()
    input.openTabs = [tab(Self.real, title: "Stadtportal"), tab("example.org", title: "Other")]
    input.history = [.init(title: "Rathaus", url: Self.url("https://\(Self.real)/rathaus"))]
    let rows = CommandBarResults.make(query: query, input: input)
    #expect(rows.contains { $0.title == "Stadtportal" })
    #expect(rows.contains { $0.title == "Rathaus" })
    #expect(!rows.contains { $0.title == "Other" })
  }

  /// The shown host is matched without folding diacritics: "paypal" does not find "pàypal-login.net", neither in a
  /// row's host nor in a title saved as that host.
  @Test func commandBarDoesNotFoldDiacriticsOfTheShownHost() {
    #expect(HostDisplay.text(forHost: Self.accented) == Self.accentedShown)
    let url = Self.url("https://\(Self.accented)/")
    var input = CommandBarResults.Input()
    input.openTabs = [.init(node: UUID(), title: HostDisplay.savedTitle(for: url), url: url)]
    input.history = [.init(title: Self.accented, url: url)]
    #expect(!CommandBarResults.make(query: "paypal", input: input).contains {
      if case .switchTo = $0.kind { true } else if case .history = $0.kind { true } else { false }
    })
    let found = CommandBarResults.make(query: "P\u{00C0}YPAL", input: input)
    #expect(found.contains { if case .switchTo = $0.kind { true } else { false } })
    #expect(found.contains { if case .history = $0.kind { true } else { false } })
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

  @Test(arguments: ["m\u{00FC}nchen", "M\u{00DC}NCHEN", "xn--mnchen"])
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

  @Test func folderPreviewDoesNotFoldDiacriticsOfTheShownHostAndShowsASavedHostTitleChecked() throws {
    let sidebar = StubSidebar()
    let space = sidebar.addSpace(title: "Work")
    let folder = sidebar.addFolder(title: "Folder", in: .pinned(space))
    let url = Self.url("https://\(Self.accented)/")
    let fakeURL = Self.url("https://\(Self.lookalike)/")
    _ = sidebar.addTab(url: url, title: HostDisplay.savedTitle(for: url), in: .folder(folder))
    _ = sidebar.addTab(url: fakeURL, title: HostDisplay.savedTitle(for: fakeURL), in: .folder(folder))
    var session = FolderPreviewSession(folder: folder, in: sidebar)
    #expect(session.items.map(\.shownTitle) == [Self.accentedShown, Self.lookalike])
    #expect(session.items.map(\.title) == [Self.accented, Self.lookalike], "searched as saved")
    session.query = "paypal"
    #expect(session.matches.isEmpty)
    session.query = "P\u{00C0}YPAL"
    #expect(session.matches.count == 1)
  }

  /// The rename field opens with the row's text, the checked host; committing it unchanged is not a rename, so no
  /// Unicode host is saved as a custom title.
  @Test func renamingASavedHostTitleUnchangedIsNotARename() {
    let tab = SidebarNodeInfo.tab(id: UUID(), url: Self.url("https://\(Self.real)/"), title: Self.real)
    let original = SidebarOutlineController.renameText(of: tab)
    #expect(original == Self.realShown)
    #expect(!SidebarOutlineController.isRename(typed: Self.realShown, original: original))
    #expect(!SidebarOutlineController.isRename(typed: " \(Self.realShown) ", original: original))
    #expect(SidebarOutlineController.isRename(typed: "Stadt", original: original))
    #expect(!SidebarOutlineController.isRename(typed: nil, original: original), "Esc")
    let fake = SidebarNodeInfo.tab(id: UUID(), url: Self.url("https://\(Self.lookalike)/"), title: Self.lookalike)
    #expect(SidebarOutlineController.renameText(of: fake) == Self.lookalike)
    let folder = SidebarNodeInfo.folder(id: UUID(), title: Self.real)
    #expect(SidebarOutlineController.renameText(of: folder) == Self.real, "a folder's title is its own")
  }

  /// Edit Pin's Name field shows a title saved as the raw host checked; an untouched Save stores no name.
  @Test func editPinShowsASavedHostTitleCheckedAndAnUntouchedSaveWritesNothing() {
    let real = Self.url("https://\(Self.real)/")
    var form = EditPinForm(kind: .pinnedTab, name: Self.real, url: real, currentPage: real)
    #expect(form.name == Self.realShown)
    #expect(form.submit() == .save(name: nil, url: nil))
    let fake = Self.url("https://\(Self.lookalike)/")
    var fakeForm = EditPinForm(kind: .favorite, name: Self.lookalike, url: fake, currentPage: fake)
    #expect(fakeForm.name == Self.lookalike)
    #expect(fakeForm.submit() == .save(name: nil, url: nil))
    var renamed = EditPinForm(kind: .pinnedTab, name: Self.real, url: real, currentPage: real)
    renamed.edit(name: "Stadt")
    #expect(renamed.submit() == .save(name: "Stadt", url: nil))
  }

  // MARK: Downloads

  @Test func downloadsHostIsChecked() {
    #expect(DownloadsFormat.host(of: Self.url("https://www.\(Self.real)/f.zip")) == Self.realShown)
    #expect(DownloadsFormat.host(of: Self.url("https://\(Self.lookalike)/f.zip")) == Self.lookalike)
  }
}
