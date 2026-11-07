import ArcImport
import Testing

struct SecretBytesTests {
  @Test func exposesTheBytesItWasGiven() {
    let secret = SecretBytes(taking: Array("hunter2".utf8))
    #expect(secret.count == 7)
    #expect(!secret.isEmpty)
    #expect(secret.withBytes { Array($0) } == Array("hunter2".utf8))
    #expect(secret.utf8String() == "hunter2")
  }

  @Test func wipeZeroesTheBytesInPlace() {
    let secret = SecretBytes(taking: Array("hunter2".utf8))
    secret.wipe()
    #expect(secret.count == 7)
    #expect(secret.withBytes { Array($0) } == [UInt8](repeating: 0, count: 7))
  }

  @Test func emptySecretIsSafe() {
    let secret = SecretBytes(taking: [])
    #expect(secret.isEmpty)
    #expect(secret.utf8String() == "")
    secret.wipe()
  }

  @Test func descriptionsNeverShowTheBytes() {
    let secret = SecretBytes(taking: Array("hunter2".utf8))
    #expect(!String(describing: secret).contains("hunter2"))
    #expect(!String(reflecting: secret).contains("hunter2"))
    #expect(!"\(secret)".contains("hunter2"))
  }
}
