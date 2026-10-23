import CoreBridge
import Foundation
import ShellUI
import SidebarModel
import Testing

/// Behavior specific to the adapter over the real `SidebarModel.Sidebar`.
@MainActor
struct ModelSidebarSourceTests {
  private static let url = URL(string: "https://a.example")!

  /// A source plus every change and every `onDidChange` value it reports.
  @MainActor
  private final class Recorder {
    let source: ModelSidebarSource
    var changes: [SidebarChange] = []
    var saved: [SidebarModel.Sidebar] = []
    private var observation: SidebarObservation?

    init(_ source: ModelSidebarSource = ModelSidebarSource()) {
      self.source = source
      observation = source.observe { [unowned self] in self.changes.append($0) }
      source.onDidChange = { [unowned self] in self.saved.append($0) }
    }

    func reset() { changes = []; saved = [] }
  }

  @Test func addTabIntoUnknownSpaceThrowsAndReportsNothing() {
    let recorder = Recorder()
    let unknown = UUID()
    #expect(throws: SidebarError.invalidDestination(.today(unknown))) {
      try recorder.source.addTab(url: Self.url, title: "A", in: .today(unknown))
    }
    #expect(recorder.changes.isEmpty)
    #expect(recorder.saved.isEmpty)
    #expect(recorder.source.sidebar == SidebarModel.Sidebar())
  }

  @Test func nestingPastTheLimitThrowsAndLeavesTheSidebarUnchanged() throws {
    let recorder = Recorder()
    let space = try recorder.source.addSpace(title: "S")
    var location = SidebarModel.Location.pinned(space)
    for _ in 0..<SidebarModel.Sidebar.maximumNestingDepth {  // fills depths 1...max
      let folder = try recorder.source.mutate { try $0.addFolder(title: "F", in: location) }
      location = .folder(folder)
    }
    let before = recorder.source.sidebar
    recorder.reset()
    #expect {
      try recorder.source.mutate { try $0.addFolder(title: "Too deep", in: location) }
    } throws: { error in
      if case SidebarError.nestingTooDeep? = error as? SidebarError { true } else { false }
    }
    #expect(recorder.source.sidebar == before)
    #expect(recorder.changes.isEmpty)
    #expect(recorder.saved.isEmpty)
  }

  @Test func everySuccessfulMutationReportsTheNewValueOnce() throws {
    let recorder = Recorder()
    let space = try recorder.source.addSpace(title: "S")
    #expect(recorder.saved == [recorder.source.sidebar])
    let tab = try recorder.source.addTab(url: Self.url, title: "A", in: .today(space))
    #expect(recorder.saved.count == 2)
    #expect(recorder.saved.last == recorder.source.sidebar)
    recorder.reset()
    recorder.source.updateTab(tab, url: Self.url, title: "A")
    #expect(recorder.saved.isEmpty)
    #expect(recorder.changes.isEmpty)
  }

  @Test func addTabStampsLastActiveAtWithCreation() throws {
    let stamp = Date(timeIntervalSinceReferenceDate: 1_000)
    let source = ModelSidebarSource(now: { stamp })
    let space = try source.addSpace(title: "S")
    let tab = try source.addTab(url: Self.url, title: "A", in: .today(space))
    let node = try #require(source.sidebar.nodes[tab])
    #expect(node.createdAt == stamp)
    guard case .tab(let item) = node.kind else { Issue.record("not a tab"); return }
    #expect(item.lastActiveAt == stamp)
  }

  @Test func markInactiveStampsWithoutRedrawing() throws {
    let recorder = Recorder()
    let space = try recorder.source.addSpace(title: "S")
    let tab = try recorder.source.addTab(url: Self.url, title: "A", in: .today(space))
    let folder = try recorder.source.mutate { try $0.addFolder(title: "F", in: .pinned(space)) }
    recorder.reset()
    let stamp = Date(timeIntervalSinceReferenceDate: 5_000)
    recorder.source.markInactive([tab, folder, UUID()], at: stamp)
    guard case .tab(let item)? = recorder.source.sidebar.nodes[tab]?.kind else {
      Issue.record("not a tab"); return
    }
    #expect(item.lastActiveAt == stamp)
    #expect(recorder.saved.count == 1)
    #expect(recorder.changes.isEmpty)
  }

  @Test func favoritesAreScopedByProfile() throws {
    let source = ModelSidebarSource()
    let work = try source.addTab(url: Self.url, title: "W", in: .favorites(profile: "work"))
    let home = try source.addTab(url: Self.url, title: "D", in: .favorites(profile: "default"))
    #expect(source.children(of: .favorites(profile: "default")) == [home])
    #expect(source.children(of: .favorites(profile: "work")) == [work])
    #expect(source.parent(of: work) == .favorites(profile: "work"))
  }

  @Test func splitMapsToSplitAndPanesToTabs() throws {
    let source = ModelSidebarSource()
    let space = try source.addSpace(title: "S")
    let split = try source.mutate {
      try $0.addSplit(orientation: .horizontal, widthFactors: [0.5, 0.5], in: .today(space))
    }
    let left = try source.addTab(url: Self.url, title: "L", in: .split(split))
    let right = try source.addTab(url: Self.url, title: "R", in: .split(split))
    #expect(source.node(split) == .split(id: split))
    #expect(source.node(left) == .tab(id: left, url: Self.url, title: "L"))
    #expect(source.children(of: .split(split)) == [left, right])
    #expect(source.parent(of: right) == .split(split))
    #expect(source.firstTab(at: split) == left)
  }

  @Test func folderMapsToFolder() throws {
    let source = ModelSidebarSource()
    let space = try source.addSpace(title: "S")
    let folder = try source.mutate { try $0.addFolder(title: "F", in: .pinned(space)) }
    #expect(source.node(folder) == .folder(id: folder, title: "F"))
    #expect(source.node(UUID()) == nil)
    #expect(source.parent(of: UUID()) == nil)
  }

  @Test func spaceMapsTitleProfileAndTheme() throws {
    let colors = [
      SidebarModel.RGBA(red: 1.2, green: 0.5, blue: -0.1, alpha: 1),
      SidebarModel.RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.5),
    ]
    let overlay = [SidebarModel.RGBA(red: 0, green: 0, blue: 0, alpha: 0.2)]
    var sidebar = SidebarModel.Sidebar()
    let themed = sidebar.addSpace(
      title: "Work", profile: "work",
      theme: SpaceTheme(baseColors: colors, overlayColors: overlay, texture: "grain", isDark: true))
    let source = ModelSidebarSource(sidebar: sidebar)
    let info = try #require(source.space(themed))
    #expect(info.id == themed)
    #expect(info.title == "Work")
    #expect(info.profile == "work")
    #expect(info.theme.isDark)
    #expect(info.theme.texture == "grain")
    #expect(info.theme.baseColors == [
      ShellUI.RGBA(red: 1.2, green: 0.5, blue: -0.1, alpha: 1, space: .sRGB),
      ShellUI.RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.5, space: .sRGB),
    ])
    #expect(info.theme.overlayColors == [ShellUI.RGBA(red: 0, green: 0, blue: 0, alpha: 0.2, space: .sRGB)])
    #expect(source.space(UUID()) == nil)
  }

  @Test func missingOrEmptyThemeMapsToTheBridgeDefault() throws {
    var sidebar = SidebarModel.Sidebar()
    let plain = sidebar.addSpace(title: "Plain")
    let empty = sidebar.addSpace(title: "Empty", theme: SpaceTheme(baseColors: [], isDark: true))
    let source = ModelSidebarSource(sidebar: sidebar)
    #expect(source.space(plain)?.theme == .bridgeDefault)
    #expect(source.space(empty)?.theme == .bridgeDefault)
  }

  @Test func tabTitlePrefersTheCustomTitle() throws {
    let source = ModelSidebarSource()
    let space = try source.addSpace(title: "S")
    let renamed = try source.mutate {
      try $0.addTab(url: Self.url, title: "Page", customTitle: "Mine", in: .today(space))
    }
    let plain = try source.addTab(url: Self.url, title: "Page", in: .today(space))
    #expect(source.node(renamed) == .tab(id: renamed, url: Self.url, title: "Mine"))
    #expect(source.node(plain) == .tab(id: plain, url: Self.url, title: "Page"))
  }
}
