import Foundation
import Synchronization
import Testing
import EngineAPI

/// The bounded on-disk thumbnail cache for history items (#370): keyed by a hash of the URL, at most N entries and
/// M bytes with the oldest evicted first, kept across instances, and emptied by `removeAll()`.
struct PageImageCacheTests {
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: "arkt-page-image-cache-\(UUID().uuidString)", directoryHint: .isDirectory)

  private func image(_ fill: UInt8, bytes: Int = 1_000) -> PageImage {
    PageImage(data: Data(repeating: fill, count: bytes), pixelWidth: 60, pixelHeight: 36, scale: 1, format: .jpeg)
  }

  /// One clock for every instance of a test, so a second instance stores newer entries than the first.
  private let clock = TestClock()

  private func cache(maxEntries: Int = 200, maxBytes: Int = 20_000_000) -> PageImageCache {
    PageImageCache(directory: directory, maxEntries: maxEntries, maxBytes: maxBytes, now: clock.now)
  }

  private func url(_ n: Int) -> URL { URL(string: "https://example.test/page/\(n)")! }

  @Test func storedImageIsFoundByItsURL() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache()
    let stored = try #require(TestImages.gradient(width: 120, height: 72))
    let image = try #require(await PageImageEncoder.encode(stored, scale: 1, .thumbnail))
    await cache.store(image, for: url(1))
    #expect(await cache.image(for: url(1)) == image)
    #expect(await cache.image(for: url(2)) == nil)
  }

  @Test func storingTheSameURLReplacesItsImage() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache()
    let gradient = try #require(TestImages.gradient(width: 80, height: 40))
    let noise = try #require(TestImages.noise(width: 80, height: 40))
    let first = try #require(await PageImageEncoder.encode(gradient, scale: 1, .thumbnail))
    let second = try #require(await PageImageEncoder.encode(noise, scale: 1, .thumbnail))
    await cache.store(first, for: url(1))
    await cache.store(second, for: url(1))
    #expect(await cache.image(for: url(1)) == second)
    #expect(await cache.count == 1)
  }

  /// The file name is a hash: no part of the URL reaches the disk.
  @Test func fileNamesDoNotContainTheURL() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache()
    let frame = try #require(TestImages.gradient(width: 80, height: 40))
    let image = try #require(await PageImageEncoder.encode(frame, scale: 1, .thumbnail))
    await cache.store(image, for: URL(string: "https://secret-host.test/private/path?q=term")!)
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(names.count == 1)
    for name in names {
      #expect(!name.contains("secret") && !name.contains("private") && !name.contains("term"))
    }
  }

  @Test func countCapEvictsTheOldestFirst() async {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache(maxEntries: 3)
    for n in 1...4 { await cache.store(image(UInt8(n)), for: url(n)) }
    #expect(await cache.count == 3)
    #expect(await cache.image(for: url(1)) == nil)
    for n in 2...4 { #expect(await cache.image(for: url(n)) != nil) }
  }

  @Test func byteCapEvictsTheOldestFirst() async {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache(maxBytes: 2_500)
    for n in 1...3 { await cache.store(image(UInt8(n), bytes: 1_000), for: url(n)) }
    #expect(await cache.count == 2)
    #expect(await cache.totalBytes <= 2_500)
    #expect(await cache.image(for: url(1)) == nil)
    #expect(await cache.image(for: url(3)) != nil)
  }

  /// Storing again makes an entry the newest, so it outlives older ones.
  @Test func restoringAnEntryMakesItTheNewest() async {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache(maxEntries: 2)
    await cache.store(image(1), for: url(1))
    await cache.store(image(2), for: url(2))
    await cache.store(image(3), for: url(1))
    await cache.store(image(4), for: url(3))
    #expect(await cache.image(for: url(2)) == nil)
    #expect(await cache.image(for: url(1)) != nil)
    #expect(await cache.image(for: url(3)) != nil)
  }

  /// An image bigger than the whole cache is not kept.
  @Test func imageOverTheByteCapIsNotStored() async {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache(maxBytes: 500)
    await cache.store(image(1, bytes: 1_000), for: url(1))
    #expect(await cache.count == 0)
  }

  @Test func entriesSurviveANewInstanceInTheirOrder() async {
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = cache(maxEntries: 3)
    for n in 1...3 { await first.store(image(UInt8(n)), for: url(n)) }
    let second = cache(maxEntries: 3)
    #expect(await second.count == 3)
    #expect(await second.image(for: url(2)) != nil)
    await second.store(image(9), for: url(9))
    #expect(await second.image(for: url(1)) == nil)
  }

  /// Eviction order is the store order, not the wall clock: a clock that steps backwards must not make the newest
  /// entry look like the oldest (#442).
  @Test func aBackwardsClockDoesNotEvictTheNewestEntry() async {
    defer { try? FileManager.default.removeItem(at: directory) }
    let backwards = TestClock(step: -1)
    let cache = PageImageCache(directory: directory, maxEntries: 1, maxBytes: 20_000_000, now: backwards.now)
    await cache.store(image(1), for: url(1))
    await cache.store(image(2), for: url(2))
    #expect(await cache.count == 1)
    #expect(await cache.image(for: url(1)) == nil)
    #expect(await cache.image(for: url(2)) != nil)
  }

  @Test func removeAllEmptiesTheCacheAndItsFolder() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = cache()
    for n in 1...3 { await cache.store(image(UInt8(n)), for: url(n)) }
    await cache.removeAll()
    #expect(await cache.count == 0)
    #expect(await cache.image(for: url(1)) == nil)
    let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    #expect(left.isEmpty)
  }

  @Test func defaultCapsMatchTheIssue() {
    #expect(PageImageCache.defaultMaxEntries == 200)
    #expect(PageImageCache.defaultMaxBytes == 20 * 1024 * 1024)
  }
}

/// A clock that moves `step` seconds per read, so store order is the age order whatever the file system's timestamp
/// resolution. A negative step moves it backwards, as a clock correction can.
final class TestClock: Sendable {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)
  private let step: Int
  private let ticks = Ticks()

  init(step: Int = 1) { self.step = step }

  var now: @Sendable () -> Date {
    { [start, step, ticks] in start.addingTimeInterval(Double(ticks.next() * step)) }
  }

  private final class Ticks: Sendable {
    private let value = Mutex(0)
    func next() -> Int { value.withLock { $0 += 1; return $0 } }
  }
}

