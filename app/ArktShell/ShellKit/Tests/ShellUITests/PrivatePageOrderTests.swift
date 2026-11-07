import EngineAPI
import Testing
@testable import ShellUI

/// The open order and the cap of a blank or incognito window's pages (#668, design/private-pages, "Order" and
/// "Close Oldest"): rows in the order the pages were opened, at most 20, and Close Oldest's pick.
@MainActor
struct PrivatePageOrderTests {
  private func pages(_ count: Int) -> [TabID] { (0..<count).map { _ in TabID() } }

  @Test func `pages keep the order they were opened in and leave when they close`() {
    var order = PrivatePageOrder()
    let tabs = pages(3)
    for tab in tabs {
      let added = order.append(tab)
      #expect(added)
    }
    #expect(order.pages == tabs)
    let again = order.append(tabs[0])
    #expect(!again, "a page enters the list once")
    #expect(order.pages == tabs)
    order.remove(tabs[1])
    #expect(order.pages == [tabs[0], tabs[2]])
    order.remove(TabID())
    #expect(order.pages == [tabs[0], tabs[2]], "removing a page that is not listed changes nothing")
  }

  @Test func `the twenty first page is refused`() {
    #expect(PrivatePageOrder.cap == 20)
    var order = PrivatePageOrder()
    for tab in pages(19) { order.append(tab) }
    #expect(!order.isFull)
    let twentieth = order.append(TabID())
    #expect(twentieth)
    #expect(order.isFull)
    let refused = TabID()
    let added = order.append(refused)
    #expect(!added)
    #expect(order.pages.count == 20)
    #expect(!order.pages.contains(refused))
  }

  /// #789: a reopened page goes back at the row it closed from, or at the bottom when the list is shorter now.
  @Test func `a page inserted at a row goes there clamped to the list`() {
    var order = PrivatePageOrder()
    let tabs = pages(3)
    for tab in tabs { order.append(tab) }
    let (middle, top, past, negative) = (TabID(), TabID(), TabID(), TabID())
    let added = [order.insert(middle, at: 1), order.insert(top, at: 0), order.insert(past, at: 99),
                 order.insert(negative, at: -3)]
    #expect(added == [true, true, true, true])
    #expect(order.pages == [negative, top, tabs[0], middle, tabs[1], tabs[2], past],
            "a row past the end is the bottom, one before the top is the top")
    let again = order.insert(middle, at: 0)
    #expect(!again, "a page enters the list once")
    #expect(order.pages.count == 7)
  }

  @Test func `an insert at the cap is refused`() {
    var order = PrivatePageOrder()
    let tabs = pages(20)
    for tab in tabs { order.append(tab) }
    let added = order.insert(TabID(), at: 0)
    #expect(!added)
    #expect(order.pages == tabs)
  }

  @Test func `close oldest picks the top row that is neither shown nor playing`() {
    var order = PrivatePageOrder()
    let tabs = pages(20)
    for tab in tabs { order.append(tab) }
    #expect(order.oldestClosable(shown: tabs[0], isPlaying: { _ in false }) == tabs[1], "the shown page is spared")
    #expect(order.oldestClosable(shown: tabs[5], isPlaying: { _ in false }) == tabs[0])
    let playing: Set<TabID> = [tabs[0], tabs[1], tabs[2]]
    #expect(order.oldestClosable(shown: tabs[3], isPlaying: { playing.contains($0) }) == tabs[4],
            "pages playing sound are spared")
    #expect(order.oldestClosable(shown: nil, isPlaying: { _ in false }) == tabs[0])
  }

  @Test func `close oldest has no pick when every page is shown or playing`() {
    var order = PrivatePageOrder()
    let tabs = pages(20)
    for tab in tabs { order.append(tab) }
    #expect(order.oldestClosable(shown: tabs[0], isPlaying: { $0 != tabs[0] }) == nil)
    #expect(order.oldestClosable(shown: nil, isPlaying: { _ in true }) == nil)
  }

  /// A muted page that still plays is spared; a muted page that went quiet keeps its mute button (`TabAudio`) but
  /// is not playing, so it is closed.
  @Test func `close oldest spares a muted page that plays and closes a muted page that is quiet`() {
    var order = PrivatePageOrder()
    let tabs = pages(3)
    for tab in tabs { order.append(tab) }
    let snapshots = [
      tabs[0]: TabSnapshot(id: tabs[0], isAudible: true, isMuted: true),
      tabs[1]: TabSnapshot(id: tabs[1], isAudible: false, isMuted: true),
      tabs[2]: TabSnapshot(id: tabs[2]),
    ]
    #expect(TabAudio(isAudible: false, isMuted: true) == .muted, "the quiet muted page still shows its button")
    let pick = order.oldestClosable(shown: tabs[2]) { snapshots[$0].map(PrivatePageOrder.isPlaying) ?? false }
    #expect(pick == tabs[1])
  }

  @Test func `the cap toast offers close oldest only when a page can be closed`() {
    let offer = PrivatePageOrder.capToast(canCloseOldest: true)
    #expect(offer.text == "This window has 20 pages open, the most it keeps.")
    #expect(offer.actionTitle == "Close Oldest")
    #expect(offer.glyph == "rectangle.stack")
    #expect(offer.kind == .notice)
    #expect(offer.duration == .seconds(4))

    let none = PrivatePageOrder.capToast(canCloseOldest: false)
    #expect(none.text == "This window has 20 pages open. Close one to open another.")
    #expect(none.actionTitle == nil)
    #expect(none.glyph == "rectangle.stack")
  }
}
