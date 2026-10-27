import CoreGraphics
import EngineAPI
import Foundation
import Testing
@testable import ShellUI

/// #116: the saved main window state (frame and screen, Space, current tab, each Space's selected tab) and where a
/// saved frame lands on the screens that exist at the next launch.
@MainActor
struct WindowSessionTests {
  private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "WindowSessionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { UserDefaults().removePersistentDomain(forName: name) }
    try body(defaults)
  }

  private static let space = UUID()
  private static let otherSpace = UUID()
  private static let tab = UUID()
  private static let otherTab = UUID()

  private func sample() -> WindowSessionState {
    WindowSessionState(frame: CGRect(x: 120, y: 80, width: 900, height: 640),
                       screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                       space: Self.space, currentTab: Self.tab,
                       selectedTabs: [Self.space: Self.tab, Self.otherSpace: Self.otherTab])
  }

  // MARK: Store

  @Test func nothingSavedReadsAsNil() {
    withSuite { defaults in
      #expect(WindowSessionStore(defaults: defaults).load() == nil)
    }
  }

  @Test func aSavedStateRoundTrips() {
    withSuite { defaults in
      let store = WindowSessionStore(defaults: defaults)
      store.save(sample())
      #expect(store.load() == sample())
      #expect(WindowSessionStore(defaults: defaults).load() == sample(), "a new store over the same defaults")
    }
  }

  @Test func aStateWithoutASpaceOrTabRoundTrips() {
    withSuite { defaults in
      let store = WindowSessionStore(defaults: defaults)
      let bare = WindowSessionState(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
      store.save(bare)
      #expect(store.load() == bare)
    }
  }

  @Test func theLatestSaveWins() {
    withSuite { defaults in
      let store = WindowSessionStore(defaults: defaults)
      store.save(sample())
      var later = sample()
      later.space = Self.otherSpace
      later.currentTab = nil
      store.save(later)
      #expect(store.load() == later)
    }
  }

  @Test func unreadableDataReadsAsNil() {
    withSuite { defaults in
      defaults.set(Data("not json".utf8), forKey: WindowSessionStore.defaultsKey)
      #expect(WindowSessionStore(defaults: defaults).load() == nil)
      defaults.set("a string", forKey: WindowSessionStore.defaultsKey)
      #expect(WindowSessionStore(defaults: defaults).load() == nil)
    }
  }

  @Test func aFrameThatIsEmptyOrNotFiniteReadsAsNil() {
    withSuite { defaults in
      let store = WindowSessionStore(defaults: defaults)
      store.save(WindowSessionState(frame: CGRect(x: 0, y: 0, width: 0, height: 600)))
      #expect(store.load() == nil)
      store.save(WindowSessionState(frame: CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600)))
      #expect(store.load() == nil)
    }
  }

  @Test func theEphemeralStoreNeverTouchesDefaults() {
    withSuite { defaults in
      let store = WindowSessionStore.ephemeral()
      store.save(sample())
      #expect(store.load() == nil)
      #expect(defaults.object(forKey: WindowSessionStore.defaultsKey) == nil)
    }
  }

  // MARK: Frame placement

  private static let minSize = CGSize(width: 640, height: 420)
  private static let main = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                           visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
  private static let right = ScreenGeometry(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                            visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055))

  private func place(_ saved: CGRect, on savedScreen: CGRect? = nil, in screens: [ScreenGeometry]) -> CGRect? {
    WindowFramePlacement.restoredFrame(saved: saved, savedScreen: savedScreen, screens: screens,
                                       minSize: Self.minSize)
  }

  @Test func aFrameInsideAScreenIsKept() {
    let saved = CGRect(x: 100, y: 100, width: 900, height: 600)
    #expect(place(saved, in: [Self.main]) == saved)
  }

  @Test func aFrameOnASecondScreenStaysThere() {
    let saved = CGRect(x: 1600, y: 200, width: 1000, height: 700)
    #expect(place(saved, on: Self.right.frame, in: [Self.main, Self.right]) == saved)
  }

  @Test func aFrameFullyOffEveryScreenIsMovedOntoTheMainScreen() throws {
    let saved = CGRect(x: 5000, y: 4000, width: 900, height: 600)
    let placed = try #require(place(saved, in: [Self.main]))
    #expect(placed.size == saved.size)
    #expect(Self.main.visibleFrame.contains(placed))
    #expect(placed == CGRect(x: 540, y: 275, width: 900, height: 600), "against the nearest corner")
  }

  @Test func aFramePartlyOffAScreenIsShiftedBackIn() throws {
    let saved = CGRect(x: -300, y: 600, width: 900, height: 600)
    let placed = try #require(place(saved, in: [Self.main]))
    #expect(placed == CGRect(x: 0, y: 275, width: 900, height: 600))
  }

  @Test func aFrameBiggerThanTheScreenIsShrunkToIt() throws {
    let saved = CGRect(x: 0, y: 0, width: 3000, height: 2000)
    let placed = try #require(place(saved, in: [Self.main]))
    #expect(placed == Self.main.visibleFrame)
  }

  @Test func aFrameNeverShrinksBelowTheWindowMinimum() throws {
    let tiny = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 500, height: 400),
                              visibleFrame: CGRect(x: 0, y: 0, width: 500, height: 380))
    let placed = try #require(place(CGRect(x: 0, y: 0, width: 900, height: 600), in: [tiny]))
    #expect(placed.size == Self.minSize, "the window has a minimum size; it may overhang a tiny screen")
    #expect(placed.origin == CGPoint(x: 0, y: 0))
  }

  @Test func aDisconnectedScreenFallsBackToTheFirstScreen() throws {
    let saved = CGRect(x: 1600, y: 200, width: 1000, height: 700)
    let placed = try #require(place(saved, on: Self.right.frame, in: [Self.main]))
    #expect(Self.main.visibleFrame.contains(placed))
    #expect(placed.size == saved.size)
  }

  @Test func aFrameOffEveryScreenGoesToTheSavedScreenWhenItStillExists() throws {
    // The screens were rearranged: the saved window is nowhere visible, but its screen is still connected.
    let moved = ScreenGeometry(frame: CGRect(x: 3000, y: 0, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: 3000, y: 0, width: 1920, height: 1055))
    let saved = CGRect(x: 1600, y: 200, width: 1000, height: 700)
    let placed = try #require(place(saved, on: moved.frame, in: [Self.main, moved]))
    #expect(moved.visibleFrame.contains(placed))
  }

  @Test func theScreenWithTheMostOverlapWins() throws {
    // Straddles both screens, mostly on the second.
    let saved = CGRect(x: 1240, y: 100, width: 1000, height: 600)
    let placed = try #require(place(saved, in: [Self.main, Self.right]))
    #expect(Self.right.visibleFrame.contains(placed))
  }

  @Test func noScreensOrAnEmptyFrameGivesNoPlacement() {
    #expect(place(CGRect(x: 0, y: 0, width: 900, height: 600), in: []) == nil)
    #expect(place(.zero, in: [Self.main]) == nil)
    #expect(place(CGRect(x: CGFloat.infinity, y: 0, width: 900, height: 600), in: [Self.main]) == nil)
  }

  // MARK: Which window owns the session

  private func request(_ kind: EngineWindowRequestKind, opener: EngineWindowID? = nil,
                       bounds: CGRect? = nil) -> EngineWindowRequest {
    EngineWindowRequest(kind: kind, openerWindow: opener, bounds: bounds, profile: EngineProfileID("default"))
  }

  @Test func engineRequestedWindowsNeverOwnTheSession() {
    for kind in [EngineWindowRequestKind.extension, .page, .startupURL] {
      let origin = SessionWindowPolicy.origin(for: request(kind, bounds: CGRect(x: 0, y: 0, width: 400, height: 300)))
      #expect(origin == .engineRequested)
      #expect(!SessionWindowPolicy.takesSession(origin, ownerIsAlive: false))
    }
    // A page's new window without features is a reopen request with an opener.
    #expect(SessionWindowPolicy.origin(for: request(.reopen, opener: EngineWindowID())) == .engineRequested)
  }

  @Test func theShellsOwnWindowsAndADockReopenCanOwnItWhenNoneDoes() {
    #expect(SessionWindowPolicy.origin(for: request(.reopen)) == .dockReopen)
    for origin in [SessionWindowOrigin.shell, .dockReopen] {
      #expect(SessionWindowPolicy.takesSession(origin, ownerIsAlive: false))
      #expect(!SessionWindowPolicy.takesSession(origin, ownerIsAlive: true), "a live owner keeps it")
    }
    #expect(!SessionWindowPolicy.takesSession(.dragOut, ownerIsAlive: false))
  }

  // MARK: Full screen

  @Test func aFullScreenWindowSavesItsWindowedFrame() {
    let windowed = CGRect(x: 100, y: 100, width: 900, height: 600)
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let state = WindowSessionState.capturing(frame: screen, windowedFrame: windowed, isFullScreen: true,
                                             screenFrame: screen, space: nil, currentTab: nil, selectedTabs: [:])
    #expect(state.frame == windowed)
    #expect(state.isFullScreen)
    let plain = WindowSessionState.capturing(frame: windowed, windowedFrame: nil, isFullScreen: false,
                                             screenFrame: screen, space: nil, currentTab: nil, selectedTabs: [:])
    #expect(plain.frame == windowed)
    #expect(!plain.isFullScreen)
  }

  @Test func aStateSavedBeforeTheFullScreenFlagStillLoads() throws {
    let old = #"{"frame":[[10,20],[800,600]],"selectedTabs":[]}"#
    let state = try JSONDecoder().decode(WindowSessionState.self, from: Data(old.utf8))
    #expect(!state.isFullScreen)
  }
}
