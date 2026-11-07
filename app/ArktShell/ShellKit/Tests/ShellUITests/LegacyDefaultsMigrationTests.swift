import Foundation
import Testing

// `LegacyDefaultsMigration` is the app target's file (`App/LegacyDefaultsMigration.swift`), compiled here through the
// symlink next to this file: the app has no test target, and the copy is pure over the two suites it is given.

@Suite struct LegacyDefaultsMigrationTests {
  private let oldName = "dev.arkt.test.legacy.\(UUID().uuidString)"
  private let newName = "dev.arkt.test.current.\(UUID().uuidString)"

  private func suites() throws -> (old: UserDefaults, new: UserDefaults) {
    let old = try #require(UserDefaults(suiteName: oldName))
    let new = try #require(UserDefaults(suiteName: newName))
    return (old, new)
  }

  private func clean() {
    UserDefaults().removePersistentDomain(forName: oldName)
    UserDefaults().removePersistentDomain(forName: newName)
  }

  private func migration(_ old: UserDefaults, _ new: UserDefaults) -> LegacyDefaultsMigration {
    LegacyDefaultsMigration(legacy: old, legacyDomain: oldName, current: new, currentDomain: newName)
  }

  @Test func copiesEveryKeyWhenTheOldDomainHasValues() throws {
    defer { clean() }
    let (old, new) = try suites()
    old.set(true, forKey: "topBarURLEnabled")
    old.set("peek", forKey: "routing")
    old.set([1, 2], forKey: "list")

    #expect(migration(old, new).runIfNeeded())

    #expect(new.bool(forKey: "topBarURLEnabled"))
    #expect(new.string(forKey: "routing") == "peek")
    #expect(new.array(forKey: "list") as? [Int] == [1, 2])
    #expect(new.bool(forKey: LegacyDefaultsMigration.flagKey))
  }

  @Test func leavesTheOldDomainIntact() throws {
    defer { clean() }
    let (old, new) = try suites()
    old.set("kept", forKey: "key")

    _ = migration(old, new).runIfNeeded()

    #expect(old.string(forKey: "key") == "kept")
    #expect(old.persistentDomain(forName: oldName)?.count == 1)
  }

  @Test func doesNotOverwriteKeysThatAlreadyExist() throws {
    defer { clean() }
    let (old, new) = try suites()
    old.set("old", forKey: "shared")
    old.set("only-old", forKey: "legacyOnly")
    new.set("new", forKey: "shared")

    _ = migration(old, new).runIfNeeded()

    #expect(new.string(forKey: "shared") == "new")
    #expect(new.string(forKey: "legacyOnly") == "only-old")
  }

  @Test func runsOnce() throws {
    defer { clean() }
    let (old, new) = try suites()
    old.set("first", forKey: "key")
    let migration = migration(old, new)
    #expect(migration.runIfNeeded())

    new.removeObject(forKey: "key")
    old.set("second", forKey: "later")

    #expect(!migration.runIfNeeded())
    #expect(new.object(forKey: "key") == nil)
    #expect(new.object(forKey: "later") == nil)
  }

  @Test func doesNothingWhenTheOldDomainIsEmpty() throws {
    defer { clean() }
    let (old, new) = try suites()

    #expect(!migration(old, new).runIfNeeded())

    #expect(new.persistentDomain(forName: newName) == nil)
    #expect(!new.bool(forKey: LegacyDefaultsMigration.flagKey))
  }
}
