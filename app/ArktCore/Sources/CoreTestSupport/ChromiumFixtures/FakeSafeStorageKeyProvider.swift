import ArcImport
import Foundation

/// A Safe Storage provider for tests: hands out a fixed password or throws a fixed failure. Never touches the Keychain.
public struct FakeSafeStorageKeyProvider: SafeStorageKeyProvider {
  private let outcome: Result<[UInt8], SafeStorageError>

  public init(password: String) { outcome = .success(Array(password.utf8)) }
  public init(failure: SafeStorageError) { outcome = .failure(failure) }

  public func withPassword<R>(_ body: ([UInt8]) throws -> R) throws -> R {
    try body(outcome.get())
  }
}
