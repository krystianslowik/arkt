import AppKit
import CoreBridge
import EngineAPI
import EngineAPITestSupport
import SidebarModel
import XCTest
@testable import ShellUI

/// Title events use the same window and sidebar path as loaded Favorites; URLs and titles are synthetic.
@MainActor
final class FavoriteUnreadIntegrationTests: XCTestCase {
  private final class Harness {
    let source: ModelSidebarSource
    let engine = InMemoryEngine()
    let controller: ShellWindowController
    let ids: [UUID]

    init() throws {
      var sidebar = SidebarModel.Sidebar()
      _ = sidebar.addSpace(title: "Space")
      ids = try ["x.com", "web.whatsapp.com", "mail.google.com"].map { host in
        try sidebar.addTab(url: URL(string: "https://\(host)/")!, title: "Saved",
                           in: .favorites(profile: "default"))
      }
      source = ModelSidebarSource(sidebar: sidebar, now: { Date(timeIntervalSinceReferenceDate: 800_000_000) })
      controller = ShellWindowController(engine: engine, sidebar: source)
      controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
      controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    func tile(_ id: UUID) throws -> FavoriteTileView {
      controller.sidebarController.view.favorites.collectionView.layoutSubtreeIfNeeded()
      return try XCTUnwrap(controller.sidebarController.view.favorites.tile(for: id))
    }

    @discardableResult
    func load(_ id: UUID, title: String) throws -> TabID {
      controller.activate(node: id)
      let tab = try XCTUnwrap(controller.engineTab(of: id))
      engine.finishLoad(tab, title: title)
      return tab
    }

    func badge(_ id: UUID) throws -> String? {
      let view = try tile(id).unreadBadgeView
      return view.isHidden ? nil : view.stringValue
    }
  }

  override func setUp() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
  }

  func testLiveTitlesClearAndReplayIncludesEmptyTitle() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    let tab = try h.load(id, title: "(1) Mail")
    XCTAssertEqual(try h.badge(id), "1")
    h.engine.setDocumentTitle(tab, "(125) Mail")
    XCTAssertEqual(try h.badge(id), "99+")
    h.engine.setDocumentTitle(tab, "Mail")
    XCTAssertNil(try h.badge(id))
    h.engine.setDocumentTitle(tab, "(0) Mail")
    XCTAssertNil(try h.badge(id))
    h.engine.setDocumentTitle(tab, "(3) Mail")
    h.engine.setDocumentTitle(tab, "")
    XCTAssertNil(try h.badge(id), "empty engine title must clear the badge even if the saved title is retained")
    XCTAssertEqual(try h.tile(id).accessibilityLabel(), "(3) Mail")

    var snapshot = try XCTUnwrap(h.engine.snapshot(of: tab))
    snapshot.title = "(7) Mail"
    h.controller.replay(snapshot, into: id)
    XCTAssertEqual(try h.badge(id), "7")
    snapshot.title = ""
    h.controller.replay(snapshot, into: id)
    XCTAssertNil(try h.badge(id), "empty snapshot replay also clears the live badge")
  }

  func testUnloadRemovalAndReuseClearBadge() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    _ = try h.load(id, title: "(8) Mail")
    let grid = h.controller.sidebarController.view.favorites
    XCTAssertEqual(try h.badge(id), "8")
    let item = try XCTUnwrap(grid.collectionView.item(at: IndexPath(item: 2, section: 0)) as? FavoriteTileItem)
    h.controller.close(node: id)
    XCTAssertNil(try h.badge(id))
    _ = try h.load(id, title: "(8) Mail")
    XCTAssertEqual(try h.badge(id), "8")
    item.prepareForReuse()
    XCTAssertTrue(item.tileView.unreadBadgeView.isHidden)
    XCTAssertNil(item.tileView.nodeID)
    h.source.mutate { $0.remove(id) }
    XCTAssertNil(grid.tile(for: id))
    XCTAssertNil(try h.badge(h.ids[0]))
  }

  func testSettingsRefreshUnchangedTitlesIndependentlyInSharedWindows() throws {
    let h = try Harness()
    let other = ShellWindowController(engine: h.engine, sidebar: h.source)
    defer { other.close(); h.controller.close() }
    other.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
    other.window?.contentView?.layoutSubtreeIfNeeded()
    _ = try h.load(h.ids[0], title: "(2) X")
    _ = try h.load(h.ids[1], title: "(4) Chat")
    other.activate(node: h.ids[0])
    let otherX = try XCTUnwrap(other.engineTab(of: h.ids[0]))
    h.engine.finishLoad(otherX, title: "(6) X")
    other.activate(node: h.ids[1])
    let otherChat = try XCTUnwrap(other.engineTab(of: h.ids[1]))
    h.engine.finishLoad(otherChat, title: "(9) Chat")
    func otherBadge(_ id: UUID) throws -> String? {
      other.sidebarController.view.favorites.collectionView.layoutSubtreeIfNeeded()
      let tile = try XCTUnwrap(other.sidebarController.view.favorites.tile(for: id))
      return tile.unreadBadgeView.isHidden ? nil : tile.unreadBadgeView.stringValue
    }
    h.controller.favoriteBadgeSettings = .init(twitterBadgeEnabled: false, whatsAppBadgeEnabled: true)
    other.favoriteBadgeSettings = h.controller.favoriteBadgeSettings
    XCTAssertNil(try h.badge(h.ids[0]))
    XCTAssertEqual(try h.badge(h.ids[1]), "4")
    XCTAssertNil(try otherBadge(h.ids[0]))
    XCTAssertEqual(try otherBadge(h.ids[1]), "9")
    h.controller.favoriteBadgeSettings = .init(twitterBadgeEnabled: true, whatsAppBadgeEnabled: false)
    other.favoriteBadgeSettings = h.controller.favoriteBadgeSettings
    XCTAssertEqual(try h.badge(h.ids[0]), "2")
    XCTAssertNil(try h.badge(h.ids[1]))
    XCTAssertEqual(try otherBadge(h.ids[0]), "6")
    XCTAssertNil(try otherBadge(h.ids[1]))
    h.controller.favoriteBadgeSettings = .init(twitterBadgeEnabled: true, whatsAppBadgeEnabled: true)
    other.favoriteBadgeSettings = h.controller.favoriteBadgeSettings
    XCTAssertEqual(try h.badge(h.ids[1]), "4")
    XCTAssertEqual(try otherBadge(h.ids[1]), "9")
  }

  func testAccessibilityAndHoverCloseSurviveTargetedTitleAndFaviconUpdates() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    let tab = try h.load(id, title: "Mail")
    let tile = try h.tile(id)
    tile.isHovered = true
    var notifications: [NSAccessibility.Notification] = []
    tile.postedNotificationsForTesting = { notifications.append($0) }
    h.engine.setDocumentTitle(tab, "(2) Mail")
    let image = NSImage(size: NSSize(width: 2, height: 2))
    let favicon = try XCTUnwrap(image.tiffRepresentation)
    h.engine.finishLoad(tab, title: "(2) Mail", favicon: favicon)
    let updated = try h.tile(id)
    XCTAssertEqual(updated.accessibilityLabel(), "(2) Mail")
    XCTAssertEqual(updated.accessibilityValue() as? String, AXID.Favorites.loaded)
    XCTAssertTrue(updated.accessibilityValueDescription()?.contains("2") == true)
    XCTAssertTrue(updated.isAccessibilitySelected())
    XCTAssertEqual(updated.accessibilityCustomActions()?.count, 1)
    XCTAssertTrue(notifications.contains(.valueChanged))
    XCTAssertTrue(updated.isCloseButtonShown)
    let button = updated.closeButton
    let content = try XCTUnwrap(button.window?.contentView)
    let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    XCTAssertTrue(content.hitTest(content.superview?.convert(center, from: nil) ?? center) === button)
    notifications.removeAll()
    h.engine.setDocumentTitle(tab, "Mail")
    XCTAssertFalse(try XCTUnwrap(h.tile(id).accessibilityValueDescription()).contains("2"))
    XCTAssertTrue(notifications.contains(.valueChanged))
    XCTAssertEqual(try h.tile(id).accessibilityCustomActions()?.count, 1)
  }

  func testBadgeBoundsAtSupportedSizesAndFlavors() throws {
    let h = try Harness()
    defer { h.controller.close() }
    let id = h.ids[2]
    let tab = try h.load(id, title: "(1) Mail")
    let tile = try h.tile(id)
    for flavor in [ThemeFlavor.light, .dark] {
      tile.flavor = flavor
      for width in [FavoritesLayout.minimumTileWidth, CGFloat(100)] {
        tile.frame.size = NSSize(width: width, height: FavoritesLayout.tileHeight)
        for (title, expected) in [("(0) Mail", ""), ("(1) Mail", "1"), ("(100) Mail", "99+")] {
          h.engine.setDocumentTitle(tab, title)
          tile.layoutSubtreeIfNeeded()
          let badge = tile.unreadBadgeView
          if expected.isEmpty { XCTAssertTrue(badge.isHidden); continue }
          XCTAssertFalse(badge.isHidden)
          XCTAssertEqual(badge.stringValue, expected)
          XCTAssertTrue(tile.bounds.contains(badge.frame))
          XCTAssertGreaterThanOrEqual(badge.bounds.width, badge.intrinsicContentSize.width)
          XCTAssertGreaterThanOrEqual(badge.bounds.height, badge.intrinsicContentSize.height)
        }
      }
    }
  }
}
