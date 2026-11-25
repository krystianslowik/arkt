import AppKit
import EngineAPITestSupport
import XCTest
@_spi(Smoke) @testable import ShellUI

/// The grouped command bar in each state of design/command-bar/README.md ("States"), light and dark, for the pull
/// request: `<state>-<light|dark>.png`, the shell window with the scrim and the bar over it. The same synthetic titles
/// and hosts as the prototype (`design/command-bar/prototype/data.js`). Skipped unless `ARKT_COMMAND_BAR_SHOTS_DIR`
/// names a folder. Each window is captured on its own (`screencapture -l`), never a screen region, and the two are
/// composed here, so nothing else on the screen can appear in a shot.
@MainActor
final class CommandBarScreenshotTests: XCTestCase {
  private var folder: URL?
  private var shell: ShellWindowController?
  private var bar: CommandBarController?

  override func setUp() async throws {
    guard let path = ProcessInfo.processInfo.environment["ARKT_COMMAND_BAR_SHOTS_DIR"], !path.isEmpty else {
      throw XCTSkip("set ARKT_COMMAND_BAR_SHOTS_DIR to write the command bar screenshots")
    }
    folder = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate()
  }

  override func tearDown() async throws {
    bar?.invalidate()
    shell?.close()
    bar = nil
    shell = nil
  }

  // MARK: Data (prototype/data.js)

  private let now = Date()
  private func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-60 * minutes) }

  private func tab(_ title: String, _ url: String, _ minutes: Double) -> CommandBarResults.OpenTab {
    .init(node: UUID(), title: title, url: URL(string: "https://\(url)")!, lastViewed: ago(minutes))
  }

  private func visit(_ title: String, _ url: String, _ hours: Double) -> CommandBarResults.HistoryVisit {
    .init(title: title, url: URL(string: "https://\(url)")!, visited: now.addingTimeInterval(-3600 * hours))
  }

  private lazy var lin = tab("Cycle 42 \u{00B7} Linear", "linear.app/acme/cycle/42", 2)
  private lazy var gh = tab("acme/atlas \u{00B7} Pull requests", "github.com/acme/atlas/pulls", 12)
  private lazy var road = tab("Q4 roadmap", "docs.example.com/q4-roadmap", 60)
  private lazy var git = tab("Git - Branches in a Nutshell",
                             "git-scm.com/book/en/v2/Git-Branching-Branches-in-a-Nutshell", 60)
  private lazy var mail = visit("Inbox (3)", "mail.example.com/u/0", 26)
  private lazy var hbook = visit("Git - Book", "git-scm.com/book/en/v2", 27)
  private lazy var cheat = visit("Git Cheat Sheet", "training.example.com/downloads/git-cheat-sheet.pdf", 80)
  private lazy var hmaps = visit("Trail map \u{00B7} Lake District", "maps.example.com/trails/lake-district", 100)

  private static let longTitle = "A very long page title that keeps going well past the width of any sensible results "
    + "list: Part 2 of 14, notes on layout, measurement and the cost of reflow in large documents \u{00B7} "
    + "The Engineering Blog"
  private static let longURL = "www.example-engineering-blog.com/2026/11/24/a-very-long-path/with/many/segments/"
    + "and-a-query?utm_source=newsletter&utm_medium=email&utm_campaign=autumn-digest&ref=sidebar#section-reflow-cost"

  private struct State {
    var query = ""
    var tabs: [CommandBarResults.OpenTab] = []
    var folders: [CommandBarResults.Folder] = []
    var history: [CommandBarResults.HistoryVisit] = []
    var extensions: [CommandBarResults.Extension] = []
    var suggestions: [String] = []
    var clipboard: URL?
  }

  private func state(_ name: String) -> State {
    switch name {
    case "empty":
      return State(tabs: [lin, gh, road], history: [mail, hmaps, hbook],
                   clipboard: URL(string: "https://example.com/notes/2026/launch-checklist"))
    case "search":
      return State(query: "git", tabs: [git, gh], folders: [.init(node: UUID(), title: "Git reading list", tabCount: 6)],
                   history: [hbook, cheat],
                   extensions: [.init(id: "pilot", name: "Git Pilot", description: "Pull request shortcuts in your toolbar")],
                   suggestions: ["git rebase onto", "git stash pop"])
    case "url":
      return State(query: "git-scm.com/book", tabs: [git], history: [hbook])
    case "worst", "small-window":
      return State(
        query: "layout",
        tabs: [tab(Self.longTitle, Self.longURL, 4), tab("Layout", "docs.example.com/layout", 60),
               tab("\u{30EC}\u{30A4}\u{30A2}\u{30A6}\u{30C8}\u{30A8}\u{30F3}\u{30B8}\u{30F3}\u{306E}\u{8A2D}\u{8A08}"
                   + "\u{3068}\u{5B9F}\u{88C5} \u{2013} layout \u{7B2C}3\u{7AE0}", "layout.example.jp/book/3", 180),
               tab("Auto Layout Guide: Anatomy of a Constraint, Priorities and Content Hugging",
                   "developer.example.com/library/archive/documentation/UserExperience", 300)],
        folders: [.init(node: UUID(), title: "Layout and typography research, collected for the redesign of the long "
                        + "reading view", tabCount: 128),
                  .init(node: UUID(), title: "Layout", tabCount: 9),
                  .init(node: UUID(), title: "\u{30EC}\u{30A4}\u{30A2}\u{30A6}\u{30C8}\u{8CC7}\u{6599} layout",
                        tabCount: 14)],
        history: [visit("CSS Grid layout: a complete guide with live examples and 40 patterns",
                        "css-tricks.example.com/snippets/css/complete-guide-grid", 26),
                  visit(Self.longTitle.replacingOccurrences(of: "Part 2", with: "Part 3"),
                        Self.longURL.replacingOccurrences(of: "autumn", with: "winter"), 27),
                  visit("Layout shift: why it happens and how to stop it", "web.example.dev/articles/cls", 80)],
        extensions: [.init(id: "inspector", name: "Layout Inspector Pro with Grid, Flexbox and Baseline Overlays",
                           description: "Draws grid and flexbox overlays on any page, measures spacing and exports "
                             + "the result"),
                     .init(id: "notes", name: "Layout Notes", description: "Sticky notes pinned to elements"),
                     .init(id: "tester", name: "Responsive Layout Tester", description: "Resize any page to common widths")],
        suggestions: ["layout engine internals and how browsers compute style, layout and paint for very large "
                      + "documents", "layout thrashing", "layout shift score"])
    default:
      return State(query: "zqxv wplk")
    }
  }

  // MARK: Rendering

  func testRenderEveryStateInLightAndDark() async throws {
    for flavor in [ThemeFlavor.light, .dark] {
      for name in ["empty", "search", "url", "worst", "no-results", "small-window"] {
        try await render(name, flavor)
      }
    }
  }

  private func render(_ name: String, _ flavor: ThemeFlavor) async throws {
    let data = state(name)
    let shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    self.shell = shell
    let window = try XCTUnwrap(shell.window)
    window.appearance = NSAppearance(named: flavor == .dark ? .darkAqua : .aqua)
    let size = name == "small-window" ? NSSize(width: 640, height: 420) : NSSize(width: 1280, height: 800)
    window.setFrame(NSRect(origin: NSPoint(x: 80, y: 80), size: size), display: true)
    shell.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    let bar = CommandBarController(parent: window)
    self.bar = bar
    bar.openTabsProvider = { data.tabs }
    bar.foldersProvider = { data.folders }
    bar.historyProvider = { data.history }
    bar.extensionsProvider = { data.extensions }
    bar.clipboardURLProvider = { data.clipboard }
    let suggestions = data.suggestions
    bar.suggestionsProvider = { _ in suggestions }
    bar.prewarm()
    bar.toggle(.newTab)
    if !data.query.isEmpty { bar.setQueryForTesting(data.query) }
    for _ in 0..<200 where !suggestions.isEmpty && !bar.results.contains(where: { $0.kind.name == "suggestion" }) {
      await Task.yield()
    }
    bar.barView.field.currentEditor()?.selectedRange = NSRange(location: data.query.utf16.count, length: 0)
    bar.panel.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(500))      // a picture, not an assertion: let the window server draw
    try compose(parent: window, panel: bar.panel, name: "\(name)-\(flavor == .dark ? "dark" : "light")")
    bar.invalidate()
    shell.close()
    self.bar = nil
    self.shell = nil
  }

  /// The parent window (with the scrim) and the panel, each captured alone, the panel drawn over the parent where it
  /// sits on screen.
  private func compose(parent: NSWindow, panel: NSWindow, name: String) throws {
    let folder = try XCTUnwrap(folder)
    let parentImage = try capture(parent, to: folder.appendingPathComponent("\(name)-parent.png"))
    let panelImage = try capture(panel, to: folder.appendingPathComponent("\(name)-panel.png"))
    let scale = parent.backingScaleFactor
    let pixels = NSSize(width: parent.frame.width * scale, height: parent.frame.height * scale)
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width),
                                             pixelsHigh: Int(pixels.height), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    parentImage.draw(in: NSRect(origin: .zero, size: pixels))
    let offset = NSPoint(x: (panel.frame.minX - parent.frame.minX) * scale,
                         y: (panel.frame.minY - parent.frame.minY) * scale)
    panelImage.draw(in: NSRect(origin: offset, size: NSSize(width: panel.frame.width * scale,
                                                            height: panel.frame.height * scale)))
    NSGraphicsContext.restoreGraphicsState()
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try data.write(to: folder.appendingPathComponent("\(name).png"))
  }

  private func capture(_ window: NSWindow, to file: URL) throws -> NSImage {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let data = try Data(contentsOf: file)
    try FileManager.default.removeItem(at: file)
    return try XCTUnwrap(NSImage(data: data))
  }
}
