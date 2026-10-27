import Foundation
import Network
import Synchronization

/// A loopback HTTP server whose downloads wait for the test: `GET /<name>/<size>` answers 200 with the attachment
/// headers at once and then sends nothing until `release` hands it bytes, so a download is in progress exactly as long as
/// a test wants. `fail` drops the connection mid-way; sending every byte closes it, which completes the download.
final class HeldDownloadServer: Sendable {
  private struct Held {
    var connection: NWConnection
    var remaining: Int
  }

  let port: UInt16
  private let listener: NWListener
  private let queue = DispatchQueue(label: "arkt.held-download-server")
  private let held = Mutex<[String: Held]>([:])

  private init(listener: NWListener, port: UInt16) {
    self.listener = listener
    self.port = port
  }

  static func start() async throws -> HeldDownloadServer {
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    let listener = try NWListener(using: parameters)
    let box = Mutex<HeldDownloadServer?>(nil)
    let queue = DispatchQueue(label: "arkt.held-download-listener")
    listener.newConnectionHandler = { connection in
      connection.start(queue: queue)
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let path = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
        box.withLock { $0 }?.accept(connection, path: path)
      }
    }
    listener.start(queue: queue)
    let deadline = ContinuousClock.now + .seconds(5)
    while listener.port == nil || listener.port?.rawValue == 0 {
      if ContinuousClock.now > deadline { listener.cancel(); throw URLError(.cannotConnectToHost) }
      try await Task.sleep(for: .milliseconds(10))
    }
    let server = HeldDownloadServer(listener: listener, port: listener.port!.rawValue)
    box.withLock { $0 = server }
    return server
  }

  func url(name: String, size: Int) -> URL {
    URL(string: "http://127.0.0.1:\(port)/\(name)/\(size)")!
  }

  private func accept(_ connection: NWConnection, path: String) {
    let parts = path.split(separator: "/").map(String.init)
    guard parts.count == 2, let size = Int(parts[1]) else {
      connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                      completion: .contentProcessed { _ in connection.cancel() })
      return
    }
    let name = parts[0]
    held.withLock { $0[name] = Held(connection: connection, remaining: size) }
    let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\n"
      + "Content-Disposition: attachment; filename=\"\(name)\"\r\nConnection: close\r\n\r\n"
    connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
  }

  /// Sends `count` more bytes of the held response to `name`; the last ones end it.
  func release(_ name: String, _ count: Int) {
    let step = held.withLock { state -> (NWConnection, Int, Bool)? in
      guard var entry = state[name] else { return nil }
      let send = min(count, entry.remaining)
      entry.remaining -= send
      let done = entry.remaining == 0
      if done { state[name] = nil } else { state[name] = entry }
      return (entry.connection, send, done)
    }
    guard let (connection, send, done) = step else { return }
    connection.send(content: Data(count: send), completion: .contentProcessed { _ in
      if done { connection.cancel() }
    })
  }

  /// Drops the connection with bytes still owed: the download fails.
  func fail(_ name: String) {
    let connection = held.withLock { $0.removeValue(forKey: name)?.connection }
    connection?.forceCancel()
  }

  func stop() {
    let all = held.withLock { state -> [NWConnection] in
      defer { state = [:] }
      return state.values.map(\.connection)
    }
    for connection in all { connection.forceCancel() }
    listener.cancel()
  }
}
