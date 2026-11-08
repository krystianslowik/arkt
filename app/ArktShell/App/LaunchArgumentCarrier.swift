#if DEBUG
import Foundation

/// Pure transport only. `required` must come from the bundle, never from this argument or its payload.
enum LaunchArgumentCarrier {
  enum Invalid: Error { case carrier }
  private static let name = "--arkt-ui-test-config"
  private static let prefix = name + "=v1:"
  private static let maxValueBytes = 4096
  private static let maxArgumentBytes = 32_768
  private static var allowed: Set<String> { Set(TestIdentity.keys + [TestIdentity.endpointKey]) }

  static func encode(_ values: [String: String], bundleIdentifier: String?) throws -> String {
    try validate(values, bundleIdentifier: bundleIdentifier)
    let pairs = values.sorted { $0.key < $1.key }.map { [$0.key, $0.value] }
    let argument = prefix + (try JSONEncoder().encode(pairs)).base64EncodedString()
    guard argument.utf8.count <= maxArgumentBytes else { throw Invalid.carrier }
    return argument
  }

  /// Nil means no carrier: the caller must retain the existing environment-only startup policy.
  /// A carrier owns every known key: process values may agree, but may not fill omissions or conflict.
  static func decode(arguments: [String], environment: [String: String], required: Bool,
                     bundleIdentifier: String?) throws -> [String: String]? {
    let matches = arguments.filter { $0.hasPrefix(name) }
    guard !matches.isEmpty else { return nil }
    guard required, matches.count == 1, let argument = matches.first,
          argument.utf8.count <= maxArgumentBytes, argument.hasPrefix(prefix),
          let data = Data(base64Encoded: String(argument.dropFirst(prefix.count))),
          let pairs = try? JSONDecoder().decode([[String]].self, from: data) else { throw Invalid.carrier }
    var values: [String: String] = [:]
    for pair in pairs {
      guard pair.count == 2, allowed.contains(pair[0]), values[pair[0]] == nil else { throw Invalid.carrier }
      values[pair[0]] = pair[1]
    }
    // Enforce one wire representation, including order, JSON structure and base64 spelling.
    guard try encode(values, bundleIdentifier: bundleIdentifier) == argument else { throw Invalid.carrier }
    for key in allowed {
      if let processValue = environment[key], values[key] != processValue { throw Invalid.carrier }
    }
    return values
  }

  private static func validate(_ values: [String: String], bundleIdentifier: String?) throws {
    guard Set(values.keys).isSubset(of: allowed),
          values.values.allSatisfy({ $0.utf8.count <= maxValueBytes && !$0.contains("\0") }),
          values[EnvironmentOverrides.uiTestKey] == "1",
          values[EnvironmentOverrides.skipOnboardingKey].map({ ["", "0", "1"].contains($0) }) ?? true,
          values[EnvironmentOverrides.defaultBrowserKey].map({ ["", "default", "notDefault"].contains($0) }) ?? true,
          EnvironmentOverrides(environment: values).uiTestStartupViolations(required: true,
            bundleIdentifier: bundleIdentifier).isEmpty,
          let endpoint = values[TestIdentity.endpointKey], TestIdentity.endpoint(endpoint) != nil else {
      throw Invalid.carrier
    }
    _ = try TestIdentity.digest(values)
  }
}
#endif
