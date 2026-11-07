import AppKit
import XCTest
@testable import ShellUI

/// A favicon decoder the test releases by hand (no clock): calls wait until `release()`.
private actor HeldDecoder {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var calls = 0
  private(set) var cancelledCalls = 0

  nonisolated var decoder: FaviconDecoder { FaviconDecoder { await self.decode($0) } }

  func decode(_ batch: [Data]) async -> [CGImage?] {
    calls += 1
    if !isOpen { await withCheckedContinuation { waiters.append($0) } }
    if Task.isCancelled { cancelledCalls += 1 }
    return batch.map { FaviconDecoder.decodeNow($0) }
  }

  func release() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }

  func hold() { isOpen = false }
}

/// #605: the sidebar decodes favicons off the main actor without a flash: a row keeps what it shows until the new
/// image is decoded, and a node that leaves (or is cleared) mid-decode gets nothing.
@MainActor
final class SidebarFaviconDecodeTests: XCTestCase {
  private var windows: [NSWindow] = []
  /// Decoders a test leaves held; released in tearDown so no decode stays suspended after the test (#675).
  private var heldDecoders: [HeldDecoder] = []

  override func tearDown() async throws {
    for decoder in heldDecoders { await decoder.release() }
    heldDecoders = []
    for window in windows { window.close() }
    windows = []
  }

  private func makeSidebar(_ sidebar: StubSidebar, decoder: FaviconDecoder) -> SidebarController {
    let controller = SidebarController(source: sidebar)
    controller.faviconDecoder = decoder
    controller.faviconImageCache = NSCache()              // the shared cache would carry images across tests
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 190, height: 800), styleMask: [.titled],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = controller.view
    controller.view.layoutSubtreeIfNeeded()
    windows.append(window)
    return controller
  }

  private func shown(_ controller: SidebarController, _ id: NodeID) throws -> NSImage? {
    let outline = try XCTUnwrap(controller.view.currentOutline)
    let row = try XCTUnwrap(controller.currentPage?.outlineController.row(for: id))
    let cell = try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarTabCellView)
    return cell.faviconView.image
  }

  private func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
  }

  func testARowKeepsItsFaviconUntilTheNewOneIsDecoded() async throws {
    let sidebar = StubSidebar.sample()
    let held = HeldDecoder()
    await held.release()
    let controller = makeSidebar(sidebar, decoder: held.decoder)
    let tab = sidebar.children(of: .today(sidebar.spaceOrder[0]))[0]
    let placeholder = try shown(controller, tab)
    controller.setFavicon(png(8), for: tab)
    XCTAssertTrue(try shown(controller, tab) === placeholder, "the letter until the first image is decoded")
    await controller.settleFaviconDecodes()
    let old = try XCTUnwrap(try shown(controller, tab))
    XCTAssertEqual(old.size, NSSize(width: 8, height: 8))

    await held.hold()
    controller.setFavicon(png(16), for: tab)
    XCTAssertTrue(try shown(controller, tab) === old, "no flash back to the letter while the new one decodes")
    XCTAssertTrue(controller.favicons[tab] === old)
    await held.release()
    await controller.settleFaviconDecodes()
    XCTAssertEqual(try shown(controller, tab)?.size, NSSize(width: 16, height: 16))
  }

  func testTheSameBytesAgainNeedNoDecode() async throws {
    let sidebar = StubSidebar.sample()
    let held = HeldDecoder()
    await held.release()
    let controller = makeSidebar(sidebar, decoder: held.decoder)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    let data = png(8)
    controller.setFavicon(data, for: today[0])
    await controller.settleFaviconDecodes()
    controller.setFavicon(data, for: today[0])
    controller.setFavicon(data, for: today[1])
    let calls = await held.calls
    XCTAssertEqual(calls, 1, "decoded bytes are cached")
    XCTAssertTrue(controller.favicons[today[1]] === controller.favicons[today[0]], "shown at once")
  }

  func testANodeRemovedMidDecodeGetsNothingAndItsDecodeIsCancelled() async throws {
    let sidebar = StubSidebar.sample()
    let held = HeldDecoder()
    let controller = makeSidebar(sidebar, decoder: held.decoder)
    let tab = sidebar.children(of: .today(sidebar.spaceOrder[0]))[0]
    controller.setFavicon(png(8), for: tab)
    sidebar.removeNode(tab)
    await held.release()
    await controller.settleFaviconDecodes()
    XCTAssertNil(controller.favicons[tab])
    let cancelled = await held.cancelledCalls
    XCTAssertEqual(cancelled, 1)
  }

  func testClearingMidDecodeShowsTheLetterAndDropsTheDecode() async throws {
    let sidebar = StubSidebar.sample()
    let held = HeldDecoder()
    let controller = makeSidebar(sidebar, decoder: held.decoder)
    let tab = sidebar.children(of: .today(sidebar.spaceOrder[0]))[0]
    let placeholder = try shown(controller, tab)
    controller.setFavicon(png(8), for: tab)
    controller.setFavicon(nil, for: tab)
    await held.release()
    await controller.settleFaviconDecodes()
    XCTAssertNil(controller.favicons[tab])
    XCTAssertTrue(try shown(controller, tab) === placeholder)
    let cancelled = await held.cancelledCalls
    XCTAssertEqual(cancelled, 1)
  }

  func testABatchIsDecodedInOneJobAndShownTogether() async throws {
    let sidebar = StubSidebar.sample()
    let held = HeldDecoder()
    let controller = makeSidebar(sidebar, decoder: held.decoder)
    let today = sidebar.children(of: .today(sidebar.spaceOrder[0]))
    controller.setFavicons([today[0]: png(8), today[1]: png(12), today[2]: png(16)])
    XCTAssertTrue(controller.favicons.isEmpty, "nothing is decoded on the main actor")
    await held.release()
    await controller.settleFaviconDecodes()
    let calls = await held.calls
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(controller.favicons.count, 3)
    XCTAssertEqual(try shown(controller, today[2])?.size, NSSize(width: 16, height: 16))
  }

  /// A tab handed to another window replays its favicon bytes there before that window first draws: the image decoded
  /// for the first window shows at once, with no decode and no letter in between. Windows share the cache.
  func testAnotherWindowShowsAnAlreadyDecodedFaviconAtOnce() async throws {
    XCTAssertTrue(SidebarController(source: StubSidebar.sample()).faviconImageCache === FaviconDecoder.sharedImages,
                  "production sidebars share one cache")
    let cache = NSCache<NSData, NSImage>()
    let open = HeldDecoder()
    await open.release()
    let firstSidebar = StubSidebar.sample()
    let first = makeSidebar(firstSidebar, decoder: open.decoder)
    first.faviconImageCache = cache
    let data = png(8)
    first.setFavicon(data, for: firstSidebar.children(of: .today(firstSidebar.spaceOrder[0]))[0])
    await first.settleFaviconDecodes()

    let held = HeldDecoder()                                 // held for the test: any decode would leave the letter
    heldDecoders.append(held)
    let secondSidebar = StubSidebar.sample()
    let second = makeSidebar(secondSidebar, decoder: held.decoder)
    second.faviconImageCache = cache
    let tab = secondSidebar.children(of: .today(secondSidebar.spaceOrder[0]))[0]
    second.setFavicon(data, for: tab)
    XCTAssertEqual(try shown(second, tab)?.size, NSSize(width: 8, height: 8), "shown in the same turn")
    let calls = await held.calls
    XCTAssertEqual(calls, 0)
  }
}
