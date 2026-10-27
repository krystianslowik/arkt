#if ARKT_CHROMIUM_ENGINE
import AppKit
import Foundation
import Network

/// The contract runner's pages (W3-9): a loopback HTTP/1.1 server on an ephemeral port, reachable as `127.0.0.1` and
/// as `localhost` (two hosts for rule 6), so no rule needs the network. One request per connection.
/// - `/page/<title>?n=<k>`: a page titled `<title>` that declares `/icon.png` as its favicon;
/// - `/find/<k>?link=<url>`: a page with the word `needle` k times and one link to `url` with the text `jump` (rules 22,
///   23);
/// - `/icon.png`: a 16 px PNG;
/// - anything else: 404.
/// The runner's own copy, as the plan allows: the UI tests' `FixtureServer` lives in a test target the app cannot link.
final class ContractPageServer: Sendable {
  let port: UInt16
  private let listener: NWListener

  private init(listener: NWListener, port: UInt16) {
    self.listener = listener
    self.port = port
  }

  /// A page on `host` (`127.0.0.1` or `localhost`) titled `title`; `serial` keeps every URL of a run unique, so the
  /// tabs probe can find a tab by its URL.
  func page(_ title: String, host: String = "127.0.0.1", serial: Int) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = Int(port)
    components.path = "/page/\(title)"
    components.queryItems = [URLQueryItem(name: "n", value: String(serial))]
    return components.url!
  }

  /// A page with `occurrences` copies of `EngineContract.findWord` and one link, `#link`, to `link`.
  func findPage(occurrences: Int, link: URL, serial: Int) -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = Int(port)
    components.path = "/find/\(occurrences)"
    components.queryItems = [URLQueryItem(name: "link", value: link.absoluteString),
                             URLQueryItem(name: "n", value: String(serial))]
    return components.url!
  }

  static func start(timeout: TimeInterval = 5) async throws -> ContractPageServer {
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    let listener = try NWListener(using: parameters)
    let queue = DispatchQueue(label: "dev.arkt.engine-contract.pages")
    let icon = iconPNG()
    listener.newConnectionHandler = { connection in serve(connection, on: queue, icon: icon) }
    let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, any Error>) in
      // Every state change and the deadline run on `queue`; the handler is cleared on the first final state, so the
      // continuation resumes exactly once.
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          listener.stateUpdateHandler = nil
          if let port = listener.port?.rawValue, port != 0 {
            continuation.resume(returning: port)
          } else {
            listener.cancel()
            continuation.resume(throwing: ServerError(description: "ready without a port"))
          }
        case .failed(let error), .waiting(let error):
          listener.stateUpdateHandler = nil
          listener.cancel()
          continuation.resume(throwing: error)
        case .cancelled:
          listener.stateUpdateHandler = nil
          continuation.resume(throwing: ServerError(description: "not ready within \(timeout) s"))
        default:
          break
        }
      }
      listener.start(queue: queue)
      queue.asyncAfter(deadline: .now() + timeout) {
        if case .ready = listener.state { return }
        listener.cancel()
      }
    }
    return ContractPageServer(listener: listener, port: port)
  }

  func stop() { listener.cancel() }

  struct ServerError: Error, CustomStringConvertible {
    let description: String
  }

  // MARK: - Requests

  private static func serve(_ connection: NWConnection, on queue: DispatchQueue, icon: Data) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
      let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
      let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
      let query = URLComponents(string: "http://x" + target)?.queryItems ?? []
      let (status, mime, body) = response(for: path, query: query, icon: icon)
      var bytes = Data(("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r\nContent-Type: \(mime)\r\n"
        + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").utf8)
      bytes.append(body)
      connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
    }
  }

  private static func response(for path: String, query: [URLQueryItem], icon: Data) -> (Int, String, Data) {
    if path == "/icon.png" { return (200, "image/png", icon) }
    if path.hasPrefix("/find/"), let count = Int(path.dropFirst("/find/".count)), (0...50).contains(count) {
      let link = query.first { $0.name == "link" }?.value ?? "about:blank"
      let words = Array(repeating: "needle", count: count).joined(separator: " filler ")
      let html = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Find</title></head><body>"
        + "<p>\(words)</p><p><a id=\"link\" href=\"\(escaped(link))\">jump</a></p></body></html>"
      return (200, "text/html; charset=utf-8", Data(html.utf8))
    }
    let prefix = "/page/"
    guard path.hasPrefix(prefix), path.count > prefix.count else {
      return (404, "text/plain", Data("not found".utf8))
    }
    let title = String(path.dropFirst(prefix.count)).removingPercentEncoding ?? ""
    let html = "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(escaped(title))</title>"
      + "<link rel=\"icon\" href=\"/icon.png\"></head><body><p>\(escaped(title))</p></body></html>"
    return (200, "text/html; charset=utf-8", Data(html.utf8))
  }

  private static func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }

  /// A plain 16 x 16 square, drawn once at start.
  private static func iconPNG() -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
    for x in 0..<16 {
      for y in 0..<16 { rep.setColor(NSColor(deviceRed: 0.2, green: 0.4, blue: 0.9, alpha: 1), atX: x, y: y) }
    }
    return rep.representation(using: .png, properties: [:]) ?? Data()
  }
}
#endif
