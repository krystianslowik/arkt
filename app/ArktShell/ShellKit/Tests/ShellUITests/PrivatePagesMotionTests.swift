import AppKit
import EngineAPI
import Motion
import QuartzCore
import Testing
@testable import ShellUI

/// The Pages list's motion (#668, design/private-pages, Motion): a row added or closed moves the rows below 0.20 s on
/// `firm`, a new row fades in, and the buttons fade 0.12 s on hover. Reduce Motion: opacity only, the rows jump.
/// Animations are read off the layers; nothing waits for them to run.
@MainActor
struct PrivatePagesMotionTests {
  private func rows(_ tabs: [TabID], shown: TabID? = nil) -> [PrivatePageRowContent] {
    tabs.enumerated().map { index, tab in
      PrivatePageRowContent(tab: tab, title: "Page \(index)", url: nil, favicon: nil, isShown: tab == shown,
                            audio: .silent)
    }
  }

  private func controlPoints(_ function: CAMediaTimingFunction) -> [Float] {
    var first = [Float](repeating: 0, count: 2), second = [Float](repeating: 0, count: 2)
    function.getControlPoint(at: 1, values: &first)
    function.getControlPoint(at: 2, values: &second)
    return first + second
  }

  private func makeList(reduceMotion: Bool) -> PrivatePagesView {
    let list = PrivatePagesView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
    list.reduceMotion = { reduceMotion }
    list.layoutSubtreeIfNeeded()
    return list
  }

  @Test func `the motion is the design's numbers`() {
    let move = PrivatePagesMotion.rows(reduceMotion: false)
    #expect(move.movesRows && move.duration == 0.20 && move.curve == MotionCurve(0.25, 1, 0.5, 1))
    #expect(move.fadeDuration == 0.20)
    let reduced = PrivatePagesMotion.rows(reduceMotion: true)
    #expect(!reduced.movesRows, "Reduce Motion: the rows jump")
    #expect(reduced.fadeDuration > 0, "a new row still fades in")
    #expect(PrivatePagesMotion.buttonFade == 0.12)
  }

  @Test func `closing a row moves the rows below on firm`() throws {
    let tabs = (0..<4).map { _ in TabID() }
    let list = makeList(reduceMotion: false)
    list.setPages(rows(tabs))
    list.setPages(rows([tabs[0], tabs[2], tabs[3]]))
    let below = list.rows.filter { $0.tab == tabs[2] || $0.tab == tabs[3] }
    for row in below {
      let move = try #require(row.layer?.animation(forKey: PrivatePagesMotion.moveKey) as? CABasicAnimation)
      #expect(move.keyPath == "position")
      #expect(move.duration == 0.20)
      #expect(move.timingFunction.map(controlPoints) == [0.25, 1, 0.5, 1])
      #expect(row.frame.minY == CGFloat(list.rows.firstIndex(of: row)!) * PrivatePagesView.rowHeight,
              "the frame is final at once; only the layer moves")
    }
    #expect(list.rows[0].layer?.animation(forKey: PrivatePagesMotion.moveKey) == nil, "rows above stay")
  }

  @Test func `a new row fades in and the rows do not move under reduce motion`() throws {
    let tabs = (0..<3).map { _ in TabID() }
    for reduce in [false, true] {
      let list = makeList(reduceMotion: reduce)
      list.setPages(rows([tabs[1], tabs[2]]))
      list.setPages(rows(tabs))
      let added = try #require(list.rows.first { $0.tab == tabs[0] })
      let fade = try #require(added.layer?.animation(forKey: PrivatePagesMotion.fadeKey) as? CABasicAnimation)
      #expect(fade.keyPath == "opacity")
      let moved = list.rows.filter { $0.layer?.animation(forKey: PrivatePagesMotion.moveKey) != nil }
      #expect(moved.count == (reduce ? 0 : 2), "rows below move, or jump under Reduce Motion")
    }
  }

  @Test func `the close button fades in on hover`() throws {
    let tab = TabID()
    let list = makeList(reduceMotion: false)
    list.setPages(rows([tab]))
    let row = try #require(list.rows.first)
    #expect(row.closeButton.alphaValue == 0)
    row.setHovered(true)
    #expect(row.closeButton.alphaValue == 1)
    let fade = try #require(row.closeButton.layer?.animation(forKey: PrivatePagesMotion.fadeKey) as? CABasicAnimation)
    #expect(fade.duration == 0.12)
  }
}
