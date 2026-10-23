import Foundation
import Network

/// Minimal HTTP/1.1 server on the loopback interface for engine tests. Serves fixed routes,
/// answers 404 otherwise, one request per connection (`Connection: close`).
final class LoopbackServer: Sendable {
  struct Response: Sendable {
    var status = 200
    var mime: String
    var body: Data
  }

  let port: UInt16
  private let listener: NWListener

  private init(listener: NWListener, port: UInt16) {
    self.listener = listener
    self.port = port
  }

  static func start(routes: [String: Response]) async throws -> LoopbackServer {
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    let listener = try NWListener(using: parameters)
    let queue = DispatchQueue(label: "arkt.loopback-server")
    listener.newConnectionHandler = { connection in
      connection.start(queue: queue)
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let path = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
        let response = routes[path] ?? Response(status: 404, mime: "text/plain", body: Data("not found".utf8))
        let reason = response.status == 200 ? "OK" : "Not Found"
        var bytes = Data(("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: \(response.mime)\r\n"
          + "Content-Length: \(response.body.count)\r\nConnection: close\r\n\r\n").utf8)
        bytes.append(response.body)
        connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
      }
    }
    listener.start(queue: queue)
    let deadline = ContinuousClock.now + .seconds(5)
    while listener.port == nil || listener.port?.rawValue == 0 {
      if ContinuousClock.now > deadline { listener.cancel(); throw URLError(.cannotConnectToHost) }
      try await Task.sleep(for: .milliseconds(10))
    }
    return LoopbackServer(listener: listener, port: listener.port!.rawValue)
  }

  func stop() { listener.cancel() }
}
