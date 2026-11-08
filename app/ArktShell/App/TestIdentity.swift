#if DEBUG
import CryptoKit
import Foundation

/// Debug-only, plain-value identity of the effective test environment. Raw values never leave the process.
enum TestIdentity {
  static let endpointKey = "ARKT_TEST_IDENTITY_ENDPOINT"
  static let keys = ["ARKT_UITEST", "ARKT_DATA_DIR", "ARKT_ARC_DIR", "ARKT_DEFAULTS_SUITE",
                     "ARKT_SKIP_ONBOARDING", "ARKT_DEFAULT_BROWSER"]
  enum Invalid: Error { case identity }

  struct Report: Codable, Equatable, Sendable {
    let nonce: String
    let pid: Int32
    let required: Bool
    let digest: String
    var isValid: Bool { TestIdentity.validNonce(nonce) && pid > 0 && required && TestIdentity.validHex(digest, count: 64) }
  }
  struct Request: Equatable, Sendable {
    let url: URL
    let report: Report
  }
  private static func validHex(_ value: String, count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
  static func validNonce(_ nonce: String) -> Bool { validHex(nonce, count: 32) }

  static func digest(_ environment: [String: String]) throws -> String {
    guard keys.prefix(4).allSatisfy({ !(environment[$0] ?? "").isEmpty }) else { throw Invalid.identity }
    // An array of optional values distinguishes a missing value from an empty string, in a fixed key order.
    let values = keys.map { environment[$0] }
    let bytes = try JSONEncoder().encode(values)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  static func endpoint(_ text: String) -> (url: URL, nonce: String)? {
    guard let components = URLComponents(string: text), components.scheme == "http",
          components.host == "127.0.0.1", components.user == nil, components.password == nil,
          components.query == nil, components.fragment == nil, let port = components.port, (1...65535).contains(port),
          components.percentEncodedPath.hasPrefix("/identity/") else { return nil }
    let nonce = String(components.percentEncodedPath.dropFirst("/identity/".count))
    guard validNonce(nonce), text == "http://127.0.0.1:\(port)/identity/\(nonce)", let url = components.url else { return nil }
    return (url, nonce)
  }

  static func request(environment: [String: String], required: Bool, pid: Int32) throws -> Request? {
    guard let text = environment[endpointKey] else { return nil }
    guard let endpoint = endpoint(text) else { throw Invalid.identity }
    let report = Report(nonce: endpoint.nonce, pid: pid, required: required, digest: try digest(environment))
    guard report.isValid else { throw Invalid.identity }
    return Request(url: endpoint.url, report: report)
  }

  static func acknowledged(status: Int, redirected: Bool) -> Bool { status == 204 && !redirected }

  static func send(_ request: Request) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
    let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var message = URLRequest(url: request.url)
    message.httpMethod = "POST"
    message.setValue("application/json", forHTTPHeaderField: "Content-Type")
    message.httpBody = try JSONEncoder().encode(request.report)
    let (_, response) = try await session.data(for: message)
    guard let http = response as? HTTPURLResponse, acknowledged(status: http.statusCode, redirected: false),
          http.url == request.url else { throw Invalid.identity }
  }

  private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
      completionHandler(nil)
    }
  }
}
#endif
