import CoreGraphics
import EngineAPI
import Foundation
import Testing
@testable import ShellUI

@MainActor
struct WindowSessionCompatibilityTests {
  @Test func preCollectionEncoderPayloadMigratesEveryField() throws {
    // Frozen JSONEncoder output from WindowSessionState at 01b1de2, before collapsedFolderIDs existed.
    let payload = #"{"currentTab":"22222222-2222-2222-2222-222222222222","frame":[[10,20],[800,600]],"isFullScreen":true,"screenFrame":[[0,0],[1920,1080]],"selectedTabs":["11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222"],"space":"11111111-1111-1111-1111-111111111111"}"#
    let name = "WindowSessionCompatibilityTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { UserDefaults().removePersistentDomain(forName: name) }
    defaults.set(Data(payload.utf8), forKey: WindowSessionStore.defaultsKey)
    let space = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let tab = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let expected = WindowSessionState(frame: CGRect(x: 10, y: 20, width: 800, height: 600),
      screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), space: space, currentTab: tab,
      selectedTabs: [space: tab], isFullScreen: true)
    #expect(WindowSessionStore(defaults: defaults).loadWindows() == [expected])
  }

  @Test func nonfiniteEncodingFailurePreservesPreviousCollectionWhileStoredInvalidFrameIsRejected() throws {
    let name = "WindowSessionCompatibilityTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { UserDefaults().removePersistentDomain(forName: name) }
    let store = WindowSessionStore(defaults: defaults)
    let valid = WindowSessionState(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    store.saveWindows([valid])
    let previous = try #require(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey))
    let nonfinite = WindowSessionState(frame: CGRect(x: CGFloat.infinity, y: 0, width: 800, height: 600))
    store.saveWindows([nonfinite])
    #expect(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey) == previous)
    #expect(store.loadWindows() == [valid])
    let zero = WindowSessionState(frame: .zero)
    store.saveWindows([zero])
    #expect(defaults.data(forKey: WindowSessionStore.windowsDefaultsKey) != previous)
    #expect(store.loadWindows() == nil)
    // Persisted invalid data is rejected even when a valid legacy value exists.
    store.save(valid)
    for frame in ["[[0,0],[0,600]]", "[[0,0],[-1,600]]", "[[1e999,0],[800,600]]"] {
      let payload = "{\"version\":1,\"windows\":[{\"frame\":\(frame)}]}"
      defaults.set(Data(payload.utf8), forKey: WindowSessionStore.windowsDefaultsKey)
      #expect(store.loadWindows() == nil)
    }
  }
}
