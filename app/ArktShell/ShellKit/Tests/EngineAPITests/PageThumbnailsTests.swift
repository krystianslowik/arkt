import Foundation
import Testing
import EngineAPI
@testable import EngineAPITestSupport

/// The command bar's thumbnails (#370) over any engine: a live tab's image within the thumbnail caps, kept in the
/// history cache under the tab's URL; a tab without a frame gives its last cached image or nil; a history item gives
/// its cached image or nil, never a fetch.
@MainActor
struct PageThumbnailsTests {
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: "arkt-page-thumbnails-\(UUID().uuidString)", directoryHint: .isDirectory)
  private let page = URL(string: "arkt-test://page/Thumbnail")!

  private func loadedTab(_ engine: InMemoryEngine, url: URL? = nil) -> TabID {
    let tab = engine.createTab(url: url ?? page, in: engine.createWindow(host: StubWindowHost()))
    engine.finishLoad(tab, title: "Thumbnail")
    return tab
  }

  @Test func liveTabGivesACappedImage() async throws {
    let engine = InMemoryEngine()
    let thumbnails = PageThumbnails(engine: engine, cache: nil)
    let image = try #require(await thumbnails.thumbnail(of: loadedTab(engine)))
    #expect(image.pixelWidth <= 600 && image.pixelHeight <= 360)
    #expect(image.data.count <= 80_000 && !image.data.isEmpty)
  }

  @Test func liveImageIsCachedUnderTheTabURL() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let engine = InMemoryEngine()
    let cache = PageImageCache(directory: directory)
    let thumbnails = PageThumbnails(engine: engine, cache: cache)
    let image = try #require(await thumbnails.thumbnail(of: loadedTab(engine)))
    #expect(await thumbnails.thumbnail(for: page) == image)
    #expect(await cache.image(for: page) == image)
  }

  /// A hidden or discarded tab has no frame to copy: its last cached image comes back, and the engine is not asked to
  /// load anything.
  @Test func tabWithoutAFrameGivesItsCachedImage() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let engine = InMemoryEngine()
    let thumbnails = PageThumbnails(engine: engine, cache: PageImageCache(directory: directory))
    let tab = loadedTab(engine)
    let cached = try #require(await thumbnails.thumbnail(of: tab))
    engine.setFrameAvailable(tab, false)
    let recorder = EventRecorder(engine)
    #expect(await thumbnails.thumbnail(of: tab) == cached)
    #expect(recorder.events(for: tab).isEmpty)
  }

  @Test func tabWithoutAFrameOrCacheGivesNil() async {
    let engine = InMemoryEngine()
    let thumbnails = PageThumbnails(engine: engine, cache: nil)
    let tab = loadedTab(engine)
    engine.setFrameAvailable(tab, false)
    #expect(await thumbnails.thumbnail(of: tab) == nil)
  }

  @Test func historyItemWithoutCacheGivesNil() async {
    defer { try? FileManager.default.removeItem(at: directory) }
    let thumbnails = PageThumbnails(engine: InMemoryEngine(), cache: PageImageCache(directory: directory))
    #expect(await thumbnails.thumbnail(for: page) == nil)
  }

  @Test func unknownAndClosedTabsGiveNil() async {
    let engine = InMemoryEngine()
    let thumbnails = PageThumbnails(engine: engine, cache: nil)
    #expect(await thumbnails.thumbnail(of: TabID()) == nil)
    let tab = loadedTab(engine)
    engine.closeTab(tab)
    #expect(await thumbnails.thumbnail(of: tab) == nil)
  }

  /// A tab that navigated while its image was being made does not file that image under its new URL.
  @Test func imageIsNotCachedUnderAURLTheTabLeft() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let engine = InMemoryEngine()
    let cache = PageImageCache(directory: directory)
    let thumbnails = PageThumbnails(engine: engine, cache: cache)
    let tab = loadedTab(engine)
    let other = URL(string: "arkt-test://page/Other")!
    engine.beforePageImageReturns = { engine.navigate(tab, to: other) }
    _ = await thumbnails.thumbnail(of: tab)
    #expect(await cache.image(for: other) == nil)
    #expect(await cache.image(for: page) == nil)
  }
}

/// The in-memory engine's page images: deterministic per URL, nil without a page.
@MainActor
struct InMemoryEnginePageImageTests {
  @Test func sameURLGivesTheSameImage() async throws {
    let engine = InMemoryEngine()
    let window = engine.createWindow(host: StubWindowHost())
    let url = URL(string: "arkt-test://page/Same")!
    let first = engine.createTab(url: url, in: window)
    let second = engine.createTab(url: url, in: window)
    let a = try #require(await engine.pageImage(of: first, .thumbnail))
    let b = try #require(await engine.pageImage(of: second, .thumbnail))
    #expect(a == b)
    let other = engine.createTab(url: URL(string: "arkt-test://page/Other")!, in: window)
    #expect(await engine.pageImage(of: other, .thumbnail) != a)
  }

  @Test func fullFrameIsLargerThanTheThumbnail() async throws {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: URL(string: "arkt-test://page/Full")!, in: engine.createWindow(host: StubWindowHost()))
    let thumbnail = try #require(await engine.pageImage(of: tab, .thumbnail))
    let full = try #require(await engine.pageImage(of: tab, .fullFrame))
    #expect(full.pixelWidth == InMemoryEngine.framePixelSize.width)
    #expect(full.pixelHeight == InMemoryEngine.framePixelSize.height)
    #expect(full.pixelWidth > thumbnail.pixelWidth)
  }

  @Test func blankTabGivesNil() async {
    let engine = InMemoryEngine()
    let tab = engine.createTab(url: nil, in: engine.createWindow(host: StubWindowHost()))
    #expect(await engine.pageImage(of: tab, .thumbnail) == nil)
  }
}
