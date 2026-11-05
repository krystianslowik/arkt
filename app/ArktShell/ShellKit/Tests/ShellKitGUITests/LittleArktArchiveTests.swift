import AppKit
@testable import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Little Arkt archive (#355): the user's close (close button, Cmd-W) and the idle timer archive the page under the
/// Little Arkt source (BH-138, KB-080, BH-137); a page that closes its own popup, or a quit, archives nothing; and
/// Reopen Closed Tab brings the last closed Little Arkt window back at its last frame.
@MainActor
final class LittleArktArchiveTests: XCTestCase {
  private var sets: [ShellWindowSet] = []
  private let popupURL = URL(string: "arkt-test://page/SignIn")!
  private var clock = Date(timeIntervalSinceReferenceDate: 900_000_000)
  private var archived: [LittleArktClosedWindow] = []
  private var takenBack: [UUID] = []
  /// Archive entries the take-back refuses (restored from the Archive meanwhile).
  private var restoredEntries: Set<UUID> = []
  private var archiveIDs: [UUID] = []

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    archived = []
    takenBack = []
    restoredEntries = []
    archiveIDs = []
  }

  override func tearDown() async throws {
    for set in sets {
      for controller in set.controllers { controller.window?.orderOut(nil) }
      for little in set.littleArkts { little.window.orderOut(nil) }
    }
    sets = []
  }

  private func makeSet() throws -> (set: ShellWindowSet, engine: InMemoryEngine) {
    let engine = InMemoryEngine()
    let world = try EngineWorld.make()
    let source = ModelSidebarSource(sidebar: world.sidebar, now: { EngineWorld.now })
    let set = ShellWindowSet(engine: engine, sidebar: source, hostLookup: { [engine] in engine.host(of: $0) })
    set.littleArktReduceMotion = { false }
    set.littleArktConfigure = { $0.drivesDisplayLink = false }           // motion is stepped by hand
    set.littleArktNow = { [unowned self] in self.clock }
    set.littleArktIsInUse = { _ in false }
    set.onLittleArktArchive = { [unowned self] page in
      self.archived.append(page)
      let id = UUID()
      self.archiveIDs.append(id)
      return id
    }
    set.onLittleArktTakeBack = { [unowned self] id in
      guard !self.restoredEntries.contains(id) else { return false }
      self.takenBack.append(id)
      return true
    }
    engine.windowHostProvider = { [weak set] request in
      guard let set else { preconditionFailure("the set outlives the test") }
      return set.host(for: request)
    }
    sets.append(set)
    return (set, engine)
  }

  private func openPopup(_ engine: InMemoryEngine, _ set: ShellWindowSet) throws
    -> (LittleArktWindowController, EngineWindowID, TabID) {
    let request = EngineWindowRequest(kind: .page, bounds: nil, profile: EngineProfileID("default"),
                                      initialURL: popupURL, isPopup: true)
    let id = try XCTUnwrap(engine.openEngineWindow(request))
    let little = try XCTUnwrap(set.littleArkts.first { $0.engineWindow == id })
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    engine.finishLoad(tab, title: "Sign in")
    little.finishMotion()
    return (little, id, tab)
  }

  // MARK: Archive on close (BH-138, KB-080)

  func testTheCloseButtonArchivesThePageUnderLittleArkt() throws {
    let (set, engine) = try makeSet()
    let (little, id, _) = try openPopup(engine, set)

    little.window.performClose(nil)
    little.finishMotion()

    XCTAssertFalse(engine.windowIDs.contains(id))
    XCTAssertTrue(little.isClosed)
    XCTAssertEqual(archived.map(\.url), [popupURL])
    XCTAssertEqual(archived.map(\.title), ["Sign in"])
    XCTAssertEqual(archived.map(\.isIdle), [false])
  }

  func testCommandWArchivesThePage() throws {
    let (set, engine) = try makeSet()
    let (little, _, _) = try openPopup(engine, set)

    little.closeTab(nil)
    little.finishMotion()

    XCTAssertEqual(archived.map(\.url), [popupURL])
    XCTAssertEqual(archived.first?.isIdle, false)
  }

  func testThePageClosingItsPopupIsNotArchived() throws {
    let (set, engine) = try makeSet()
    let (little, id, _) = try openPopup(engine, set)

    engine.closeWindow(id)                                  // window.close() in the page
    little.finishMotion()

    XCTAssertTrue(little.isClosed)
    XCTAssertTrue(archived.isEmpty)
    XCTAssertFalse(set.canReopenClosedLittleArkt, "nothing the user closed")
  }

  func testAQuitClosingTheWindowArchivesNothing() throws {
    let (set, engine) = try makeSet()
    let (little, id, _) = try openPopup(engine, set)

    engine.engineCloseWindow(id, reason: .appQuit)
    little.finishMotion()

    XCTAssertTrue(little.isClosed)
    XCTAssertTrue(archived.isEmpty)
  }

  func testALeaveSitePromptTheUserConfirmsStillArchives() throws {
    let (set, engine) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)

    little.closeTab(nil)
    XCTAssertTrue(archived.isEmpty, "nothing archived while the page asks")
    XCTAssertTrue(engine.answerDialog(tab, accept: true))
    little.finishMotion()

    XCTAssertFalse(engine.windowIDs.contains(id))
    XCTAssertEqual(archived.map(\.url), [popupURL])
  }

  func testACancelledLeaveSitePromptForgetsTheClose() throws {
    let (set, engine) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)
    XCTAssertTrue(engine.answerDialog(tab, accept: false))   // the user stays

    engine.closeWindow(id)                                  // later the page closes itself
    XCTAssertTrue(engine.answerDialog(tab, accept: true))
    little.finishMotion()

    XCTAssertTrue(little.isClosed)
    XCTAssertTrue(archived.isEmpty, "a close the user cancelled is not archived later")
  }

  func testAQuitWhileALeaveSitePromptIsUpArchivesNothing() throws {
    let (set, engine) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)                                    // the prompt is up

    engine.engineEndWindow(id, reason: .appQuit)
    little.finishMotion()

    XCTAssertTrue(little.isClosed)
    XCTAssertTrue(archived.isEmpty, "the quit closed it, not the user's Cmd-W")
    XCTAssertFalse(set.canReopenClosedLittleArkt)
  }

  func testOpenInWhileALeaveSitePromptIsUpArchivesNothing() throws {
    let (set, engine) = try makeSet()
    let (little, id, tab) = try openPopup(engine, set)
    engine.holdClose(tab)
    little.closeTab(nil)                                    // the prompt is up

    little.openIn()                                         // Open in instead: the Cmd-W is no longer the intent
    little.finishMotion()                                   // the engine does not move a closing tab: it stays here
    little.finishMotion()
    XCTAssertTrue(engine.answerDialog(tab, accept: true))   // the prompt resolves and the window goes
    little.finishMotion()

    XCTAssertFalse(engine.windowIDs.contains(id))
    XCTAssertTrue(little.isClosed)
    XCTAssertTrue(archived.isEmpty, "Open in replaced the close; nothing goes to the Archive")
    XCTAssertFalse(set.canReopenClosedLittleArkt)
  }

  // MARK: Idle (BH-137)

  func testIdleWindowsAreCandidatesFromTheirLastActivity() throws {
    let (set, engine) = try makeSet()
    let start = clock
    let (little, _, _) = try openPopup(engine, set)

    XCTAssertEqual(set.littleArktIdleCandidates().map(\.id), [little.id])
    XCTAssertEqual(set.littleArktIdleCandidates().first?.lastActiveAt, start)

    clock = start.addingTimeInterval(3600)
    little.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
    XCTAssertEqual(set.littleArktIdleCandidates().first?.lastActiveAt, start.addingTimeInterval(3600),
                   "leaving the window counts as activity")
  }

  func testAWindowInUseAPagePlayingSoundOrAskingBeforeLeavingIsNoCandidate() throws {  // BH-076
    let (set, engine) = try makeSet()
    let (inUse, _, _) = try openPopup(engine, set)
    let (audible, _, audibleTab) = try openPopup(engine, set)
    let (holding, _, holdingTab) = try openPopup(engine, set)
    let (idle, _, _) = try openPopup(engine, set)
    set.littleArktIsInUse = { $0 === inUse }
    engine.setAudible(audibleTab, true)
    engine.holdClose(holdingTab)

    XCTAssertEqual(set.littleArktIdleCandidates().map(\.id), [idle.id])
    _ = (audible, holding)
  }

  func testIdleTimeStartsAgainWhenAPageStopsPlaying() throws {  // not closed the moment the sound ends
    let (set, engine) = try makeSet()
    let start = clock
    let (little, _, tab) = try openPopup(engine, set)
    engine.setAudible(tab, true)
    clock = start.addingTimeInterval(7 * 3600)
    XCTAssertTrue(set.littleArktIdleCandidates().isEmpty)

    engine.setAudible(tab, false)
    clock = start.addingTimeInterval(7 * 3600 + 60)

    XCTAssertEqual(set.littleArktIdleCandidates().map(\.id), [little.id])
    XCTAssertEqual(set.littleArktIdleCandidates().first?.lastActiveAt, start.addingTimeInterval(7 * 3600),
                   "the last pass that saw it playing")
  }

  func testClosingIdleWindowsArchivesThemAsIdle() throws {
    let (set, engine) = try makeSet()
    let (idle, idleWindow, _) = try openPopup(engine, set)
    let (kept, keptWindow, _) = try openPopup(engine, set)

    set.closeIdleLittleArkts([idle.id])
    idle.finishMotion()

    XCTAssertFalse(engine.windowIDs.contains(idleWindow))
    XCTAssertTrue(engine.windowIDs.contains(keptWindow))
    XCTAssertFalse(kept.isClosed)
    XCTAssertEqual(archived.map(\.url), [popupURL])
    XCTAssertEqual(archived.map(\.isIdle), [true])
  }

  // MARK: Reopen Closed Tab (Cmd-Shift-T)

  /// Close Little Arkt Windows (#356) is the user's close too: a hidden window (Hide All) closes without the motion
  /// and is archived and reopenable, like a window on screen.
  func testCloseLittleArktWindowsArchivesHiddenWindowsAndTheyCanBeReopened() throws {
    let (set, engine) = try makeSet()
    let (hidden, hiddenID, _) = try openPopup(engine, set)
    hidden.window.orderOut(nil)
    let (shown, shownID, _) = try openPopup(engine, set)

    set.littleArktMenus.closeAllWindows(nil)

    XCTAssertTrue(hidden.isClosed, "the hidden window closes at once, without the motion")
    XCTAssertFalse(engine.windowIDs.contains(hiddenID))
    shown.finishMotion()
    XCTAssertTrue(shown.isClosed)
    XCTAssertFalse(engine.windowIDs.contains(shownID))
    XCTAssertEqual(archived.map(\.url), [popupURL, popupURL], "both pages go to the Archive")
    XCTAssertEqual(archived.map(\.isIdle), [false, false])

    XCTAssertNotNil(set.reopenClosedLittleArkt(), "Cmd-Shift-T brings the last one back")
    let reopened = try XCTUnwrap(set.reopenClosedLittleArkt(), "and the hidden one after it")
    let tab = try XCTUnwrap(reopened.engineWindow.flatMap { engine.activeTab(in: $0) })
    XCTAssertEqual(engine.snapshot(of: tab)?.url, popupURL)
    XCTAssertEqual(takenBack.count, 2)
  }

  func testReopenBringsTheLastClosedLittleArktBackAtItsLastFrame() throws {
    let (set, engine) = try makeSet()
    let (first, _, _) = try openPopup(engine, set)
    let (second, _, _) = try openPopup(engine, set)
    let frame = CGRect(x: 120, y: 140, width: 420, height: 520)
    second.window.setFrame(frame, display: false)
    first.closeTab(nil)
    first.finishMotion()
    second.closeTab(nil)
    second.finishMotion()
    XCTAssertTrue(set.canReopenClosedLittleArkt)

    let reopened = try XCTUnwrap(set.reopenClosedLittleArkt())

    XCTAssertEqual(reopened.window.frame, frame, "at its last frame")
    let id = try XCTUnwrap(reopened.engineWindow)
    let tab = try XCTUnwrap(engine.activeTab(in: id))
    XCTAssertEqual(engine.snapshot(of: tab)?.url, popupURL)
    XCTAssertEqual(takenBack.count, 1, "its Archive entry is taken back")
    XCTAssertTrue(set.canReopenClosedLittleArkt, "the earlier close is next")
    XCTAssertNotNil(set.reopenClosedLittleArkt())
    XCTAssertFalse(set.canReopenClosedLittleArkt)
    XCTAssertNil(set.reopenClosedLittleArkt())
  }

  func testCommandShiftTInALittleArktWindowReopensTheLastClosedOne() throws {
    let (set, engine) = try makeSet()
    let (closing, _, _) = try openPopup(engine, set)
    let (other, _, _) = try openPopup(engine, set)
    let item = NSMenuItem(title: "Reopen Closed Tab", action: #selector(ShellWindowController.reopenClosedTab(_:)),
                          keyEquivalent: "t")
    XCTAssertFalse(other.validateMenuItem(item), "nothing to reopen yet")
    closing.closeTab(nil)
    closing.finishMotion()
    XCTAssertTrue(other.validateMenuItem(item))

    other.reopenClosedTab(nil)

    XCTAssertEqual(set.littleArkts.count, 2)
    XCTAssertFalse(set.canReopenClosedLittleArkt)
  }

  func testReopenInAMainWindowWithNothingOfItsOwnReopensTheLittleArkt() throws {
    let (set, engine) = try makeSet()
    let main = set.openWindow()
    let (little, _, _) = try openPopup(engine, set)
    XCTAssertFalse(main.canReopenClosed)
    little.closeTab(nil)
    little.finishMotion()
    let item = NSMenuItem(title: "Reopen Closed Tab", action: #selector(ShellWindowController.reopenClosedTab(_:)),
                          keyEquivalent: "t")
    XCTAssertTrue(main.validateMenuItem(item))

    main.reopenClosedTab(nil)

    XCTAssertEqual(set.littleArkts.count, 1)
    XCTAssertFalse(set.canReopenClosedLittleArkt)
  }

  func testReopenSkipsAWindowWhoseEntryWasRestoredFromTheArchive() throws {
    let (set, engine) = try makeSet()
    let (first, _, _) = try openPopup(engine, set)
    let (second, _, _) = try openPopup(engine, set)
    let firstFrame = CGRect(x: 100, y: 100, width: 400, height: 500)
    first.window.setFrame(firstFrame, display: false)
    first.closeTab(nil)
    first.finishMotion()
    second.closeTab(nil)
    second.finishMotion()
    restoredEntries = [archiveIDs[1]]                       // the second page is a Today row now

    let reopened = try XCTUnwrap(set.reopenClosedLittleArkt())

    XCTAssertEqual(reopened.window.frame, firstFrame, "the earlier window came back instead")
    XCTAssertEqual(takenBack, [archiveIDs[0]])
    XCTAssertFalse(set.canReopenClosedLittleArkt)
  }

  // MARK: Reopen with no key window (the app's router)

  func testTheRouterReopensTheLastLittleArktWhenNoWindowTakesTheAction() throws {
    let (set, engine) = try makeSet()
    let (little, _, _) = try openPopup(engine, set)
    let router = ReopenClosedRouter(windows: { set }, responder: { _ in nil })
    let item = NSMenuItem(title: "Reopen Closed Tab", action: #selector(ShellWindowController.reopenClosedTab(_:)),
                          keyEquivalent: "t")
    XCTAssertFalse(router.validateMenuItem(item))
    little.closeTab(nil)
    little.finishMotion()
    XCTAssertTrue(set.littleArkts.isEmpty, "no window left")
    XCTAssertTrue(router.validateMenuItem(item))

    router.reopenClosedTab(item)

    XCTAssertEqual(set.littleArkts.count, 1)
    XCTAssertFalse(router.validateMenuItem(item))
  }

  func testTheRouterLeavesTheActionToTheWindowThatTakesIt() throws {
    let (set, engine) = try makeSet()
    let (closing, _, _) = try openPopup(engine, set)
    let (key, _, _) = try openPopup(engine, set)
    var asked = 0
    key.onReopenClosed = { asked += 1 }
    let router = ReopenClosedRouter(windows: { set }, responder: { _ in key })
    closing.closeTab(nil)
    closing.finishMotion()

    router.reopenClosedTab(nil)

    XCTAssertEqual(asked, 1, "the key Little Arkt window handled it")
    XCTAssertEqual(set.littleArkts.count, 1)
  }
}
