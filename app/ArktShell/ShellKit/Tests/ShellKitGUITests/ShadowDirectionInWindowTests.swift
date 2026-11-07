import AppKit
import EngineAPI
import XCTest
@testable import ShellUI

/// The #767 and #773 lifts cast down inside the host chain they ship in: a flipped container (as `OnboardingStepView`
/// and `ShellRootView` are) in a window on screen, where AppKit itself joins the layers. `ShadowDirectionTests` covers
/// the same sites offscreen; this checks the window's own layer tree, drawn from its root.
@MainActor
final class ShadowDirectionInWindowTests: XCTestCase {
  private final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
  }

  private var window: NSWindow!
  private var container: FlippedContainer!

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 520, height: 360), styleMask: [.borderless],
                      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
    content.wantsLayer = true
    content.layer?.backgroundColor = CGColor(gray: 1, alpha: 1)
    window.contentView = content
    container = FlippedContainer(frame: content.bounds)
    container.wantsLayer = true
    content.addSubview(container)
  }

  override func tearDown() async throws { window.close() }

  func testTheSliderKnobAndTheSpacePreviewCastDownInAFlippedHost() throws {
    let slider = ThemeSliderView(label: "Grain", identifier: "test.slider")
    slider.frame = NSRect(x: 40, y: 40, width: 200, height: 24)   // flipped: 40 pt from the top
    slider.setValue(0.3)
    container.addSubview(slider)
    let preview = SpacePreviewView(frame: NSRect(x: 40, y: 120, width: 340, height: 196))
    preview.configure(theme: SpaceThemeCatalog.defaultFamily.light, name: "Work", animated: false)
    container.addSubview(preview)
    window.orderFront(nil)
    container.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    let knob = try XCTUnwrap(layers(under: try XCTUnwrap(slider.layer)).first { $0 is ShadowPathLayer })
    let image = try render()
    try expectCastsDown(knob, in: image, band: 3)
    try expectCastsDown(try XCTUnwrap(preview.layer), in: image, band: 16)
  }

  /// #773: the Settings switch, segmented control and pane item, and the sidebar and Archive row lifts, as the
  /// Settings content views and the outline and Archive tables host them. Light: the plates and rows draw no shadow in
  /// dark.
  func testTheSettingsControlsAndTheRowLiftsCastDownInAFlippedHost() throws {
    window.appearance = NSAppearance(named: .aqua)
    let toggle = SettingsSwitch(frame: NSRect(x: 40, y: 40, width: 32, height: 20))
    container.addSubview(toggle)
    let segments = SettingsSegmentedControl(segments: ["Light", "Dark", "Auto"], selected: 0)
    segments.frame = NSRect(origin: NSPoint(x: 120, y: 40), size: segments.intrinsicContentSize)
    container.addSubview(segments)
    let item = SettingsPaneItemView(pane: .general)
    item.frame.origin = NSPoint(x: 400, y: 30)
    container.addSubview(item)
    item.setSelected(true, animated: false)
    let sidebarRow = SidebarRowView(frame: NSRect(x: 40, y: 120, width: 220, height: 41))
    sidebarRow.state = .current
    container.addSubview(sidebarRow)
    let archiveRow = ArchiveRowView(frame: NSRect(x: 280, y: 120, width: 220, height: 37))
    // Outside a table AppKit paints its own selection over a selected row; off, so the fill and its lift are drawn.
    archiveRow.selectionHighlightStyle = .none
    container.addSubview(archiveRow)
    archiveRow.isSelected = true
    window.orderFront(nil)
    container.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    let image = try render()
    // The knob and the plates sit 2 pt inside their tracks: the bands stay on the track.
    for (control, band) in [(toggle, 1), (segments, 1.5), (item, 1.5)] as [(NSView, CGFloat)] {
      let plate = try XCTUnwrap(layers(under: try XCTUnwrap(control.layer)).first { $0 is ShadowPathLayer })
      try expectCastsDown(plate, in: image, band: band)
    }
    try expectCastsDown(sidebarRow.backgroundLayer, in: image, band: 1.5)
    let fill = try XCTUnwrap(archiveRow.layer?.sublayers?.first { $0.shadowOpacity > 0 }, "the selected fill")
    try expectCastsDown(fill, in: image, band: 1.5)
  }

  /// #794: the shown private page's row and the extensions row lifted during a drag, in light.
  func testTheShownPrivateRowAndTheLiftedExtensionsRowCastDownInAFlippedHost() throws {
    window.appearance = NSAppearance(named: .aqua)
    let tab = TabID()
    let privateRow = PrivatePageRowView(tab: tab)
    privateRow.frame = NSRect(x: 40, y: 40, width: 220, height: 32)
    privateRow.flavor = .light
    privateRow.apply(PrivatePageRowContent(tab: tab, title: "Private", url: nil, favicon: nil, isShown: true),
                     favicon: nil)
    container.addSubview(privateRow)
    let extensionsRow = ExtensionsPanelRow(action: ExtensionAction(id: "test.extension", name: "Test Extension"))
    extensionsRow.frame.origin = NSPoint(x: 40, y: 140)
    container.addSubview(extensionsRow)
    extensionsRow.setLifted(true)
    window.orderFront(nil)
    container.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    let image = try render()
    for (row, band) in [(privateRow, 1.5), (extensionsRow, 4)] as [(NSView, CGFloat)] {
      let fill = try XCTUnwrap(row.layer?.sublayers?.first { $0.shadowOpacity > 0 }, "\(type(of: row))'s fill")
      try expectCastsDown(fill, in: image, band: band)
    }
  }

  /// The lifts #783 found already casting down stay down: the current Favorite tile and the content card, unflipped
  /// views inside the flipped container (their layers are not flipped), and the Little Arkt flight's card shadow on
  /// its own overlay window. Light: the three lifts are clear in dark.
  func testTheFavoriteTileTheContentCardAndTheFlightStayDown() throws {
    window.appearance = NSAppearance(named: .aqua)
    let tile = FavoriteTileView(frame: NSRect(x: 40, y: 40, width: 52, height: 46))
    tile.flavor = .light
    tile.isCurrent = true
    container.addSubview(tile)
    let card = ContentCardView()
    card.frame = NSRect(x: 160, y: 40, width: 300, height: 200)
    container.addSubview(card)
    window.orderFront(nil)
    container.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    XCTAssertFalse(tile.fillLayer.contentsAreFlipped(), "the tile's fill measures y upwards")
    let cardLayer = try XCTUnwrap(card.layer)
    XCTAssertFalse(cardLayer.contentsAreFlipped(), "the card's layer measures y upwards")

    // On screen the page's layers fill the card. The offscreen renderer draws no shadow for a layer with no content
    // of its own, so an opaque sublayer stands in for them (here and for the flight's shadow layer).
    cardLayer.insertSublayer(Self.standIn(cardLayer.bounds), at: 0)

    let image = try render()
    try expectCastsDown(tile.fillLayer, in: image, band: 1.5)
    try expectCastsDown(cardLayer, in: image, band: 2)

    let flight = LittleArktFlight(source: CGRect(x: 120, y: 120, width: 200, height: 140), scale: 1, opacity: 1,
                                  target: CGRect(x: 360, y: 120, width: 320, height: 220),
                                  span: CGRect(x: 80, y: 80, width: 640, height: 320), level: .normal, flavor: .light)
    flight.drivesDisplayLink = false
    defer { flight.runToEnd() }
    // The overlay is clear; an opaque backdrop gives the two bands something to differ on.
    flight.overlay.contentView?.layer?.backgroundColor = CGColor(gray: 1, alpha: 1)
    flight.tick(at: 0)                                         // the first frame: the card at its source, on screen
    XCTAssertTrue(flight.overlay.isVisible)
    XCTAssertEqual(flight.shadowLayer.shadowOpacity, 1, "light carries the shadow")
    flight.shadowLayer.addSublayer(Self.standIn(flight.shadowLayer.bounds))
    try expectCastsDown(flight.shadowLayer, in: try render(flight.overlay), band: 2)
  }

  /// #796: the selected Archive row in the Archive window's own table, focused and unfocused: its fill shows
  /// (`tabCurrent`, lighter than the window behind it) and its lift casts down. The table draws no selection of its
  /// own (`selectionHighlightStyle = .none`), so AppKit adds no selection view over the row. The selection is made
  /// with the keyboard, and the row and the accessibility table both report it.
  func testTheSelectedArchiveRowInTheArchiveTable() async throws {
    let controller = ArchiveWindowController(dataSource: ArchiveRowsStub(count: 2))
    let archive = try XCTUnwrap(controller.window)
    defer { archive.close() }
    archive.appearance = NSAppearance(named: .aqua)
    await controller.reload()
    archive.orderFront(nil)
    let table = try XCTUnwrap(controller.tableView as? ArchiveTableView)
    XCTAssertEqual(table.selectionHighlightStyle, .none, "the rows draw the selection themselves")
    XCTAssertTrue(archive.makeFirstResponder(table))
    for _ in 0..<2 { table.keyDown(with: try Self.down()) }   // Down from no selection: row 0, then row 1
    XCTAssertEqual(table.selectedRow, 1)
    archive.contentView?.layoutSubtreeIfNeeded()
    archive.displayIfNeeded()
    let row = try XCTUnwrap(table.rowView(atRow: 1, makeIfNecessary: false) as? ArchiveRowView)
    let other = try XCTUnwrap(table.rowView(atRow: 0, makeIfNecessary: false) as? ArchiveRowView)
    XCTAssertTrue(row.isSelected)
    XCTAssertFalse(other.isSelected)
    XCTAssertEqual(row.displayedFill, ShellTokens.tabCurrent.resolve(.light))
    XCTAssertNil(other.displayedFill)
    XCTAssertTrue(row.isAccessibilitySelected())
    XCTAssertFalse(other.isAccessibilitySelected())
    let selected = try XCTUnwrap(table.axProxyRows.element.accessibilitySelectedRows())
    XCTAssertEqual(selected.compactMap { ($0 as? AXProxyRow)?.accessibilityIndex() }, [1])
    XCTAssertEqual(row.subviews.filter { !($0 is NSTableCellView) }, [], "no selection view over the row")
    let rowLayer = try XCTUnwrap(row.layer)

    // The table emphasizes its selection while it is first responder in the key window; the runner is never active,
    // so both states are set by hand.
    for focused in [true, false] {
      row.isEmphasized = focused
      archive.displayIfNeeded()
      let image = try render(archive)   // the render's display pass inserts the fill
      let fill = try XCTUnwrap(rowLayer.sublayers?.first { $0.cornerRadius == SidebarMetrics.rowCornerRadius })
      let rect = fill.convert(fill.bounds, to: image.root)
      let height = image.root.bounds.height
      let shown = image.luminance(x: rect.midX, yFromTop: height - rect.midY)
      let window = image.luminance(x: rect.midX, yFromTop: height - rect.minY + 40)   // the empty table below
      XCTAssertGreaterThan(shown, window + 0.02, "focused \(focused): the fill (\(shown)) over the window (\(window))")
      try expectCastsDown(fill, in: image, band: 1.5)
    }
  }

  // MARK: Helpers

  private static func down() throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                   context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
                                   isARepeat: false, keyCode: 125))
  }

  private static func standIn(_ frame: CGRect) -> CALayer {
    let layer = CALayer()
    layer.frame = frame
    layer.backgroundColor = CGColor(gray: 0.5, alpha: 1)
    return layer
  }

  private func layers(under layer: CALayer) -> [CALayer] {
    [layer] + (layer.sublayers ?? []).flatMap { layers(under: $0) }
  }

  /// The topmost layer of `window`'s tree (the test window by default).
  private func root(of window: NSWindow? = nil) throws -> CALayer {
    var root = try XCTUnwrap((window ?? self.window).contentView?.layer)
    while let up = root.superlayer { root = up }
    return root
  }

  /// A window's layer tree from its unflipped root, at 2x, rows counted from the top.
  private func render(_ window: NSWindow? = nil) throws -> Rendered {
    let root = try root(of: window)
    XCTAssertFalse(root.contentsAreFlipped(), "the root measures y upwards")
    let width = Int(root.bounds.width * 2), height = Int(root.bounds.height * 2)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.scaleBy(x: 2, y: 2)
    root.render(in: context)
    return Rendered(root: root, pixels: pixels, width: width, height: height)
  }

  /// Across the element's middle, the `band` points under its bottom edge are darker than those over its top edge.
  private func expectCastsDown(_ element: CALayer, in image: Rendered, band: CGFloat,
                               file: StaticString = #filePath, line: UInt = #line) throws {
    let rect = element.convert(element.bounds, to: image.root)   // root points, y up
    let height = image.root.bounds.height
    let xs = stride(from: rect.minX + rect.width * 0.3, through: rect.maxX - rect.width * 0.3, by: 1)
    let under = image.mean(xs: xs, yFromTop: (height - rect.minY + 0.5)...(height - rect.minY + band))
    let over = image.mean(xs: xs, yFromTop: (height - rect.maxY - band)...(height - rect.maxY - 0.5))
    XCTAssertLessThan(under, over - 0.003, "the band under \(type(of: element)) is darker than the band over it",
                      file: file, line: line)
  }
}

/// A window's layer tree drawn into an sRGB bitmap at 2x.
private struct Rendered {
  let root: CALayer
  let pixels: [UInt8]
  let width: Int
  let height: Int

  /// Rec. 709 luminance at (`x`, `yFromTop`) points, 0 to 1.
  func luminance(x: CGFloat, yFromTop y: CGFloat) -> Double {
    let px = min(max(Int(x * 2), 0), width - 1), py = min(max(Int(y * 2), 0), height - 1)
    let i = (py * width + px) * 4
    return (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
  }

  func mean(xs: StrideThrough<CGFloat>, yFromTop rows: ClosedRange<CGFloat>) -> Double {
    var sum = 0.0, count = 0
    for x in xs {
      for y in stride(from: rows.lowerBound, through: rows.upperBound, by: 0.5) {
        sum += luminance(x: x, yFromTop: y)
        count += 1
      }
    }
    return sum / Double(max(count, 1))
  }
}

/// A few archived tabs, for the Archive window's rows.
@MainActor
final class ArchiveRowsStub: ArchiveListDataSource {
  var canRestore = true
  var onChange: (@MainActor () -> Void)?
  private let rows: [ArchiveRow]
  init(count: Int = 1) {
    rows = (0..<count).map { ArchiveRow(id: UUID(), title: "Archived \($0)", detail: "a.example - Work", reason: "Closed") }
  }
  func loadPage() async -> ArchiveListPage { ArchiveListPage(rows: rows, unreadable: 0, mayHaveMore: false) }
  func loadMore() async -> ArchiveListPage { await loadPage() }
  func refresh() async -> ArchiveListPage { await loadPage() }
  func restore(_ id: UUID) -> Bool { false }
}
