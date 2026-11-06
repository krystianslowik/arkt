import AppKit
import EngineAPI
import EngineAPITestSupport
import Foundation
import Synchronization
import Testing
@testable import FakeEngineKit

/// #725: FakeEngine's favicon fetch after the page script has found the icon URL. The icon comes from
/// `FaviconStubProtocol`, not the network, and each test awaits the fetch task itself, so the required lane has no
/// wall-clock wait.
@MainActor
struct FakeEngineFaviconFetchTests {
  init() { _ = NSApplication.shared }

  /// A session whose requests `FaviconStubProtocol` answers.
  static func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FaviconStubProtocol.self]
    return URLSession(configuration: configuration)
  }

  /// The fetch converts the icon on the concurrent pool: a converter that records the thread it ran on never sees
  /// the main thread, though `fetchFavicon` itself runs on the main actor.
  @Test func fetchFaviconConvertsOffTheMainThread() async throws {
    let engine = FakeEngine()
    let tab = engine.createTab(url: nil, in: engine.createWindow(host: StubWindowHost()))
    engine.faviconSession = Self.stubSession()
    let threads = Mutex<[Bool]>([])
    engine.faviconConverter = { data in
      threads.withLock { $0.append(pthread_main_np() != 0) }
      return FakeEngine.contractFavicon(data)
    }

    await engine.fetchFavicon(tab, from: FaviconStubProtocol.url("svg"), pageURL: nil).value

    #expect(threads.withLock { $0 } == [false], "converted once, off the main thread")
    let favicon = try #require(engine.snapshot(of: tab)?.faviconData)
    #expect(Array(favicon.prefix(4)) == [0x89, 0x50, 0x4E, 0x47], "the SVG reached the tab as PNG")
  }

  /// An icon larger than `maxFaviconBytes` is dropped and never converted.
  @Test func anOversizedIconIsDroppedUnconverted() async {
    let engine = FakeEngine()
    let tab = engine.createTab(url: nil, in: engine.createWindow(host: StubWindowHost()))
    engine.faviconSession = Self.stubSession()
    let conversions = Mutex(0)
    engine.faviconConverter = { data in
      conversions.withLock { $0 += 1 }
      return FakeEngine.contractFavicon(data)
    }

    await engine.fetchFavicon(tab, from: FaviconStubProtocol.url("huge"), pageURL: nil).value
    #expect(engine.snapshot(of: tab)?.faviconData == nil)
    #expect(conversions.withLock { $0 } == 0)

    await engine.fetchFavicon(tab, from: FaviconStubProtocol.url("png"), pageURL: nil).value
    #expect(engine.snapshot(of: tab)?.faviconData != nil, "control: a small icon from the same stub arrives")
  }

  /// A body without a usable length is read only up to the cap: one byte past it, and the rest is never pulled.
  @Test func theBodyIsReadOnlyUpToTheCap() async throws {
    let limit = 16
    let small = CountingBytes(count: limit)
    #expect(try await FakeEngine.readFavicon(small, limit: limit) == Data(repeating: 7, count: limit),
            "control: a body at the cap is read whole")

    let large = CountingBytes(count: limit * 1000)
    #expect(try await FakeEngine.readFavicon(large, limit: limit) == nil)
    #expect(large.pulled == limit + 1, "stopped one byte past the cap, never read the whole body")
  }

  @Test func theDefaultCapIsTheFaviconLimit() async throws {
    let limit = FakeEngine.maxFaviconBytes
    let body = CountingBytes(count: limit + 10)
    #expect(try await FakeEngine.readFavicon(body) == nil)
    #expect(body.pulled == limit + 1)
  }
}

/// `count` bytes of 7, counting how many were pulled.
final class CountingBytes: AsyncSequence, Sendable {
  typealias Element = UInt8
  let count: Int
  private let pulledCount = Mutex(0)
  var pulled: Int { pulledCount.withLock { $0 } }

  init(count: Int) { self.count = count }

  struct AsyncIterator: AsyncIteratorProtocol {
    let source: CountingBytes
    mutating func next() async -> UInt8? {
      source.pulledCount.withLock { pulled in
        guard pulled < source.count else { return nil }
        pulled += 1
        return 7
      }
    }
  }

  func makeAsyncIterator() -> AsyncIterator { AsyncIterator(source: self) }
}

/// Answers `favicon-stub://icon/<name>` from memory: `svg` is a small SVG, `png` bytes that start with the PNG
/// signature (they pass through unparsed), and `huge` a body larger than `FakeEngine.maxFaviconBytes`.
final class FaviconStubProtocol: URLProtocol {
  static func url(_ name: String) -> URL { URL(string: "favicon-stub://icon/\(name)")! }

  override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "favicon-stub" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let body: Data, type: String
    switch url.lastPathComponent {
    case "svg":
      let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7"/></svg>"#
      (body, type) = (Data(svg.utf8), "image/svg+xml")
    case "png": (body, type) = (Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]), "image/png")
    default: (body, type) = (Data(count: FakeEngine.maxFaviconBytes + 1), "image/png")
    }
    let headers = ["Content-Type": type, "Content-Length": "\(body.count)"]
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
