import Foundation
import os

/// Thumbnails for the command bar's preview column (#370), over any engine: a live tab's current frame through
/// `EngineClient.pageImage(of:_:)`, kept in a `PageImageCache` under the tab's URL so the page's history item can
/// show it later. Never loads, wakes or fetches anything: a tab without a frame gives its last cached image, a URL
/// without a cache entry gives nil.
@MainActor
public final class PageThumbnails {
  private let engine: any EngineClient
  private let cache: PageImageCache?
  private let log = Logger(subsystem: "dev.arkt.shell", category: "PageThumbnails")

  /// Always `.thumbnail`: the cache is sized for thumbnails, never full frames.
  public init(engine: any EngineClient, cache: PageImageCache?) {
    self.engine = engine
    self.cache = cache
  }

  /// The tab's thumbnail: its live frame, else the image last cached for its URL; nil for an unknown or closed tab.
  public func thumbnail(of id: TabID) async -> PageImage? {
    guard let url = engine.snapshot(of: id)?.url else { return nil }
    if let live = await engine.pageImage(of: id, .thumbnail) {
      // The tab may have navigated while its frame was copied: file the image only under the URL it still shows.
      if let cache, engine.snapshot(of: id)?.url == url { await cache.store(live, for: url) }
      log.debug("live thumbnail \(live.pixelWidth)x\(live.pixelHeight) px, \(live.data.count) bytes")
      return live
    }
    return await cache?.image(for: url)
  }

  /// The thumbnail cached for a page (a history item); nil when none was captured.
  public func thumbnail(for url: URL) async -> PageImage? {
    await cache?.image(for: url)
  }
}
