import Foundation
import Testing
@testable import ShellUI

@Suite @MainActor
struct WindowSessionObservationTests {
  @Test func actualStoreAndImmutableInitial() throws {
    let suite = "dev.arkt.observation-test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = WindowSessionStore(defaults: defaults)
    let observer = WindowSessionObservation(read: { store.rawCollectionValue }, launchID: "first")
    #expect(observer.snapshot.initial == .absent)
    defaults.set("wrong", forKey: WindowSessionStore.windowsDefaultsKey)
    #expect(observer.snapshot.current == .nonData)
    let malformed = Data([0, 255, 42])
    defaults.set(malformed, forKey: WindowSessionStore.windowsDefaultsKey)
    #expect(observer.snapshot.current == .data(malformed))
    #expect(observer.snapshot.initial == .absent)
    #expect(defaults.object(forKey: WindowSessionStore.windowsDefaultsKey) as? Data == malformed)
    #expect(!observer.snapshot.launchComplete)
    observer.finishLaunch()
    #expect(observer.snapshot.launchComplete)
    #expect(observer.snapshot.launchID == "first")
    let second = WindowSessionObservation(read: { store.rawCollectionValue }, launchID: "second")
    #expect(second.snapshot.initial == .data(malformed))
    #expect(second.snapshot.launchID != observer.snapshot.launchID)
    let encoded = try observer.snapshot.json()
    #expect(try WindowSessionObservation.Report.decode(encoded) == observer.snapshot)
    #expect(throws: (any Error).self) { try WindowSessionObservation.Report.decode("invalid") }
  }

  @Test func actualCollectionSaveIsObservable() throws {
    let suite = "dev.arkt.observation-test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = WindowSessionStore(defaults: defaults)
    let observer = WindowSessionObservation(read: { store.rawCollectionValue }, launchID: "save")
    let spaces = [UUID(), UUID()]
    let tabs = [UUID(), UUID()]
    let states = [WindowSessionState(frame: CGRect(x: 1, y: 2, width: 300, height: 400),
                                     space: spaces[0], currentTab: tabs[0]),
                  WindowSessionState(frame: CGRect(x: 5, y: 6, width: 300, height: 400),
                                     space: spaces[1], currentTab: tabs[1])]
    store.saveWindows(states)
    guard case .data(let data) = observer.snapshot.current else { Issue.record("missing saved data"); return }
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let windows = try #require(object["windows"] as? [[String: Any]])
    #expect(windows.count == 2)
    guard windows.count == 2 else { return }
    for index in 0..<2 {
      #expect(windows[index]["space"] as? String == spaces[index].uuidString)
      #expect(windows[index]["currentTab"] as? String == tabs[index].uuidString)
    }
  }
}
