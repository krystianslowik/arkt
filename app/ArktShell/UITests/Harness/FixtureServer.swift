import Foundation
import Network
import Synchronization

/// Loopback HTTP/1.1 server that serves the pages the UI tests open (plan, decision 2), so a test never touches the
/// network. It listens on `127.0.0.1` only, on an ephemeral port, and answers one request per connection
/// (`Connection: close`):
/// - `/p/<name>`: a page titled `Fixture <name>` with a link to `/p/<name>-next`;
/// - `/favicon.ico`: 404, so the engine's favicon fetch stays on loopback and finds nothing;
/// - any other path: a generic page titled after the path, so rewritten Arc fixture URLs always load.
///
/// Starts from the shape of `ShellKitGUITests/LoopbackServer.swift`, which this target cannot import; #93 removes the
/// duplication.
final class FixtureServer: Sendable {
  /// Prefix of the title of every page this server serves.
  static let titlePrefix = "Fixture "

  let port: UInt16
  private let listener: NWListener
  private let log: RequestLog

  private init(listener: NWListener, port: UInt16, log: RequestLog) {
    self.listener = listener
    self.port = port
    self.log = log
  }

  /// `http://127.0.0.1:<port>`, the origin of every page the server serves.
  var base: String { "http://127.0.0.1:\(port)" }

  /// The URL of the `/p/<name>` page.
  func page(_ name: String) -> String { "\(base)/p/\(name)" }

  /// The title of the `/p/<name>` page.
  static func title(ofPage name: String) -> String { titlePrefix + name }

  /// Paths of every request so far, in arrival order. Paths only: the pages are synthetic, but the log stays as small
  /// as what the tests compare against.
  var requestedPaths: [String] { log.paths.withLock { $0 } }

  /// Starts listening and returns once the listener is ready. The wait is bounded: a listener that is not ready
  /// within `timeout` seconds is cancelled and the start throws.
  static func start(timeout: TimeInterval = 5) async throws -> FixtureServer {
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    let listener = try NWListener(using: parameters)
    let queue = DispatchQueue(label: "dev.arkt.uitest.fixture-server")
    let log = RequestLog()
    listener.newConnectionHandler = { connection in
      serve(connection, on: queue, log: log)
    }
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
            continuation.resume(throwing: HarnessError("fixture server is ready without a port"))
          }
        case .failed(let error), .waiting(let error):
          // A listener waits when it cannot bind (for example a sandbox without network.server); that never fixes
          // itself during a test.
          listener.stateUpdateHandler = nil
          listener.cancel()
          continuation.resume(throwing: error)
        case .cancelled:
          listener.stateUpdateHandler = nil
          continuation.resume(throwing: HarnessError("fixture server did not start within \(timeout) s"))
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
    return FixtureServer(listener: listener, port: port, log: log)
  }

  func stop() { listener.cancel() }

  // MARK: - Requests

  /// The paths the server was asked for; shared with the connection handler, which runs on the server's queue.
  private final class RequestLog: Sendable {
    let paths = Mutex<[String]>([])
  }

  private static func serve(_ connection: NWConnection, on queue: DispatchQueue, log: RequestLog) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
      let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      let path = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
      log.paths.withLock { $0.append(path) }
      let response = Self.response(for: path)
      var bytes = Data(("HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Not Found")\r\n"
        + "Content-Type: \(response.mime)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n").utf8)
      bytes.append(response.body)
      connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
    }
  }

  private struct Response {
    var status = 200
    var mime = "text/html; charset=utf-8"
    var body: Data
  }

  private static func response(for path: String) -> Response {
    if path == "/favicon.ico" {
      return Response(status: 404, mime: "text/plain", body: Data("not found".utf8))
    }
    if path.hasPrefix("/p/"), path.count > 3 {
      let name = String(path.dropFirst(3))
      return Response(body: html(title: title(ofPage: name), link: "/p/\(name)-next"))
    }
    return Response(body: html(title: titlePrefix + path, link: nil))
  }

  private static func html(title: String, link: String?) -> Data {
    var body = "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(escaped(title))</title></head><body>"
    if let link { body += "<a href=\"\(escaped(link))\">Next</a>" }
    body += "</body></html>"
    return Data(body.utf8)
  }

  private static func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
