import Foundation
import Network
import Synchronization

/// Loopback HTTP/1.1 server that serves the pages the UI tests open (plan, decision 2), so a test never touches the
/// network. It listens on `127.0.0.1` only, on an ephemeral port, and answers one request per connection
/// (`Connection: close`):
/// - `/p/<name>`: a page titled `Fixture <name>` with a link to `/p/<name>-next`;
/// - `/routing/<name>`: a page with its fixture title also visible in its body;
/// - `/x/<name>`: the same page, but its link goes to `localhost` instead of `127.0.0.1`, so it is a link to another
///   site and the Peek rules apply (BH-144, #348);
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

  /// The URL of the `/x/<name>` page: the same page, whose link goes to another site.
  func crossSitePage(_ name: String) -> String { "\(base)/x/\(name)" }

  /// The title of the `/p/<name>` page.
  static func title(ofPage name: String) -> String { titlePrefix + name }

  /// Paths of every request so far, in arrival order. Paths only: the pages are synthetic, but the log stays as small
  /// as what the tests compare against.
  var requestedPaths: [String] { log.paths.withLock { $0 } }

  /// One expected launch at a time; accepted reports remain observable until the next arm.
  func armIdentity(nonce: String, digest: String) {
    log.identity.withLock { $0 = IdentityState(nonce: nonce, digest: digest) }
  }

  var acceptedIdentity: TestIdentity.Report? { log.identity.withLock { $0?.accepted } }

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
  private struct IdentityState: Sendable {
    let nonce: String
    let digest: String
    var accepted: TestIdentity.Report?
  }

  private final class RequestLog: Sendable {
    let paths = Mutex<[String]>([])
    let identity = Mutex<IdentityState?>(nil)
  }

  private static func serve(_ connection: NWConnection, on queue: DispatchQueue, log: RequestLog) {
    connection.start(queue: queue)
    receive(connection, accumulated: Data(), log: log)
  }

  private static func receive(_ connection: NWConnection, accumulated: Data, log: RequestLog) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
      var bytes = accumulated
      bytes.append(data ?? Data())
      guard error == nil, bytes.count <= 8192 else { connection.cancel(); return }
      guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
        if complete { connection.cancel() } else { receive(connection, accumulated: bytes, log: log) }
        return
      }
      guard let header = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else {
        connection.cancel(); return
      }
      let lines = header.components(separatedBy: "\r\n")
      let first = lines.first?.split(separator: " ") ?? []
      guard first.count == 3 else { connection.cancel(); return }
      let path = String(first[1])
      let lengths = lines.dropFirst().filter { $0.lowercased().hasPrefix("content-length:") }
      let transfer = lines.dropFirst().contains { $0.lowercased().hasPrefix("transfer-encoding:") }
      guard !transfer, lengths.count <= 1 else { connection.cancel(); return }
      let length: Int
      if let line = lengths.first {
        guard let parsed = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)),
              (0...4096).contains(parsed) else { connection.cancel(); return }
        length = parsed
      } else { length = 0 }
      let body = bytes[boundary.upperBound...]
      guard body.count >= length else {
        if complete { connection.cancel() } else { receive(connection, accumulated: bytes, log: log) }
        return
      }
      log.paths.withLock { $0.append(path) }
      let reply: Response
      if path.hasPrefix("/identity/") {
        let payload = Data(body.prefix(length))
        let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
        let keys = Set(object?.keys.map { $0 } ?? [])
        let report = keys == Set(["nonce", "pid", "required", "digest"])
          ? try? JSONDecoder().decode(TestIdentity.Report.self, from: payload) : nil
        let accepted = log.identity.withLock { state in
          guard first[0] == "POST", lengths.count == 1, let report, report.isValid,
                var current = state, current.accepted == nil, current.nonce == report.nonce,
                current.digest == report.digest, path == "/identity/" + current.nonce else { return false }
          current.accepted = report
          state = current
          return true
        }
        reply = Response(status: accepted ? 204 : 403, mime: "text/plain", body: Data())
      } else {
        reply = response(for: path, crossSiteBase: crossSiteBase(of: header))
      }
      let reason = reply.status == 204 ? "No Content" : reply.status == 200 ? "OK" : "Rejected"
      var output = Data(("HTTP/1.1 \(reply.status) \(reason)\r\n"
        + "Content-Type: \(reply.mime)\r\nContent-Length: \(reply.body.count)\r\nConnection: close\r\n\r\n").utf8)
      output.append(reply.body)
      connection.send(content: output, completion: .contentProcessed { _ in connection.cancel() })
    }
  }

  /// `localhost` on the port the request came to: another host, so a link to it is a link to another site (BH-144).
  private static func crossSiteBase(of request: String) -> String {
    let host = request.split(separator: "\r\n")
      .first { $0.lowercased().hasPrefix("host:") }?
      .split(separator: ":", maxSplits: 1).last?
      .trimmingCharacters(in: .whitespaces) ?? ""
    return "http://localhost:\(host.split(separator: ":").last ?? "80")"
  }

  private struct Response {
    var status = 200
    var mime = "text/html; charset=utf-8"
    var body: Data
  }

  private static func response(for path: String, crossSiteBase: String) -> Response {
    if path == "/favicon.ico" {
      return Response(status: 404, mime: "text/plain", body: Data("not found".utf8))
    }
    if path.hasPrefix("/routing/"), path.count > 9 {
      let title = title(ofPage: String(path.dropFirst(9)))
      return Response(body: Data("<!doctype html><html><head><title>\(escaped(title))</title></head>"
        .appending("<body><p>\(escaped(title))</p></body></html>").utf8))
    }
    if path.hasPrefix("/x/"), path.count > 3 {
      let name = String(path.dropFirst(3))
      return Response(body: html(title: title(ofPage: name), link: "\(crossSiteBase)/p/\(name)-next"))
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
