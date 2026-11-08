import CoreGraphics
import EngineAPI
import Foundation
import Testing
@testable import ShellUI

/// #116: the persisted collection is independent of window and engine lifetimes.
@MainActor
struct MultiWindowSessionTests {
  private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "MultiWindowSessionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { UserDefaults().removePersistentDomain(forName: name) }
    try body(defaults)
  }

  private func window(_ x: CGFloat, space: SpaceID, tab: NodeID,
                      collapsed: Set<NodeID>) -> WindowSessionState {
    var state = WindowSessionState(frame: CGRect(x: x, y: 80, width: 900, height: 640),
                                   space: space, currentTab: tab, selectedTabs: [space: tab])
    state.collapsedFolderIDs = collapsed
    return state
  }

  @Test func multipleWindowsAndTheirFolderStatesRoundTrip() throws {
    try withSuite { defaults in
      let space = UUID(), tab = UUID(), folder = UUID(), otherFolder = UUID()
      let first = window(100, space: space, tab: tab, collapsed: [folder])
      let second = window(1100, space: space, tab: tab, collapsed: [otherFolder])
      WindowSessionStore(defaults: defaults).saveWindows([first, second])

      let restored = try #require(WindowSessionStore(defaults: defaults).loadWindows())
      #expect(restored == [first, second])
      try #require(restored.count == 2)
      #expect(restored[0].collapsedFolderIDs == [folder])
      #expect(restored[1].collapsedFolderIDs == [otherFolder])
    }
  }

  @Test func latestCollectionReplacesEarlierWindows() {
    withSuite { defaults in
      let space = UUID(), tab = UUID()
      let first = window(100, space: space, tab: tab, collapsed: [])
      let second = window(1100, space: space, tab: tab, collapsed: [UUID()])
      let store = WindowSessionStore(defaults: defaults)
      store.saveWindows([first, second])
      store.saveWindows([second])
      #expect(WindowSessionStore(defaults: defaults).loadWindows() == [second])
    }
  }

  @Test func legacySingleWindowLoadsAsOneWindowWithDefaultFolderState() throws {
    try withSuite { defaults in
      let legacy = WindowSessionState(frame: CGRect(x: 100, y: 80, width: 900, height: 640),
                                      space: UUID(), currentTab: UUID())
      WindowSessionStore(defaults: defaults).save(legacy)
      let restored = try #require(WindowSessionStore(defaults: defaults).loadWindows())
      #expect(restored == [legacy])
      #expect(restored.first?.collapsedFolderIDs == [])
    }
  }

  @Test func savedEmptyCollectionDoesNotResurrectLegacyWindow() {
    withSuite { defaults in
      let legacy = WindowSessionState(frame: CGRect(x: 100, y: 80, width: 900, height: 640))
      let store = WindowSessionStore(defaults: defaults)
      store.save(legacy)
      store.saveWindows([])
      #expect(WindowSessionStore(defaults: defaults).loadWindows() == [])
    }
  }

  @Test func noSavedCollectionOrLegacyWindowReadsAsNil() {
    withSuite { defaults in
      #expect(WindowSessionStore(defaults: defaults).loadWindows() == nil)
    }
  }

  @Test func oldEncodedStateDefaultsCollapsedFoldersToEmpty() throws {
    let old = #"{"frame":[[10,20],[800,600]],"selectedTabs":[]}"#
    let state = try JSONDecoder().decode(WindowSessionState.self, from: Data(old.utf8))
    #expect(state.collapsedFolderIDs.isEmpty)
  }

  @Test func malformedOrUnsupportedCollectionDoesNotResurrectLegacy() {
    withSuite { defaults in
      let store = WindowSessionStore(defaults: defaults)
      store.save(WindowSessionState(frame: CGRect(x: 0, y: 0, width: 800, height: 600)))
      for data in [Data("invalid".utf8), Data(#"{"version":2,"windows":[]}"#.utf8),
                   Data(#"{"version":1,"windows":[{}]}"#.utf8)] {
        defaults.set(data, forKey: WindowSessionStore.windowsDefaultsKey)
        #expect(store.loadWindows() == nil)
      }
      defaults.set("invalid", forKey: WindowSessionStore.windowsDefaultsKey)
      #expect(store.loadWindows() == nil)
    }
  }

  @Test func invalidFrameRejectsWholeCollectionAndInvalidLegacyDoesNotMigrate() {
    withSuite { defaults in
      let store = WindowSessionStore(defaults: defaults)
      let valid = WindowSessionState(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
      let invalid = WindowSessionState(frame: .zero)
      store.save(invalid)
      #expect(store.loadWindows() == nil)
      store.save(valid)
      store.saveWindows([valid, invalid])
      #expect(store.loadWindows() == nil)
    }
  }

  @Test func ephemeralCollectionDoesNotPersist() {
    let store = WindowSessionStore.ephemeral()
    store.saveWindows([])
    #expect(store.loadWindows() == nil)
  }

}
