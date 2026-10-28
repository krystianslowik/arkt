import AppKit
import EngineAPI
import XCTest
import EngineAPITestSupport
@_spi(Smoke) @testable import ShellUI

/// The preview column on a live command bar (#372): width spring, column metrics, Reduce Motion, stale
/// thumbnails, Cmd-Return. The spring is stepped on an injected clock. Nothing here waits on a wall clock.
@MainActor
final class CommandBarPreviewWindowTests: XCTestCase {
  var shell: ShellWindowController!
  var bar: CommandBarController!
  var window: NSWindow!
  var announcements: [String] = []
  var clock = 100.0

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    shell = ShellWindowController(engine: InMemoryEngine(), sidebar: StubSidebar.sample())
    window = try XCTUnwrap(shell.window)
    window.setFrame(NSRect(x: 100, y: 100, width: 1280, height: 800), display: true)
    shell.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
    bar = CommandBarController(parent: window)
    bar.settings.dismissSearchSuggestionNotice()
    bar.announce = { [unowned self] in announcements.append($0) }
    bar.dismissFinisher = { $0() }
    bar.barView.selectionMotion.drivesFramesItself = false
    bar.barView.widthMotion.drivesFramesItself = false
    bar.barView.widthMotion.now = { [unowned self] in self.clock }
    bar.barView.widthMotion.reduceMotion = { false }
    bar.prewarm()
    announcements = []
  }

  override func tearDown() async throws {
    bar.invalidate()
    shell.close()
  }

  private func tab(_ title: String, space: String = "Work") -> CommandBarResults.OpenTab {
    .init(node: UUID(), title: title,
          url: URL(string: "https://example.test/\(title.replacingOccurrences(of: " ", with: "-"))")!,
          lastViewed: Date().addingTimeInterval(-12 * 60), spaceTitle: space)
  }

  private func moveDown() {
    let editor = (bar.barView.field.currentEditor() as? NSTextView) ?? NSTextView()
    _ = bar.control(bar.barView.field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
  }

  private func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                               windowNumber: bar.panel.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code))
    bar.panel.sendEvent(event)
  }

  private func settleWidth() {
    clock += 2
    bar.barView.widthMotion.presentFrame()
  }

  /// A small synthetic page image. Not a capture of a real page.
  private func pageImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> PageImage {
    let pixelsWide = 80
    let pixelsHigh = 48
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSRect(x: 8, y: 30, width: 48, height: 6).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    return PageImage(data: data, pixelWidth: pixelsWide, pixelHeight: pixelsHigh, scale: 2, format: .png)
  }

  private func writeBar(_ name: String) throws {
    bar.barView.layoutSubtreeIfNeeded()
    bar.barView.displayIfNeeded()
    let bounds = bar.barView.bounds
    let rep = try XCTUnwrap(bar.barView.bitmapImageRepForCachingDisplay(in: bounds))
    bar.barView.cacheDisplay(in: bounds, to: rep)
    let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: "/tmp/arkt-372-preview", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent(name))
    XCTAssertGreaterThan(data.count, 5_000, name)
  }

  private func previewAnnouncements() -> [String] {
    announcements.filter { $0.hasPrefix("Preview, ") }
  }

  // MARK: Width

  func testAnEmptyQueryStaysNarrow() throws {
    bar.openTabsProvider = { [self.tab("Pull requests")] }
    bar.toggle(.newTab)
    XCTAssertEqual(bar.panel.frame.width, 680, accuracy: 0.5)
    XCTAssertTrue(bar.barView.previewColumn.isHidden)
    XCTAssertTrue(previewAnnouncements().isEmpty)
  }

  func testTheBarWidensOnASpringWithoutMovingTheLeadingEdgeOrLayingOutPerFrame() throws {
    let first = tab("Pull requests")
    let second = tab("Notes")
    bar.openTabsProvider = { [first, second] }
    bar.toggle(.newTab)
    let narrowMinX = bar.panel.frame.minX
    let narrowWidth = bar.panel.frame.width
    XCTAssertEqual(narrowWidth, 680, accuracy: 0.5)
    let scrollMinX = bar.barView.scrollView.frame.minX

    bar.setQueryForTesting("example")
    XCTAssertEqual(bar.panel.frame.width, 968, accuracy: 0.5)
    XCTAssertEqual(bar.panel.frame.minX, narrowMinX, accuracy: 0.5, "the list's leading edge does not move")
    XCTAssertEqual(bar.panel.frame.height, CommandBarGeometry.contentHeight(rowCount: bar.results.count), accuracy: 0.5)
    XCTAssertEqual(bar.barView.scrollView.frame.minX, scrollMinX, accuracy: 0.5)
    XCTAssertEqual(bar.barView.drawnWidth, 680, accuracy: 1, "the mask starts at the narrow width")
    XCTAssertTrue(bar.barView.widthMotion.isRunning)
    XCTAssertTrue(bar.barView.widthMotion.isSignpostOpen)
    XCTAssertEqual(bar.barView.previewColumn.lastTransition, .appear)
    XCTAssertEqual(previewAnnouncements(), ["Preview, \(first.title)"])

    let layouts = bar.barView.layoutCount
    clock += 0.05
    bar.barView.widthMotion.presentFrame()
    XCTAssertEqual(bar.barView.layoutCount, layouts, "a presented frame does not lay out")
    XCTAssertGreaterThan(bar.barView.drawnWidth, 680)
    XCTAssertLessThan(bar.barView.drawnWidth, 968)

    let mid = bar.barView.drawnWidth
    let fades = bar.barView.previewColumn.contentFadeCount
    moveDown()
    XCTAssertEqual(bar.barView.previewColumn.lastTransition, .crossfade)
    XCTAssertEqual(bar.barView.drawnWidth, mid, accuracy: 0.01, "moving between preview rows keeps the width")
    XCTAssertGreaterThan(bar.barView.previewColumn.contentFadeCount, fades)
    XCTAssertEqual(previewAnnouncements().count, 1, "VoiceOver is not told again on a crossfade")
    XCTAssertEqual(bar.panel.frame.width, 968, accuracy: 0.5)
    XCTAssertTrue(bar.barView.widthMotion.isSignpostOpen, "a retarget does not open a second interval")

    moveDown()
    XCTAssertEqual(bar.results[bar.barView.table.selectedRow].rowKind, .searchSuggestion)
    XCTAssertFalse(bar.barView.previewColumn.isHidden, "the column clips away with the spring")
    XCTAssertEqual(bar.barView.drawnWidth, mid, accuracy: 0.01)
    settleWidth()
    XCTAssertFalse(bar.barView.widthMotion.isRunning)
    XCTAssertFalse(bar.barView.widthMotion.isSignpostOpen)
    XCTAssertEqual(bar.panel.frame.width, 680, accuracy: 0.5)
    XCTAssertEqual(bar.panel.frame.minX, narrowMinX, accuracy: 0.5)
    XCTAssertTrue(bar.barView.previewColumn.isHidden)
    XCTAssertLessThanOrEqual(bar.barView.layoutCount, layouts + 2, "one layout when the narrow spring rests")
  }

  func testReduceMotionSnapsTheWidthAndStillFadesTheContent() throws {
    bar.barView.widthMotion.reduceMotion = { true }
    bar.openTabsProvider = { [self.tab("Pull requests"), self.tab("Notes")] }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    XCTAssertFalse(bar.barView.widthMotion.isRunning)
    XCTAssertFalse(bar.barView.widthMotion.isSignpostOpen)
    XCTAssertEqual(bar.panel.frame.width, 968, accuracy: 0.5)
    XCTAssertEqual(bar.barView.drawnWidth, 968, accuracy: 0.5)
    let fades = bar.barView.previewColumn.contentFadeCount
    XCTAssertGreaterThan(fades, 0)
    moveDown()
    XCTAssertGreaterThan(bar.barView.previewColumn.contentFadeCount, fades)
    XCTAssertEqual(bar.panel.frame.width, 968, accuracy: 0.5)
    XCTAssertEqual(bar.barView.previewColumn.lastTransition, .crossfade)
    moveDown()
    XCTAssertEqual(bar.panel.frame.width, 680, accuracy: 0.5)
    XCTAssertTrue(bar.barView.previewColumn.isHidden)
  }

  // MARK: Column

  func testTheColumnMatchesThePreviewMetrics() throws {
    bar.barView.widthMotion.reduceMotion = { true }
    let long = String(repeating: "Pull requests ", count: 12)
    bar.openTabsProvider = {
      [self.tab(long)] + (1...4).map { self.tab("Page \($0)") }
    }
    window.appearance = NSAppearance(named: .darkAqua)
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    bar.barView.layoutSubtreeIfNeeded()
    let column = bar.barView.previewColumn
    XCTAssertEqual(column.frame.width, 300, accuracy: 0.5)
    XCTAssertLessThanOrEqual(column.frame.maxY, bar.barView.bounds.height - CommandBarGeometry.hintStripHeight)
    let well = try XCTUnwrap(column.subviews.flatMap(\.subviews).first { $0.layer?.cornerRadius == 10 })
    XCTAssertEqual(well.frame.height, 116, accuracy: 0.5)
    XCTAssertEqual(well.frame.minY, 12, accuracy: 0.5)
    XCTAssertLessThan(well.frame.maxY, column.splitButton.frame.minY, "the thumbnail sits above the buttons")
    XCTAssertEqual(well.layer?.cornerRadius, 10)
    XCTAssertEqual(column.splitButton.frame.height, 30, accuracy: 0.5)
    XCTAssertEqual(column.primaryButton.frame.height, 30, accuracy: 0.5)
    XCTAssertGreaterThan(column.primaryButton.frame.width, column.splitButton.frame.width)
    XCTAssertEqual(column.primaryButton.layer?.backgroundColor, BrandTokens.accent.resolve(.dark).cgColor)
    let label = try XCTUnwrap(column.primaryButton.subviews.compactMap { $0 as? NSTextField }.first)
    XCTAssertEqual(label.textColor, BrandTokens.onAccent.resolve(.dark).nsColor())
    XCTAssertEqual(label.stringValue, "Switch to Tab")
    XCTAssertEqual(column.splitButton.accessibilityLabel(), "Split View")
    let splitLabel = try XCTUnwrap(column.splitButton.subviews.compactMap { $0 as? NSTextField }.first)
    XCTAssertEqual(splitLabel.stringValue, "Split View")
    XCTAssertGreaterThanOrEqual(splitLabel.frame.width + 0.5, splitLabel.fittingSize.width)
    XCTAssertEqual(column.accessibilityLabel(), "Preview, \(long)")
    XCTAssertFalse(column.splitButton.acceptsFirstResponder)
    XCTAssertFalse(column.primaryButton.acceptsFirstResponder)
    let title = try XCTUnwrap(column.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }
      .first { $0.stringValue == long })
    XCTAssertEqual(title.maximumNumberOfLines, 1)
    XCTAssertLessThanOrEqual(title.frame.maxX, column.bounds.width - 12 + 0.5)
    XCTAssertEqual(bar.barView.escapeKey.frame.height, 18, accuracy: 0.5)
    let cap = try XCTUnwrap(column.primaryButton.subviews.compactMap { $0 as? CommandBarKeyCapView }.first)
    XCTAssertEqual(cap.frame.height, 16, accuracy: 0.5)
    let dot = column.subviews.flatMap(\.subviews).first { abs($0.frame.width - 6) < 0.5 && abs($0.frame.height - 6) < 0.5 }
    XCTAssertEqual(dot?.isHidden, false)
  }

  func testAStaleThumbnailIsDroppedWhenTheSelectionMoves() async throws {
    let first = tab("Pull requests")
    let second = tab("Notes")
    bar.openTabsProvider = { [first, second] }
    bar.barView.widthMotion.reduceMotion = { true }
    let imageA = try pageImage(red: 0.85, green: 0.25, blue: 0.2)
    let imageB = try pageImage(red: 0.2, green: 0.45, blue: 0.75)
    final class Box {
      var first: CheckedContinuation<PageImage?, Never>?
      var second: CheckedContinuation<PageImage?, Never>?
    }
    let box = Box()
    bar.thumbnailForPreview = { thumbnail in
      let isFirst: Bool
      if case .liveTab(let node) = thumbnail { isFirst = node == first.node } else { isFirst = false }
      return await withCheckedContinuation { continuation in
        MainActor.assumeIsolated {
          if isFirst { box.first = continuation } else { box.second = continuation }
        }
      }
    }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    for _ in 0..<30 where box.first == nil { await Task.yield() }
    let pendingA = try XCTUnwrap(box.first)
    XCTAssertNil(bar.barView.previewColumn.shownImage, "the well shows until the image arrives")
    moveDown()
    for _ in 0..<30 where box.second == nil { await Task.yield() }
    let pendingB = try XCTUnwrap(box.second)
    pendingA.resume(returning: imageA)
    for _ in 0..<30 { await Task.yield() }
    XCTAssertNil(bar.barView.previewColumn.shownImage, "the first tab's image arrived after the move")
    pendingB.resume(returning: imageB)
    for _ in 0..<30 where bar.barView.previewColumn.shownImage == nil { await Task.yield() }
    XCTAssertNotNil(bar.barView.previewColumn.shownImage)
  }

  func testCmdReturnSplitsAndOptReturnOpensATab() throws {
    bar.barView.widthMotion.reduceMotion = { true }
    var opened: [(URL, CommandBarController.OpenTarget)] = []
    var switched: [NodeID] = []
    bar.onOpen = { opened.append(($0, $1)) }
    bar.onSwitch = { switched.append($0) }
    let page = tab("Pull requests")
    bar.openTabsProvider = { [page] }
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    try key(36, "\r", .command)
    XCTAssertFalse(bar.isVisible)
    XCTAssertEqual(opened.map(\.1), [.newSplitPane])
    XCTAssertEqual(opened.map(\.0), [page.url])
    XCTAssertTrue(switched.isEmpty)

    opened = []
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    try key(36, "\r", .option)
    XCTAssertFalse(bar.isVisible)
    XCTAssertEqual(opened.map(\.1), [.newTab])
    XCTAssertTrue(switched.isEmpty)

    opened = []
    bar.toggle(.newTab)
    bar.setQueryForTesting("https://example.test/address")
    XCTAssertEqual(bar.panel.frame.width, 680, accuracy: 0.5, "an address row has no preview")
    try key(36, "\r", .command)
    XCTAssertEqual(opened.map(\.1), [.newTab])
  }

  func testHistoryOffersOpenAndStillSplits() throws {
    bar.barView.widthMotion.reduceMotion = { true }
    let url = URL(string: "https://notes.example.test/today")!
    bar.historyProvider = {
      [CommandBarResults.HistoryVisit(title: "Notes", url: url, visited: Date().addingTimeInterval(-12 * 60))]
    }
    var opened: [(URL, CommandBarController.OpenTarget)] = []
    bar.onOpen = { opened.append(($0, $1)) }
    bar.toggle(.newTab)
    bar.setQueryForTesting("Notes")
    let column = bar.barView.previewColumn
    bar.barView.layoutSubtreeIfNeeded()
    XCTAssertEqual(column.primaryButton.accessibilityLabel(), "Open")
    XCTAssertEqual(column.splitButton.accessibilityLabel(), "Split View")
    XCTAssertFalse(column.accessibilityLabel()?.contains("open in") ?? true)
    let dot = column.subviews.flatMap(\.subviews).first { abs($0.frame.width - 6) < 0.5 }
    XCTAssertEqual(dot?.isHidden, true)
    try key(36, "\r", .command)
    XCTAssertEqual(opened.map(\.0), [url])
    XCTAssertEqual(opened.map(\.1), [.newSplitPane])
  }

  func testScreenshotsOfTheTabAndHistoryStates() async throws {
    bar.barView.widthMotion.reduceMotion = { true }
    let image = try pageImage(red: 0.22, green: 0.4, blue: 0.34)
    bar.thumbnailForPreview = { _ in image }
    bar.openTabsProvider = { (1...5).map { self.tab("Page \($0)") } }
    window.appearance = NSAppearance(named: .darkAqua)
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    for _ in 0..<40 where bar.barView.previewColumn.shownImage == nil { await Task.yield() }
    XCTAssertNotNil(bar.barView.previewColumn.shownImage)
    try writeBar("tab-dark.png")

    bar.hide()
    window.appearance = NSAppearance(named: .aqua)
    bar.toggle(.newTab)
    bar.setQueryForTesting("example")
    for _ in 0..<40 where bar.barView.previewColumn.shownImage == nil { await Task.yield() }
    try writeBar("tab-light.png")

    bar.hide()
    bar.openTabsProvider = { [] }
    bar.historyProvider = {
      (0..<5).map { index in
        CommandBarResults.HistoryVisit(title: index == 0 ? "Notes" : "Notes \(index)",
                                       url: URL(string: "https://notes.example.test/\(index)")!,
                                       visited: Date().addingTimeInterval(-12 * 60))
      }
    }
    window.appearance = NSAppearance(named: .darkAqua)
    bar.toggle(.newTab)
    bar.setQueryForTesting("Notes")
    for _ in 0..<40 where bar.barView.previewColumn.shownImage == nil { await Task.yield() }
    XCTAssertEqual(bar.barView.previewColumn.primaryButton.accessibilityLabel(), "Open")
    try writeBar("history.png")
  }
}
