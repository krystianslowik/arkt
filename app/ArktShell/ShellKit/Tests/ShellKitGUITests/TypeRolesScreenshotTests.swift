import AppKit
import EngineAPI
import EngineAPITestSupport
import XCTest
@_spi(Smoke) @testable import ShellUI

/// Light and dark 2x screenshots of the surfaces with the most text (#621): the Settings window on its General and
/// Shortcuts panes, the command bar with results and a preview, and the Archive window with filter chips and its
/// banner. Rendered at both sides of a type change and compared pixel by pixel to show the change moved nothing.
/// Skipped unless `ARKT_TYPE_SHOTS_DIR` names a folder; writes `type-<surface>-<light|dark>.png` there. Stub settings
/// in a private defaults suite, an in-memory engine and stub Archive rows; no page loads, no clipboard.
@MainActor
final class TypeRolesScreenshotTests: XCTestCase {
  private var folder: URL?
  private var suiteName = ""

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_TYPE_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_TYPE_SHOTS_DIR to write the type role screenshots")
    }
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    folder = url
    suiteName = "dev.arkt.tests.typeShots.\(UUID().uuidString)"
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  override func tearDown() async throws {
    if !suiteName.isEmpty { UserDefaults().removePersistentDomain(forName: suiteName) }
  }

  func testSettingsShots() throws {
    for flavor in [ThemeFlavor.light, .dark] {
      for pane in [SettingsPane.general, .shortcuts] { try settingsShot(pane, flavor) }
    }
  }

  func testCommandBarShots() throws {
    for flavor in [ThemeFlavor.light, .dark] { try commandBarShot(flavor) }
  }

  func testArchiveShots() async throws {
    for flavor in [ThemeFlavor.light, .dark] { try await archiveShot(flavor) }
  }

  // MARK: - Surfaces

  private func settingsShot(_ pane: SettingsPane, _ flavor: ThemeFlavor) throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    var services = SettingsServices()
    let shortcuts = MainMenu.make(commands: AppCommands()).menu
    services.shortcutsMenu = { shortcuts }
    let controller = SettingsWindowController(settings: AppSettings(defaults: defaults), services: services)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.appearance = appearance(flavor)
    controller.show(pane: pane)
    controller.select(pane, animated: false)
    try write(window, name: "settings-\(pane.rawValue)", flavor)
  }

  private func commandBarShot(_ flavor: ThemeFlavor) throws {
    let shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    let window = try XCTUnwrap(shell.window)
    window.appearance = appearance(flavor)
    shell.showWindow(nil)
    window.setFrame(NSRect(x: 0, y: 0, width: 1280, height: 800), display: true)
    let bar = CommandBarController(parent: window)
    defer {
      bar.invalidate()
      shell.close()
    }
    var clock = 100.0
    bar.settings.dismissSearchSuggestionNotice()
    bar.dismissFinisher = { $0() }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.barView.widthMotion.drivesFramesItself = false
    bar.barView.widthMotion.now = { clock }
    bar.barView.widthMotion.reduceMotion = { true }
    bar.panel.appearance = appearance(flavor)
    bar.prewarm()
    let viewed = Date(timeIntervalSinceNow: -12 * 60)
    bar.openTabsProvider = {
      ["Pull requests", "Release notes", "Example docs"].map { title in
        .init(node: UUID(), title: title,
              url: URL(string: "https://example.test/\(title.replacingOccurrences(of: " ", with: "-"))")!,
              lastViewed: viewed, spaceTitle: "Work")
      }
    }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    clock += 2
    bar.barView.widthMotion.presentFrame()
    XCTAssertFalse(bar.barView.previewColumn.isHidden, "the shot shows the preview column")
    try write(bar.panel, name: "command-bar", flavor)
  }

  private func archiveShot(_ flavor: ThemeFlavor) async throws {
    let source = ArchiveShotSource()
    let controller = ArchiveWindowController(dataSource: source)
    controller.searchDebounce = .zero
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    window.appearance = appearance(flavor)
    controller.show()
    await controller.pendingLoad?.value
    controller.setSpaceFilter(.space(source.work))
    await controller.pendingLoad?.value
    controller.setCloseTypeFilter(.closed)
    await controller.pendingLoad?.value
    XCTAssertFalse(controller.chipStrip.isHidden, "the shot shows the filter chips")
    try write(window, name: "archive", flavor)
  }

  // MARK: - Rendering

  private func appearance(_ flavor: ThemeFlavor) -> NSAppearance? {
    NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
  }

  private func write(_ window: NSWindow, name: String, _ flavor: ThemeFlavor) throws {
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    var root = try XCTUnwrap(window.contentView?.layer)
    while let up = root.superlayer { root = up }
    let folder = try XCTUnwrap(folder)
    let data = try render(root, size: root.bounds.size)
    try data.write(to: folder.appendingPathComponent("type-\(name)-\(flavor == .dark ? "dark" : "light").png"))
  }

  /// `layer`'s tree drawn by Core Animation at 2x.
  private func render(_ layer: CALayer, size: CGSize) throws -> Data {
    let scale: CGFloat = 2
    let width = Int(size.width * scale), height = Int(size.height * scale)
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
    context.cgContext.scaleBy(x: scale, y: scale)
    layer.render(in: context.cgContext)
    return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }
}

/// Archived rows with a matched folder, two Spaces and the education banner, for the type shots.
@MainActor
private final class ArchiveShotSource: ArchiveListDataSource {
  var onChange: (@MainActor () -> Void)?
  var canRestore = true
  let work = UUID()
  var spaceOptions: [ArchiveSpaceOption] {
    [ArchiveSpaceOption(id: work, title: "Work", color: RGBA.srgb(hex: 0x3B82F6))]
  }

  private var page: ArchiveListPage {
    let link = URL(string: "https://a.example")
    let rows = [
      ArchiveRow(id: UUID(), title: "Quarterly planning notes", detail: "a.example - Work - 1 hour ago",
                 reason: "Closed", kind: .tab(link), place: .space(color: nil), time: "1h"),
      ArchiveRow(id: UUID(), title: "Release checklist", detail: "a.example - Work - 3 hours ago", reason: "Closed",
                 kind: .tab(link), place: .space(color: nil), time: "3h",
                 matchedChildren: [ArchiveChildRow(id: UUID(), title: "Example changelog", url: link)]),
      ArchiveRow(id: UUID(), title: "Design review", detail: "a.example - Work - yesterday", reason: "Closed",
                 kind: .tab(link), place: .space(color: nil), time: "1d"),
    ]
    return ArchiveListPage(rows: rows, unreadable: 0, mayHaveMore: false, total: 42, matching: rows.count)
  }

  func loadPage() async -> ArchiveListPage { page }
  func loadMore() async -> ArchiveListPage { page }
  func refresh() async -> ArchiveListPage { page }
  func restore(_ id: UUID) -> Bool { false }
  func educationBanner() async -> ArchiveBanner? {
    ArchiveBanner(headline: "Tabs archive themselves", detail: "Unpinned tabs move here after 12 hours.")
  }
}
